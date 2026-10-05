"""Canvas LMS import: the REST calls and the pure JSON -> record parsing.

Canvas is where every course lists its deadlines, including the ones that are
actually submitted elsewhere. Gradescope assignments show up as LTI external
tools and Autograder projects are linked from the description, so the parser
tags each assignment with its real destination. The network half is a thin
urllib client with Link-header pagination; the parsing half is pure and
covered by `canvas.test.jac` against recorded API payloads.
"""

import json;
import re;
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
     TAG_RE: re.Pattern[str] = re.compile(r"<[^>]+>");

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
