"""The planner service: the one server every client talks to.

This module is the entry point of the `planner` service app ([apps.planner]
in jac.toml). Its walkers are the whole API. The web app colocates it in its
own process, the phone UI reaches it through the web server, and the CLI
bridges to it over HTTP. All walkers are authenticated (plain `walker`), so
each user's graph hangs off their own root:

    root ─┬─> Profile                       (settings, Canvas token)
          ├─> Course ─┬─> Meeting           (weekly class schedule)
          │           └─> Assignment        (course work)
          └─> Assignment                    (personal tasks)

Walkers report `core.views` objects, never raw nodes, so every client gets
the same pre-formatted deadline labels and grade math.
"""

import from datetime { datetime, timedelta }
import from core.views {
    OpResult,
    MeetingView,
    CourseView,
    AssignmentView,
    ClassSlot,
    DayColumn,
    WeekView,
    Stats,
    Dashboard,
    SettingsView,
    SyncResult,
    StudyPlan,
    GradeSummary,
    Snapshot
}
import core.logic as lg;
import core.canvas as cv;
import core.advisor as adv;
import core.gcal as gc;
import from core.logic { GradeInput, DAY_SHORT, SOURCES, STATUSES }
import from core.canvas { CanvasError, CanvasAssignment, CanvasCourse }
import from core.advisor { TaskBrief, Busy }

glob GCAL_COLOR: str = "#64748b";

glob PALETTE: list[str] = [
         "#2563eb",
         "#db2777",
         "#16a34a",
         "#ea580c",
         "#7c3aed",
         "#0891b2",
         "#ca8a04",
         "#dc2626"
     ],
     MEETING_KINDS: list[str] = [
         "Lecture",
         "Discussion",
         "Lab",
         "Office Hours",
         "Seminar",
         "Study Group"
     ];

# ================================================================ graph ====

node Profile {
    has display_name: str = "",
        canvas_url: str = "https://umich.instructure.com",
        canvas_token: str = "",
        canvas_feed_url: str = "",
        gcal_url: str = "",
        gcal_events: str = "",
        gcal_synced: str = "",
        last_sync: str = "",
        last_sync_summary: str = "";
}

node Course {
    has code: str = "",
        name: str = "",
        color: str = "#2563eb",
        term: str = "",
        instructor: str = "",
        canvas_id: int = 0,
        canvas_url: str = "",
        gradescope_url: str = "",
        autograder_url: str = "",
        website_url: str = "",
        target: float = 90.0,
        weights: dict[str, float] = {},
        created: str = "";
}

node Meeting {
    has kind: str = "Lecture",
        days: list[int] = [],
        start: str = "09:00",
        end: str = "10:00",
        location: str = "";
}

node Assignment {
    has title: str = "",
        source: str = "other",
        due: str = "",
        status: str = "todo",
        priority: int = 2,
        category: str = "",
        points: float = 0.0,
        score: float | None = None,
        url: str = "",
        notes: str = "",
        est_hours: float = 0.0,
        subtasks: list[str] = [],
        subtasks_done: list[bool] = [],
        canvas_id: int = 0,
        created: str = "",
        completed: str = "";
}

# ============================================================== helpers ====

def _profile -> Profile {
    found = [root -->[?:Profile]];
    if found {
        return found[0];
    }
    made = Profile();
    root ++> made;
    return made;
}

def _courses -> list[Course] {
    items = [root -->[?:Course]];
    return sorted(items, key=lambda (c: Course) -> str { c.code.lower(); });
}

def _course_by_ref(ref: str) -> Course | None {
    want = (ref or "").strip();
    if not want {
        return None;
    }
    norm = lg.normalize_code(want);
    for c in [root -->[?:Course]] {
        cid = jid(c);
        if cid == want or (len(want) >= 4 and cid.startswith(want)) {
            return c;
        }
    }
    for c in [root -->[?:Course]] {
        if lg.normalize_code(c.code) == norm {
            return c;
        }
    }
    return None;
}

def _course_of(a: Assignment) -> Course | None {
    owners = [a <--[?:Course]];
    return owners[0] if owners else None;
}

def _all_assignments -> list[tuple[Assignment, Course | None]] {
    out: list[tuple[Assignment, Course | None]] = [];
    for c in [root -->[?:Course]] {
        for a in [c -->[?:Assignment]] {
            out.append((a, c));
        }
    }
    for a in [root -->[?:Assignment]] {
        out.append((a, None));
    }
    return out;
}

def _find_assignment(ref: str) -> tuple[Assignment | None, Course | None] {
    want = (ref or "").strip().lower();
    if not want {
        return (None, None);
    }
    matches: list[tuple[Assignment, Course | None]] = [];
    for (a, c) in _all_assignments() {
        aid = jid(a);
        if aid == want {
            return (a, c);
        }
        if len(want) >= 3 and aid.startswith(want) {
            matches.append((a, c));
        }
    }
    if len(matches) == 1 {
        return matches[0];
    }
    return (None, None);
}

def _meeting_by_ref(ref: str) -> tuple[Meeting | None, Course | None] {
    for c in [root -->[?:Course]] {
        for m in [c -->[?:Meeting]] {
            if jid(m) == ref {
                return (m, c);
            }
        }
    }
    return (None, None);
}

def _next_color -> str {
    used = [c.color for c in [root -->[?:Course]]];
    for color in PALETTE {
        if color not in used {
            return color;
        }
    }
    return PALETTE[len(used) % len(PALETTE)];
}

