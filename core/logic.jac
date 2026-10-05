"""Pure planning logic shared by the service and its tests.

Nothing here touches the graph: dates in and strings out, so every rule
(what counts as "due soon", how a grade is weighted, how "eecs 482 p3 due fri
5pm" is understood) is unit-tested in `logic.test.jac`. Times are naive local
times formatted as `YYYY-MM-DDTHH:MM`; the server's clock is the user's clock.
"""

import re;
import from datetime { datetime, timedelta }
import from core.views { CategoryGrade, GradeSummary, QuickParse }

glob DAY_SHORT: list[str] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
     DAY_ALIASES: dict[str, int] = {
         "mon": 0,
         "monday": 0,
         "tue": 1,
         "tues": 1,
         "tuesday": 1,
         "wed": 2,
         "weds": 2,
         "wednesday": 2,
         "thu": 3,
         "thur": 3,
         "thurs": 3,
         "thursday": 3,
         "fri": 4,
         "friday": 4,
         "sat": 5,
         "saturday": 5,
         "sun": 6,
         "sunday": 6
     },
     MONTHS: dict[str, int] = {
         "jan": 1,
         "feb": 2,
         "mar": 3,
         "apr": 4,
         "may": 5,
         "jun": 6,
         "jul": 7,
         "aug": 8,
         "sep": 9,
         "sept": 9,
         "oct": 10,
         "nov": 11,
         "dec": 12
     },
     SOURCES: list[str] = ["canvas", "gradescope", "autograder", "other"],
     STATUSES: list[str] = ["todo", "doing", "done"];

# ---------------------------------------------------------------- clock ----

def now_local -> datetime {
    return datetime.now().replace(second=0, microsecond=0);
}

def to_iso(d: datetime) -> str {
    return d.strftime("%Y-%m-%dT%H:%M");
}

def parse_iso(text: str) -> datetime | None {
    raw = (text or "").strip();
    if not raw {
        return None;
    }
    if raw.endswith("Z") {
        raw = raw[:-1] + "+00:00";
    }
    try {
        d = datetime.fromisoformat(raw);
    } except ValueError {
        return None;
    }
    if d.tzinfo is not None {
        d = d.astimezone().replace(tzinfo=None);
    }
    return d.replace(second=0, microsecond=0);
}

def start_of_day(d: datetime) -> datetime {
    return d.replace(hour=0, minute=0, second=0, microsecond=0);
}

def start_of_week(d: datetime) -> datetime {
    return start_of_day(d) - timedelta(days=d.weekday());
}

# ----------------------------------------------------------- formatting ----

def clock_label(d: datetime) -> str {
    hour = d.hour % 12 or 12;
    suffix = "AM" if d.hour < 12 else "PM";
    if d.minute == 0 {
        return f"{hour} {suffix}";
    }
    return f"{hour}:{d.minute:02d} {suffix}";
}

def hhmm_label(hhmm: str) -> str {
    parts = (hhmm or "").split(":");
    if len(parts) != 2 {
        return hhmm;
    }
    try {
        d = datetime(2000, 1, 1, int(parts[0]), int(parts[1]));
    } except ValueError {
        return hhmm;
    }
    return clock_label(d);
}

def range_label(start: str, end: str) -> str {
    if not end {
        return hhmm_label(start);
    }
    return hhmm_label(start) + " – " + hhmm_label(end);
}

def days_label(days: list[int]) -> str {
    picked = sorted(set([d for d in days if 0 <= d <= 6]));
    if picked == [0, 2] {
        return "Mon/Wed";
    }
    if picked == [1, 3] {
        return "Tue/Thu";
    }
    if picked == [0, 2, 4] {
        return "Mon/Wed/Fri";
    }
    if picked == [0, 1, 2, 3, 4] {
        return "Weekdays";
    }
    return "/".join([DAY_SHORT[d] for d in picked]);
}

