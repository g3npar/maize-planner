"""Google Calendar import: your own events as busy time in the planner.

Google gives every calendar a private iCal link (Google Calendar → Settings →
your calendar → Integrate calendar → "Secret address in iCal format"). Sync
downloads it, expands recurring events into the dates around now, and the
planner shows them next to class meetings: on Today, in the week view, and as
busy time the study plan works around. Read-only; nothing is written back.

The parsing half is pure (`gcal.test.jac`); `fetch_calendar` is the only
network call.
"""

import json;
import re;
import urllib.request;
import urllib.error;
import from datetime { datetime, timedelta, timezone }
import from core.canvas { ics_events, ics_unescape }
import from core.logic { to_iso, parse_iso }

obj CalEvent {
    has title: str = "",
        start: str = "",
        end: str = "",
        location: str = "",
        all_day: bool = False;
}

obj CalendarError(Exception) {
    has message: str = "";
}

glob WEEKDAYS: dict[str, int] = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6},
     BYDAY_RE: re.Pattern[str] = re.compile(r"^([+-]?\d{0,2})(MO|TU|WE|TH|FR|SA|SU)$"),
     DURATION_RE: re.Pattern[str] = re.compile(
         r"^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$"
     ),
     # Stop expanding a runaway rule (e.g. a daily event from years ago).
     MAX_STEPS: int = 20000;

# --------------------------------------------------------------- parsing ----

"""An iCal date or date-time as a naive local datetime, and whether it is a
whole day. UTC ("Z") and TZID times are converted to the server's zone."""
def ics_time(params: str, value: str) -> tuple[datetime | None, bool] {
    raw = value.strip();
    try {
        if ("VALUE=DATE" in params.upper() and "DATE-TIME" not in params.upper())
            or len(raw) == 8 {
            return (datetime.strptime(raw[:8], "%Y%m%d"), True);
        }
        if raw.endswith("Z") {
            d = datetime.strptime(raw[:-1], "%Y%m%dT%H%M%S").replace(tzinfo=timezone.utc);
            return (d.astimezone().replace(tzinfo=None), False);
        }
        d = datetime.strptime(raw[:15], "%Y%m%dT%H%M%S");
        tzid = re.search(r"TZID=([^;:]+)", params, re.IGNORECASE);
        if tzid is not None {
            import from zoneinfo { ZoneInfo }
            try {
                zoned = d.replace(tzinfo=ZoneInfo(tzid.group(1).strip('"')));
                return (zoned.astimezone().replace(tzinfo=None), False);
            } except Exception {}
        }
        return (d, False);
    } except ValueError {
        return (None, False);
    }
}

def parse_duration(text: str) -> timedelta | None {
    m = DURATION_RE.match((text or "").strip().upper());
    if m is None or not any(m.groups()[1:]) {
        return None;
    }
    (sign, w, d, h, mi, s) = m.groups();
    span = timedelta(
        weeks=int(w or 0),
        days=int(d or 0),
        hours=int(h or 0),
        minutes=int(mi or 0),
        seconds=int(s or 0)
    );
    return -span if sign == "-" else span;
}

def parse_rule(text: str) -> dict[str, str] {
    rule: dict[str, str] = {};
    for part in (text or "").split(";") {
        if "=" in part {
            (k, v) = part.split("=", 1);
            rule[k.strip().upper()] = v.strip().upper();
        }
    }
    return rule;
}