def _clean_source(source: str) -> str {
    s = (source or "").strip().lower();
    if s in ["gs"] {
        return "gradescope";
    }
    if s in ["ag", "autograder.io"] {
        return "autograder";
    }
    return s if s in SOURCES else "other";
}

def _clean_due(text: str, now: datetime) -> str {
    raw = (text or "").strip();
    if not raw {
        return "";
    }
    d = lg.parse_iso(raw);
    if d is None {
        d = lg.parse_when(raw, now);
    }
    return lg.to_iso(d) if d is not None else "";
}

def _assignment_view(a: Assignment, c: Course | None, now: datetime) -> AssignmentView {
    due = lg.parse_iso(a.due);
    done = a.status == "done";
    link = a.url;
    if not link and c is not None {
        if a.source == "gradescope" {
            link = c.gradescope_url;
        } elif a.source == "autograder" {
            link = c.autograder_url;
        } elif a.source == "canvas" {
            link = c.canvas_url;
        }
    }
    aid = jid(a);
    return AssignmentView(
        id=aid,
        short_id=lg.short_id(aid),
        course_id=jid(c) if c is not None else "",
        course_code=c.code if c is not None else "Personal",
        course_color=c.color if c is not None else "#64748b",
        title=a.title,
        source=a.source,
        due=a.due,
        due_label=lg.due_label(due, now),
        due_in=lg.due_in(due, now, done),
        due_date=due.strftime("%Y-%m-%d") if due is not None else "",
        urgency=lg.urgency(due, now, done),
        status=a.status,
        priority=a.priority,
        category=a.category,
        points=a.points,
        score=a.score,
        url=link,
        notes=a.notes,
        est_hours=a.est_hours,
        subtasks=list(a.subtasks),
        subtasks_done=[bool(x) for x in a.subtasks_done],
        from_canvas=a.canvas_id > 0
    );
}

def _sort_key(v: AssignmentView) -> tuple[int, str, int, str] {
    return (
        1 if v.status == "done" else 0,
        v.due or "9999-99-99",
        -v.priority,
        v.title.lower()
    );
}

def _meeting_view(m: Meeting, c: Course) -> MeetingView {
    return MeetingView(
        id=jid(m),
        course_id=jid(c),
        kind=m.kind,
        days=list(m.days),
        days_label=lg.days_label(m.days),
        start=m.start,
        end=m.end,
        time_label=lg.range_label(m.start, m.end),
        location=m.location
    );
}

def _grade_for(c: Course) -> GradeSummary {
    items = [
        GradeInput(category=a.category, points=a.points, score=a.score)
        for a in [c -->[?:Assignment]]
    ];
    return lg.compute_grade(items, c.weights, c.target);
}

def _course_view(c: Course, now: datetime) -> CourseView {
    work = [c -->[?:Assignment]];
    open_items = [a for a in work if a.status != "done"];
    overdue = 0;
    next_due = "";
    for a in open_items {
        d = lg.parse_iso(a.due);
        if d is not None and d < now {
            overdue += 1;
        } elif d is not None and (not next_due or a.due < next_due) {
            next_due = a.due;
        }
    }
    meetings = sorted(
        [_meeting_view(m, c) for m in [c -->[?:Meeting]]],
        key=lambda (m: MeetingView) -> tuple[int, str] {
            (min(m.days) if m.days else 7, m.start);
        }
    );
    next_label = lg.due_label(lg.parse_iso(next_due), now) if next_due else "";
    return CourseView(
        id=jid(c),
        code=c.code,
        name=c.name,
        color=c.color,
        term=c.term,
        instructor=c.instructor,
        canvas_id=c.canvas_id,
        canvas_url=c.canvas_url,
        gradescope_url=c.gradescope_url,
        autograder_url=c.autograder_url,
        website_url=c.website_url,
        target=c.target,
        weights=dict(c.weights),
        meetings=meetings,
        open_count=len(open_items),
        overdue_count=overdue,
        next_due=next_label,
        grade=_grade_for(c)
    );
}

def _slots_on(day: datetime, now: datetime) -> list[ClassSlot] {
    slots: list[ClassSlot] = [];
    weekday = day.weekday();
    for c in [root -->[?:Course]] {
        for m in [c -->[?:Meeting]] {
            if weekday not in m.days {
                continue;
            }
            state = "upcoming";
            begin = lg.parse_iso(day.strftime("%Y-%m-%dT") + m.start);
            finish = lg.parse_iso(day.strftime("%Y-%m-%dT") + m.end);
            if begin is not None and finish is not None {
                if finish <= now {
                    state = "past";
                } elif begin <= now {
                    state = "now";
                }
            }
            slots.append(
                ClassSlot(
                    course_id=jid(c),
                    course_code=c.code,
                    color=c.color,
                    kind=m.kind,
                    day=weekday,
                    start=m.start,
                    end=m.end,
                    time_label=lg.range_label(m.start, m.end),
                    location=m.location,
                    state=state
                )
            );
        }
    }
    # Google Calendar events show up as slots too, so Today, the week view
    # and the study plan's busy time all see them.
    events = gc.load_events(_profile().gcal_events);
    for (i, (ev, begin, finish)) in enumerate(gc.events_on(events, day)) {
        state = "upcoming";
        if not ev.all_day {
            if finish <= now {
                state = "past";
            } elif begin <= now {
                state = "now";
            }
        }
        start_s = "" if ev.all_day else begin.strftime("%H:%M");
        end_s = "" if ev.all_day else (
            "23:59" if finish.date() > begin.date() else finish.strftime("%H:%M")
        );
        slots.append(
            ClassSlot(
                course_id=f"gcal-{i}",
                course_code=ev.title,
                color=GCAL_COLOR,
                kind="Calendar",
                day=weekday,
                start=start_s,
                end=end_s,
                time_label="All day" if ev.all_day else lg.range_label(start_s, end_s),
                location=ev.location,
                state=state
            )
        );
    }
    return sorted(slots, key=lambda (s: ClassSlot) -> str { s.start; });
}

