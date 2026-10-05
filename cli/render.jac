"""Terminal rendering: colors, rows and tables. Pure string functions."""

import os;
import sys;
import from core.planner { AssignmentView, ClassSlot, CourseView }

glob SOURCE_TAGS: dict[str, str] = {
         "canvas": "Canvas",
         "gradescope": "Gradescope",
         "autograder": "Autograder",
         "other": ""
     },
     URGENCY_HEX: dict[str, str] = {
         "overdue": "#ef4444",
         "today": "#f97316",
         "tomorrow": "#eab308",
         "week": "#60a5fa",
         "later": "#94a3b8",
         "none": "#94a3b8",
         "done": "#22c55e"
     },
     SOURCE_HEX: dict[str, str] = {
         "canvas": "#f0634b",
         "gradescope": "#2bb3b0",
         "autograder": "#a78bfa",
         "other": "#94a3b8"
     };

glob _color: list[bool] = [];

def use_color -> bool {
    if not _color {
        wants = sys.stdout.isatty() and not os.environ.get("NO_COLOR") and os.environ.get(
            "TERM", ""
        ) != "dumb";
        _color.append(bool(wants));
    }
    return _color[0];
}

def set_color(enabled: bool) {
    _color.clear();
    _color.append(enabled);
}

def hex_fg(text: str, hex_color: str) -> str {
    if not use_color() or len(hex_color) != 7 {
        return text;
    }
    try {
        r = int(hex_color[1:3], 16);
        g = int(hex_color[3:5], 16);
        b = int(hex_color[5:7], 16);
    } except ValueError {
        return text;
    }
    return f"\x1b[38;2;{r};{g};{b}m{text}\x1b[0m";
}

def bold(text: str) -> str {
    return f"\x1b[1m{text}\x1b[0m" if use_color() else text;
}

def dim(text: str) -> str {
    return f"\x1b[2m{text}\x1b[0m" if use_color() else text;
}

def strike(text: str) -> str {
    return f"\x1b[9m{text}\x1b[0m" if use_color() else text;
}

def pad(text: str, width: int) -> str {
    visible = len(strip_ansi(text));
    return text + " " * max(0, width - visible);
}

def strip_ansi(text: str) -> str {
    import re;
    return re.sub(r"\x1b\[[0-9;]*m", "", text);
}

def truncate(text: str, width: int) -> str {
    return text if len(text) <= width else text[:max(0, width - 1)] + "…";
}

def check_box(status: str) -> str {
    if status == "done" {
        return hex_fg("✔", "#22c55e");
    }
    if status == "doing" {
        return hex_fg("◐", "#38bdf8");
    }
    return "○";
}

def task_line(a: AssignmentView, show_course: bool = True) -> str {
    title = truncate(a.title, 46);
    if a.priority >= 3 {
        title = hex_fg("!! ", "#ef4444") + title;
    }
    title = strike(title) if a.status == "done" else bold(title);
    parts = [
        dim(a.short_id),
        check_box(a.status),
        pad(hex_fg(a.course_code, a.course_color), 10) if show_course else "",
        title
    ];
    extras: list[str] = [];
    tag = SOURCE_TAGS.get(a.source, "");
    if tag {
        extras.append(hex_fg(tag, SOURCE_HEX.get(a.source, "#94a3b8")));
    }
    if a.subtasks {
        done = len([x for x in a.subtasks_done if x]);
        extras.append(dim(f"{done}/{len(a.subtasks)} steps"));
    }
    if a.score is not None {
        extras.append(dim(f"{a.score:g}/{a.points:g}"));
    }
    when = dim(a.due_label) + ("  " + hex_fg(a.due_in, URGENCY_HEX.get(a.urgency, "#94a3b8")) if a.due_in else "");
    head = " ".join([p for p in parts if p]);
    tail = ("  " + dim("·") + " " + ("  ".join(extras))) if extras else "";
    return f"{head}{tail}\n         {when}";
}

def section(title: str, count: int, hex_color: str) -> str {
    return hex_fg("● ", hex_color) + bold(title.upper()) + dim(f"  {count}");
}

def class_line(s: ClassSlot) -> str {
    state = "";
    if s.state == "now" {
        state = hex_fg("  ← now", "#22c55e");
    } elif s.state == "past" {
        state = dim("  (done)");
    }
    where = dim(" · " + s.location) if s.location else "";
    return f"  {pad(s.time_label, 18)} {hex_fg(s.course_code, s.color)} {s.kind}{where}{state}";
}

def grade_bar(pct: float | None, width: int, hex_color: str) -> str {
    if pct is None {
        return dim("·" * width);
    }
    filled = int(round(max(0.0, min(pct, 100.0)) / 100.0 * width));
    return hex_fg("█" * filled, hex_color) + dim("░" * (width - filled));
}

def course_line(c: CourseView) -> str {
    g = c.grade;
    grade = f"{g.letter:<3}{g.current:6.1f}%" if g.current is not None else "   –      ";
    overdue = hex_fg(f"  {c.overdue_count} overdue", "#ef4444") if c.overdue_count else "";
    return (
        f"{pad(hex_fg(bold(c.code), c.color), 10)} {pad(truncate(c.name or '', 34), 35)}"
        + f"{grade}  {grade_bar(g.current, 20, c.color)}  {c.open_count} open{overdue}"
    );
}
