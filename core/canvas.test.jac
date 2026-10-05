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
