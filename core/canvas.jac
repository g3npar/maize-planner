"""Canvas LMS import: the REST calls and the pure JSON -> record parsing.

Canvas is where every course lists its deadlines, including the ones that are
actually submitted elsewhere. Gradescope assignments show up as LTI external
tools and Autograder projects are linked from the description, so the parser
tags each assignment with its real destination. The network half is a thin
urllib client with Link-header pagination; the parsing half is pure and
covered by `canvas.test.jac` against recorded API payloads.

Schools that don't let students create access tokens (UMich) still give each
student a private calendar feed (Canvas → Calendar → Calendar Feed). The feed
half parses that .ics: every assignment with its course and due date, but no
points, grades or groups.
"""

import json;
import re;
import from datetime { datetime, timezone }
import urllib.request;
import urllib.error;
import urllib.parse;
import from core.logic { parse_iso, to_iso }

obj CanvasCourse {
    has canvas_id: int = 0,
        code: str = "",
        name: str = "",
        term: str = "",
        url: str = "",
        apply_weights: bool = False;
}

obj CanvasAssignment {
    has canvas_id: int = 0,
        title: str = "",
        due: str = "",
        points: float = 0.0,
        url: str = "",
        source: str = "canvas",
        category: str = "",
        submitted: bool = False,
        score: float | None = None,
        external_url: str = "";
}

obj CanvasError(Exception) {
    has message: str = "",
        status: int = 0;
}

glob COURSE_CODE_RE: re.Pattern[str] = re.compile(r"\b([A-Z]{2,8})\s*[-_ ]?\s*(\d{3}[A-Z]?)\b"),
     GRADESCOPE_RE: re.Pattern[str] = re.compile(r"gradescope", re.IGNORECASE),
     AUTOGRADER_RE: re.Pattern[str] = re.compile(r"autograder(\.io)?", re.IGNORECASE),
     TAG_RE: re.Pattern[str] = re.compile(r"<[^>]+>"),
     FEED_SUMMARY_RE: re.Pattern[str] = re.compile(r"^(.*?)\s*\[([^\[\]]+)\]\s*$"),
     FEED_ASSIGNMENT_RE: re.Pattern[str] = re.compile(r"(?:assignment_|/assignments/)(\d+)"),
     FEED_UID_RE: re.Pattern[str] = re.compile(r"^event-assignment-(\d+)$"),
     FEED_COURSE_RE: re.Pattern[str] = re.compile(r"(?:course_|/courses/)(\d+)"),
     FEED_BASE_RE: re.Pattern[str] = re.compile(r"^(https?://[^/]+)");

# --------------------------------------------------------------- parsing ----

def clean_base(base_url: str) -> str {
    base = (base_url or "").strip().rstrip("/");
    if base and not base.startswith("http") {
        base = "https://" + base;
    }
    if base.endswith("/api/v1") {
        base = base[:-7];
    }
    return base;
}

"""Shorten "EECS 482 001 FA 2026" to "EECS 482"; falls back to the raw code."""
def short_code(course_code: str, name: str) -> str {
    for text in [course_code or "", name or ""] {
        m = COURSE_CODE_RE.search(text.upper());
        if m is not None {
            return m.group(1) + " " + m.group(2);
        }
    }
    return (course_code or name or "Course").strip()[:24];
}

def parse_course(raw: dict[str, any], base_url: str) -> CanvasCourse | None {
    cid = int(raw.get("id") or 0);
    name = str(raw.get("name") or "");
    if not cid or not name or raw.get("access_restricted_by_date") {
        return None;
    }
    term_obj = raw.get("term");
    term = str(term_obj.get("name") or "") if isinstance(term_obj, dict) else "";
    return CanvasCourse(
        canvas_id=cid,
        code=short_code(str(raw.get("course_code") or ""), name),
        name=name,
        term=term,
        url=f"{clean_base(base_url)}/courses/{cid}",
        apply_weights=bool(raw.get("apply_assignment_group_weights"))
    );
}

