"""Plan a study session: AI (or built-in) picks what to do, laid out around classes."""

import from "lucide-react" { Sparkles, Wand2, Check, Lightbulb, Cpu }
import from core.planner { AssignmentView, StudyPlan }
import from core.state { Planner }
import from .ui { Empty, CourseChip }

def clock(iso: str) -> str {
    if len(iso) < 16 {
        return iso;
    }
    h = int(iso[11:13]);
    m = iso[14:16];
    suffix = "AM" if h < 12 else "PM";
    h12 = h % 12;
    if h12 == 0 {
        h12 = 12;
    }
    return str(h12) + ":" + m + " " + suffix;
}

def:pub PlanTips(tips: list[str]) -> JsxElement {
    if not tips {
        return <></>;
    }
    <div className="card">
        <div className="card-head"><Lightbulb size={16}/><h2>Tips</h2></div>
        <ul style={{"margin": "0", "paddingLeft": "18px"}} className="stack">
            {for t in tips { <li key={t}>{t}</li> }}
        </ul>
    </div>
}

def:pub PlanResult(plan: StudyPlan, onOpenBlock: Callable[[str], None]) -> JsxElement {
    <div className="stack">
        <div className="row-flex">
            {(<span className="ai-badge">AI plan</span>) if plan.source == "ai" else (<span className="badge" style={{"--chip": "#475569"}}><Cpu size={11}/> Built-in planner</span>)}
            <span className="grow"></span>
            {plan.note and <span className="muted tiny">{plan.note}</span>}
        </div>
        <div style={{"fontSize": "15px", "fontWeight": "600"}}>{plan.summary}</div>
        {not plan.blocks and <div className="muted">Nothing to schedule right now.</div>}
        <div className="timeline">
            {for b in plan.blocks {
                <div key={b.start + b.assignment_id} className="tl-item" style={{"--chip": b.color}}>
                    <div className="tl-time">{clock(b.start)}<div className="muted">{str(b.minutes)} min</div></div>
                    <div style={{"cursor": "pointer"}} onClick={lambda (e: MouseEvent) { onOpenBlock(b.assignment_id); }}>
                        <div className="row-flex"><CourseChip code={b.course_code} color={b.color}/><b>{b.title}</b></div>
                        <div className="muted small" style={{"marginTop": "3px"}}>{b.reason}</div>
                    </div>
                    <div className="muted small">→ {clock(b.end)}</div>
                </div>
            }}
        </div>
    </div>
}

def:pub PlanPage(p: Planner, onOpen: Callable[[AssignmentView], None]) -> JsxElement {
    has hours: float = 3.0,
        goal: str = "",
        useAi: bool = True;

    can with entry {
        if p.settings is None {
            p.loadSettings();
        }
    }
    aiReady = p.settings is not None and p.settings.ai_ready;
    plan = p.plan;

    def open_block(assignment_id: str) {
        a = p.findAssignment(assignment_id);
        if a is not None {
            onOpen(a);
        }
    }

    <div className="grid-2">
        <div className="stack" style={{"gap": "20px"}}>
            <div className="card">
                <div className="card-head">
                    <h2>Plan a study session</h2>
                    <span className="spacer"></span>
                    {aiReady and <span className="ai-badge">AI ready</span>}
                </div>
                <div className="stack">
                    <div className="field">
                        <label>How long do you have? <b>{f"{hours:g} hours"}</b></label>
                        <input type="range" min="0.5" max="8" step="0.5" value={hours} onChange={lambda (e: ChangeEvent) { hours = parseFloat(e.target.value); }}/>
                    </div>
                    <div className="field">
                        <label>Anything to focus on? (optional)</label>
                        <input className="input" value={goal} placeholder="e.g. get ahead on 482, midterm is next week" onChange={lambda (e: ChangeEvent) { goal = e.target.value; }}/>
                    </div>
                    <label className="row-flex small" style={{"cursor": "pointer"}}>
                        <input type="checkbox" checked={useAi and aiReady} disabled={not aiReady} onChange={lambda (e: ChangeEvent) { useAi = e.target.checked; }}/>
                        Use AI {not aiReady and <span className="muted">(set ANTHROPIC_API_KEY, OPENAI_API_KEY or GEMINI_API_KEY before `jac run` to enable)</span>}
                    </label>
                    <div>
                        <button className="btn primary" disabled={p.planBusy} onClick={lambda (e: MouseEvent) { p.makePlan(hours, goal, useAi and aiReady); }}>
                            <Wand2 size={16}/>{"Planning…" if p.planBusy else "Build my plan"}
                        </button>
                    </div>
                </div>
            </div>
            {plan is not None and <PlanTips tips={plan.tips}/>}
        </div>
        <div className="card">
            {plan is None and <Empty
                title="Your plan shows up here"
                hint="The planner looks at every open assignment - deadlines, effort estimates, priorities and today's classes - and lays out focused blocks."
                emoji="🗓️"
            />}
            {plan is not None and <PlanResult plan={plan} onOpenBlock={open_block}/>}
        </div>
    </div>
}
