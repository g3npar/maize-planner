"""Classes: schedule, links to each platform, and a full course editor."""

import from "lucide-react" { Plus, Pencil, MapPin, Clock, ExternalLink, Trash2, X, GraduationCap }
import from core.planner { CourseView }
import from core.state { Planner, CourseDraft, course_draft_from, fmt_pct, COURSE_COLORS, WEEKDAYS }
import from .ui { Modal, Empty, CourseChip }

def:pub PlatformLinks(c: CourseView) -> JsxElement {
    links: list[tuple[str, str, str]] = [];
    if c.canvas_url {
        links.append(("Canvas", c.canvas_url, "#e2432b"));
    }
    if c.gradescope_url {
        links.append(("Gradescope", c.gradescope_url, "#1a8a88"));
    }
    if c.autograder_url {
        links.append(("Autograder", c.autograder_url, "#7c3aed"));
    }
    if c.website_url {
        links.append(("Website", c.website_url, "#475569"));
    }
    <div className="links">
        {for (label, href, color) in links {
            <a key={label} className="btn sm" href={href} target="_blank" rel="noreferrer" style={{"color": color}}>
                <ExternalLink size={13}/>{label}
            </a>
        }}
    </div>
}

def:pub ClassesPage(p: Planner, onEdit: Callable[[CourseDraft], None]) -> JsxElement {
    <>
        <div className="toolbar">
            <span className="muted">{str(len(p.courses))} classes</span>
            <span className="grow"></span>
            <button className="btn primary" onClick={lambda (e: MouseEvent) { onEdit(CourseDraft()); }}><Plus size={16}/> Add class</button>
        </div>
        {not p.courses and <div className="card"><Empty
            title="No classes yet"
            hint="Add them by hand, sync from Canvas in Settings, or load the demo semester."
            emoji="📚"
        >
            <button className="btn primary" onClick={lambda (e: MouseEvent) { onEdit(CourseDraft()); }}>Add class</button>
            <button className="btn maize" onClick={lambda (e: MouseEvent) { p.loadDemo(); }}>Load demo semester</button>
        </Empty></div>}
        <div className="grid-cards">
            {for c in p.courses {
                <div key={c.id} className="card course-card" style={{"--chip": c.color}}>
                    <div className="row-flex" style={{"alignItems": "flex-start"}}>
                        <div className="grow">
                            <div className="course-code">{c.code}</div>
                            <div className="course-name">{c.name or "—"}{(" · " + c.term) if c.term else ""}</div>
                        </div>
                        <div className="letter" title="Current grade">{c.grade.letter or "–"}</div>
                        <button className="btn ghost icon" title="Edit class" onClick={lambda (e: MouseEvent) { onEdit(course_draft_from(c)); }}><Pencil size={15}/></button>
                    </div>
                    <div className="row-flex small" style={{"margin": "12px 0 6px", "gap": "14px"}}>
                        <span><b>{str(c.open_count)}</b> open</span>
                        {c.overdue_count > 0 and <span style={{"color": "var(--danger)"}}><b>{str(c.overdue_count)}</b> overdue</span>}
                        {c.next_due and <span className="muted">next: {c.next_due}</span>}
                    </div>
                    <div style={{"margin": "6px 0 10px"}}>
                        {not c.meetings and <div className="muted small">No meeting times yet.</div>}
                        {for m in c.meetings {
                            <div key={m.id} className="meeting">
                                <b className="meeting-kind">{m.kind}</b>
                                <div className="grow">
                                    <div className="row-flex" style={{"gap": "5px"}}><Clock size={12}/>{m.days_label + " · " + m.time_label}</div>
                                    {m.location and <div className="row-flex muted" style={{"gap": "5px"}}><MapPin size={12}/>{m.location}</div>}
                                </div>
                            </div>
                        }}
                    </div>
                    <PlatformLinks c={c}/>
                </div>
            }}
        </div>
    </>
}

obj WeightRow {
    has name: str = "",
        pct: str = "";
}

def rows_from(weights: dict[str, float]) -> list[WeightRow] {
    out: list[WeightRow] = [];
    for key in weights.keys() {
        out.append(WeightRow(name=key, pct=f"{weights[key]:g}"));
    }
    return out;
}