def _open_views(now: datetime) -> list[AssignmentView] {
    views = [
        _assignment_view(a, c, now)
        for (a, c) in _all_assignments()
        if a.status != "done"
    ];
    return sorted(views, key=_sort_key);
}

def _set_status(a: Assignment, status: str, now: datetime) {
    if status not in STATUSES {
        return;
    }
    if status == "done" and a.status != "done" {
        a.completed = lg.to_iso(now);
    }
    if status != "done" {
        a.completed = "";
    }
    a.status = status;
}

def _attach(a: Assignment, course: Course | None) {
    old = _course_of(a);
    if old is not None and course is not None and jid(old) == jid(course) {
        return;
    }
    if old is not None {
        old del --> a;
    } else {
        root del --> a;
    }
    if course is not None {
        course ++> a;
    } else {
        root ++> a;
    }
}

# ============================================================ dashboard ====

def _dashboard -> Dashboard {
    now = lg.now_local();
    prof = _profile();
    views = _open_views(now);
    today_d = lg.start_of_day(now);
    week_end = today_d + timedelta(days=7);
    dash = Dashboard(
        greeting=lg.greeting(now, prof.display_name),
        date_label=now.strftime("%A, %B ") + str(now.day),
        now=lg.to_iso(now),
        overdue=[v for v in views if v.urgency == "overdue"],
        today=[v for v in views if v.urgency == "today"],
        tomorrow=[v for v in views if v.urgency == "tomorrow"],
        week=[v for v in views if v.urgency == "week"],
        classes_today=_slots_on(now, now),
        course_count=len([root -->[?:Course]]),
        canvas_connected=bool(prof.canvas_token or prof.canvas_feed_url),
        calendar_connected=bool(prof.gcal_url),
        last_sync=prof.last_sync
    );
    upcoming = [s for s in dash.classes_today if s.state != "past"];
    if upcoming {
        dash.next_class = upcoming[0];
    } else {
        for offset in range(1, 8) {
            later = _slots_on(today_d + timedelta(days=offset), now);
            if later {
                first = later[0];
                first.state = DAY_SHORT[first.day];
                dash.next_class = first;
                break;
            }
        }
    }
    done_week = 0;
    hours = 0.0;
    week_start = lg.start_of_week(now);
    for (a, _) in _all_assignments() {
        if a.status == "done" {
            finished = lg.parse_iso(a.completed);
            if finished is not None and finished >= week_start {
                done_week += 1;
            }
        } else {
            d = lg.parse_iso(a.due);
            if d is not None and d < week_end {
                hours += a.est_hours;
            }
        }
    }
    dash.stats = Stats(
        open=len(views),
        overdue=len(dash.overdue),
        due_today=len(dash.today),
        due_week=len(dash.today) + len(dash.tomorrow) + len(dash.week),
        done_week=done_week,
        hours_week=round(hours, 1)
    );
    return dash;
}

walker get_dashboard {
    has reports: list[Dashboard] = [];

    can build with Root entry {
        report _dashboard();
    }
}

"""Dashboard, courses, the filtered assignment list and, when asked, the week
and gradebook, in one round trip. The UI used to make these calls one after
another, and each costs a full trip to the hosted server."""
walker load_all {
    has course: str = "",
        source: str = "",
        status: str = "open",
        week_offset: int = 0,
        with_week: bool = False,
        with_gradebook: bool = False,
        reports: list[Snapshot] = [];

    can build with Root entry {
        # Plain function calls, not nested spawns: a nested walker's reports
        # would be added to this response too.
        now = lg.now_local();
        snap = Snapshot(
            dashboard=_dashboard(),
            courses=[_course_view(c, now) for c in _courses()],
            assignments=_assignment_list(self.course, self.status, self.source, "", now)
        );
        if self.with_week {
            snap.week = _week(self.week_offset);
        }
        if self.with_gradebook {
            snap.gradebook = _assignment_list("", "all", "", "", now);
        }
        report snap;
    }
}

def _week(offset: int) -> WeekView {
    now = lg.now_local();
    start = lg.start_of_week(now) + timedelta(days=7 * offset);
    views = [_assignment_view(a, c, now) for (a, c) in _all_assignments()];
    by_day: dict[str, list[AssignmentView]] = {};
    for v in views {
        if v.due_date {
            by_day.setdefault(v.due_date, []).append(v);
        }
    }
    days: list[DayColumn] = [];
    for i in range(7) {
        day = start + timedelta(days=i);
        key = day.strftime("%Y-%m-%d");
        days.append(
            DayColumn(
                date=key,
                label=day.strftime("%b ") + str(day.day),
                weekday=DAY_SHORT[i],
                is_today=key == now.strftime("%Y-%m-%d"),
                classes=_slots_on(day, now),
                due=sorted(by_day.get(key, []), key=_sort_key)
            )
        );
    }
    end = start + timedelta(days=6);
    return WeekView(
        start=start.strftime("%Y-%m-%d"),
        label=start.strftime("%b ") + str(start.day) + " – " + end.strftime(
            "%b "
        ) + str(end.day),
        days=days
    );
}

