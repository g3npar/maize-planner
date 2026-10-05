"""Study-plan layout and fallbacks. No network: the AI path uses MockLLM."""

import from jaclang.byllm.lib { MockLLM }

def sample_tasks -> list[TaskBrief] {
    return [
        TaskBrief(ref="a", title="Reading", course="EECS 449", hours_until_due=120.0, est_hours=1.0),
        TaskBrief(ref="b", title="Project 3", course="EECS 482", source="autograder", hours_until_due=30.0, est_hours=6.0, priority=3),
        TaskBrief(ref="c", title="HW 4", course="MATH 217", source="gradescope", hours_until_due=-2.0, est_hours=1.0)
    ];
}

test "heuristic puts overdue first and fits the budget" {
    now = datetime(2026, 9, 28, 14, 0);
    picks = heuristic_picks(sample_tasks(), 150, now);
    assert picks[0].ref == "c";
    assert picks[0].reason.startswith("Overdue");
    assert picks[1].ref == "b";
    assert sum([p.minutes for p in picks]) <= 150;
}

test "layout hops over a class and adds breaks" {
    now = datetime(2026, 9, 28, 14, 2);
    briefs = {t.ref: t for t in sample_tasks()};
    picks = [PlanPick(ref="b", minutes=60, reason="x"), PlanPick(ref="a", minutes=30, reason="y")];
    busy = [Busy(start=datetime(2026, 9, 28, 15, 0), end=datetime(2026, 9, 28, 16, 30))];
    blocks = lay_out(picks, briefs, {"b": ("EECS 482", "#f00")}, now, 240, busy);
    assert len(blocks) == 2;
    assert blocks[0].start == "2026-09-28T16:35";
    assert blocks[0].course_code == "EECS 482";
    assert blocks[1].start == "2026-09-28T17:45";
    assert blocks[1].minutes == 30;
}

test "build_plan without AI uses the built-in planner" {
    now = datetime(2026, 9, 28, 9, 0);
    plan = build_plan(sample_tasks(), {}, [], now, 2.0, "", False);
    assert plan.source == "heuristic";
    assert len(plan.blocks) >= 2;
    assert plan.tips;
    empty = build_plan([], {}, [], now, 2.0, "", False);
    assert "caught up" in empty.summary;
}

test "fallback steps depend on where work is submitted" {
    assert "autograder" in " ".join(fallback_steps("P3", "autograder")).lower();
    assert "gradescope" in " ".join(fallback_steps("HW", "gradescope")).lower();
    assert len(fallback_steps("Essay", "canvas")) == 5;
}

test "AI draft is laid out and unknown refs are dropped" {
    llm = (MockLLM(
        outputs=[
            PlanDraft(
                summary="Knock out the overdue homework, then build momentum on P3.",
                picks=[
                    PlanPick(ref="c", minutes=40, reason="Overdue"),
                    PlanPick(ref="zzz", minutes=30, reason="hallucinated"),
                    PlanPick(ref="b", minutes=90, reason="Due tomorrow")
                ],
                tips=["Write tests first"]
            )
        ]
    ) as any) as Model;
    now = datetime(2026, 9, 28, 9, 0);
    briefs = {t.ref: t for t in sample_tasks()};
    draft = draft_plan(sample_tasks(), 180, "Monday 9 AM", "");
    picks = [p for p in draft.picks if p.ref in briefs];
    blocks = lay_out(picks, briefs, {}, now, 180, []);
    assert [b.assignment_id for b in blocks] == ["c", "b"];
    assert blocks[1].start == "2026-09-28T09:40";
}