def date_label(d: datetime, now: datetime) -> str {
    delta = (start_of_day(d) - start_of_day(now)).days;
    if delta == 0 {
        return "Today";
    }
    if delta == 1 {
        return "Tomorrow";
    }
    if delta == -1 {
        return "Yesterday";
    }
    if 1 < delta < 7 {
        return DAY_SHORT[d.weekday()];
    }
    label = d.strftime("%b ") + str(d.day);
    if d.year != now.year {
        label += f", {d.year}";
    }
    return DAY_SHORT[d.weekday()] + " " + label;
}

def due_label(d: datetime | None, now: datetime) -> str {
    if d is None {
        return "No due date";
    }
    return date_label(d, now) + " · " + clock_label(d);
}

def span_label(minutes: int) -> str {
    if minutes < 60 {
        return f"{max(minutes, 1)}m";
    }
    hours = minutes // 60;
    if hours < 48 {
        rest = minutes % 60;
        return f"{hours}h" + (f" {rest}m" if rest and hours < 10 else "");
    }
    days = hours // 24;
    left = hours % 24;
    return f"{days}d" + (f" {left}h" if left and days < 7 else "");
}

def due_in(d: datetime | None, now: datetime, done: bool) -> str {
    if d is None {
        return "";
    }
    minutes = int((d - now).total_seconds() // 60);
    if done {
        return "done";
    }
    if minutes < 0 {
        return span_label(-minutes) + " overdue";
    }
    return "in " + span_label(minutes);
}

def urgency(d: datetime | None, now: datetime, done: bool) -> str {
    if done {
        return "done";
    }
    if d is None {
        return "none";
    }
    if d < now {
        return "overdue";
    }
    days = (start_of_day(d) - start_of_day(now)).days;
    if days == 0 {
        return "today";
    }
    if days == 1 {
        return "tomorrow";
    }
    if days < 7 {
        return "week";
    }
    return "later";
}

def greeting(now: datetime, name: str) -> str {
    part = "Good morning";
    if now.hour >= 17 {
        part = "Good evening";
    } elif now.hour >= 12 {
        part = "Good afternoon";
    }
    return part + (", " + name if name else "");
}

def short_id(full: str) -> str {
    return full[:6];
}

# ------------------------------------------------------ parsing "when" ----

def _parse_clock(text: str) -> tuple[int, int] | None {
    t = text.strip().lower().replace(".", "");
    if t in ["noon", "midday"] {
        return (12, 0);
    }
    if t in ["midnight", "eod", "end of day"] {
        return (23, 59);
    }
    m = re.fullmatch(r"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?", t);
    if m is None {
        return None;
    }
    hour = int(m.group(1));
    minute = int(m.group(2) or "0");
    suffix = m.group(3) or "";
    if suffix.startswith("p") and hour < 12 {
        hour += 12;
    }
    if suffix.startswith("a") and hour == 12 {
        hour = 0;
    }
    if not suffix and m.group(2) is None {
        return None;
    }
    if hour > 23 or minute > 59 {
        return None;
    }
    return (hour, minute);
}

"""Pull a trailing time ("11:59pm", "at 5 pm", "noon") off a phrase."""
def _split_time(text: str) -> tuple[str, tuple[int, int] | None] {
    t = text.strip().lower();
    m = re.search(
        r"(?:\s+at\s+|\s+@\s*|\s+|^)(\d{1,2}(?::\d{2})?\s*(?:am|pm|a|p)|\d{1,2}:\d{2}|noon|midnight|eod)$",
        t
    );
    if m is None {
        return (t, None);
    }
    clock = _parse_clock(m.group(1));
    if clock is None {
        return (t, None);
    }
    return (t[:m.start()].strip(), clock);
}

"""Understand the due dates people actually type.

today / tonight / tomorrow / fri / next fri / in 3 days / 10/5 /
2026-10-05 / oct 5 - each optionally followed by a time. A date with no
time is due at 11:59 PM, the way most course deadlines are.
"""
def parse_when(text: str, now: datetime) -> datetime | None {
    raw = (text or "").strip().lower();
    if not raw {
        return None;
    }
    iso = parse_iso(text.strip().replace(" ", "T", 1));
    if iso is not None and re.match(r"\d{4}-\d{2}-\d{2}[t ]\d{1,2}:\d{2}", raw) {
        return iso;
    }
    (phrase, clock) = _split_time(raw);
    phrase = phrase.replace(",", " ").strip();
    phrase = re.sub(r"^(on|by|due)\s+", "", phrase).strip();
    base: datetime | None = None;
    today = start_of_day(now);
    if phrase in ["", "today", "tod"] {
        base = today;
    } elif phrase == "tonight" {
        base = today;
        if clock is None {
            clock = (23, 59);
        }
    } elif phrase in ["tomorrow", "tmrw", "tmr", "tom"] {
        base = today + timedelta(days=1);
    } elif phrase in DAY_ALIASES {
        ahead = (DAY_ALIASES[phrase] - now.weekday()) % 7;
        base = today + timedelta(days=ahead);
    } elif phrase.startswith("next ") and phrase[5:] in DAY_ALIASES {
        ahead = (DAY_ALIASES[phrase[5:]] - now.weekday()) % 7;
        base = today + timedelta(days=(ahead or 7) + (7 if ahead else 0));
    } elif phrase == "next week" {
        base = today + timedelta(days=7);
    } else {
        rel = re.fullmatch(r"in\s+(\d+)\s*(d|day|days|w|wk|week|weeks|h|hr|hrs|hour|hours)", phrase);
        num = re.fullmatch(r"(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?", phrase);
        ymd = re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})", phrase);
        mon = re.fullmatch(r"([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s+(\d{4}))?", phrase);
        if rel is not None {
            amount = int(rel.group(1));
            unit = rel.group(2);
            if unit.startswith("h") {
                return now + timedelta(hours=amount);
            }
            base = today + timedelta(days=amount * (7 if unit.startswith("w") else 1));
        } elif ymd is not None {
            try {
                base = datetime(int(ymd.group(1)), int(ymd.group(2)), int(ymd.group(3)));
            } except ValueError {
                return None;
            }
        } elif num is not None {
            year = int(num.group(3)) if num.group(3) else now.year;
            if year < 100 {
                year += 2000;
            }
            try {
                picked = datetime(year, int(num.group(1)), int(num.group(2)));
            } except ValueError {
                return None;
            }
            if not num.group(3) and picked < today - timedelta(days=60) {
                picked = picked.replace(year=year + 1);
            }
            base = picked;
        } elif mon is not None and mon.group(1)[:3] in MONTHS {
            key: str = mon.group(1)[:3];
            day_text: str = mon.group(2);
            year_text: str = mon.group(3) or "";
            year = int(year_text) if year_text else now.year;
            try {
                on_day = datetime(year, MONTHS[key], int(day_text));
            } except ValueError {
                return None;
            }
            if not year_text and on_day < today - timedelta(days=60) {
                on_day = on_day.replace(year=year + 1);
            }
            base = on_day;
        } else {
            return None;
        }
    }
    if base is None {
        return None;
    }
    (hour, minute) = clock if clock is not None else (23, 59);
    return base.replace(hour=hour, minute=minute);
}