"""Where is this assignment really submitted? Returns (source, link)."""
def detect_source(raw: dict[str, any]) -> tuple[str, str] {
    types = [str(t) for t in (raw.get("submission_types") or [])];
    tool = raw.get("external_tool_tag_attributes");
    tool_url = str(tool.get("url") or "") if isinstance(tool, dict) else "";
    description = str(raw.get("description") or "");
    name = str(raw.get("name") or "");
    if GRADESCOPE_RE.search(tool_url) or GRADESCOPE_RE.search(name) {
        return ("gradescope", tool_url);
    }
    if "external_tool" in types and GRADESCOPE_RE.search(description) {
        return ("gradescope", tool_url);
    }
    if AUTOGRADER_RE.search(name) or AUTOGRADER_RE.search(tool_url) {
        return ("autograder", tool_url);
    }
    link = re.search(r"https?://autograder\.io[^\s\"'<>]*", description);
    if link is not None {
        return ("autograder", link.group(0));
    }
    if GRADESCOPE_RE.search(TAG_RE.sub(" ", description)) {
        return ("gradescope", tool_url);
    }
    return ("canvas", tool_url);
}

def parse_assignment(
    raw: dict[str, any], groups: dict[int, str]
) -> CanvasAssignment | None {
    aid = int(raw.get("id") or 0);
    if not aid {
        return None;
    }
    if raw.get("published") is False {
        return None;
    }
    (source, external) = detect_source(raw);
    due_dt = parse_iso(str(raw.get("due_at") or ""));
    sub = raw.get("submission");
    submitted = False;
    score: float | None = None;
    if isinstance(sub, dict) {
        state = str(sub.get("workflow_state") or "");
        submitted = state in ["submitted", "graded", "pending_review"] or bool(
            sub.get("submitted_at")
        );
        if sub.get("score") is not None and state == "graded" {
            score = float(str(sub.get("score")));
        }
    }
    group_id = int(raw.get("assignment_group_id") or 0);
    return CanvasAssignment(
        canvas_id=aid,
        title=str(raw.get("name") or "Untitled").strip(),
        due=to_iso(due_dt) if due_dt is not None else "",
        points=float(raw.get("points_possible") or 0.0),
        url=str(raw.get("html_url") or ""),
        source=source,
        category=groups.get(group_id, ""),
        submitted=submitted,
        score=score,
        external_url=external
    );
}

def parse_groups(raw: list[dict[str, any]]) -> tuple[dict[int, str], dict[str, float]] {
    names: dict[int, str] = {};
    weights: dict[str, float] = {};
    for g in raw {
        gid = int(g.get("id") or 0);
        name = str(g.get("name") or "").strip();
        if not gid or not name {
            continue;
        }
        names[gid] = name;
        weight = float(g.get("group_weight") or 0.0);
        if weight > 0 {
            weights[name] = weight;
        }
    }
    return (names, weights);
}

def next_link(link_header: str) -> str {
    for part in (link_header or "").split(",") {
        m = re.search(r"<([^>]+)>\s*;\s*rel=\"next\"", part);
        if m is not None {
            return m.group(1);
        }
    }
    return "";
}

# ---------------------------------------------------------- calendar feed ----

def clean_feed_url(url: str) -> str {
    feed = (url or "").strip();
    if feed.startswith("webcal://") {
        feed = "https://" + feed[9:];
    }
    return feed;
}

def ics_unescape(text: str) -> str {
    out: list[str] = [];
    i = 0;
    while i < len(text) {
        ch = text[i];
        if ch == "\\" and i + 1 < len(text) {
            nxt = text[i + 1];
            out.append("\n" if nxt in "nN" else nxt);
            i += 2;
            continue;
        }
        out.append(ch);
        i += 1;
    }
    return "".join(out);
}

"""Split an .ics into its VEVENTs, each as {NAME: (params, value)}."""
def ics_events(text: str) -> list[dict[str, tuple[str, str]]] {
    lines: list[str] = [];
    for raw in (text or "").replace("\r\n", "\n").replace("\r", "\n").split("\n") {
        if raw[:1] in [" ", "\t"] and lines {
            lines[-1] = lines[-1] + raw[1:];
        } else {
            lines.append(raw);
        }
    }
    events: list[dict[str, tuple[str, str]]] = [];
    current: dict[str, tuple[str, str]] | None = None;
    for line in lines {
        if line == "BEGIN:VEVENT" {
            current = {};
        } elif line == "END:VEVENT" {
            if current is not None {
                events.append(current);
            }
            current = None;
        } elif current is not None and ":" in line {
            (head, value) = line.split(":", 1);
            (name, _, params) = head.partition(";");
            key = name.upper();
            # A recurring event can list skipped dates on several lines.
            if key in ["EXDATE", "RDATE"] and key in current {
                current[key] = (params, ",".join([current[key][1], value]));
            } else {
                current[key] = (params, value);
            }
        }
    }
    return events;
}

