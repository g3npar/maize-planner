"""Today: what is overdue, due soon, and where you need to be."""

import from "lucide-react" {
    AlertTriangle,
    CalendarClock,
    CalendarDays,
    CheckCircle2,
    Clock,
    MapPin,
    RefreshCw,
    Sparkles,
    Timer,
    BookOpen,
    Plus,
    Link2
}
import from core.planner { AssignmentView, ClassSlot }
import from core.state { Planner }
import from .ui { AssignmentRow, CourseChip, Empty, Stat }

def:pub Group(
    title: str,
    items: list[AssignmentView],
    color: str,
    p: Planner,
    onOpen: Callable[[AssignmentView], None],
    bulk: bool = False
) -> JsxElement {
    shown = p.visible(items);
    if not shown {
        return <></>;
    }
    <div>
        <div className="section-title">
            <span style={{"color": color}}>●</span>{title}
            <span className="muted">{str(len(shown))}</span>
            {bulk and len(shown) > 1 and <>
                <span className="spacer"></span>
                <button className="btn ghost sm" style={{"textTransform": "none", "letterSpacing": "normal"}} onClick={lambda (e: MouseEvent) {
                    if window.confirm(f"Mark all {len(shown)} {title.lower()} assignments done?") {
                        p.markDone([a.id for a in shown]);
                    }
                }}><CheckCircle2 size={14}/> Mark all done</button>
            </>}
        </div>
        <div className="list">
            {for a in shown {
                <AssignmentRow
                    key={a.id}
                    a={a}
                    busy={p.busyId == a.id}
                    onToggle={p.toggleDone}
                    onOpen={onOpen}
                />
            }}
        </div>
    </div>
}

def:pub ClassLine(s: ClassSlot) -> JsxElement {
    <div className={"block" + (" past" if s.state == "past" else "") + (" now" if s.state == "now" else "")} style={{"--chip": s.color}}>
        <div className="row-flex" style={{"justifyContent": "space-between"}}>
            <span className="n">{s.course_code} · {s.kind}</span>
            {s.state == "now" and <span className="badge" style={{"--chip": s.color}}>Now</span>}
        </div>
        <div className="t row-flex" style={{"gap": "10px"}}>
            <span className="row-flex" style={{"gap": "4px"}}><Clock size={12}/>{s.time_label}</span>
            {s.location and <span className="row-flex" style={{"gap": "4px"}}><MapPin size={12}/>{s.location}</span>}
        </div>
    </div>
}

