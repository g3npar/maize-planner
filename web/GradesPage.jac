"""Grades: weighted current grade, target math, and quick score entry."""

import from "lucide-react" { Target, Pencil }
import from core.planner { AssignmentView, CourseView }
import from core.state { Planner, fmt_pct, CourseDraft, course_draft_from }
import from .ui { Empty, CourseChip }

def pct_width(value: float | None) -> str {
    if value is None {
        return "0%";
    }
    return str(max(0.0, min(value, 100.0))) + "%";
}

def:pub ScoreCell(p: Planner, a: AssignmentView) -> JsxElement {
    has value: str = (f"{a.score:g}" if a.score is not None else "");

    def save(e: FocusEvent) {
        text = value.strip();
        old = f"{a.score:g}" if a.score is not None else "";
        if text == old {
            return;
        }
        v = parseFloat(text);
        if not text {
            p.setScore(a.id, None, a.points);
        } elif not isNaN(v) {
            p.setScore(a.id, v, a.points);
        }
    }

    def on_key(e: KeyboardEvent) {
        if e.key == "Enter" {
            e.target.blur();
        }
    }

    <span className="row-flex" style={{"flexWrap": "nowrap", "gap": "4px"}}>
        <input
            className="input"
            style={{"width": "74px", "padding": "4px 8px"}}
            inputMode="decimal"
            value={value}
            placeholder="–"
            onChange={lambda (e: ChangeEvent) { value = e.target.value; }}
            onBlur={save}
            onKeyDown={on_key}
        />
        <span className="muted small">{f"/ {a.points:g}"}</span>
    </span>
}

def:pub CourseGrades(
    p: Planner,
    c: CourseView,
    items: list[AssignmentView],
    onEdit: Callable[[CourseDraft], None]
) -> JsxElement {
    g = c.grade;
    <div className="card" style={{"--chip": c.color}}>
        <div className="row-flex" style={{"alignItems": "flex-start", "gap": "16px"}}>
            <div className="grow">
                <div className="row-flex">
                    <CourseChip code={c.code} color={c.color}/>
                    <span className="muted small">{c.name}</span>
                </div>
                <div className="row-flex" style={{"alignItems": "baseline", "gap": "10px", "marginTop": "8px"}}>
                    <span className="grade-big">{fmt_pct(g.current)}</span>
                    {g.letter and <span className="letter">{g.letter}</span>}
                </div>
                <div className="muted small">
                    {str(g.graded_count)} graded of {str(g.total_count)} · {"weighted categories" if g.weighted else "total points"}
                </div>
            </div>
            <div style={{"textAlign": "right"}}>
                <div className="row-flex small" style={{"justifyContent": "flex-end", "gap": "5px"}}><Target size={14}/> Target {f"{c.target:g}%"}</div>
                <button className="btn sm" style={{"marginTop": "8px"}} onClick={lambda (e: MouseEvent) { onEdit(course_draft_from(c)); }}><Pencil size={13}/> Weights</button>
            </div>
        </div>
        <div className="bar" style={{"margin": "14px 0 6px"}}>
            <span style={{"width": pct_width(g.current)}}></span>
            <div className="target" style={{"left": pct_width(c.target)}}></div>
        </div>
        {g.note and <div className={"callout small" + (" warn" if g.needed is not None and g.needed > 95 else "")} style={{"marginTop": "10px"}}>{g.note}</div>}
        {len(g.categories) > 0 and <table className="grid" style={{"marginTop": "12px"}}>
            <thead><tr><th>Category</th><th>Weight</th><th>Earned</th><th style={{"width": "36%"}}>Score</th><th>Left</th></tr></thead>
            <tbody>
                {for cat in g.categories {
                    <tr key={cat.name}>
                        <td><b>{cat.name}</b></td>
                        <td>{f"{cat.weight:g}%" if cat.weight else "–"}</td>
                        <td className="muted">{f"{cat.earned:g}/{cat.possible:g}" if cat.possible else "–"}</td>
                        <td>
                            <div className="row-flex" style={{"flexWrap": "nowrap"}}>
                                <div className="bar grow"><span style={{"width": pct_width(cat.pct)}}></span></div>
                                <span className="small" style={{"minWidth": "48px", "textAlign": "right"}}>{fmt_pct(cat.pct)}</span>
                            </div>
                        </td>
                        <td className="muted">{str(cat.remaining)}</td>
                    </tr>
                }}
            </tbody>
        </table>}
        {len(items) > 0 and <details style={{"marginTop": "12px"}}>
            <summary className="small" style={{"cursor": "pointer", "fontWeight": "650"}}>Scores for each assignment ({str(len(items))})</summary>
            <table className="grid" style={{"marginTop": "8px"}}>
                <tbody>
                    {for a in items {
                        <tr key={a.id}>
                            <td>{a.title}<div className="muted tiny">{a.category or "Uncategorized"} · {a.due_label}</div></td>
                            <td style={{"width": "150px"}}><ScoreCell p={p} a={a}/></td>
                        </tr>
                    }}
                </tbody>
            </table>
        </details>}
    </div>
}

def:pub GradesPage(p: Planner, onEdit: Callable[[CourseDraft], None]) -> JsxElement {
    can with entry {
        p.loadGradebook();
    }
    if not p.courses {
        return <div className="card"><Empty title="No classes yet" hint="Grades appear once you have classes with graded work." emoji="🎓"/></div>;
    }
    <div className="grid-cards" style={{"gridTemplateColumns": "repeat(auto-fill, minmax(420px, 1fr))"}}>
        {for c in p.courses {
            <CourseGrades
                key={c.id}
                p={p}
                c={c}
                items={[a for a in p.gradebook if a.course_id == c.id and a.points > 0]}
                onEdit={onEdit}
            />
        }}
    </div>
}