"""An .ics DTSTART/DUE value as a local ISO time; date-only means 23:59."""
def ics_due(params: str, value: str) -> str {
    raw = value.strip();
    try {
        if ("VALUE=DATE" in params.upper() and "DATE-TIME" not in params.upper()) or len(raw) == 8 {
            day = datetime.strptime(raw[:8], "%Y%m%d");
            return to_iso(day.replace(hour=23, minute=59));
        }
        if raw.endswith("Z") {
            d = datetime.strptime(raw[:-1], "%Y%m%dT%H%M%S").replace(tzinfo=timezone.utc);
            return to_iso(d.astimezone().replace(tzinfo=None));
        }
        d = datetime.strptime(raw[:15], "%Y%m%dT%H%M%S");
        tzid = re.search(r"TZID=([^;]+)", params, re.IGNORECASE);
        if tzid is not None {
            import from zoneinfo { ZoneInfo }
            try {
                d = d.replace(tzinfo=ZoneInfo(tzid.group(1).strip('"')));
                return to_iso(d.astimezone().replace(tzinfo=None));
            } except Exception {}
        }
        return to_iso(d);
    } except ValueError {
        return "";
    }
}

"""Assignments in a Canvas calendar feed, each with the course it belongs to.

Canvas titles assignment events "Name [Course]" and links them to
/courses/<id>/assignments/<id> (or calendar?include_contexts=course_<id>
...#assignment_<id>). Plain calendar events (lectures, office hours) are
skipped, and an assignment listed twice (section overrides) is kept once.
"""
def parse_feed(text: str) -> list[tuple[CanvasCourse, CanvasAssignment]] {
    out: list[tuple[CanvasCourse, CanvasAssignment]] = [];
    seen: set[int] = set();
    for ev in ics_events(text) {
        uid = ics_unescape(ev.get("UID", ("", ""))[1]).strip();
        url = ics_unescape(ev.get("URL", ("", ""))[1]).strip();
        m = FEED_ASSIGNMENT_RE.search(url);
        if m is None {
            m = FEED_UID_RE.search(uid);
        }
        if m is None {
            continue;
        }
        aid = int(m.group(1));
        if aid in seen {
            continue;
        }
        seen.add(aid);
        summary = ics_unescape(ev.get("SUMMARY", ("", ""))[1]).strip();
        sm = FEED_SUMMARY_RE.match(summary);
        title = (sm.group(1) if sm is not None else summary).strip() or "Untitled";
        label = sm.group(2).strip() if sm is not None else "";
        cm = FEED_COURSE_RE.search(url);
        cid = int(cm.group(1)) if cm is not None else 0;
        bm = FEED_BASE_RE.match(url);
        base = bm.group(1) if bm is not None else "";
        (params, value) = ev.get("DTSTART", ev.get("DUE", ("", "")));
        description = ics_unescape(ev.get("DESCRIPTION", ("", ""))[1]);
        (source, external) = detect_source({"name": title, "description": description});
        course = CanvasCourse(
            canvas_id=cid,
            code=short_code(label, label) if label else "Canvas",
            name=label,
            url=f"{base}/courses/{cid}" if base and cid else ""
        );
        item = CanvasAssignment(
            canvas_id=aid,
            title=title,
            due=ics_due(params, value),
            url=f"{base}/courses/{cid}/assignments/{aid}" if base and cid else url,
            source=source,
            external_url=external
        );
        out.append((course, item));
    }
    return out;
}

# --------------------------------------------------------------- network ----