walker get_week {
    has offset: int = 0,
        reports: list[WeekView] = [];

    can build with Root entry {
        report _week(self.offset);
    }
}

# ============================================================== courses ====

walker list_courses {
    has reports: list[list[CourseView]] = [];

    can build with Root entry {
        now = lg.now_local();
        report [_course_view(c, now) for c in _courses()];
    }
}

walker save_course {
    has id: str = "",
        code: str = "",
        name: str = "",
        color: str = "",
        term: str = "",
        instructor: str = "",
        canvas_url: str = "",
        gradescope_url: str = "",
        autograder_url: str = "",
        website_url: str = "",
        target: float = 90.0,
        weights: dict[str, float] = {},
        reports: list[CourseView] = [];

    can save with Root entry {
        code = self.code.strip();
        course = _course_by_ref(self.id) if self.id else None;
        if course is None and code {
            course = _course_by_ref(code);
        }
        if course is None {
            if not code {
                return;
            }
            course = Course(
                code=code,
                color=self.color or _next_color(),
                created=lg.to_iso(lg.now_local())
            );
            root ++> course;
        }
        if code {
            course.code = code;
        }
        course.name = self.name.strip();
        if self.color {
            course.color = self.color;
        }
        course.term = self.term.strip();
        course.instructor = self.instructor.strip();
        course.canvas_url = self.canvas_url.strip();
        course.gradescope_url = self.gradescope_url.strip();
        course.autograder_url = self.autograder_url.strip();
        course.website_url = self.website_url.strip();
        course.target = max(0.0, min(float(self.target), 100.0));
        course.weights = {
            str(k).strip(): float(v)
            for (k, v) in self.weights.items()
            if str(k).strip() and float(v) > 0
        };
        report _course_view(course, lg.now_local());
    }
}

walker delete_course {
    has id: str = "",
        reports: list[OpResult] = [];

    can remove with Root entry {
        course = _course_by_ref(self.id);
        if course is None {
            report OpResult(ok=False, message="No such course");
            return;
        }
        code = course.code;
        removed = 0;
        for a in [course -->[?:Assignment]] {
            del a;
            removed += 1;
        }
        for m in [course -->[?:Meeting]] {
            del m;
        }
        del course;
        report OpResult(ok=True, message=f"Deleted {code} and {removed} assignments");
    }
}

walker add_meeting {
    has course_id: str = "",
        kind: str = "Lecture",
        days: list[int] = [],
        start: str = "09:00",
        end: str = "10:00",
        location: str = "",
        reports: list[MeetingView] = [];

    can add with Root entry {
        course = _course_by_ref(self.course_id);
        days = sorted(set([int(d) for d in self.days if 0 <= int(d) <= 6]));
        if course is None or not days or not self.start {
            return;
        }
        m = Meeting(
            kind=self.kind if self.kind else "Lecture",
            days=days,
            start=self.start,
            end=self.end,
            location=self.location.strip()
        );
        course ++> m;
        report _meeting_view(m, course);
    }
}

walker delete_meeting {
    has id: str = "",
        reports: list[OpResult] = [];

    can remove with Root entry {
        (m, _) = _meeting_by_ref(self.id);
        if m is None {
            report OpResult(ok=False, message="No such meeting");
            return;
        }
        del m;
        report OpResult(ok=True, message="Meeting removed");
    }
}

# ========================================================== assignments ====

"""Does an assignment pass the list filters (status "open" = not done)?"""
def _matches(a: Assignment, status: str, source: str, search: str) -> bool {
    if status == "open" and a.status == "done" {
        return False;
    }
    if status in ["todo", "doing", "done"] and a.status != status {
        return False;
    }
    if source and a.source != _clean_source(source) {
        return False;
    }
    if search and search.lower() not in (a.title + " " + a.notes + " " + a.category).lower() {
        return False;
    }
    return True;
}

"""The `list_assignments` result as a function, for `load_all`."""
def _assignment_list(
    course: str, status: str, source: str, search: str, now: datetime
) -> list[AssignmentView] {
    pairs: list[tuple[Assignment, Course | None]] = [];
    if course {
        target = _course_by_ref(course);
        if target is None {
            return [];
        }
        pairs = [(a, target) for a in [target -->[?:Assignment]]];
    } else {
        pairs = _all_assignments();
    }
    found = [
        _assignment_view(a, c, now)
        for (a, c) in pairs
        if _matches(a, status, source, search)
    ];
    return sorted(found, key=_sort_key);
}

walker list_assignments {
    """Walk root -> courses -> assignments, filtering as it goes."""
    has course: str = "",
        status: str = "open",
        source: str = "",
        search: str = "",
        found: list[AssignmentView] = [],
        reports: list[list[AssignmentView]] = [];

    can start with Root entry {
        self.found = [];
        target = _course_by_ref(self.course) if self.course else None;
        if self.course and target is None {
            return;
        }
        if target is not None {
            visit [target];
        } else {
            visit [-->[?:Course]];
            if self.course == "" {
                visit [-->[?:Assignment]];
            }
        }
    }

    can in_course with Course entry {
        visit [-->[?:Assignment]];
    }

    can collect with Assignment entry {
        if _matches(here, self.status, self.source, self.search) {
            self.found.append(_assignment_view(here, _course_of(here), lg.now_local()));
        }
    }

    can finish with Root exit {
        report sorted(self.found, key=_sort_key);
    }
}

