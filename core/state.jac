"""Client state shared by the web app and the phone app.

`usePlanner()` is the single place a UI talks to the planner service: it owns
the session, every piece of server data, and every action (all walker spawns
live in `state.impl.jac`). The web renderer (HTML, `web/`) and the phone
renderer (React Native via mobUI, `core/phone/`) are both thin views over it,
so a feature added here shows up on both screens at once.
"""

import from core.planner {
    get_dashboard,
    get_week,
    list_courses,
    list_assignments,
    save_assignment,
    quick_add,
    set_status,
    set_status_many,
    set_score,
    delete_assignment,
    set_subtasks,
    toggle_subtask,
    breakdown,
    save_course,
    delete_course,
    add_meeting,
    delete_meeting,
    get_settings,
    save_settings,
    sync_canvas,
    study_plan,
    export_ics,
    load_demo,
    Dashboard,
    WeekView,
    CourseView,
    AssignmentView,
    MeetingView,
    SettingsView,
    SyncResult,
    StudyPlan,
    OpResult
}
import from "@jac/runtime" {
    jacLogin,
    jacSignup,
    jacLogout,
    jacIsLoggedIn,
    SignupResult,
    BridgeError,
    BridgeUnavailable,
    BridgeTimeout,
    BridgeRejected,
    __getLocalStorage,
    __setLocalStorage,
    __removeLocalStorage
}
import from "react" { useEffect }

glob POLL_MS: int = 30000,
     AUTO_SYNC_HOURS: int = 3,
     # Status writes still in flight; the reload waits for the last one.
     # A mutable glob, not hook state, so it is current after an await.
     PENDING: dict[str, int] = {"writes": 0};

# ---------------------------------------------------------------- drafts ----

obj AssignmentDraft {
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
        est_hours: float = 0.0;
}

obj CourseDraft {
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
        weights: dict[str, float] = {};
}

def:pub draft_from(a: AssignmentView) -> AssignmentDraft {
    return AssignmentDraft(
        id=a.id,
        course_id=a.course_id,
        title=a.title,
        source=a.source,
        due=a.due,
        priority=a.priority,
        category=a.category,
        points=a.points,
        url=a.url,
        notes=a.notes,
        est_hours=a.est_hours
    );
}

def:pub course_draft_from(c: CourseView) -> CourseDraft {
    return CourseDraft(
        id=c.id,
        code=c.code,
        name=c.name,
        color=c.color,
        term=c.term,
        instructor=c.instructor,
        canvas_url=c.canvas_url,
        gradescope_url=c.gradescope_url,
        autograder_url=c.autograder_url,
        website_url=c.website_url,
        target=c.target,
        weights=c.weights
    );
}

# --------------------------------------------------------------- session ----

obj Session {
    has loggedIn: bool,
        checking: bool,
        signup: bool,
        username: str,
        password: str,
        error: str,
        busy: bool,
        setUsername: Callable[[str], None],
        setPassword: Callable[[str], None],
        toggleMode: Callable[[], None],
        submit: Callable[[], None],
        logout: Callable[[], None];
}

def:pub stored_username -> str {
    return __getLocalStorage("planner_username") or "";
}

def:pub useSession -> Session {
    has loggedIn: bool = False,
        checking: bool = True,
        signup: bool = False,
        username: str = "",
        password: str = "",
        error: str = "",
        busy: bool = False;

    can with entry {
        loggedIn = jacIsLoggedIn();
        username = stored_username();
        checking = False;
    }

    async def submit -> None {
        if busy {
            return;
        }
        error = "";
        name = username.strip();
        if not name or not password {
            error = "Enter a username and password";
            return;
        }
        if signup and len(password) < 6 {
            error = "Use at least 6 characters for the password";
            return;
        }
        busy = True;
        ok: bool = False;
        made: SignupResult | None = None;
        try {
            if signup {
                made = await jacSignup(name, password);
                if made is None or not made.success {
                    error = (made.error if made is not None else "") or "That username is taken";
                    return;
                }
            }
            ok = await jacLogin(name, password);
            if ok {
                __setLocalStorage("planner_username", name);
                password = "";
                loggedIn = True;
            } else {
                error = "Wrong username or password";
            }
        } except Exception {
            error = "Can't reach the planner server - is `jac run` running?";
        } finally {
            busy = False;
        }
    }

    def logout {
        jacLogout();
        __removeLocalStorage("planner_username");
        loggedIn = False;
        password = "";
        error = "";
    }

    return Session(
        loggedIn=loggedIn,
        checking=checking,
        signup=signup,
        username=username,
        password=password,
        error=error,
        busy=busy,
        setUsername=lambda (v: str) { username = v; },
        setPassword=lambda (v: str) { password = v; },
        toggleMode=lambda {
            signup = not signup;
            error = "";
        },
        submit=submit,
        logout=logout
    );
}

