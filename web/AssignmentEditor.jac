"""Create / edit one assignment: details, grade, and a step checklist."""

import from "lucide-react" { Trash2, Sparkles, Plus, Check, ExternalLink, X }
import from core.planner { AssignmentView, CourseView }
import from core.state { Planner, AssignmentDraft, source_label }
import from .ui { Modal, SourceBadge }

def to_float(text: str) -> float {
    t = text.strip();
    if not t {
        return 0.0;
    }
    v = parseFloat(t);
    return 0.0 if isNaN(v) else v;
}

def step_done(a: AssignmentView, i: int) -> bool {
    return i < len(a.subtasks_done) and bool(a.subtasks_done[i]);
}

def:pub ProgressPanel(p: Planner, a: AssignmentView, pointsText: str) -> JsxElement {
    has score: str = (f"{a.score:g}" if a.score is not None else ""),
        newStep: str = "";

    async def saveScore -> None {
        if not score.strip() {
            await p.setScore(a.id, None, to_float(pointsText));
        } else {
            await p.setScore(a.id, to_float(score), to_float(pointsText));
        }
    }

    async def addStep -> None {
        if not newStep.strip() {
            return;
        }
        steps = list(a.subtasks) + [newStep.strip()];
        flags = [step_done(a, i) for i in range(len(a.subtasks))] + [False];
        newStep = "";
        await p.setSubtasks(a.id, steps, flags);
    }

    async def removeStep(index: int) -> None {
        steps = [s for (i, s) in enumerate(a.subtasks) if i != index];
        flags = [step_done(a, i) for i in range(len(a.subtasks)) if i != index];
        await p.setSubtasks(a.id, steps, flags);
    }

    def onStepKey(e: KeyboardEvent) {
        if e.key == "Enter" {
            e.preventDefault();
            addStep();
        }
    }

    <div className="form-grid">
        <div className="stack" style={{"gap": "8px"}}>
            <div className="section-title" style={{"margin": "0"}}>Status</div>
            <div className="seg">
                {for (st, label) in [("todo", "To do"), ("doing", "In progress"), ("done", "Done")] {
                    <button key={st} type="button" className={"on" if a.status == st else ""} onClick={lambda (e: MouseEvent) { p.setStatus(a.id, st); }}>{label}</button>
                }}
            </div>
            <div className="section-title" style={{"margin": "8px 0 0"}}>Score</div>
            <div className="row-flex" style={{"flexWrap": "nowrap"}}>
                <input className="input" inputMode="decimal" style={{"width": "110px"}} value={score} placeholder="score" onChange={lambda (e: ChangeEvent) { score = e.target.value; }}/>
                <span className="muted">{"/ " + (pointsText or "?")}</span>
                <button className="btn sm" onClick={lambda (e: MouseEvent) { saveScore(); }}>Save score</button>
            </div>
            <div className="muted tiny">Scores feed the Grades page. Canvas grades import automatically.</div>
        </div>
        <div className="stack" style={{"gap": "6px"}}>
            <div className="row-flex">
                <div className="section-title" style={{"margin": "0"}}>Steps</div>
                <span className="grow"></span>
                <button className="btn sm" disabled={p.busyId == a.id} onClick={lambda (e: MouseEvent) { p.breakdown(a.id); }}>
                    <Sparkles size={14}/>{"Thinking…" if p.busyId == a.id else "Break it down"}
                </button>
            </div>
            <div className="steps">
                {not a.subtasks and <div className="muted small">No steps yet - add your own or let the planner suggest some.</div>}
                {for (i, step) in enumerate(a.subtasks) {
                    <div key={str(i) + step} className={"step" + (" done" if step_done(a, i) else "")} onClick={lambda (e: MouseEvent) { p.toggleSubtask(a.id, i); }}>
                        <span className={"box" + (" on" if step_done(a, i) else "")}>
                            {step_done(a, i) and <Check size={11} strokeWidth={3}/>}
                        </span>
                        <span className="grow">{step}</span>
                        <button className="btn ghost icon" style={{"padding": "2px"}} onClick={lambda (e: MouseEvent) { e.stopPropagation(); removeStep(i); }}><X size={13}/></button>
                    </div>
                }}
            </div>
            <div className="row-flex" style={{"flexWrap": "nowrap"}}>
                <input className="input" value={newStep} placeholder="Add a step and press Enter" onChange={lambda (e: ChangeEvent) { newStep = e.target.value; }} onKeyDown={onStepKey}/>
                <button className="btn icon" onClick={lambda (e: MouseEvent) { addStep(); }}><Plus size={15}/></button>
            </div>
        </div>
    </div>
}