def _get(url: str, token: str) -> tuple[any, str] {
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/json",
            "User-Agent": "jac-personal-planner/0.1"
        }
    );
    try {
        with urllib.request.urlopen(req, timeout=25) as resp {
            body = resp.read().decode("utf-8");
            link = resp.headers.get("Link") or "";
            return (json.loads(body), link);
        }
    } except urllib.error.HTTPError as e {
        if e.code == 401 {
            raise CanvasError(
                message="Canvas rejected the access token (401). Generate a new one under Account → Settings → New Access Token.",
                status=401
            );
        }
        raise CanvasError(message=f"Canvas returned HTTP {e.code} for {url}", status=e.code);
    } except urllib.error.URLError as e {
        raise CanvasError(message=f"Could not reach Canvas: {str(e.reason)}");
    } except TimeoutError {
        raise CanvasError(message="Canvas did not answer within 25 seconds");
    } except json.JSONDecodeError {
        raise CanvasError(message="Canvas answered with something that is not JSON - check the Canvas URL");
    }
}

def get_all(base_url: str, path: str, token: str, params: dict[str, any]) -> list[dict[str, any]] {
    query = urllib.parse.urlencode(params, doseq=True);
    url = f"{clean_base(base_url)}/api/v1{path}?{query}";
    out: list[dict[str, any]] = [];
    pages = 0;
    while url and pages < 20 {
        (data, link) = _get(url, token);
        if isinstance(data, dict) and data.get("errors") {
            raise CanvasError(message="Canvas error: " + json.dumps(data.get("errors"))[:200]);
        }
        if isinstance(data, list) {
            out.extend([d for d in data if isinstance(d, dict)]);
        }
        url = next_link(link);
        pages += 1;
    }
    return out;
}

def fetch_courses(base_url: str, token: str) -> list[CanvasCourse] {
    raw = get_all(
        base_url,
        "/courses",
        token,
        {"enrollment_state": "active", "include[]": ["term"], "per_page": 100}
    );
    courses: list[CanvasCourse] = [];
    for r in raw {
        c = parse_course(r, base_url);
        if c is not None {
            courses.append(c);
        }
    }
    return courses;
}

def fetch_course_work(
    base_url: str, token: str, canvas_id: int
) -> tuple[list[CanvasAssignment], dict[str, float]] {
    groups_raw = get_all(
        base_url, f"/courses/{canvas_id}/assignment_groups", token, {"per_page": 100}
    );
    (names, weights) = parse_groups(groups_raw);
    raw = get_all(
        base_url,
        f"/courses/{canvas_id}/assignments",
        token,
        {"include[]": ["submission"], "order_by": "due_at", "per_page": 100}
    );
    items: list[CanvasAssignment] = [];
    for r in raw {
        a = parse_assignment(r, names);
        if a is not None {
            items.append(a);
        }
    }
    return (items, weights);
}

def fetch_feed(feed_url: str) -> list[tuple[CanvasCourse, CanvasAssignment]] {
    url = clean_feed_url(feed_url);
    if not url.startswith("https://") and not url.startswith("http://") {
        raise CanvasError(
            message="That doesn't look like a calendar feed link. Copy it from Canvas → Calendar → Calendar Feed."
        );
    }
    req = urllib.request.Request(
        url, headers={"Accept": "text/calendar", "User-Agent": "jac-personal-planner/0.1"}
    );
    try {
        with urllib.request.urlopen(req, timeout=25) as resp {
            body = resp.read().decode("utf-8", errors="replace");
        }
    } except urllib.error.HTTPError as e {
        if e.code in [401, 403, 404] {
            raise CanvasError(
                message=f"Canvas didn't recognize that calendar feed ({e.code}). Copy the link again from Calendar → Calendar Feed.",
                status=e.code
            );
        }
        raise CanvasError(message=f"Canvas returned HTTP {e.code} for the calendar feed", status=e.code);
    } except urllib.error.URLError as e {
        raise CanvasError(message=f"Could not reach Canvas: {str(e.reason)}");
    } except TimeoutError {
        raise CanvasError(message="Canvas did not answer within 25 seconds");
    }
    if "BEGIN:VCALENDAR" not in body[:2000] {
        raise CanvasError(
            message="That link isn't a calendar feed. Copy it from Canvas → Calendar → Calendar Feed."
        );
    }
    return parse_feed(body);
}