def _add_months(d: datetime, months: int) -> datetime | None {
    total = d.month - 1 + months;
    try {
        return d.replace(year=d.year + total // 12, month=total % 12 + 1);
    } except ValueError {
        return None;  # e.g. the 31st in a 30-day month: that month is skipped
    }
}

"""Days of `month_start`'s month matching BYDAY entries like 2TU or -1FR."""
def _monthly_byday(month_start: datetime, byday: list[str]) -> list[datetime] {
    days: list[datetime] = [];
    nxt = _add_months(month_start, 1);
    if nxt is None {
        return days;
    }
    month_days: list[datetime] = [];
    d = month_start;
    while d < nxt {
        month_days.append(d);
        d = d + timedelta(days=1);
    }
    for spec in byday {
        m = BYDAY_RE.match(spec);
        if m is None {
            continue;
        }
        wd = WEEKDAYS[m.group(2)];
        matching = [x for x in month_days if x.weekday() == wd];
        if not m.group(1) or m.group(1) in ["+", "-"] {
            days.extend(matching);
        } else {
            n = int(m.group(1));
            if 0 < n <= len(matching) {
                days.append(matching[n - 1]);
            } elif 0 < -n <= len(matching) {
                days.append(matching[n]);
            }
        }
    }
    return sorted(days);
}

"""Start times of a recurring event (RRULE) that fall in [lo, hi].

Supports what Google exports: FREQ DAILY/WEEKLY/MONTHLY/YEARLY with
INTERVAL, COUNT, UNTIL, BYDAY (weekly, or 2TU-style in monthly) and
BYMONTHDAY. COUNT counts every occurrence from the first, as in RFC 5545.
"""
def expand_rule(
    first: datetime, rule: dict[str, str], lo: datetime, hi: datetime
) -> list[datetime] {
    freq = rule.get("FREQ", "");
    interval = max(1, int(rule.get("INTERVAL", "1") or "1"));
    count = int(rule["COUNT"]) if rule.get("COUNT", "").isdigit() else 0;
    until: datetime | None = None;
    if rule.get("UNTIL") {
        (until, whole_day) = ics_time("", rule["UNTIL"]);
        if until is not None and whole_day {
            until = until + timedelta(days=1) - timedelta(seconds=1);
        }
    }
    byday = [d for d in rule.get("BYDAY", "").split(",") if d];
    bymonthday = [int(d) for d in rule.get("BYMONTHDAY", "").split(",") if d.lstrip("-").isdigit()];
    out: list[datetime] = [];
    emitted = 0;
    steps = 0;
    period = 0;
    while steps < MAX_STEPS {
        steps += 1;
        candidates: list[datetime] = [];
        if freq == "DAILY" {
            candidates = [first + timedelta(days=period * interval)];
        } elif freq == "WEEKLY" {
            week_start = first - timedelta(days=first.weekday()) + timedelta(weeks=period * interval);
            wds = sorted(set([WEEKDAYS[d[-2:]] for d in byday if d[-2:] in WEEKDAYS])) or [first.weekday()];
            candidates = [week_start + timedelta(days=wd) for wd in wds];
        } elif freq == "MONTHLY" {
            month_start = _add_months(first.replace(day=1), period * interval);
            if month_start is not None {
                if byday {
                    candidates = _monthly_byday(month_start, byday);
                } else {
                    for md in (bymonthday or [first.day]) {
                        try {
                            if md > 0 {
                                candidates.append(month_start.replace(day=md));
                            } else {
                                nxt = _add_months(month_start, 1);
                                if nxt is not None {
                                    candidates.append(nxt + timedelta(days=md));
                                }
                            }
                        } except ValueError {}
                    }
                }
            }
        } elif freq == "YEARLY" {
            try {
                candidates = [first.replace(year=first.year + period * interval)];
            } except ValueError {
                candidates = [];  # Feb 29 in a non-leap year
            }
        } else {
            return [first] if lo <= first <= hi else [];
        }
        for cand in sorted(candidates) {
            if cand < first {
                continue;
            }
            # The rule has ended: past UNTIL, out of COUNT, or past the window.
            if (until is not None and cand > until) or (count and emitted >= count) or cand > hi {
                return out;
            }
            if cand >= lo {
                out.append(cand);
            }
            emitted += 1;
        }
        period += 1;
    }
    return out;
}

def _dates(params: str, value: str) -> list[str] {
    found: list[str] = [];
    for part in value.split(",") {
        (d, _) = ics_time(params, part);
        if d is not None {
            found.append(to_iso(d));
        }
    }
    return found;
}

"""Events (recurring ones expanded) that overlap [lo, hi], sorted by start."""
def parse_calendar(text: str, lo: datetime, hi: datetime) -> list[CalEvent] {
    raw = ics_events(text);
    moved: set[tuple[str, str]] = set();
    for ev in raw {
        if "RECURRENCE-ID" in ev {
            (rp, rv) = ev["RECURRENCE-ID"];
            (rid, _) = ics_time(rp, rv);
            if rid is not None {
                moved.add((ev.get("UID", ("", ""))[1], to_iso(rid)));
            }
        }
    }
    out: list[CalEvent] = [];
    for ev in raw {
        if ev.get("STATUS", ("", ""))[1].upper() == "CANCELLED" {
            continue;
        }
        (sp, sv) = ev.get("DTSTART", ("", ""));
        (start, all_day) = ics_time(sp, sv);
        if start is None {
            continue;
        }
        end: datetime | None = None;
        if "DTEND" in ev {
            (ep, evv) = ev["DTEND"];
            (end, _) = ics_time(ep, evv);
        } elif "DURATION" in ev {
            span = parse_duration(ev["DURATION"][1]);
            end = start + span if span is not None else None;
        }
        if end is None or end < start {
            end = start + (timedelta(days=1) if all_day else timedelta(0));
        }
        length = end - start;
        uid = ev.get("UID", ("", ""))[1];
        title = ics_unescape(ev.get("SUMMARY", ("", ""))[1]).strip() or "Busy";
        location = ics_unescape(ev.get("LOCATION", ("", ""))[1]).strip();
        starts = [start];
        if "RRULE" in ev and "RECURRENCE-ID" not in ev {
            excluded: list[str] = [];
            if "EXDATE" in ev {
                (xp, xv) = ev["EXDATE"];
                excluded = _dates(xp, xv);
            }
            first: datetime = start or lo;
            expanded = expand_rule(first, parse_rule(ev["RRULE"][1]), lo - length, hi);
            starts = [
                s
                for s in expanded
                if to_iso(s) not in excluded and (uid, to_iso(s)) not in moved
            ];
        }
        for s in starts {
            e = s + length;
            if s > hi or e < lo or (e == lo and e > s) {
                continue;
            }
            out.append(
                CalEvent(
                    title=title,
                    start=to_iso(s),
                    end=to_iso(e),
                    location=location,
                    all_day=all_day
                )
            );
        }
    }
    return sorted(out, key=lambda (e: CalEvent) -> str { e.start; });
}

# ------------------------------------------------------- stored events ----

"""Events as compact JSON for the Profile node (rows, not objects)."""
def dump_events(events: list[CalEvent]) -> str {
    return json.dumps([[e.title, e.start, e.end, e.location, e.all_day] for e in events]);
}

glob _LOADED: dict[str, list[CalEvent]] = {};

def load_events(text: str) -> list[CalEvent] {
    if not text {
        return [];
    }
    if text in _LOADED {
        return _LOADED[text];
    }
    events: list[CalEvent] = [];
    try {
        for row in json.loads(text) {
            events.append(
                CalEvent(title=row[0], start=row[1], end=row[2], location=row[3], all_day=bool(row[4]))
            );
        }
    } except (ValueError, IndexError, TypeError) {
        return [];
    }
    _LOADED.clear();  # keep only the latest calendar in memory
    _LOADED[text] = events;
    return events;
}

"""The parts of each event that fall on `day`: (event, start, end) with the
times clipped to the day. All-day events come back with start = end = day."""
def events_on(events: list[CalEvent], day: datetime) -> list[tuple[CalEvent, datetime, datetime]] {
    day0 = day.replace(hour=0, minute=0, second=0, microsecond=0);
    day1 = day0 + timedelta(days=1);
    found: list[tuple[CalEvent, datetime, datetime]] = [];
    for e in events {
        s = parse_iso(e.start);
        f = parse_iso(e.end);
        if s is None or f is None {
            continue;
        }
        if e.all_day {
            if s <= day0 < f {
                found.append((e, day0, day0));
            }
        } elif s < day1 and (f > day0 or (f == s and s >= day0)) {
            found.append((e, max(s, day0), min(f, day1)));
        }
    }
    return found;
}

# --------------------------------------------------------------- network ----

def clean_calendar_url(url: str) -> str {
    link = (url or "").strip();
    if link.startswith("webcal://") {
        link = "https://" + link[9:];
    }
    return link;
}

def fetch_calendar(url: str) -> str {
    link = clean_calendar_url(url);
    if not link.startswith("https://") and not link.startswith("http://") {
        raise CalendarError(
            message="That doesn't look like a calendar link. In Google Calendar copy Settings → your calendar → \"Secret address in iCal format\"."
        );
    }
    req = urllib.request.Request(
        link, headers={"Accept": "text/calendar", "User-Agent": "jac-personal-planner/0.1"}
    );
    try {
        with urllib.request.urlopen(req, timeout=25) as resp {
            body = resp.read().decode("utf-8", errors="replace");
        }
    } except urllib.error.HTTPError as e {
        if e.code in [401, 403, 404] {
            raise CalendarError(
                message=f"Google didn't recognize that calendar link ({e.code}). Copy the secret iCal address again; it changes if you reset it."
            );
        }
        raise CalendarError(message=f"The calendar server returned HTTP {e.code}");
    } except urllib.error.URLError as e {
        raise CalendarError(message=f"Could not reach the calendar: {str(e.reason)}");
    } except TimeoutError {
        raise CalendarError(message="The calendar did not answer within 25 seconds");
    }
    if "BEGIN:VCALENDAR" not in body[:2000] {
        raise CalendarError(
            message="That link isn't an iCal calendar. Use the \"Secret address in iCal format\", not the public or embed link."
        );
    }
    return body;
}
