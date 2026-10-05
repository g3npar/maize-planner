"""Every assignment, filterable by status, class, where it's submitted, and text."""

import from "lucide-react" { Plus, Search }
import from core.planner { AssignmentView }
import from core.state { Planner, source_label }
import from .ui { AssignmentRow, Empty }

def matches(a: AssignmentView, needle: str) -> bool {
    if not needle {
        return True;
    }
    hay = (a.title + " " + a.course_code + " " + a.category + " " + a.notes).lower();
    return needle.lower() in hay;
}

def:pub TasksPage(
    p: Planner,
    onOpen: Callable[[AssignmentView], None],
    onNew: Callable[[], None]
) -> JsxElement {
    shown = [a for a in p.assignments if matches(a, p.search.strip())];
    groups: list[tuple[str, str, list[AssignmentView]]] = [];
    if p.filterStatus == "open" {
        buckets = [
            ("overdue", "Overdue", "#dc2626"),
            ("today", "Today", "#ea580c"),
            ("tomorrow", "Tomorrow", "#ca8a04"),
            ("week", "Next 7 days", "#2563eb"),
            ("later", "Later", "#64748b"),
            ("none", "No due date", "#94a3b8")
        ];
        for (key, label, color) in buckets {
            items = [a for a in shown if a.urgency == key];
            if items {
                groups.append((label, color, items));
            }
        }
    } else {
        groups.append(("", "", shown));
    }

    <>
        <div className="toolbar">
            <div className="seg">
                {for (key, label) in [("open", "Open"), ("done", "Done"), ("all", "All")] {
                    <button key={key} className={"on" if p.filterStatus == key else ""} onClick={lambda (e: MouseEvent) { p.setFilterStatus(key); }}>{label}</button>
                }}
            </div>
            <select className="select" value={p.filterCourse} onChange={lambda (e: ChangeEvent) { p.setFilterCourse(e.target.value); }}>
                <option value="">All classes</option>
                {for c in p.courses { <option key={c.id} value={c.id}>{c.code}</option> }}
            </select>
            <select className="select" value={p.filterSource} onChange={lambda (e: ChangeEvent) { p.setFilterSource(e.target.value); }}>
                <option value="">Anywhere</option>
                {for s in ["canvas", "gradescope", "autograder", "other"] {
                    <option key={s} value={s}>{source_label(s)}</option>
                }}
            </select>
            <div className="quickadd" style={{"margin": "0", "maxWidth": "260px", "boxShadow": "none"}}>
                <Search size={15} className="muted"/>
                <input value={p.search} placeholder="Search titles, notes…" onChange={lambda (e: ChangeEvent) { p.setSearch(e.target.value); }}/>
            </div>
            <span className="grow"></span>
            <button className="btn primary" onClick={lambda (e: MouseEvent) { onNew(); }}><Plus size={16}/> New assignment</button>
        </div>
        <div className="card">
            {not shown and <Empty
                title={"No matches" if p.search else ("All caught up!" if p.filterStatus == "open" else "Nothing here yet")}
                hint={"Try a different search." if p.search else "Use the bar at the top to add something in plain English."}
                emoji={"🔎" if p.search else "🎉"}
            />}
            {for (label, color, items) in groups {
                <div key={label or "all"}>
                    {label and <div className="section-title">
                        <span style={{"color": color}}>●</span>{label}<span className="muted">{str(len(items))}</span>
                    </div>}
                    <div className="list">
                        {for a in items {
                            <AssignmentRow key={a.id} a={a} busy={p.busyId == a.id} onToggle={p.toggleDone} onOpen={onOpen}/>
                        }}
                    </div>
                </div>
            }}
        </div>
    </>
}
