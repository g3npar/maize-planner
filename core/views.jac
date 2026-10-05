"""View models: the typed shapes every client (web, phone, CLI) receives.

The planner service never hands raw graph nodes across the wire. Each walker
reports one of these plain `obj`s, with dates and deadlines already formatted
on the server, so the three clients render identical text.
"""

obj OpResult {
    has ok: bool = True,
        message: str = "",
        id: str = "";
}

obj MeetingView {
    has id: str = "",
        course_id: str = "",
        kind: str = "Lecture",
        days: list[int] = [],
        days_label: str = "",
        start: str = "",
        end: str = "",
        time_label: str = "",
        location: str = "";
}

obj CategoryGrade {
    has name: str = "",
        weight: float = 0.0,
        earned: float = 0.0,
        possible: float = 0.0,
        pct: float | None = None,
        graded: int = 0,
        remaining: int = 0;
}

obj GradeSummary {
    has current: float | None = None,
        letter: str = "",
        graded_count: int = 0,
        total_count: int = 0,
        weighted: bool = False,
        categories: list[CategoryGrade] = [],
        needed: float | None = None,
        note: str = "";
}

obj CourseView {
    has id: str = "",
        code: str = "",
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
        meetings: list[MeetingView] = [],
        open_count: int = 0,
        overdue_count: int = 0,
        next_due: str = "",
        grade: GradeSummary = GradeSummary();
}

obj AssignmentView {
    has id: str = "",
        short_id: str = "",
        course_id: str = "",
        course_code: str = "",
        course_color: str = "#64748b",
        title: str = "",
        source: str = "other",
        due: str = "",
        due_label: str = "",
        due_in: str = "",
        due_date: str = "",
        urgency: str = "none",
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
        from_canvas: bool = False;
}

obj ClassSlot {
    has course_id: str = "",
        course_code: str = "",
        color: str = "#2563eb",
        kind: str = "",
        day: int = 0,
        start: str = "",
        end: str = "",
        time_label: str = "",
        location: str = "",
        state: str = "upcoming";
}

obj DayColumn {
    has date: str = "",
        label: str = "",
        weekday: str = "",
        is_today: bool = False,
        classes: list[ClassSlot] = [],
        due: list[AssignmentView] = [];
}

obj WeekView {
    has start: str = "",
        label: str = "",
        days: list[DayColumn] = [];
}

obj Stats {
    has open: int = 0,
        overdue: int = 0,
        due_today: int = 0,
        due_week: int = 0,
        done_week: int = 0,
        hours_week: float = 0.0;
}

obj Dashboard {
    has greeting: str = "",
        date_label: str = "",
        now: str = "",
        overdue: list[AssignmentView] = [],
        today: list[AssignmentView] = [],
        tomorrow: list[AssignmentView] = [],
        week: list[AssignmentView] = [],
        classes_today: list[ClassSlot] = [],
        next_class: ClassSlot | None = None,
        stats: Stats = Stats(),
        course_count: int = 0,
        canvas_connected: bool = False,
        calendar_connected: bool = False,
        last_sync: str = "";
}

obj SettingsView {
    has display_name: str = "",
        canvas_url: str = "",
        has_token: bool = False,
        token_hint: str = "",
        has_feed: bool = False,
        has_gcal: bool = False,
        gcal_count: int = 0,
        gcal_synced: str = "",
        last_sync: str = "",
        last_sync_summary: str = "",
        ai_ready: bool = False,
        ai_model: str = "";
}

obj SyncResult {
    has ok: bool = False,
        message: str = "",
        courses_added: int = 0,
        courses_matched: int = 0,
        assignments_added: int = 0,
        assignments_updated: int = 0,
        marked_done: int = 0,
        errors: list[str] = [];
}

obj PlanBlock {
    has start: str = "",
        end: str = "",
        minutes: int = 0,
        title: str = "",
        course_code: str = "",
        color: str = "#2563eb",
        assignment_id: str = "",
        reason: str = "";
}

obj StudyPlan {
    has source: str = "heuristic",
        summary: str = "",
        blocks: list[PlanBlock] = [],
        tips: list[str] = [],
        note: str = "";
}

obj QuickParse {
    has title: str = "",
        course_code: str = "",
        due: str = "",
        source: str = "other",
        priority: int = 2,
        points: float = 0.0;
}

"""Everything a screen shows, in one response (see the `load_all` walker)."""
obj Snapshot {
    has dashboard: Dashboard | None = None,
        courses: list[CourseView] = [],
        assignments: list[AssignmentView] = [],
        week: WeekView | None = None,
        gradebook: list[AssignmentView] | None = None;
}
