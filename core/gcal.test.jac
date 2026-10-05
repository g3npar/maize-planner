"""Google Calendar parsing and recurrence against feeds shaped like Google's export."""

glob CAL: str = "\r\n".join(
    [
        "BEGIN:VCALENDAR",
        "PRODID:-//Google Inc//Google Calendar 70.9054//EN",
        "BEGIN:VEVENT",
        "DTSTART:20261005T100000",
        "DTEND:20261005T113000",
        "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261016T235959",
        "EXDATE:20261007T100000",
        "UID:lab@google.com",
        "SUMMARY:Research lab\\, room 3",
        "LOCATION:BBB 1670",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "DTSTART:20261009T150000",
        "DTEND:20261009T163000",
        "RECURRENCE-ID:20261009T100000",
        "UID:lab@google.com",
        "SUMMARY:Research lab (moved)",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "DTSTART:20261006T180000",
        "DTEND:20261006T190000",
        "UID:cancelled@google.com",
        "STATUS:CANCELLED",
        "SUMMARY:Dropped meeting",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "DTSTART;VALUE=DATE:20261012",
        "DTEND;VALUE=DATE:20261014",
        "UID:trip@google.com",
        "SUMMARY:Fall break",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "DTSTART:20261008T230000",
        "DURATION:PT2H",
        "UID:late@google.com",
        "SUMMARY:Late shift",
        "END:VEVENT",
        "END:VCALENDAR"
    ]
);

test "recurring events expand with skipped and moved dates" {
    lo = datetime(2026, 10, 5);
    hi = datetime(2026, 10, 31);
    events = parse_calendar(CAL, lo, hi);
    lab = [e for e in events if e.title == "Research lab, room 3"];
    # Mon 5, (Wed 7 skipped), (Fri 9 moved), Mon 12, Wed 14, Fri 16; UNTIL stops after the 16th.
    assert [e.start for e in lab] == [
        "2026-10-05T10:00",
        "2026-10-12T10:00",
        "2026-10-14T10:00",
        "2026-10-16T10:00"
    ];
    assert lab[0].end == "2026-10-05T11:30";
    assert lab[0].location == "BBB 1670";
    moved = [e for e in events if e.title == "Research lab (moved)"];
    assert len(moved) == 1 and moved[0].start == "2026-10-09T15:00";
    assert not [e for e in events if e.title == "Dropped meeting"];
    trip = [e for e in events if e.title == "Fall break"][0];
    assert trip.all_day and trip.start == "2026-10-12T00:00" and trip.end == "2026-10-14T00:00";
    late = [e for e in events if e.title == "Late shift"][0];
    assert late.end == "2026-10-09T01:00";
}

test "only the window is expanded" {
    events = parse_calendar(CAL, datetime(2026, 10, 13), datetime(2026, 10, 15));
    assert [e.start for e in events if e.title.startswith("Research lab")] == ["2026-10-14T10:00"];
    assert [e.title for e in events if e.all_day] == ["Fall break"];
}

test "daily count, monthly by weekday and month-end rules" {
    first = datetime(2026, 9, 1, 9, 0);
    lo = datetime(2026, 9, 1);
    hi = datetime(2027, 3, 1);
    daily = expand_rule(first, parse_rule("FREQ=DAILY;INTERVAL=2;COUNT=3"), lo, hi);
    assert [d.day for d in daily] == [1, 3, 5];
    # COUNT counts from the first occurrence, even ones before the window.
    late = expand_rule(first, parse_rule("FREQ=DAILY;COUNT=3"), datetime(2026, 9, 2), hi);
    assert [d.day for d in late] == [2, 3];
    second_tue = expand_rule(
        datetime(2026, 9, 8, 12, 0), parse_rule("FREQ=MONTHLY;BYDAY=2TU;COUNT=3"), lo, hi
    );
    assert [(d.month, d.day) for d in second_tue] == [(9, 8), (10, 13), (11, 10)];
    last_fri = expand_rule(
        datetime(2026, 9, 25, 12, 0), parse_rule("FREQ=MONTHLY;BYDAY=-1FR;COUNT=2"), lo, hi
    );
    assert [(d.month, d.day) for d in last_fri] == [(9, 25), (10, 30)];
    # The 31st only exists in some months.
    thirty_first = expand_rule(
        datetime(2026, 10, 31, 8, 0), parse_rule("FREQ=MONTHLY;COUNT=3"), lo, hi
    );
    assert [(d.month, d.day) for d in thirty_first] == [(10, 31), (12, 31), (1, 31)];
    yearly = expand_rule(datetime(2026, 9, 1), parse_rule("FREQ=YEARLY"), lo, datetime(2028, 12, 1));
    assert [d.year for d in yearly] == [2026, 2027, 2028];
}

test "durations, utc times and per-day clipping" {
    assert parse_duration("PT1H30M") == timedelta(hours=1, minutes=30);
    assert parse_duration("P1D") == timedelta(days=1);
    assert parse_duration("P") is None;
    (d, whole) = ics_time("", "20261010T140000Z");
    assert not whole;
    assert d == datetime(2026, 10, 10, 14, 0, tzinfo=timezone.utc).astimezone().replace(tzinfo=None);
    (d2, whole2) = ics_time("VALUE=DATE", "20261010");
    assert whole2 and d2 == datetime(2026, 10, 10);
    events = parse_calendar(CAL, datetime(2026, 10, 5), datetime(2026, 10, 31));
    late = [e for e in events if e.title == "Late shift"];
    (ev, s, f) = events_on(late, datetime(2026, 10, 8))[0];
    assert s == datetime(2026, 10, 8, 23, 0) and f == datetime(2026, 10, 9);
    (ev2, s2, f2) = events_on(late, datetime(2026, 10, 9))[0];
    assert s2 == datetime(2026, 10, 9) and f2 == datetime(2026, 10, 9, 1, 0);
    assert len(events_on([e for e in events if e.all_day], datetime(2026, 10, 13))) == 1;
    assert len(events_on([e for e in events if e.all_day], datetime(2026, 10, 14))) == 0;
    assert load_events(dump_events(late))[0].end == late[0].end;
    assert clean_calendar_url("webcal://calendar.google.com/x/basic.ics") == "https://calendar.google.com/x/basic.ics";
}