def:pub CourseEditor(
    p: Planner,
    draft: CourseDraft,
    onClose: Callable[[], None],
    onSaved: Callable[[CourseView], None]
) -> JsxElement {
    has code: str = draft.code,
        name: str = draft.name,
        color: str = draft.color or COURSE_COLORS[len(p.courses) % len(COURSE_COLORS)],
        term: str = draft.term,
        instructor: str = draft.instructor,
        canvasUrl: str = draft.canvas_url,
        gradescopeUrl: str = draft.gradescope_url,
        autograderUrl: str = draft.autograder_url,
        websiteUrl: str = draft.website_url,
        target: str = f"{draft.target:g}",
        weights: list[WeightRow] = rows_from(draft.weights),
        saving: bool = False,
        confirmDelete: bool = False;

    live: CourseView | None = None;
    for c in p.courses {
        if c.id == draft.id {
            live = c;
        }
    }
    total = 0.0;
    for w in weights {
        v = parseFloat(w.pct);
        if not isNaN(v) {
            total += v;
        }
    }

    def weight_map -> dict[str, float] {
        out: dict[str, float] = {};
        for w in weights {
            v = parseFloat(w.pct);
            if w.name.strip() and not isNaN(v) and v > 0 {
                out[w.name.strip()] = v;
            }
        }
        return out;
    }

    def set_row(index: int, field: str, value: str) {
        fresh: list[WeightRow] = [];
        for (i, w) in enumerate(weights) {
            if i == index {
                fresh.append(WeightRow(name=value if field == "name" else w.name, pct=value if field == "pct" else w.pct));
            } else {
                fresh.append(w);
            }
        }
        weights = fresh;
    }

    async def save -> None {
        if not code.strip() {
            return;
        }
        saving = True;
        t = parseFloat(target);
        saved = await p.saveCourse(
            CourseDraft(
                id=draft.id,
                code=code,
                name=name,
                color=color,
                term=term,
                instructor=instructor,
                canvas_url=canvasUrl,
                gradescope_url=gradescopeUrl,
                autograder_url=autograderUrl,
                website_url=websiteUrl,
                target=90.0 if isNaN(t) else t,
                weights=weight_map()
            )
        );
        saving = False;
        if saved is not None {
            if draft.id {
                onClose();
            } else {
                onSaved(saved);
            }
        }
    }

    async def remove -> None {
        await p.deleteCourse(draft.id);
        onClose();
    }

    footer = <>
        {draft.id and not confirmDelete and <button className="btn danger" onClick={lambda (e: MouseEvent) { confirmDelete = True; }}><Trash2 size={15}/> Delete class</button>}
        {confirmDelete and <button className="btn danger" onClick={lambda (e: MouseEvent) { remove(); }}><Trash2 size={15}/> Delete it and its assignments</button>}
        <span className="grow"></span>
        <button className="btn" onClick={lambda (e: MouseEvent) { onClose(); }}>Cancel</button>
        <button className="btn primary" disabled={saving or not code.strip()} onClick={lambda (e: MouseEvent) { save(); }}>
            {"Saving…" if saving else ("Save class" if draft.id else "Add class")}
        </button>
    </>;

    <Modal title={("Edit " + draft.code) if draft.id else "Add a class"} onClose={onClose} footer={footer} wide={True}>
        <div className="form-grid">
            <div className="field">
                <label>Course code</label>
                <input className="input" value={code} autoFocus={not draft.id} placeholder="EECS 482" onChange={lambda (e: ChangeEvent) { code = e.target.value; }}/>
            </div>
            <div className="field">
                <label>Name</label>
                <input className="input" value={name} placeholder="Introduction to Operating Systems" onChange={lambda (e: ChangeEvent) { name = e.target.value; }}/>
            </div>
            <div className="field">
                <label>Term · Instructor</label>
                <div className="row-flex" style={{"flexWrap": "nowrap"}}>
                    <input className="input" value={term} placeholder="Fall 2026" onChange={lambda (e: ChangeEvent) { term = e.target.value; }}/>
                    <input className="input" value={instructor} placeholder="Prof. …" onChange={lambda (e: ChangeEvent) { instructor = e.target.value; }}/>
                </div>
            </div>
            <div className="field">
                <label>Color</label>
                <div className="swatches">
                    {for col in COURSE_COLORS {
                        <button key={col} type="button" className={"swatch" + (" on" if col == color else "")} style={{"background": col}} onClick={lambda (e: MouseEvent) { color = col; }}></button>
                    }}
                </div>
            </div>
            <div className="field">
                <label>Canvas course page</label>
                <input className="input" value={canvasUrl} placeholder="https://umich.instructure.com/courses/…" onChange={lambda (e: ChangeEvent) { canvasUrl = e.target.value; }}/>
            </div>
            <div className="field">
                <label>Gradescope course page</label>
                <input className="input" value={gradescopeUrl} placeholder="https://www.gradescope.com/courses/…" onChange={lambda (e: ChangeEvent) { gradescopeUrl = e.target.value; }}/>
            </div>
            <div className="field">
                <label>Autograder.io page</label>
                <input className="input" value={autograderUrl} placeholder="https://autograder.io/web/course/…" onChange={lambda (e: ChangeEvent) { autograderUrl = e.target.value; }}/>
            </div>
            <div className="field">
                <label>Course website</label>
                <input className="input" value={websiteUrl} placeholder="https://eecs482.org" onChange={lambda (e: ChangeEvent) { websiteUrl = e.target.value; }}/>
            </div>
        </div>

        <div className="form-grid">
            <div className="stack" style={{"gap": "8px"}}>
                <div className="section-title" style={{"margin": "0"}}><GraduationCap size={14}/> Grade weights</div>
                <div className="muted tiny">Category names should match the assignments' categories (Canvas assignment groups import automatically). Leave empty to grade by total points.</div>
                {for (i, w) in enumerate(weights) {
                    <div key={str(i)} className="row-flex" style={{"flexWrap": "nowrap"}}>
                        <input className="input" value={w.name} placeholder="Projects" onChange={lambda (e: ChangeEvent) { set_row(i, "name", e.target.value); }}/>
                        <input className="input" style={{"width": "90px"}} inputMode="decimal" value={w.pct} placeholder="%" onChange={lambda (e: ChangeEvent) { set_row(i, "pct", e.target.value); }}/>
                        <button className="btn ghost icon" onClick={lambda (e: MouseEvent) { weights = [x for (j, x) in enumerate(weights) if j != i]; }}><X size={14}/></button>
                    </div>
                }}
                <div className="row-flex">
                    <button className="btn sm" onClick={lambda (e: MouseEvent) { weights = weights + [WeightRow()]; }}><Plus size={13}/> Category</button>
                    <span className={"small" + ("" if abs(total - 100.0) < 0.01 or not weights else " prio")}>{f"Total {total:g}%"}</span>
                </div>
                <div className="field" style={{"maxWidth": "200px"}}>
                    <label>Target grade (%)</label>
                    <input className="input" inputMode="decimal" value={target} onChange={lambda (e: ChangeEvent) { target = e.target.value; }}/>
                </div>
            </div>
            <div className="stack" style={{"gap": "8px"}}>
                <div className="section-title" style={{"margin": "0"}}><Clock size={14}/> Meeting times</div>
                {live is None and <div className="muted small">Save the class first, then add lectures, discussions and office hours.</div>}
                {live is not None and <MeetingEditor p={p} c={live}/>}
            </div>
        </div>
    </Modal>
}

