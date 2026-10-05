"""AI study planning with an always-available fallback.

`plan_session` asks the model which open assignments deserve the next few
hours and why; the server then lays those picks out as concrete time blocks
around today's classes. `suggest_steps` breaks one assignment into a
checklist. Both degrade to deterministic heuristics when no API key is set
or the model call fails, so the feature never breaks the planner.
"""

import os;
import from datetime { datetime, timedelta }
import from jaclang.byllm.lib { Model }
import from core.logic { urgency_score, to_iso, clock_label, parse_iso }
import from core.views { PlanBlock, StudyPlan }

# ---------------------------------------------------------------- model ----

def ai_model_name -> str {
    explicit = os.environ.get("PLANNER_AI_MODEL", "") or os.environ.get(
        "BYLLM_DEFAULT_MODEL", ""
    );
    if explicit {
        return explicit;
    }
    if os.environ.get("ANTHROPIC_API_KEY") {
        return "anthropic/claude-sonnet-5";
    }
    if os.environ.get("OPENAI_API_KEY") {
        return "gpt-4o-mini";
    }
    if os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") {
        return "gemini/gemini-2.0-flash";
    }
    return "";
}

glob llm: Model = Model(model_name=ai_model_name() or "gpt-4o-mini");

# ---------------------------------------------------------- AI contract ----

obj TaskBrief {
    has ref: str = "",
        title: str = "",
        course: str = "",
        source: str = "",
        status: str = "todo",
        priority: int = 2,
        hours_until_due: float | None = None,
        est_hours: float = 0.0,
        open_steps: list[str] = [];
}

sem TaskBrief = "One open assignment the student could work on.";
sem TaskBrief.ref = "Identifier to copy verbatim into PlanPick.ref.";
sem TaskBrief.hours_until_due = "Hours until the deadline; negative means overdue; null means no deadline.";
sem TaskBrief.priority = "Student-set priority: 1 low, 2 normal, 3 high.";
sem TaskBrief.est_hours = "Student's estimate of total hours still needed (0 = unknown).";
sem TaskBrief.source = "Where it is submitted: canvas, gradescope, autograder (autograder.io; submit early and often, tests are hidden until run) or other.";

obj PlanPick {
    has ref: str = "",
        minutes: int = 45,
        reason: str = "";
}

sem PlanPick = "One focused work block in the plan, in the order it should happen.";
sem PlanPick.ref = "The TaskBrief.ref this block works on.";
sem PlanPick.minutes = "Length of the block in minutes, between 20 and 120.";
sem PlanPick.reason = "Short, specific reason this block comes now (under 14 words).";

obj PlanDraft {
    has summary: str = "",
        picks: list[PlanPick] = [],
        tips: list[str] = [];
}

sem PlanDraft.summary = "One or two encouraging sentences describing the strategy for this session.";
sem PlanDraft.picks = "Ordered work blocks whose minutes sum to at most the available minutes.";
sem PlanDraft.tips = "Two or three concrete, specific study tips for these assignments.";

def draft_plan(
    tasks: list[TaskBrief], available_minutes: int, now_label: str, goal: str
) -> PlanDraft by llm(temperature=0.3, max_tokens=900);

sem draft_plan = "You are a sharp academic coach for a university student. Build a study session plan: pick which open assignments to work on and for how long, most urgent and highest-leverage first. Overdue and due-within-24h work comes first; start large projects (especially autograder projects) days early; batch small tasks; never exceed the available minutes.";
sem draft_plan.tasks = "All open assignments with deadlines and effort estimates.";
sem draft_plan.available_minutes = "Total minutes the student has for this session.";
sem draft_plan.now_label = "Current local day and time.";
sem draft_plan.goal = "Optional focus the student asked for; may be empty.";

def draft_steps(title: str, course: str, source: str, notes: str) -> list[str] by llm(
    temperature=0.3, max_tokens=500
);

sem draft_steps = "Break a university assignment into 4-7 concrete, checkable steps, each under 12 words, in the order to do them. For autograder projects include writing tests and submitting early; for Gradescope include scanning/tagging pages.";

# ------------------------------------------------------------- layout ----

obj Busy {
    has start: datetime,
        end: datetime;
}

def round_up(d: datetime, minutes: int) -> datetime {
    extra = (minutes - d.minute % minutes) % minutes;
    return d.replace(second=0, microsecond=0) + timedelta(minutes=extra);
}

"""Place picks back to back from `start`, hopping over busy class slots.

A 10 minute break follows any block of 50 minutes or more. `meta` maps a
ref to (course_code, color) for display.
"""
def lay_out(
    picks: list[PlanPick],
    briefs: dict[str, TaskBrief],
    meta: dict[str, tuple[str, str]],
    start: datetime,
    available_minutes: int,
    busy: list[Busy]
) -> list[PlanBlock] {
    blocks: list[PlanBlock] = [];
    cursor = round_up(start, 5);
    budget = available_minutes;
    for pick in picks {
        if pick.ref not in briefs or budget < 15 {
            continue;
        }
        length = min(max(int(pick.minutes), 15), 150, budget);
        moved = True;
        while moved {
            moved = False;
            for b in busy {
                if cursor < b.end and cursor + timedelta(minutes=length) > b.start {
                    cursor = round_up(b.end + timedelta(minutes=5), 5);
                    moved = True;
                }
            }
        }
        brief = briefs[pick.ref];
        (code, color) = meta.get(pick.ref, ("", "#64748b"));
        end = cursor + timedelta(minutes=length);
        blocks.append(
            PlanBlock(
                start=to_iso(cursor),
                end=to_iso(end),
                minutes=length,
                title=brief.title,
                course_code=code,
                color=color,
                assignment_id=pick.ref,
                reason=pick.reason
            )
        );
        budget -= length;
        cursor = end + timedelta(minutes=(10 if length >= 50 else 0));
    }
    return blocks;
}

