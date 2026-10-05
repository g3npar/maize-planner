"""Canvas parsing against payloads shaped like real /api/v1 responses."""

test "course codes are shortened and restricted courses skipped" {
    assert short_code("EECS 482 001 FA 2026", "") == "EECS 482";
    assert short_code("EECS482", "Intro OS") == "EECS 482";
    assert short_code("", "MATH 217: Linear Algebra") == "MATH 217";
    assert short_code("Orientation", "") == "Orientation";
    c = parse_course(
        {
            "id": 70123,
            "name": "EECS 449 001 FA 2026",
            "course_code": "EECS 449 001 FA 2026",
            "term": {"name": "Fall 2026"},
            "apply_assignment_group_weights": True
        },
        "umich.instructure.com/"
    );
    assert c is not None;
    assert c.code == "EECS 449";
    assert c.term == "Fall 2026";
    assert c.url == "https://umich.instructure.com/courses/70123";
    assert c.apply_weights;
    assert parse_course({"id": 5, "access_restricted_by_date": True}, "x") is None;
}

test "assignments are tagged with where they are really submitted" {
    groups = {11: "Projects", 12: "Homework"};
    gs = parse_assignment(
        {
            "id": 1,
            "name": "Homework 3",
            "due_at": "2026-10-06T03:59:00Z",
            "points_possible": 20,
            "html_url": "https://umich.instructure.com/courses/1/assignments/1",
            "submission_types": ["external_tool"],
            "external_tool_tag_attributes": {
                "url": "https://www.gradescope.com/auth/lti/callback"
            },
            "assignment_group_id": 12,
            "submission": {"workflow_state": "unsubmitted", "score": None}
        },
        groups
    );
    assert gs is not None;
    assert gs.source == "gradescope";
    assert gs.category == "Homework";
    assert gs.points == 20.0;
    assert not gs.submitted;
    assert gs.due.startswith("2026-10-0");
    ag = parse_assignment(
        {
            "id": 2,
            "name": "Project 2: Thread Library",
            "due_at": None,
            "points_possible": 100,
            "description": "<p>Submit on <a href=\"https://autograder.io/web/project/2451\">autograder.io</a></p>",
            "submission_types": ["none"],
            "assignment_group_id": 11,
            "submission": {
                "workflow_state": "graded",
                "score": 96.5,
                "submitted_at": "2026-09-20T01:00:00Z"
            }
        },
        groups
    );
    assert ag is not None;
    assert ag.source == "autograder";
    assert ag.external_url == "https://autograder.io/web/project/2451";
    assert ag.due == "";
    assert ag.submitted;
    assert ag.score == 96.5;
    plain = parse_assignment(
        {"id": 3, "name": "Reading reflection", "submission_types": ["online_text_entry"]},
        groups
    );
    assert plain is not None;
    assert plain.source == "canvas";
    assert plain.category == "";
    assert parse_assignment({"id": 4, "name": "Draft", "published": False}, groups) is None;
}

test "assignment group weights and pagination links" {
    (names, weights) = parse_groups(
        [
            {"id": 11, "name": "Projects", "group_weight": 60},
            {"id": 12, "name": "Exams", "group_weight": 40},
            {"id": 13, "name": "Extra credit", "group_weight": 0}
        ]
    );
    assert names[11] == "Projects";
    assert weights == {"Projects": 60.0, "Exams": 40.0};
    link = "<https://x/api/v1/courses?page=1>; rel=\"current\",<https://x/api/v1/courses?page=2>; rel=\"next\"";
    assert next_link(link) == "https://x/api/v1/courses?page=2";
    assert next_link("<https://x?page=1>; rel=\"first\"") == "";
    assert clean_base("https://umich.instructure.com/api/v1/") == "https://umich.instructure.com";
}

glob FEED: str = "\r\n".join(
    [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Instructure//Canvas",
        "BEGIN:VEVENT",
        "DTSTAMP:20261001T120000Z",
        "DTSTART:20261010T035900Z",
        "DTEND:20261010T035900Z",
        "SUMMARY:Project 2: Threads\\, locks [EECS 482 001 FA 2026]",
        "UID:event-assignment-901",
        "URL:https://umich.instructure.com/calendar?include_contexts=course_70123&month=10&ye",
        " ar=2026#assignment_901",
        "DESCRIPTION:Submit on autograder.io\\nhttps://autograder.io/web/project/42",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "DTSTART;VALUE=DATE:20261015",
        "SUMMARY:Homework 4 (Gradescope) [EECS 449 001 FA 2026]",
        "UID:event-assignment-902",
        "URL:https://umich.instructure.com/courses/70200/assignments/902",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "DTSTART:20261010T035900Z",
        "SUMMARY:Project 2: Threads\\, locks [EECS 482 001 FA 2026]",
        "UID:event-assignment-override-55",
        "URL:https://umich.instructure.com/calendar?include_contexts=course_70123#assignment_901",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "DTSTART:20261008T140000Z",
        "SUMMARY:Office hours [EECS 482 001 FA 2026]",
        "UID:event-calendar-event-77",
        "URL:https://umich.instructure.com/calendar?include_contexts=course_70123#calendar_event_77",
        "END:VEVENT",
        "END:VCALENDAR"
    ]
);

"""A UTC wall time as the server's local ISO time, the way the parser stores it."""
def _local(utc: datetime) -> str {
    return to_iso(utc.replace(tzinfo=timezone.utc).astimezone().replace(tzinfo=None));
}

test "calendar feed assignments are parsed with their course" {
    entries = parse_feed(FEED);
    assert len(entries) == 2;
    (c1, a1) = entries[0];
    assert a1.canvas_id == 901;
    assert a1.title == "Project 2: Threads, locks";
    assert c1.canvas_id == 70123;
    assert c1.code == "EECS 482";
    assert c1.name == "EECS 482 001 FA 2026";
    assert c1.url == "https://umich.instructure.com/courses/70123";
    assert a1.url == "https://umich.instructure.com/courses/70123/assignments/901";
    assert a1.source == "autograder";
    assert a1.external_url == "https://autograder.io/web/project/42";
    assert a1.due == _local(datetime(2026, 10, 10, 3, 59));
    (c2, a2) = entries[1];
    assert a2.canvas_id == 902;
    assert c2.canvas_id == 70200;
    assert c2.code == "EECS 449";
    assert a2.due == "2026-10-15T23:59";
    assert a2.source == "gradescope";
    assert a2.points == 0.0;
}

test "calendar feed links and dates" {
    assert clean_feed_url(" webcal://umich.instructure.com/feeds/calendars/user_abc.ics ") == "https://umich.instructure.com/feeds/calendars/user_abc.ics";
    # 23:59 EDT is 03:59 UTC the next day.
    assert ics_due("TZID=America/Detroit", "20261010T235900") == _local(
        datetime(2026, 10, 11, 3, 59)
    );
    assert ics_due("", "garbage") == "";
    assert parse_feed("") == [];
}