# ---------------------------------------------------------------- planner ----

obj Planner {
    has session: Session,
        loading: bool,
        refreshing: bool,
        error: str,
        notice: str,
        dashboard: Dashboard | None,
        courses: list[CourseView],
        assignments: list[AssignmentView],
        gradebook: list[AssignmentView],
        filterCourse: str,
        filterSource: str,
        filterStatus: str,
        search: str,
        week: WeekView | None,
        weekOffset: int,
        settings: SettingsView | None,
        plan: StudyPlan | None,
        planBusy: bool,
        syncBusy: bool,
        syncResult: SyncResult | None,
        busyId: str,
        hiddenIds: list[str],
        refresh: Callable[[], None],
        setFilterCourse: Callable[[str], None],
        setFilterSource: Callable[[str], None],
        setFilterStatus: Callable[[str], None],
        setSearch: Callable[[str], None],
        loadWeek: Callable[[int], None],
        loadSettings: Callable[[], None],
        loadGradebook: Callable[[], None],
        quickAdd: Callable[[str], bool],
        saveAssignment: Callable[[AssignmentDraft], AssignmentView | None],
        setStatus: Callable[[str, str], None],
        toggleDone: Callable[[AssignmentView], None],
        markDone: Callable[[list[str]], None],
        visible: Callable[[list[AssignmentView]], list[AssignmentView]],
        setScore: Callable[[str, float | None, float], None],
        deleteAssignment: Callable[[str], None],
        toggleSubtask: Callable[[str, int], None],
        setSubtasks: Callable[[str, list[str], list[bool]], None],
        breakdown: Callable[[str], None],
        saveCourse: Callable[[CourseDraft], CourseView | None],
        deleteCourse: Callable[[str], None],
        addMeeting: Callable[[str, str, list[int], str, str, str], None],
        deleteMeeting: Callable[[str], None],
        saveSettings: Callable[[str, str, str, str, bool], None],
        syncCanvas: Callable[[], None],
        makePlan: Callable[[float, str, bool], None],
        loadDemo: Callable[[], None],
        exportIcs: Callable[[], str],
        findAssignment: Callable[[str], AssignmentView | None],
        say: Callable[[str], None],
        dismiss: Callable[[], None];
}

def:pub describe_error(e: any) -> str {
    if isinstance(e, BridgeUnavailable) {
        return "Can't reach the planner server. Is `jac run` still running?";
    }
    if isinstance(e, BridgeTimeout) {
        return "The server took too long to answer. Try again.";
    }
    if isinstance(e, BridgeRejected) {
        return "Your session expired - please sign in again.";
    }
    text = str(e);
    if "UNAUTHORIZED" in text or "Unauthorized" in text or "401" in text {
        return "Your session expired - please sign in again.";
    }
    return "Something went wrong: " + text[:140];
}

def:pub clear_read_cache {
    globalThis.__jacCacheState__ = None;
}

glob CHANGE_EVENT: str = "planner-changed";

def can_broadcast -> bool {
    host: any = globalThis.window;
    return bool(host) and bool(host.addEventListener) and bool(globalThis.CustomEvent);
}

"""Tell other planner views in this page (e.g. the embedded phone) to reload."""
def:pub announce_change(source: str) {
    if can_broadcast() {
        event_type: any = globalThis.CustomEvent;
        host: any = globalThis.window;
        host.dispatchEvent(new(event_type, CHANGE_EVENT, {"detail": {"source": source}}));
    }
}

