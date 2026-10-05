"""Tests for the pure planning rules. `fixed_now()` is Monday 2026-09-28, 2:00 PM."""

def fixed_now -> datetime {
    return datetime(2026, 9, 28, 14, 0);
}

def when(text: str) -> str {
    d = parse_when(text, fixed_now());
    return to_iso(d) if d is not None else "";
}

test "parse_when understands relative days" {
    assert when("today") == "2026-09-28T23:59";
    assert when("tonight") == "2026-09-28T23:59";
    assert when("tomorrow 9am") == "2026-09-29T09:00";
    assert when("fri") == "2026-10-02T23:59";
    assert when("friday 5pm") == "2026-10-02T17:00";
    assert when("mon") == "2026-09-28T23:59";
    assert when("next wed") == "2026-10-07T23:59";
    assert when("in 3 days") == "2026-10-01T23:59";
    assert when("in 2 weeks") == "2026-10-12T23:59";
    assert when("in 4 hours") == "2026-09-28T18:00";
}

test "parse_when understands explicit dates and times" {
    assert when("10/5") == "2026-10-05T23:59";
    assert when("10/5 11:59pm") == "2026-10-05T23:59";
    assert when("oct 12 noon") == "2026-10-12T12:00";
    assert when("October 12th at 3:30 pm") == "2026-10-12T15:30";
    assert when("2026-11-02") == "2026-11-02T23:59";
    assert when("2026-11-02 08:15") == "2026-11-02T08:15";
    assert when("12/15/2026 10am") == "2026-12-15T10:00";
    assert when("1/10") == "2027-01-10T23:59";
    assert when("gibberish") == "";
    assert when("13/45") == "";
}

test "parse_iso converts UTC to local naive time" {
    d = parse_iso("2026-10-06T03:59:00Z");
    assert d is not None;
    assert d.tzinfo is None;
    assert parse_iso("") is None;
    assert parse_iso("not a date") is None;
}

test "deadline labels and urgency" {
    soon = datetime(2026, 9, 28, 23, 59);
    assert due_label(soon, fixed_now()) == "Today · 11:59 PM";
    assert due_label(datetime(2026, 9, 29, 9, 0), fixed_now()) == "Tomorrow · 9 AM";
    assert due_label(datetime(2026, 10, 2, 17, 30), fixed_now()) == "Fri · 5:30 PM";
    assert due_label(datetime(2026, 10, 20, 12, 0), fixed_now()) == "Tue Oct 20 · 12 PM";
    assert due_label(None, fixed_now()) == "No due date";
    assert urgency(soon, fixed_now(), False) == "today";
    assert urgency(datetime(2026, 9, 27, 23, 59), fixed_now(), False) == "overdue";
    assert urgency(datetime(2026, 9, 29, 12, 0), fixed_now(), False) == "tomorrow";
    assert urgency(datetime(2026, 10, 3, 12, 0), fixed_now(), False) == "week";
    assert urgency(datetime(2026, 10, 30, 12, 0), fixed_now(), False) == "later";
    assert urgency(soon, fixed_now(), True) == "done";
    assert due_in(soon, fixed_now(), False) == "in 9h 59m";
    assert due_in(datetime(2026, 9, 28, 12, 0), fixed_now(), False) == "2h overdue";
    assert due_in(datetime(2026, 10, 1, 14, 0), fixed_now(), False) == "in 3d";
}

test "meeting labels" {
    assert days_label([0, 2]) == "Mon/Wed";
    assert days_label([3, 1]) == "Tue/Thu";
    assert days_label([4]) == "Fri";
    assert range_label("10:30", "12:00") == "10:30 AM – 12 PM";
    assert range_label("13:05", "") == "1:05 PM";
}

test "quick_parse pulls course, due date, source and priority" {
    codes = ["EECS 482", "EECS 449", "MATH 217"];
    q = quick_parse("eecs482 Project 3 due fri 11:59pm #ag !!", codes, fixed_now());
    assert q.course_code == "EECS 482";
    assert q.title == "Project 3";
    assert q.due == "2026-10-02T23:59";
    assert q.source == "autograder";
    assert q.priority == 3;
    q2 = quick_parse("MATH 217: problem set 4 by tomorrow 5pm #gs 20 pts", codes, fixed_now());
    assert q2.course_code == "MATH 217";
    assert q2.title == "problem set 4";
    assert q2.due == "2026-09-29T17:00";
    assert q2.source == "gradescope";
    assert q2.points == 20.0;
    q3 = quick_parse("call the bank", codes, fixed_now());
    assert q3.course_code == "";
    assert q3.title == "call the bank";
    assert q3.due == "";
    assert q3.priority == 2;
    q4 = quick_parse("EECS 449 reading response due in 2 days ~", codes, fixed_now());
    assert q4.priority == 1;
    assert q4.due == "2026-09-30T23:59";
}

test "unweighted grade is total points" {
    items = [
        GradeInput(category="HW", points=10.0, score=9.0),
        GradeInput(category="HW", points=10.0, score=8.0),
        GradeInput(category="HW", points=20.0, score=None)
    ];
    g = compute_grade(items, {}, 90.0);
    assert g.current == 85.0;
    assert g.letter == "B";
    assert g.graded_count == 2;
    assert not g.weighted;
    # need 0.9 * 40 - 17 = 19 of 20 -> 95%
    assert g.needed == 95.0;
}

test "weighted grade renormalises over graded categories" {
    items = [
        GradeInput(category="Projects", points=100.0, score=90.0),
        GradeInput(category="Projects", points=100.0, score=None),
        GradeInput(category="Exams", points=100.0, score=None)
    ];
    g = compute_grade(items, {"Projects": 60.0, "Exams": 40.0}, 90.0);
    assert g.weighted;
    assert g.current == 90.0;
    # locked: 60 * 0.5 * 90 = 2700 ; future weight = 40 + 30 = 70
    # need (90 * 100 - 2700) / 70 = 90
    assert g.needed == 90.0;
    names = [c.name for c in g.categories];
    assert names == ["Projects", "Exams"];
}

test "zero-point work stays out of the grade" {
    items = [
        GradeInput(category="HW", points=10.0, score=10.0),
        GradeInput(category="", points=0.0, score=None)
    ];
    g = compute_grade(items, {}, 90.0);
    assert g.total_count == 1;
    assert [c.name for c in g.categories] == ["HW"];
    assert g.current == 100.0;
}

test "grade with nothing graded" {
    g = compute_grade([GradeInput(category="HW", points=10.0)], {}, 93.0);
    assert g.current is None;
    assert g.needed == 93.0;
    empty = compute_grade([], {}, 90.0);
    assert empty.current is None;
    assert empty.note == "No graded work yet";
}

test "urgency score orders pressing work first" {
    overdue = urgency_score(datetime(2026, 9, 27, 12, 0), fixed_now(), 2, 1.0);
    tonight = urgency_score(datetime(2026, 9, 28, 23, 59), fixed_now(), 2, 2.0);
    next_week = urgency_score(datetime(2026, 10, 5, 23, 59), fixed_now(), 2, 2.0);
    assert overdue > tonight > next_week;
}