def:pub MeetingEditor(p: Planner, c: CourseView) -> JsxElement {
    has kind: str = "Lecture",
        days: list[int] = [],
        start: str = "10:00",
        end: str = "11:30",
        location: str = "";

    def toggle_day(d: int) {
        days = [x for x in days if x != d] if d in days else days + [d];
    }

    async def add -> None {
        await p.addMeeting(c.id, kind, days, start, end, location);
        days = [];
        location = "";
    }

    <div className="stack" style={{"gap": "8px"}}>
        {for m in c.meetings {
            <div key={m.id} className="meeting">
                <b className="meeting-kind">{m.kind}</b>
                <span className="grow">{m.days_label} {m.time_label}{(" · " + m.location) if m.location else ""}</span>
                <button className="btn ghost icon" title="Remove" onClick={lambda (e: MouseEvent) { p.deleteMeeting(m.id); }}><X size={14}/></button>
            </div>
        }}
        <div className="card" style={{"padding": "12px", "boxShadow": "none", "background": "var(--surface-2)"}}>
            <div className="stack" style={{"gap": "8px"}}>
                <div className="row-flex" style={{"flexWrap": "nowrap"}}>
                    <select className="select" value={kind} onChange={lambda (e: ChangeEvent) { kind = e.target.value; }}>
                        {for k in ["Lecture", "Discussion", "Lab", "Office Hours", "Seminar", "Study Group"] {
                            <option key={k} value={k}>{k}</option>
                        }}
                    </select>
                    <input className="input" value={location} placeholder="Room" onChange={lambda (e: ChangeEvent) { location = e.target.value; }}/>
                </div>
                <div className="daypick">
                    {for (i, d) in enumerate(WEEKDAYS) {
                        <button key={d} type="button" className={"on" if i in days else ""} onClick={lambda (e: MouseEvent) { toggle_day(i); }}>{d}</button>
                    }}
                </div>
                <div className="row-flex" style={{"flexWrap": "nowrap"}}>
                    <input className="input" type="time" value={start} onChange={lambda (e: ChangeEvent) { start = e.target.value; }}/>
                    <span className="muted">to</span>
                    <input className="input" type="time" value={end} onChange={lambda (e: ChangeEvent) { end = e.target.value; }}/>
                    <button className="btn primary" disabled={not days} onClick={lambda (e: MouseEvent) { add(); }}><Plus size={14}/> Add</button>
                </div>
            </div>
        </div>
    </div>
}