# ---------------------------------------------------------- heuristics ----

def heuristic_reason(brief: TaskBrief) -> str {
    h = brief.hours_until_due;
    if h is not None and h < 0 {
        return "Overdue - close this out first";
    }
    if h is not None and h <= 24 {
        return "Due within a day";
    }
    if brief.source == "autograder" and h is not None and h <= 120 {
        return "Autograder project - submit early to see test results";
    }
    if brief.priority >= 3 {
        return "Marked high priority";
    }
    if brief.est_hours >= 4 {
        return "Big job - chip away at it early";
    }
    if h is not None and h <= 72 {
        return "Due in the next few days";
    }
    return "Keeps you ahead of the week";
}

def heuristic_picks(tasks: list[TaskBrief], available_minutes: int, now: datetime) -> list[PlanPick] {
    scored: list[tuple[float, TaskBrief]] = [];
    for t in tasks {
        due = None if t.hours_until_due is None else now + timedelta(
            hours=t.hours_until_due
        );
        scored.append((urgency_score(due, now, t.priority, t.est_hours), t));
    }
    scored.sort(key=lambda (p: tuple[float, TaskBrief]) -> float { -p[0]; });
    picks: list[PlanPick] = [];
    left = available_minutes;
    for (_, t) in scored {
        if left < 20 {
            break;
        }
        want = int(t.est_hours * 60) if t.est_hours > 0 else 60;
        minutes = max(25, min(want, 75, left));
        picks.append(PlanPick(ref=t.ref, minutes=minutes, reason=heuristic_reason(t)));
        left -= minutes;
    }
    return picks;
}

def heuristic_tips(tasks: list[TaskBrief]) -> list[str] {
    tips: list[str] = [];
    if [t for t in tasks if t.source == "autograder"] {
        tips.append("Submit to the autograder early - the hidden tests tell you what to fix next.");
    }
    if [t for t in tasks if t.source == "gradescope"] {
        tips.append("Leave 10 minutes to upload to Gradescope and tag every page.");
    }
    if [t for t in tasks if t.hours_until_due is not None and t.hours_until_due < 0] {
        tips.append("Check the late policy for overdue work before starting new tasks.");
    }
    tips.append("Silence your phone and work in 50 minute sprints with short breaks.");
    return tips[:3];
}

def fallback_steps(title: str, source: str) -> list[str] {
    if source == "autograder" {
        return [
            "Read the spec and starter code end to end",
            "List the public test cases and edge cases",
            "Write your own tests first",
            "Implement the core functionality",
            "Submit to the autograder early and read failures",
            "Fix failing tests and clean up style",
            "Final submission well before the deadline"
        ];
    }
    if source == "gradescope" {
        return [
            "Read every problem and note what is asked",
            "Solve the problems you are confident about",
            "Go to office hours for the hard ones",
            "Write up clean final answers",
            "Scan or export to PDF",
            "Upload to Gradescope and tag each page"
        ];
    }
    return [
        "Re-read the instructions for " + title,
        "Gather the materials you need",
        "Do a rough first pass",
        "Review and polish",
        "Submit and confirm it went through"
    ];
}

# ------------------------------------------------------------ public ----

def build_plan(
    tasks: list[TaskBrief],
    meta: dict[str, tuple[str, str]],
    busy: list[Busy],
    now: datetime,
    hours: float,
    goal: str,
    use_ai: bool
) -> StudyPlan {
    available = max(30, min(int(hours * 60), 12 * 60));
    briefs = {t.ref: t for t in tasks};
    plan = StudyPlan();
    if not tasks {
        plan.summary = "Nothing open - you are all caught up. Enjoy the free time!";
        plan.source = "heuristic";
        return plan;
    }
    picks: list[PlanPick] = [];
    model = ai_model_name();
    if use_ai and model {
        try {
            draft = draft_plan(
                tasks,
                available,
                now.strftime("%A %b %d, ") + clock_label(now),
                goal
            );
            picks = [p for p in draft.picks if p.ref in briefs];
            if picks {
                plan.source = "ai";
                plan.summary = draft.summary;
                plan.tips = draft.tips[:3];
                plan.note = "Planned by " + model;
            }
        } except Exception as e {
            plan.note = "AI unavailable (" + type(e).__name__ + "), used the built-in planner";
        }
    } elif use_ai {
        plan.note = "No AI key set (ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY) - used the built-in planner";
    }
    if not picks {
        picks = heuristic_picks(tasks, available, now);
        plan.source = "heuristic";
        plan.tips = heuristic_tips(tasks);
        total = sum([p.minutes for p in picks]);
        noun = "block" if len(picks) == 1 else "blocks";
        plan.summary = f"{len(picks)} focused {noun}, {total // 60}h {total % 60}m of work, most urgent first.";
    }
    plan.blocks = lay_out(picks, briefs, meta, now, available, busy);
    return plan;
}

def suggest_steps(title: str, course: str, source: str, notes: str) -> tuple[list[str], str] {
    if ai_model_name() {
        try {
            steps = [s.strip() for s in draft_steps(title, course, source, notes) if s.strip()];
            if steps {
                return (steps[:8], "ai");
            }
        } except Exception {
            return (fallback_steps(title, source), "heuristic");
        }
    }
    return (fallback_steps(title, source), "heuristic");
}

def plan_start(now: datetime, start_hint: str) -> datetime {
    hinted = parse_iso(start_hint) if start_hint else None;
    if hinted is not None and hinted > now {
        return hinted;
    }
    return now;
}
