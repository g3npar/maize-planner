"""A seven-day grid: class meetings on top, deadlines underneath."""

import from "lucide-react" { ChevronLeft, ChevronRight, MapPin, Download }
import from core.planner { AssignmentView }
import from core.state { Planner, urgency_color }
import from .ui { Empty }

def due_time(a: AssignmentView) -> str {
    parts = a.due_label.split(" · ");
    return parts[len(parts) - 1];
}

def:pub WeekPage(
    p: Planner,
    onOpen: Callable[[AssignmentView], None],
    onExport: Callable[[], None]
) -> JsxElement {
    can with entry {
        if p.week is None {
            p.loadWeek(0);
        }
    }
    w = p.week;
    if w is None {
        return <div className="card"><Empty title="Loading your week…" emoji="⏳"/></div>;
    }

    <>
        <div className="toolbar">
            <button className="btn icon" onClick={lambda (e: MouseEvent) { p.loadWeek(p.weekOffset - 1); }} title="Previous week"><ChevronLeft size={17}/></button>
            <button className="btn" disabled={p.weekOffset == 0} onClick={lambda (e: MouseEvent) { p.loadWeek(0); }}>This week</button>
            <button className="btn icon" onClick={lambda (e: MouseEvent) { p.loadWeek(p.weekOffset + 1); }} title="Next week"><ChevronRight size={17}/></button>
            <h2 style={{"fontSize": "17px", "marginLeft": "6px"}}>{w.label}</h2>
            <span className="grow"></span>
            <button className="btn" onClick={lambda (e: MouseEvent) { onExport(); }}><Download size={15}/> Export to calendar (.ics)</button>
        </div>
        <div className="week">
            {for day in w.days {
                <div key={day.date} className={"day" + (" today" if day.is_today else "")}>
                    <div className="day-head">
                        <span className="wd">{day.weekday}</span>
                        <span className="muted small">{day.label}</span>
                    </div>
                    <div className="day-body">
                        {for s in day.classes {
                            <div key={s.course_id + s.start} className={"block" + (" past" if s.state == "past" else "") + (" now" if s.state == "now" else "")} style={{"--chip": s.color}}>
                                <div className="t">{s.time_label}</div>
                                <div className="n">{s.course_code}</div>
                                <div className="t">{s.kind}{(" · " + s.location) if s.location else ""}</div>
                            </div>
                        }}
                        {len(day.classes) > 0 and len(day.due) > 0 and <div style={{"borderTop": "1px dashed var(--border)", "margin": "4px 0"}}></div>}
                        {for a in day.due {
                            <div key={a.id} className={"due-pill" + (" done" if a.status == "done" else "")} onClick={lambda (e: MouseEvent) { onOpen(a); }} style={{"borderLeft": "3px solid " + a.course_color}}>
                                <div className="t" style={{"color": urgency_color(a.urgency)}}>
                                    {"Due " + due_time(a)}
                                </div>
                                <div className="n">{a.title}</div>
                                <div className="tiny muted">{a.course_code}</div>
                            </div>
                        }}
                        {not day.classes and not day.due and <div className="muted tiny" style={{"textAlign": "center", "marginTop": "20px"}}>Free day</div>}
                    </div>
                </div>
            }}
        </div>
    </>
}