def:pub TodayPage(
    p: Planner,
    onOpen: Callable[[AssignmentView], None],
    go: Callable[[str], None],
    onNewCourse: Callable[[], None]
) -> JsxElement {
    d = p.dashboard;
    if d is None {
        return <div className="card"><Empty title="Loading your planner…" emoji="⏳"/></div>;
    }
    s = d.stats;
    nothing = not d.overdue and not d.today and not d.tomorrow and not d.week;

    <>
        <div className="hero">
            <div>
                <h2>{d.greeting} 👋</h2>
                <p>{d.date_label} · {str(s.due_week)} due in the next 7 days</p>
            </div>
            <div className="row-flex">
                <button className="btn" onClick={lambda (e: MouseEvent) { go("plan"); }}>
                    <Sparkles size={16}/> Plan my session
                </button>
                {(d.canvas_connected or d.calendar_connected) and <button
                    className="btn"
                    disabled={p.syncBusy}
                    onClick={lambda (e: MouseEvent) { p.syncCanvas(); }}
                >
                    <RefreshCw size={16} className={"spin" if p.syncBusy else ""}/>
                    {"Syncing…" if p.syncBusy else ("Sync Canvas" if d.canvas_connected else "Sync calendar")}
                </button>}
            </div>
        </div>

        {d.course_count == 0 and <div className="card">
            <div className="card-head"><h2>Let's set up your semester</h2></div>
            <div className="grid-cards">
                <div className="stack">
                    <div className="row-flex"><Link2 size={18}/><b>Connect Canvas</b></div>
                    <div className="muted small">Paste your Canvas calendar feed link and every course and deadline is imported — Gradescope and Autograder assignments get tagged automatically.</div>
                    <div><button className="btn primary sm" onClick={lambda (e: MouseEvent) { go("settings"); }}>Open settings</button></div>
                </div>
                <div className="stack">
                    <div className="row-flex"><BookOpen size={18}/><b>Add a class by hand</b></div>
                    <div className="muted small">Course code, meeting times, grade weights and links to its Gradescope / Autograder pages.</div>
                    <div><button className="btn sm" onClick={lambda (e: MouseEvent) { onNewCourse(); }}><Plus size={14}/> Add class</button></div>
                </div>
                <div className="stack">
                    <div className="row-flex"><Sparkles size={18}/><b>Just exploring?</b></div>
                    <div className="muted small">Load a realistic demo semester (EECS 482, EECS 449, MATH 217) to try every feature.</div>
                    <div><button className="btn maize sm" onClick={lambda (e: MouseEvent) { p.loadDemo(); }}>Load demo semester</button></div>
                </div>
            </div>
        </div>}

        <div className="stats">
            <Stat label="Overdue" value={str(s.overdue)} alert={s.overdue > 0} icon={<AlertTriangle size={14}/>}/>
            <Stat label="Due today" value={str(s.due_today)} icon={<CalendarClock size={14}/>}/>
            <Stat label="Next 7 days" value={str(s.due_week)} icon={<CalendarDays size={14}/>}/>
            <Stat label="Done this week" value={str(s.done_week)} icon={<CheckCircle2 size={14}/>}/>
            <Stat label="Est. hours this week" value={f"{s.hours_week:g}"} icon={<Timer size={14}/>}/>
        </div>

        <div className="grid-2">
            <div className="card">
                <div className="card-head">
                    <h2>Up next</h2>
                    <span className="spacer"></span>
                    <button className="btn ghost sm" onClick={lambda (e: MouseEvent) { go("tasks"); }}>All assignments →</button>
                </div>
                {nothing and <Empty
                    title="Nothing due in the next week"
                    hint="Add something with the bar above - try “eecs482 p3 due fri 11:59pm #ag”."
                    emoji="🎉"
                />}
                <Group title="Overdue" items={d.overdue} color="#dc2626" p={p} onOpen={onOpen} bulk={True}/>
                <Group title="Today" items={d.today} color="#ea580c" p={p} onOpen={onOpen}/>
                <Group title="Tomorrow" items={d.tomorrow} color="#ca8a04" p={p} onOpen={onOpen}/>
                <Group title="This week" items={d.week} color="#2563eb" p={p} onOpen={onOpen}/>
            </div>
            <div className="stack" style={{"gap": "20px"}}>
                <div className="card">
                    <div className="card-head">
                        <h2>Today's classes</h2>
                        <span className="spacer"></span>
                        <button className="btn ghost sm" onClick={lambda (e: MouseEvent) { go("week"); }}>Week →</button>
                    </div>
                    {not d.classes_today and <div className="muted small" style={{"padding": "4px 0 8px"}}>No classes today.</div>}
                    <div className="stack" style={{"gap": "8px"}}>
                        {for c in d.classes_today {
                            <ClassLine key={c.course_id + c.start} s={c}/>
                        }}
                    </div>
                    {d.next_class and not d.classes_today and <div style={{"marginTop": "6px"}}>
                        <div className="section-title">Next class · {d.next_class.state}</div>
                        <ClassLine s={d.next_class}/>
                    </div>}
                </div>
                <div className="card">
                    <div className="card-head">
                        <h2>Your classes</h2>
                        <span className="spacer"></span>
                        <button className="btn ghost sm" onClick={lambda (e: MouseEvent) { go("grades"); }}>Grades →</button>
                    </div>
                    {not p.courses and <div className="muted small">No classes yet.</div>}
                    <div className="stack" style={{"gap": "8px"}}>
                        {for c in p.courses {
                            <div key={c.id} className="row-flex" style={{"justifyContent": "space-between"}}>
                                <CourseChip code={c.code} color={c.color}/>
                                <span className="small muted">
                                    {str(c.open_count)} open
                                    {c.overdue_count > 0 and <b style={{"color": "var(--danger)"}}>{" · " + str(c.overdue_count) + " overdue"}</b>}
                                </span>
                                <span className="small" style={{"fontWeight": "700"}}>
                                    {(c.grade.letter + " · " + f"{c.grade.current:.1f}%") if c.grade.current is not None else "–"}
                                </span>
                            </div>
                        }}
                    </div>
                </div>
            </div>
        </div>
    </>
}