def:pub usePlanner -> Planner {
    session = useSession();
    has loading: bool = True,
        refreshing: bool = False,
        error: str = "",
        notice: str = "",
        dashboard: Dashboard | None = None,
        courses: list[CourseView] = [],
        assignments: list[AssignmentView] = [],
        gradebook: list[AssignmentView] = [],
        filterCourse: str = "",
        filterSource: str = "",
        filterStatus: str = "open",
        search: str = "",
        week: WeekView | None = None,
        weekOffset: int = 0,
        settings: SettingsView | None = None,
        plan: StudyPlan | None = None,
        planBusy: bool = False,
        syncBusy: bool = False,
        syncResult: SyncResult | None = None,
        busyId: str = "",
        hiddenIds: list[str] = [],
        autoSynced: bool = False,
        instanceId: str = str(Math.random());

    async def refresh -> None;
    async def reloadList -> None;
    async def loadWeek(offset: int) -> None;
    async def loadSettings -> None;
    async def loadGradebook -> None;
    async def quickAdd(text: str) -> bool;
    async def saveAssignment(d: AssignmentDraft) -> AssignmentView | None;
    async def setStatus(id: str, status: str) -> None;
    async def toggleDone(a: AssignmentView) -> None;
    async def markDone(ids: list[str]) -> None;
    async def settle -> None;
    async def setScore(id: str, score: float | None, points: float) -> None;
    async def deleteAssignment(id: str) -> None;
    async def toggleSubtask(id: str, index: int) -> None;
    async def setSubtasks(id: str, steps: list[str], done: list[bool]) -> None;
    async def breakdownTask(id: str) -> None;
    async def saveCourse(d: CourseDraft) -> CourseView | None;
    async def deleteCourse(id: str) -> None;
    async def addMeeting(
        course_id: str, kind: str, days: list[int], start: str, end: str, location: str
    ) -> None;
    async def deleteMeeting(id: str) -> None;
    async def saveSettings(name: str, url: str, token: str, feed: str, clear: bool) -> None;
    async def syncCanvas -> None;
    async def makePlan(hours: float, goal: str, useAi: bool) -> None;
    async def loadDemo -> None;
    async def exportIcs -> str;
    def fail(e: any) -> None;
    def replaceItem(v: AssignmentView) -> None;

    can with [session.loggedIn] entry {
        if session.loggedIn {
            loading = True;
            refresh();
        } else {
            dashboard = None;
            courses = [];
            assignments = [];
            week = None;
            settings = None;
            plan = None;
            loading = False;
        }
    }

    can with (filterCourse, filterSource, filterStatus) entry {
        if session.loggedIn and not loading {
            reloadList();
        }
    }

    useEffect(
        lambda {
            timer = setInterval(
                lambda {
                    if session.loggedIn and jacIsLoggedIn() {
                        refreshing = True;
                        refresh();
                    }
                },
                POLL_MS
            );
            return lambda { clearInterval(timer); };
        },
        [session.loggedIn]
    );

    useEffect(
        lambda {
            if not can_broadcast() {
                return lambda {};
            }
            host: any = globalThis.window;
            handler = lambda (e: any) {
                if e.detail and e.detail.source != instanceId and jacIsLoggedIn() {
                    clear_read_cache();
                    refresh();
                }
            };
            host.addEventListener(CHANGE_EVENT, handler);
            return lambda { host.removeEventListener(CHANGE_EVENT, handler); };
        },
        [instanceId]
    );

    # New Canvas assignments only arrive on a sync, so sync on open when the
    # last one is more than AUTO_SYNC_HOURS old (once per page load).
    can with [dashboard] entry {
        d = dashboard;
        if d is None or autoSynced or syncBusy or not d.canvas_connected {
            return;
        }
        autoSynced = True;
        age_ms = Date.parse(d.now) - Date.parse(d.last_sync) if d.last_sync else Infinity;
        if not (age_ms < AUTO_SYNC_HOURS * 3600000) {
            syncCanvas();
        }
    }

    def visible(items: list[AssignmentView]) -> list[AssignmentView] {
        if not hiddenIds {
            return items;
        }
        return [a for a in items if a.id not in hiddenIds];
    }

    def findAssignment(id: str) -> AssignmentView | None {
        for a in assignments {
            if a.id == id {
                return a;
            }
        }
        if dashboard is not None {
            for group in [dashboard.overdue, dashboard.today, dashboard.tomorrow, dashboard.week] {
                for a in group {
                    if a.id == id {
                        return a;
                    }
                }
            }
        }
        return None;
    }

    return Planner(
        session=session,
        loading=loading,
        refreshing=refreshing,
        error=error,
        notice=notice,
        dashboard=dashboard,
        courses=courses,
        assignments=assignments,
        gradebook=gradebook,
        filterCourse=filterCourse,
        filterSource=filterSource,
        filterStatus=filterStatus,
        search=search,
        week=week,
        weekOffset=weekOffset,
        settings=settings,
        plan=plan,
        planBusy=planBusy,
        syncBusy=syncBusy,
        syncResult=syncResult,
        busyId=busyId,
        hiddenIds=hiddenIds,
        refresh=lambda {
            clear_read_cache();
            refresh();
        },
        setFilterCourse=lambda (v: str) { filterCourse = v; },
        setFilterSource=lambda (v: str) { filterSource = v; },
        setFilterStatus=lambda (v: str) { filterStatus = v; },
        setSearch=lambda (v: str) { search = v; },
        loadWeek=loadWeek,
        loadSettings=loadSettings,
        loadGradebook=loadGradebook,
        quickAdd=quickAdd,
        saveAssignment=saveAssignment,
        setStatus=setStatus,
        toggleDone=toggleDone,
        markDone=markDone,
        visible=visible,
        setScore=setScore,
        deleteAssignment=deleteAssignment,
        toggleSubtask=toggleSubtask,
        setSubtasks=setSubtasks,
        breakdown=breakdownTask,
        saveCourse=saveCourse,
        deleteCourse=deleteCourse,
        addMeeting=addMeeting,
        deleteMeeting=deleteMeeting,
        saveSettings=saveSettings,
        syncCanvas=syncCanvas,
        makePlan=makePlan,
        loadDemo=loadDemo,
        exportIcs=exportIcs,
        findAssignment=findAssignment,
        say=lambda (msg: str) { notice = msg; },
        dismiss=lambda {
            notice = "";
            error = "";
        }
    );
}