# ------------------------------------------------------------ quick add ----

def normalize_code(code: str) -> str {
    return re.sub(r"[^a-z0-9]", "", (code or "").lower());
}

"""Return the course code whose letters+number start `text` (spaces optional)."""
def match_course(text: str, codes: list[str]) -> str {
    flat = normalize_code(text[:24]);
    best = "";
    for code in codes {
        key = normalize_code(code);
        if key and flat.startswith(key) and len(key) > len(normalize_code(best)) {
            best = code;
        }
    }
    return best;
}

def _strip_course_prefix(text: str, code: str) -> str {
    key = normalize_code(code);
    consumed = "";
    idx = 0;
    while idx < len(text) and normalize_code(consumed) != key {
        consumed += text[idx];
        idx += 1;
    }
    return text[idx:].lstrip(" :-–—").strip();
}

"""Turn "EECS 482 project 3 due fri 11:59pm #autograder !!" into fields."""
def quick_parse(text: str, codes: list[str], now: datetime) -> QuickParse {
    out = QuickParse();
    work = " " + (text or "").strip() + " ";
    tag_sources: dict[str, str] = {
        "#gs": "gradescope",
        "#gradescope": "gradescope",
        "#ag": "autograder",
        "#autograder": "autograder",
        "#canvas": "canvas"
    };
    for (tag, src) in tag_sources.items() {
        pattern = re.compile(re.escape(tag) + r"(?=\s)", re.IGNORECASE);
        if pattern.search(work) {
            out.source = src;
            work = pattern.sub(" ", work);
        }
    }
    pts = re.search(r"\s(\d+(?:\.\d+)?)\s*(?:pts|points)\b", work, re.IGNORECASE);
    if pts is not None {
        out.points = float(pts.group(1));
        work = work[:pts.start()] + " " + work[pts.end():];
    }
    if re.search(r"\s!!!?(?=\s)", work) {
        out.priority = 3;
    } elif re.search(r"\s!(?=\s)", work) {
        out.priority = 2;
    }
    if re.search(r"\s(?:~|low)(?=\s)", work) {
        out.priority = 1;
    }
    work = re.sub(r"\s(?:!!!?|!|~)(?=\s)", " ", work);
    due_match = re.search(r"\s(?:due|by|@)\s+(.+?)\s*$", work, re.IGNORECASE);
    if due_match is not None {
        when = parse_when(due_match.group(1), now);
        if when is not None {
            out.due = to_iso(when);
            work = work[:due_match.start()];
        }
    }
    work = work.strip();
    code = match_course(work, codes);
    if code {
        out.course_code = code;
        work = _strip_course_prefix(work, code);
    }
    if out.source == "other" {
        low = work.lower();
        if "gradescope" in low {
            out.source = "gradescope";
        } elif "autograder" in low {
            out.source = "autograder";
        }
    }
    out.title = re.sub(r"\s+", " ", work).strip() or "Untitled task";
    return out;
}