walker save_assignment {
    has id: str = "",
        course_id: str = "",
        title: str = "",
        source: str = "other",
        due: str = "",
        priority: int = 2,
        category: str = "",
        points: float = 0.0,
        url: str = "",
        notes: str = "",
        est_hours: float = 0.0,
        reports: list[AssignmentView] = [];

    can save with Root entry {
        now = lg.now_local();
        course = _course_by_ref(self.course_id) if self.course_id else None;
        a: Assignment | None = None;
        if self.id {
            (a, _) = _find_assignment(self.id);
            if a is None {
                return;
            }
        }
        if a is None {
            if not self.title.strip() {
                return;
            }
            a = Assignment(created=lg.to_iso(now));
            if course is not None {
                course ++> a;
            } else {
                root ++> a;
            }
        } else {
            _attach(a, course);
        }
        a.title = self.title.strip() or a.title;
        a.source = _clean_source(self.source);
        a.due = _clean_due(self.due, now);
        a.priority = max(1, min(int(self.priority), 3));
        a.category = self.category.strip();
        a.points = max(0.0, float(self.points));
        a.url = self.url.strip();
        a.notes = self.notes;
        a.est_hours = max(0.0, float(self.est_hours));
        report _assignment_view(a, course, now);
    }
}

walker quick_add {
    has text: str = "",
        reports: list[AssignmentView] = [];

    can add with Root entry {
        now = lg.now_local();
        codes = [c.code for c in [root -->[?:Course]]];
        q = lg.quick_parse(self.text, codes, now);
        if not self.text.strip() {
            return;
        }
        course = _course_by_ref(q.course_code) if q.course_code else None;
        a = Assignment(
            title=q.title,
            source=q.source,
            due=q.due,
            priority=q.priority,
            points=q.points,
            created=lg.to_iso(now)
        );
        if course is not None {
            course ++> a;
        } else {
            root ++> a;
        }
        report _assignment_view(a, course, now);
    }
}

walker set_status {
    has id: str = "",
        status: str = "done",
        reports: list[AssignmentView] = [];

    can update with Root entry {
        (a, c) = _find_assignment(self.id);
        if a is None {
            return;
        }
        now = lg.now_local();
        _set_status(a, self.status, now);
        report _assignment_view(a, c, now);
    }
}

"""Set many assignments' status in one call (the "Mark all done" button)."""
walker set_status_many {
    has ids: list[str] = [],
        status: str = "done",
        reports: list[int] = [];

    can update with Root entry {
        now = lg.now_local();
        changed = 0;
        for ref in self.ids {
            (a, _) = _find_assignment(ref);
            if a is not None and a.status != self.status {
                _set_status(a, self.status, now);
                changed += 1;
            }
        }
        report changed;
    }
}

walker set_score {
    has id: str = "",
        score: float | None = None,
        points: float = 0.0,
        reports: list[AssignmentView] = [];

    can update with Root entry {
        (a, c) = _find_assignment(self.id);
        if a is None {
            return;
        }
        if self.points > 0 {
            a.points = float(self.points);
        }
        a.score = None if self.score is None else float(self.score);
        now = lg.now_local();
        if a.score is not None {
            _set_status(a, "done", now);
        }
        report _assignment_view(a, c, now);
    }
}

walker delete_assignment {
    has id: str = "",
        reports: list[OpResult] = [];

    can remove with Root entry {
        (a, _) = _find_assignment(self.id);
        if a is None {
            report OpResult(ok=False, message="No such assignment");
            return;
        }
        title = a.title;
        del a;
        report OpResult(ok=True, message="Deleted " + title);
    }
}

walker set_subtasks {
    has id: str = "",
        subtasks: list[str] = [],
        done: list[bool] = [],
        reports: list[AssignmentView] = [];

    can update with Root entry {
        (a, c) = _find_assignment(self.id);
        if a is None {
            return;
        }
        steps = [s.strip() for s in self.subtasks if s.strip()];
        flags = [bool(self.done[i]) if i < len(self.done) else False for i in range(len(steps))];
        a.subtasks = steps;
        a.subtasks_done = flags;
        report _assignment_view(a, c, lg.now_local());
    }
}

