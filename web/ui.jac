"""Small building blocks shared by every web page."""

import from "lucide-react" { Check, ExternalLink, X, Flag, ListChecks }
import from core.planner { AssignmentView }
import from core.state { source_label, source_color, urgency_color, progress_of }

def:pub CourseChip(code: str, color: str) -> JsxElement {
    <span className="chip" style={{"--chip": color}}>
        <span className="dot"></span>
        {code}
    </span>
}

def:pub SourceBadge(source: str) -> JsxElement {
    <span className="badge" style={{"--chip": source_color(source)}}>
        {source_label(source)}
    </span>
}

def:pub AssignmentRow(
    a: AssignmentView,
    onToggle: Callable[[AssignmentView], None],
    onOpen: Callable[[AssignmentView], None],
    busy: bool = False,
    showCourse: bool = True
) -> JsxElement {
    done = a.status == "done";
    steps = progress_of(a);

    def handle_check(e: MouseEvent) {
        e.stopPropagation();
        onToggle(a);
    }

    def handle_link(e: MouseEvent) {
        e.stopPropagation();
    }

    <div
        className={"item" + (" done" if done else "")}
        onClick={lambda (e: MouseEvent) { onOpen(a); }}
    >
        <button
            className={"check" + (" on" if done else "")}
            style={{"--ring": a.course_color}}
            onClick={handle_check}
            disabled={busy}
            title={"Mark not done" if done else "Mark done"}
        >
            {done and <Check size={13} strokeWidth={3}/>}
        </button>
        <div className="item-main">
            <div className="item-title">
                {a.priority >= 3 and <span className="prio" title="High priority">!! </span>}
                {a.title}
            </div>
            <div className="item-meta">
                {showCourse and <CourseChip code={a.course_code} color={a.course_color}/>}
                <SourceBadge source={a.source}/>
                {a.status == "doing" and <span className="badge" style={{"--chip": "#0891b2"}}>In progress</span>}
                {steps and <span className="row-flex" style={{"gap": "3px"}}><ListChecks size={13}/>{steps}</span>}
                {a.score is not None and <span>{f"{a.score:g}/{a.points:g}"}</span>}
                {a.est_hours > 0 and not done and <span>{f"~{a.est_hours:g}h"}</span>}
            </div>
        </div>
        {a.url and <a
            className="btn ghost icon"
            href={a.url}
            target="_blank"
            rel="noreferrer"
            onClick={handle_link}
            title={"Open in " + source_label(a.source)}
        >
            <ExternalLink size={15}/>
        </a>}
        <div className="item-due">
            <span className="when">{a.due_label}</span>
            {a.due_in and <span className="left" style={{"color": urgency_color(a.urgency)}}>
                {a.due_in}
            </span>}
        </div>
    </div>
}

def:pub Modal(
    title: str,
    onClose: Callable[[], None],
    children: any = None,
    footer: any = None,
    wide: bool = False
) -> JsxElement {
    def stop(e: MouseEvent) {
        e.stopPropagation();
    }

    <div className="backdrop" onMouseDown={lambda (e: MouseEvent) { onClose(); }}>
        <div
            className="modal"
            style={{"width": "min(880px, 100%)"} if wide else {}}
            onMouseDown={stop}
        >
            <div className="modal-head">
                <h2>{title}</h2>
                <button className="btn ghost icon" onClick={lambda (e: MouseEvent) { onClose(); }} title="Close">
                    <X size={18}/>
                </button>
            </div>
            <div className="modal-body">{children}</div>
            {footer and <div className="modal-foot">{footer}</div>}
        </div>
    </div>
}

def:pub Empty(title: str, hint: str = "", emoji: str = "✨", children: any = None) -> JsxElement {
    <div className="empty">
        <div className="big">{emoji}</div>
        <div style={{"fontWeight": "700", "color": "var(--text)"}}>{title}</div>
        {hint and <div className="small" style={{"marginTop": "4px"}}>{hint}</div>}
        {children and <div className="row-flex" style={{"justifyContent": "center", "marginTop": "14px"}}>{children}</div>}
    </div>
}

def:pub Stat(label: str, value: str, alert: bool = False, icon: any = None) -> JsxElement {
    <div className={"stat" + (" alert" if alert else "")}>
        <div className="label">{icon}{label}</div>
        <div className="value">{value}</div>
    </div>
}

def:pub PriorityFlag(priority: int) -> JsxElement {
    colors = ["#94a3b8", "#94a3b8", "#2563eb", "#dc2626"];
    names = ["", "Low", "Normal", "High"];
    <span className="row-flex small" style={{"gap": "4px", "color": colors[priority]}}>
        <Flag size={13}/>{names[priority]}
    </span>
}
