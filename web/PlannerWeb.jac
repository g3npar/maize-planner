"""The web app shell: navigation, quick add, modals and toasts.

All data and actions come from `usePlanner()` in core/state.jac - the same
hook the phone app renders - so this file is only layout and routing.
"""

import from "lucide-react" {
    LayoutDashboard,
    ListTodo,
    CalendarDays,
    BookOpen,
    GraduationCap,
    Sparkles,
    Settings,
    Smartphone,
    RefreshCw,
    Plus,
    X,
    LogOut
}
import from "react" { useEffect }
import from core.planner { AssignmentView, CourseView }
import from core.state {
    usePlanner,
    AssignmentDraft,
    CourseDraft,
    draft_from,
    course_draft_from,
    clear_read_cache
}
import from .AuthPage { AuthPage }
import from .TodayPage { TodayPage }
import from .TasksPage { TasksPage }
import from .WeekPage { WeekPage }
import from .ClassesPage { ClassesPage, CourseEditor }
import from .GradesPage { GradesPage }
import from .PlanPage { PlanPage }
import from .SettingsPage { SettingsPage }
import from .PhonePage { PhonePage }
import from .AssignmentEditor { AssignmentEditor }

glob TITLES: dict[str, str] = {
         "today": "Today",
         "tasks": "Assignments",
         "week": "Week",
         "classes": "Classes",
         "grades": "Grades",
         "plan": "Study plan",
         "settings": "Settings",
         "phone": "Phone app"
     };

def stored(key: str, fallback: str) -> str {
    try {
        return localStorage.getItem(key) or fallback;
    } except Exception {
        return fallback;
    }
}

def remember(key: str, value: str) {
    try {
        localStorage.setItem(key, value);
    } except Exception {}
}

def apply_theme(theme: str) {
    page: any = document.documentElement;
    if theme == "light" or theme == "dark" {
        page.setAttribute("data-theme", theme);
    } else {
        page.removeAttribute("data-theme");
    }
}

def save_file(filename: str, text: str, mime: str) {
    blob_type: any = globalThis.Blob;
    url_api: any = globalThis.URL;
    doc: any = document;
    blob: any = new(blob_type, [text], {"type": mime});
    href: str = url_api.createObjectURL(blob);
    link: any = doc.createElement("a");
    link.href = href;
    link.download = filename;
    doc.body.appendChild(link);
    link.click();
    link.remove();
    url_api.revokeObjectURL(href);
}

def:pub NavButton(
    id: str,
    label: str,
    icon: any,
    active: bool,
    onPick: Callable[[str], None],
    count: int = 0,
    hot: bool = False
) -> JsxElement {
    <button className={"nav-item" + (" active" if active else "")} onClick={lambda (e: MouseEvent) { onPick(id); }}>
        {icon}
        <span>{label}</span>
        {count > 0 and <span className={"count" + (" hot" if hot else "")}>{str(count)}</span>}
    </button>
}