def:pub AssignmentEditor(
    p: Planner,
    draft: AssignmentDraft,
    onClose: Callable[[], None]
) -> JsxElement {
    has title: str = draft.title,
        courseId: str = draft.course_id,
        source: str = draft.source,
        due: str = draft.due,
        priority: int = draft.priority,
        category: str = draft.category,
        points: str = (f"{draft.points:g}" if draft.points else ""),
        url: str = draft.url,
        notes: str = draft.notes,
        estHours: str = (f"{draft.est_hours:g}" if draft.est_hours else ""),
        saving: bool = False,
        confirmDelete: bool = False;

    live: AssignmentView | None = p.findAssignment(draft.id) if draft.id else None;
    if live is None and draft.id {
        for g in p.gradebook {
            if g.id == draft.id {
                live = g;
            }
        }
    }
    course: CourseView | None = None;
    for c in p.courses {
        if c.id == courseId {
            course = c;
        }
    }
    categories: list[str] = list(course.weights.keys()) if course is not None else [];


    async def save -> None {
        if not title.strip() {
            return;
        }
        saving = True;
        saved = await p.saveAssignment(
            AssignmentDraft(
                id=draft.id,
                course_id=courseId,
                title=title,
                source=source,
                due=due,
                priority=priority,
                category=category,
                points=to_float(points),
                url=url,
                notes=notes,
                est_hours=to_float(estHours)
            )
        );
        saving = False;
        if saved is not None {
            onClose();
        }
    }

    async def remove -> None {
        await p.deleteAssignment(draft.id);
        onClose();
    }

    footer = <>
        {draft.id and not confirmDelete and <button className="btn danger" onClick={lambda (e: MouseEvent) { confirmDelete = True; }}>
            <Trash2 size={15}/> Delete
        </button>}
        {confirmDelete and <button className="btn danger" onClick={lambda (e: MouseEvent) { remove(); }}>
            <Trash2 size={15}/> Really delete?
        </button>}
        <span className="grow"></span>
        <button className="btn" onClick={lambda (e: MouseEvent) { onClose(); }}>Cancel</button>
        <button className="btn primary" disabled={saving or not title.strip()} onClick={lambda (e: MouseEvent) { save(); }}>
            {"Saving…" if saving else ("Save changes" if draft.id else "Add assignment")}
        </button>
    </>;

    <Modal title={"Edit assignment" if draft.id else "New assignment"} onClose={onClose} footer={footer}>
        {live is not None and live.from_canvas and <div className="callout small">
            Imported from Canvas - the next sync refreshes the title, due date and points. Your notes, priority, estimate and steps are kept.
        </div>}
        <div className="form-grid">
            <div className="field full">
                <label>Title</label>
                <input className="input" value={title} autoFocus={not draft.id} placeholder="Project 3: Virtual memory pager" onChange={lambda (e: ChangeEvent) { title = e.target.value; }}/>
            </div>
            <div className="field">
                <label>Class</label>
                <select className="select" value={courseId} onChange={lambda (e: ChangeEvent) { courseId = e.target.value; }}>
                    <option value="">Personal (no class)</option>
                    {for c in p.courses {
                        <option key={c.id} value={c.id}>{c.code + (" - " + c.name if c.name else "")}</option>
                    }}
                </select>
            </div>
            <div className="field">
                <label>Submitted on</label>
                <select className="select" value={source} onChange={lambda (e: ChangeEvent) { source = e.target.value; }}>
                    {for s in ["canvas", "gradescope", "autograder", "other"] {
                        <option key={s} value={s}>{source_label(s)}</option>
                    }}
                </select>
            </div>
            <div className="field">
                <label>Due</label>
                <input className="input" type="datetime-local" value={due} onChange={lambda (e: ChangeEvent) { due = e.target.value; }}/>
            </div>
            <div className="field">
                <label>Priority</label>
                <div className="seg">
                    {for (n, label) in [(1, "Low"), (2, "Normal"), (3, "High")] {
                        <button key={label} type="button" className={"on" if priority == n else ""} onClick={lambda (e: MouseEvent) { priority = n; }}>{label}</button>
                    }}
                </div>
            </div>
            <div className="field">
                <label>Grade category</label>
                <input className="input" list="cat-options" value={category} placeholder="Projects" onChange={lambda (e: ChangeEvent) { category = e.target.value; }}/>
                <datalist id="cat-options">
                    {for c in categories { <option key={c} value={c}></option> }}
                </datalist>
            </div>
            <div className="field">
                <label>Points possible · Est. hours</label>
                <div className="row-flex" style={{"flexWrap": "nowrap"}}>
                    <input className="input" inputMode="decimal" value={points} placeholder="100" onChange={lambda (e: ChangeEvent) { points = e.target.value; }}/>
                    <input className="input" inputMode="decimal" value={estHours} placeholder="hours" onChange={lambda (e: ChangeEvent) { estHours = e.target.value; }}/>
                </div>
            </div>
            <div className="field full">
                <label>Link</label>
                <div className="row-flex" style={{"flexWrap": "nowrap"}}>
                    <input className="input" value={url} placeholder="https://autograder.io/web/project/…" onChange={lambda (e: ChangeEvent) { url = e.target.value; }}/>
                    {url and <a className="btn icon" href={url} target="_blank" rel="noreferrer"><ExternalLink size={15}/></a>}
                </div>
            </div>
            <div className="field full">
                <label>Notes</label>
                <textarea className="textarea" value={notes} placeholder="Office hours Thursday, partner: …" onChange={lambda (e: ChangeEvent) { notes = e.target.value; }}></textarea>
            </div>
        </div>

        {live is not None and <ProgressPanel p={p} a={live} pointsText={points}/>}
    </Modal>
}