# ------------------------------------------------------ display helpers ----

glob SOURCE_LABELS: dict[str, str] = {
         "canvas": "Canvas",
         "gradescope": "Gradescope",
         "autograder": "Autograder",
         "other": "Other"
     },
     SOURCE_COLORS: dict[str, str] = {
         "canvas": "#e2432b",
         "gradescope": "#1a8a88",
         "autograder": "#7c3aed",
         "other": "#64748b"
     },
     URGENCY_COLORS: dict[str, str] = {
         "overdue": "#dc2626",
         "today": "#ea580c",
         "tomorrow": "#ca8a04",
         "week": "#2563eb",
         "later": "#64748b",
         "none": "#94a3b8",
         "done": "#16a34a"
     },
     WEEKDAYS: list[str] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
     COURSE_COLORS: list[str] = [
         "#2563eb",
         "#db2777",
         "#16a34a",
         "#ea580c",
         "#7c3aed",
         "#0891b2",
         "#ca8a04",
         "#dc2626",
         "#0f766e",
         "#475569"
     ];

def:pub source_label(source: str) -> str {
    return SOURCE_LABELS[source] if source in SOURCE_LABELS else "Other";
}

def:pub source_color(source: str) -> str {
    return SOURCE_COLORS[source] if source in SOURCE_COLORS else "#64748b";
}

def:pub urgency_color(urgency: str) -> str {
    return URGENCY_COLORS[urgency] if urgency in URGENCY_COLORS else "#64748b";
}

def:pub fmt_pct(value: float | None) -> str {
    if value is None {
        return "–";
    }
    return f"{value:.1f}%";
}

def:pub progress_of(a: AssignmentView) -> str {
    if not a.subtasks {
        return "";
    }
    done = len([x for x in a.subtasks_done if x]);
    return str(done) + "/" + str(len(a.subtasks));
}