walker toggle_subtask {
    has id: str = "",
        index: int = 0,
        reports: list[AssignmentView] = [];

    can update with Root entry {
        (a, c) = _find_assignment(self.id);
        if a is None or self.index < 0 or self.index >= len(a.subtasks) {
            return;
        }
        flags = [bool(x) for x in a.subtasks_done];
        while len(flags) < len(a.subtasks) {
            flags.append(False);
        }
        flags[self.index] = not flags[self.index];
        a.subtasks_done = flags;
        now = lg.now_local();
        if all(flags) and a.status == "todo" {
            _set_status(a, "doing", now);
        } elif `any(flags) and a.status == "todo" {
            _set_status(a, "doing", now);
        }
        report _assignment_view(a, c, now);
    }
}

walker breakdown {
    has id: str = "",
        reports: list[AssignmentView] = [];

    can suggest with Root entry {
        (a, c) = _find_assignment(self.id);
        if a is None {
            return;
        }
        (steps, _) = adv.suggest_steps(
            a.title, c.code if c is not None else "", a.source, a.notes
        );
        a.subtasks = steps;
        a.subtasks_done = [False for _ in steps];
        report _assignment_view(a, c, lg.now_local());
    }
}

# ============================================================ settings ====

def _settings_view(p: Profile) -> SettingsView {
    token = p.canvas_token;
    return SettingsView(
        display_name=p.display_name,
        canvas_url=p.canvas_url,
        has_token=bool(token),
        token_hint=("…" + token[-4:]) if len(token) >= 8 else "",
        has_feed=bool(p.canvas_feed_url),
        has_gcal=bool(p.gcal_url),
        gcal_count=len(gc.load_events(p.gcal_events)),
        gcal_synced=p.gcal_synced,
        last_sync=p.last_sync,
        last_sync_summary=p.last_sync_summary,
        ai_ready=bool(adv.ai_model_name()),
        ai_model=adv.ai_model_name()
    );
}

walker get_settings {
    has reports: list[SettingsView] = [];

    can read with Root entry {
        report _settings_view(_profile());
    }
}

walker save_settings {
    has display_name: str = "",
        canvas_url: str = "",
        canvas_token: str = "",
        canvas_feed_url: str = "",
        clear_token: bool = False,
        reports: list[SettingsView] = [];

    can save with Root entry {
        p = _profile();
        p.display_name = self.display_name.strip();
        if self.canvas_url.strip() {
            p.canvas_url = cv.clean_base(self.canvas_url);
        }
        # clear_token disconnects Canvas entirely: token and calendar feed.
        if self.clear_token {
            p.canvas_token = "";
            p.canvas_feed_url = "";
        } else {
            if self.canvas_token.strip() {
                p.canvas_token = self.canvas_token.strip();
            }
            if self.canvas_feed_url.strip() {
                p.canvas_feed_url = cv.clean_feed_url(self.canvas_feed_url);
            }
        }
        report _settings_view(p);
    }
}

"""Store (or with `clear`, remove) the Google Calendar iCal link."""
walker save_calendar {
    has url: str = "",
        clear: bool = False,
        reports: list[SettingsView] = [];

    can save with Root entry {
        p = _profile();
        if self.clear {
            p.gcal_url = "";
            p.gcal_events = "";
            p.gcal_synced = "";
        } elif self.url.strip() {
            p.gcal_url = gc.clean_calendar_url(self.url);
        }
        report _settings_view(p);
    }
}

"""Re-download the calendar, keeping events from last week to ~4 months out."""
def _refresh_calendar(prof: Profile, now: datetime) -> int {
    text = gc.fetch_calendar(prof.gcal_url);
    lo = lg.start_of_week(now) - timedelta(days=7);
    events = gc.parse_calendar(text, lo, now + timedelta(days=120));
    prof.gcal_events = gc.dump_events(events);
    prof.gcal_synced = lg.to_iso(now);
    return len(events);
}

# ========================================================= canvas sync ====

"""Create or update the assignment for a Canvas item.

A calendar-feed item (`from_feed`) has no points or submission status: the
stored points are left alone, and an assignment that is already past due when
it is first imported is assumed submitted and marked done."""
def _apply_canvas_item(
    course: Course,
    item: CanvasAssignment,
    now: datetime,
    result: SyncResult,
    from_feed: bool = False
) {
    existing: Assignment | None = None;
    for a in [course -->[?:Assignment]] {
        if a.canvas_id == item.canvas_id {
            existing = a;
            break;
        }
    }
    link = item.external_url if item.source == "autograder" and item.external_url else item.url;
    if existing is None {
        due = lg.parse_iso(item.due);
        stale = due is not None and due < now - timedelta(days=14);
        if stale and not item.submitted and item.score is None {
            return;
        }
        made = Assignment(
            title=item.title,
            source=item.source,
            due=item.due,
            points=item.points,
            category=item.category,
            url=link,
            score=item.score,
            canvas_id=item.canvas_id,
            created=lg.to_iso(now)
        );
        if item.submitted or item.score is not None or (from_feed and due is not None and due < now) {
            made.status = "done";
            made.completed = item.due or lg.to_iso(now);
        }
        course ++> made;
        result.assignments_added += 1;
        return;
    }
    changed = False;
    points = existing.points if from_feed else item.points;
    if existing.title != item.title or existing.due != item.due or existing.points != points {
        existing.title = item.title;
        existing.due = item.due;
        existing.points = points;
        changed = True;
    }
    if item.category and existing.category != item.category {
        existing.category = item.category;
        changed = True;
    }
    if not existing.url and link {
        existing.url = link;
    }
    if item.score is not None and existing.score != item.score {
        existing.score = item.score;
        changed = True;
    }
    if (item.submitted or item.score is not None) and existing.status != "done" {
        _set_status(existing, "done", now);
        result.marked_done += 1;
    }
    if changed {
        result.assignments_updated += 1;
    }
}

"""The planner course for a Canvas course: linked by Canvas id, else matched
by code, else created."""
def _link_canvas_course(rc: CanvasCourse, now: datetime, result: SyncResult) -> Course {
    course: Course | None = None;
    if rc.canvas_id {
        for c in [root -->[?:Course]] {
            if c.canvas_id == rc.canvas_id {
                course = c;
            }
        }
    }
    if course is None {
        course = _course_by_ref(rc.code);
        if course is not None {
            result.courses_matched += 1;
        }
    }
    if course is None {
        course = Course(
            code=rc.code,
            name=rc.name,
            color=_next_color(),
            term=rc.term,
            created=lg.to_iso(now)
        );
        root ++> course;
        result.courses_added += 1;
    }
    if rc.canvas_id {
        course.canvas_id = rc.canvas_id;
    }
    if rc.url {
        course.canvas_url = rc.url;
    }
    if not course.name {
        course.name = rc.name;
    }
    if not course.term {
        course.term = rc.term;
    }
    return course;
}

"""Sync from the private calendar feed, for schools without student tokens."""
def _sync_feed(prof: Profile, now: datetime, result: SyncResult) {
    try {
        entries = cv.fetch_feed(prof.canvas_feed_url);
    } except CanvasError as e {
        result.message = e.message;
        return;
    }
    courses: dict[str, Course] = {};
    for (rc, item) in entries {
        key = str(rc.canvas_id) if rc.canvas_id else rc.code;
        if key not in courses {
            courses[key] = _link_canvas_course(rc, now, result);
        }
        _apply_canvas_item(courses[key], item, now, result, from_feed=True);
    }
    result.ok = True;
    result.message = (
        f"Synced {len(courses)} courses from the calendar feed: {result.assignments_added} new, "
        + f"{result.assignments_updated} updated."
    );
}

walker sync_canvas {
    has reports: list[SyncResult] = [];

    can sync with Root entry {
        prof = _profile();
        result = SyncResult();
        now = lg.now_local();
        cal_note = "";
        if prof.gcal_url {
            try {
                cal_note = f" Google Calendar: {_refresh_calendar(prof, now)} events.";
            } except gc.CalendarError as e {
                result.errors.append("Google Calendar: " + e.message);
            }
        }
        if not prof.canvas_token and not prof.canvas_feed_url {
            if prof.gcal_url {
                result.ok = not result.errors;
                result.message = cal_note.strip() or "Google Calendar sync failed.";
                if result.ok {
                    prof.last_sync = lg.to_iso(now);
                    prof.last_sync_summary = result.message;
                }
            } else {
                result.message = "Add a Canvas calendar feed or access token in Settings first.";
            }
            report result;
            return;
        }
        if not prof.canvas_token {
            _sync_feed(prof, now, result);
            result.message += cal_note;
            if result.ok {
                prof.last_sync = lg.to_iso(now);
                prof.last_sync_summary = result.message;
            }
            report result;
            return;
        }
        try {
            remote = cv.fetch_courses(prof.canvas_url, prof.canvas_token);
        } except CanvasError as e {
            result.message = e.message;
            report result;
            return;
        }
        for rc in remote {
            course = _link_canvas_course(rc, now, result);
            try {
                (items, weights) = cv.fetch_course_work(
                    prof.canvas_url, prof.canvas_token, rc.canvas_id
                );
            } except CanvasError as e {
                result.errors.append(rc.code + ": " + e.message);
                continue;
            }
            if weights and rc.apply_weights and not course.weights {
                course.weights = weights;
            }
            for item in items {
                _apply_canvas_item(course, item, now, result);
            }
        }
        result.ok = True;
        result.message = (
            f"Synced {len(remote)} courses: {result.assignments_added} new, "
            + f"{result.assignments_updated} updated, {result.marked_done} marked done."
            + cal_note
        );
        prof.last_sync = lg.to_iso(now);
        prof.last_sync_summary = result.message;
        report result;
    }
}

# ================================================================= AI ====

walker study_plan {
    has hours: float = 3.0,
        goal: str = "",
        use_ai: bool = True,
        reports: list[StudyPlan] = [];

    can plan with Root entry {
        now = lg.now_local();
        briefs: list[TaskBrief] = [];
        meta: dict[str, tuple[str, str]] = {};
        for (a, c) in _all_assignments() {
            if a.status == "done" {
                continue;
            }
            d = lg.parse_iso(a.due);
            remaining = [
                s
                for (i, s) in enumerate(a.subtasks)
                if not (i < len(a.subtasks_done) and a.subtasks_done[i])
            ];
            ref = jid(a);
            briefs.append(
                TaskBrief(
                    ref=ref,
                    title=a.title,
                    course=c.code if c is not None else "Personal",
                    source=a.source,
                    status=a.status,
                    priority=a.priority,
                    hours_until_due=None if d is None else round(
                        (d - now).total_seconds() / 3600.0, 1
                    ),
                    est_hours=a.est_hours,
                    open_steps=remaining[:5]
                )
            );
            meta[ref] = (c.code if c is not None else "Personal", c.color if c is not None else "#64748b");
        }
        busy: list[Busy] = [];
        for offset in range(2) {
            day = lg.start_of_day(now) + timedelta(days=offset);
            for s in _slots_on(day, now) {
                b0 = lg.parse_iso(day.strftime("%Y-%m-%dT") + s.start);
                b1 = lg.parse_iso(day.strftime("%Y-%m-%dT") + s.end);
                if b0 is not None and b1 is not None {
                    busy.append(Busy(start=b0, end=b1));
                }
            }
        }
        report adv.build_plan(briefs, meta, busy, now, self.hours, self.goal, self.use_ai);
    }
}

# =============================================================== export ====

def _ics_escape(text: str) -> str {
    return text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace(
        "\n", "\\n"
    );
}

walker export_ics {
    has include_done: bool = False,
        reports: list[str] = [];

    can export with Root entry {
        now = lg.now_local();
        lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//personal-planner//jac//EN",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:Planner deadlines"
        ];
        stamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ");
        for (a, c) in _all_assignments() {
            d = lg.parse_iso(a.due);
            if d is None or (a.status == "done" and not self.include_done) {
                continue;
            }
            code = c.code if c is not None else "Personal";
            start = d - timedelta(minutes=30);
            lines.extend(
                [
                    "BEGIN:VEVENT",
                    "UID:" + jid(a) + "@personal-planner",
                    "DTSTAMP:" + stamp,
                    "DTSTART:" + start.strftime("%Y%m%dT%H%M%S"),
                    "DTEND:" + d.strftime("%Y%m%dT%H%M%S"),
                    "SUMMARY:" + _ics_escape(f"[{code}] {a.title} due"),
                    "DESCRIPTION:" + _ics_escape(
                        f"Submit via {a.source}. {a.url}".strip()
                    ),
                    "BEGIN:VALARM",
                    "TRIGGER:-PT24H",
                    "ACTION:DISPLAY",
                    "DESCRIPTION:" + _ics_escape(a.title + " is due tomorrow"),
                    "END:VALARM",
                    "END:VEVENT"
                ]
            );
        }
        lines.append("END:VCALENDAR");
        _ = now;
        report "\r\n".join(lines) + "\r\n";
    }
}

# ================================================================= demo ====

walker load_demo {
    """Seed a realistic semester so the planner can be explored without Canvas."""
    has reports: list[OpResult] = [];

    can seed with Root entry {
        if [root -->[?:Course]] {
            report OpResult(ok=False, message="You already have courses - demo data is only loaded into an empty planner.");
            return;
        }
        now = lg.now_local();
        today = lg.start_of_day(now);

        def at(days: int, hhmm: str) -> str {
            (h, m) = hhmm.split(":");
            return lg.to_iso(today + timedelta(days=days, hours=int(h), minutes=int(m)));
        }

        specs = [
            (
                "EECS 482",
                "Introduction to Operating Systems",
                "https://eecs482.org",
                {"Projects": 50.0, "Midterm": 20.0, "Final": 30.0},
                [("Lecture", [0, 2], "10:30", "12:00", "Chrysler 220"), ("Discussion", [4], "13:30", "14:30", "DOW 1013")]
            ),
            (
                "EECS 449",
                "Conversational AI",
                "https://eecs449.org",
                {"Assignments": 40.0, "Project": 40.0, "Participation": 20.0},
                [("Lecture", [1, 3], "12:00", "13:30", "BBB 1670")]
            ),
            (
                "MATH 217",
                "Linear Algebra",
                "",
                {"Homework": 30.0, "Exams": 70.0},
                [("Lecture", [0, 2, 4], "09:00", "10:00", "East Hall 1360"), ("Office Hours", [3], "15:00", "16:00", "EH 2847")]
            )
        ];
        made: dict[str, Course] = {};
        for (i, (code, name, site, weights, meets)) in enumerate(specs) {
            c = Course(
                code=code,
                name=name,
                color=PALETTE[i],
                term="Fall 2026",
                website_url=site,
                canvas_url="https://umich.instructure.com",
                gradescope_url="https://www.gradescope.com" if code != "EECS 482" else "",
                autograder_url="https://autograder.io" if code == "EECS 482" else "",
                weights=weights,
                created=lg.to_iso(now)
            );
            root ++> c;
            for (kind, days, s, e, loc) in meets {
                c ++> Meeting(kind=kind, days=days, start=s, end=e, location=loc);
            }
            made[code] = c;
        }
        work = [
            ("EECS 482", "Project 1: Disk scheduler", "autograder", -20, "23:59", "Projects", 100.0, 97.0, 8.0),
            ("EECS 482", "Project 2: Thread library", "autograder", 4, "23:59", "Projects", 100.0, None, 20.0),
            ("EECS 482", "Midterm exam", "other", 12, "18:00", "Midterm", 100.0, None, 10.0),
            ("EECS 482", "Project 2 partner eval", "canvas", 5, "12:00", "Projects", 0.0, None, 0.25),
            ("EECS 449", "Assignment 1: Personal planner in Jac", "canvas", 7, "23:59", "Assignments", 10.0, None, 10.0),
            ("EECS 449", "Reading response 4", "canvas", 0, "23:59", "Participation", 5.0, None, 1.0),
            ("EECS 449", "Reading response 3", "canvas", -7, "23:59", "Participation", 5.0, 5.0, 1.0),
            ("MATH 217", "Problem set 3", "gradescope", -10, "20:00", "Homework", 20.0, 18.0, 4.0),
            ("MATH 217", "Problem set 4", "gradescope", 1, "20:00", "Homework", 20.0, None, 4.0),
            ("MATH 217", "Problem set 2", "gradescope", -2, "20:00", "Homework", 20.0, None, 4.0),
            ("MATH 217", "Exam 1", "other", 16, "18:00", "Exams", 100.0, None, 12.0)
        ];
        for (code, title, source, days, hhmm, cat, pts, score, est) in work {
            a = Assignment(
                title=title,
                source=source,
                due=at(days, hhmm),
                category=cat,
                points=pts,
                score=score,
                est_hours=est,
                priority=3 if "Project 2" in title else 2,
                created=lg.to_iso(now)
            );
            if score is not None {
                a.status = "done";
                a.completed = a.due;
            }
            if title == "Problem set 2" {
                a.status = "doing";
                a.notes = "Stuck on 4b - go to Thursday office hours";
            }
            made[code] ++> a;
        }
        root ++> Assignment(
            title="Renew bus pass",
            source="other",
            due=at(2, "17:00"),
            priority=1,
            created=lg.to_iso(now)
        );
        p = _profile();
        if not p.display_name {
            p.display_name = "Wolverine";
        }
        report OpResult(ok=True, message="Loaded a demo semester: 3 courses, 12 assignments.");
    }
}