# --------------------------------------------------------------- grades ----

obj GradeInput {
    has category: str = "",
        points: float = 0.0,
        score: float | None = None;
}

def letter_for(pct: float) -> str {
    cutoffs: list[tuple[float, str]] = [
        (93.0, "A"),
        (90.0, "A-"),
        (87.0, "B+"),
        (83.0, "B"),
        (80.0, "B-"),
        (77.0, "C+"),
        (73.0, "C"),
        (70.0, "C-"),
        (67.0, "D+"),
        (60.0, "D")
    ];
    for (cut, letter) in cutoffs {
        if pct >= cut {
            return letter;
        }
    }
    return "E";
}

"""Weighted course grade, plus the average still needed to hit `target`.

With category weights, each category contributes (earned / possible) *
weight, renormalised over the categories that have graded work. Without
weights, it is plain total points. Ungraded work with points counts as
"remaining" and drives the needed-average estimate.
"""
def compute_grade(
    items: list[GradeInput], weights: dict[str, float], target: float
) -> GradeSummary {
    counted = [item for item in items if item.points > 0];
    summary = GradeSummary(total_count=len(counted));
    usable = {k: float(v) for (k, v) in (weights or {}).items() if float(v) > 0};
    cats: dict[str, CategoryGrade] = {};
    remaining_points: dict[str, float] = {};
    for item in counted {
        name = item.category or "Uncategorized";
        if name not in cats {
            cats[name] = CategoryGrade(name=name, weight=usable.get(name, 0.0));
            remaining_points[name] = 0.0;
        }
        cat = cats[name];
        if item.score is not None and item.points > 0 {
            cat.earned += float(item.score);
            cat.possible += item.points;
            cat.graded += 1;
            summary.graded_count += 1;
        } elif item.score is None and item.points > 0 {
            cat.remaining += 1;
            remaining_points[name] = remaining_points[name] + item.points;
        }
    }
    for name in usable.keys() {
        if name not in cats {
            cats[name] = CategoryGrade(name=name, weight=usable[name]);
            remaining_points[name] = 0.0;
        }
    }
    for cat in cats.values() {
        if cat.possible > 0 {
            cat.pct = round(100.0 * cat.earned / cat.possible, 2);
        }
    }
    summary.categories = sorted(
        cats.values(),
        key=lambda (c: CategoryGrade) -> tuple[float, str] { (-c.weight, c.name); }
    );
    weighted = [c for c in cats.values() if c.weight > 0];
    summary.weighted = len(weighted) > 0;
    if summary.weighted {
        graded_w = sum([c.weight for c in weighted if c.pct is not None]);
        if graded_w > 0 {
            achieved = sum([c.weight * (c.pct or 0.0) for c in weighted if c.pct is not None]);
            summary.current = round(achieved / graded_w, 2);
        }
        total_w = sum([c.weight for c in weighted]);
        open_w = sum([c.weight for c in weighted if c.pct is None]);
        partial = 0.0;
        for c in weighted {
            if c.pct is not None and remaining_points.get(c.name, 0.0) > 0 {
                share = remaining_points[c.name] / (c.possible + remaining_points[c.name]);
                partial += c.weight * share;
            }
        }
        future_w = open_w + partial;
        if summary.current is not None and future_w > 0 and total_w > 0 {
            locked = (total_w - future_w) * (
                achieved_on_locked(weighted, remaining_points)
            );
            summary.needed = round((target * total_w - locked) / future_w, 1);
        } elif summary.current is None and total_w > 0 {
            summary.needed = target;
        }
    } else {
        earned = sum([c.earned for c in cats.values()]);
        possible = sum([c.possible for c in cats.values()]);
        left = sum(remaining_points.values());
        if possible > 0 {
            summary.current = round(100.0 * earned / possible, 2);
        }
        if left > 0 {
            summary.needed = round(
                100.0 * ((target / 100.0) * (possible + left) - earned) / left, 1
            );
        }
    }
    if summary.current is not None {
        summary.letter = letter_for(summary.current);
    }
    if summary.needed is not None {
        if summary.needed <= 0 {
            summary.note = f"Target {target:g}% is locked in";
        } elif summary.needed > 100 {
            summary.note = f"Target {target:g}% needs {summary.needed:g}% on remaining work";
        } else {
            summary.note = f"Average {summary.needed:g}% on remaining work to reach {target:g}%";
        }
    } elif summary.current is None {
        summary.note = "No graded work yet";
    }
    return summary;
}

"""Average percent over the already-graded share of the weighted categories."""
def achieved_on_locked(
    weighted: list[CategoryGrade], remaining_points: dict[str, float]
) -> float {
    num = 0.0;
    den = 0.0;
    for c in weighted {
        if c.pct is None {
            continue;
        }
        left = remaining_points.get(c.name, 0.0);
        share = c.possible / (c.possible + left) if (c.possible + left) > 0 else 1.0;
        num += c.weight * share * c.pct;
        den += c.weight * share;
    }
    return num / den if den > 0 else 0.0;
}

# ------------------------------------------------------------- urgency ----

"""Higher is more pressing: soon deadlines, high priority, big jobs."""
def urgency_score(
    due: datetime | None, now: datetime, priority: int, est_hours: float
) -> float {
    if due is None {
        return 1.0 + priority;
    }
    hours_left = (due - now).total_seconds() / 3600.0;
    if hours_left < 0 {
        return 1000.0 + priority * 10;
    }
    effort = max(est_hours, 1.0);
    soon = 60.0 if hours_left <= 24 else 0.0;
    return 100.0 * effort / max(hours_left, 1.0) + priority * 5 + soon;
}