def:pub PlannerWeb -> JsxElement {
    p = usePlanner();
    has tab: str = stored("planner_tab", "today"),
        editing: AssignmentDraft | None = None,
        editKey: int = 0,
        courseDraft: CourseDraft | None = None,
        quick: str = "",
        adding: bool = False,
        theme: str = stored("planner_theme", "system");

    can with entry {
        document.title = "Maize Planner";
    }

    can with [theme] entry {
        apply_theme(theme);
        remember("planner_theme", theme);
    }

    can with [p.notice] entry {
        if p.notice {
            shown = p.notice;
            setTimeout(
                lambda {
                    if shown == p.notice {
                        p.dismiss();
                    }
                },
                4500
            );
        }
    }

    useEffect(
        lambda {
            handler = lambda (e: KeyboardEvent) {
                target = e.target;
                typing = target and target.tagName in ["INPUT", "TEXTAREA", "SELECT"];
                if e.key == "/" and not typing {
                    e.preventDefault();
                    box: any = document.getElementById("quickadd");
                    if box {
                        box.focus();
                    }
                }
            };
            window.addEventListener("keydown", handler);
            return lambda { window.removeEventListener("keydown", handler); };
        },
        []
    );

    def go(next: str) {
        tab = next;
        remember("planner_tab", next);
    }

    def open_assignment(a: AssignmentView) {
        editing = draft_from(a);
        editKey = editKey + 1;
    }

    def new_assignment {
        editing = AssignmentDraft(course_id=p.filterCourse);
        editKey = editKey + 1;
    }

    def edit_course(d: CourseDraft) {
        courseDraft = d;
        editKey = editKey + 1;
    }

    def course_saved(c: CourseView) {
        courseDraft = course_draft_from(c);
        editKey = editKey + 1;
    }

    async def submit_quick -> None {
        text = quick.strip();
        if not text or adding {
            return;
        }
        adding = True;
        ok = await p.quickAdd(text);
        adding = False;
        if ok {
            quick = "";
        }
    }

    def quick_key(e: KeyboardEvent) {
        if e.key == "Enter" {
            e.preventDefault();
            submit_quick();
        }
        if e.key == "Escape" {
            quick = "";
            e.target.blur();
        }
    }

    async def export_ics -> None {
        text = await p.exportIcs();
        if text {
            save_file("planner.ics", text, "text/calendar");
            p.say("Downloaded planner.ics - import it into your calendar app.");
        }
    }

    if p.session.checking {
        return <div></div>;
    }
    if not p.session.loggedIn {
        return <AuthPage session={p.session}/>;
    }

    d = p.dashboard;
    overdue = d.stats.overdue if d is not None else 0;
    open_count = d.stats.open if d is not None else 0;
    initial = (p.session.username or "?")[0].upper();

    <div className="app">
        <nav className="sidebar">
            <div className="brand">
                <div className="brand-mark">M</div>
                <div>
                    <div className="brand-name">Maize Planner</div>
                    <div className="brand-sub">classes · deadlines · grades</div>
                </div>
            </div>
            <NavButton id="today" label="Today" icon={<LayoutDashboard size={18}/>} active={tab == "today"} onPick={go} count={overdue} hot={True}/>
            <NavButton id="tasks" label="Assignments" icon={<ListTodo size={18}/>} active={tab == "tasks"} onPick={go} count={open_count}/>
            <NavButton id="week" label="Week" icon={<CalendarDays size={18}/>} active={tab == "week"} onPick={go}/>
            <NavButton id="classes" label="Classes" icon={<BookOpen size={18}/>} active={tab == "classes"} onPick={go} count={len(p.courses)}/>
            <NavButton id="grades" label="Grades" icon={<GraduationCap size={18}/>} active={tab == "grades"} onPick={go}/>
            <NavButton id="plan" label="Study plan" icon={<Sparkles size={18}/>} active={tab == "plan"} onPick={go}/>
            <NavButton id="phone" label="Phone app" icon={<Smartphone size={18}/>} active={tab == "phone"} onPick={go}/>
            <div className="nav-spacer"></div>
            <NavButton id="settings" label="Settings" icon={<Settings size={18}/>} active={tab == "settings"} onPick={go}/>
            <div className="nav-foot">
                <div className="user-line">
                    <div className="avatar">{initial}</div>
                    <div className="grow">
                        <div style={{"fontWeight": "650"}}>{p.session.username or "Signed in"}</div>
                        <div className="tiny muted">{"Canvas connected" if d is not None and d.canvas_connected else "Canvas not connected"}</div>
                    </div>
                    <button className="btn ghost icon" title="Sign out" onClick={lambda (e: MouseEvent) { p.session.logout(); }}><LogOut size={16}/></button>
                </div>
            </div>
        </nav>
        <div className="main">
            <header className="topbar">
                <h1>{TITLES[tab] if tab in TITLES else "Planner"}</h1>
                <div className="quickadd">
                    <Plus size={16} className="muted"/>
                    <input
                        id="quickadd"
                        value={quick}
                        disabled={adding}
                        placeholder="Quick add: “eecs482 p3 due fri 11:59pm #ag !!”  ·  #gs #ag #canvas  ·  ! priority"
                        onChange={lambda (e: ChangeEvent) { quick = e.target.value; }}
                        onKeyDown={quick_key}
                    />
                    <span className="kbd">/</span>
                    <button className="btn primary sm" disabled={not quick.strip() or adding} onClick={lambda (e: MouseEvent) { submit_quick(); }}>Add</button>
                </div>
                <button className="btn icon" title="Refresh" onClick={lambda (e: MouseEvent) { p.refresh(); }}>
                    <RefreshCw size={16} className={"spin" if p.refreshing else ""}/>
                </button>
            </header>
            <main className="content">
                {tab == "today" and <TodayPage p={p} onOpen={open_assignment} go={go} onNewCourse={lambda { edit_course(CourseDraft()); }}/>}
                {tab == "tasks" and <TasksPage p={p} onOpen={open_assignment} onNew={new_assignment}/>}
                {tab == "week" and <WeekPage p={p} onOpen={open_assignment} onExport={export_ics}/>}
                {tab == "classes" and <ClassesPage p={p} onEdit={edit_course}/>}
                {tab == "grades" and <GradesPage p={p} onEdit={edit_course}/>}
                {tab == "plan" and <PlanPage p={p} onOpen={open_assignment}/>}
                {tab == "phone" and <PhonePage/>}
                {tab == "settings" and <SettingsPage p={p} theme={theme} onTheme={lambda (t: str) { theme = t; }} onExport={export_ics}/>}
            </main>
        </div>
        {editing is not None and <AssignmentEditor key={"a" + str(editKey)} p={p} draft={editing} onClose={lambda { editing = None; }}/>}
        {courseDraft is not None and <CourseEditor key={"c" + str(editKey)} p={p} draft={courseDraft} onClose={lambda { courseDraft = None; }} onSaved={course_saved}/>}
        <div className="toasts">
            {p.error and <div className="toast error">
                <span>{p.error}</span>
                <button onClick={lambda (e: MouseEvent) { p.dismiss(); }}><X size={15}/></button>
            </div>}
            {p.notice and <div className="toast">
                <span>{p.notice}</span>
                <button onClick={lambda (e: MouseEvent) { p.dismiss(); }}><X size={15}/></button>
            </div>}
        </div>
    </div>
}
