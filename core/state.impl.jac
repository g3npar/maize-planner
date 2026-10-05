"""Action bodies for `usePlanner` - every walker call the UIs make.

Each mutation follows write-then-refresh: call the walker, patch the item
in place for instant feedback, then reload the dashboard and lists so every
derived number (stats, grades, week view) stays consistent.
"""

impl usePlanner.fail(e: any) -> None {
    message = describe_error(e);
    error = message;
    if "session expired" in message {
        session.logout();
    }
}

impl usePlanner.replaceItem(v: AssignmentView) -> None {
    assignments = [v if a.id == v.id else a for a in assignments];
}

impl usePlanner.refresh -> None {
    if not jacIsLoggedIn() {
        loading = False;
        refreshing = False;
        return;
    }
    try {
        res = root spawn load_all(
            course=filterCourse,
            source=filterSource,
            status=filterStatus,
            week_offset=weekOffset,
            with_week=week is not None,
            with_gradebook=bool(gradebook)
        );
        if res.reports {
            snap = res.reports[0];
            applySnapshot(snap);
            if not filterCourse and not filterSource and filterStatus == "open" {
                write_cached_snapshot(session.username, snap);
            }
        }
    } except Exception as e {
        fail(e);
    } finally {
        loading = False;
        refreshing = False;
    }
}

impl usePlanner.applySnapshot(snap: Snapshot) -> None {
    dashboard = snap.dashboard;
    courses = snap.courses or [];
    assignments = snap.assignments or [];
    if snap.week is not None {
        week = snap.week;
    }
    if snap.gradebook is not None {
        gradebook = snap.gradebook;
    }
}

impl usePlanner.reloadList -> None {
    try {
        items = root spawn list_assignments(
            course=filterCourse, source=filterSource, status=filterStatus, search=""
        );
        assignments = items.reports[0] if items.reports else [];
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.loadWeek(offset: int) -> None {
    try {
        weekOffset = offset;
        wk = root spawn get_week(offset=offset);
        week = wk.reports[0] if wk.reports else None;
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.loadSettings -> None {
    try {
        res = root spawn get_settings();
        settings = res.reports[0] if res.reports else None;
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.loadGradebook -> None {
    try {
        res = root spawn list_assignments(course="", source="", status="all", search="");
        gradebook = res.reports[0] if res.reports else [];
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.quickAdd(text: str) -> bool {
    if not text.strip() {
        return False;
    }
    try {
        res = root spawn quick_add(text=text);
        if res.reports {
            made = res.reports[0];
            notice = "Added “" + made.title + "” · " + made.course_code + " · " + made.due_label;
            announce_change(instanceId);
        await refresh();
            return True;
        }
    } except Exception as e {
        fail(e);
    }
    return False;
}

impl usePlanner.saveAssignment(d: AssignmentDraft) -> AssignmentView | None {
    try {
        res = root spawn save_assignment(
            id=d.id,
            course_id=d.course_id,
            title=d.title,
            source=d.source,
            due=d.due,
            priority=d.priority,
            category=d.category,
            points=d.points,
            url=d.url,
            notes=d.notes,
            est_hours=d.est_hours
        );
        if res.reports {
            saved = res.reports[0];
            notice = ("Saved “" if d.id else "Added “") + saved.title + "”";
            announce_change(instanceId);
        await refresh();
            return saved;
        }
        error = "Give the assignment a title first.";
    } except Exception as e {
        fail(e);
    }
    return None;
}

"""Reload once no status write is pending, then show hidden items again
(the reload has dropped the ones that are done)."""
impl usePlanner.settle -> None {
    if PENDING["writes"] > 0 {
        return;
    }
    announce_change(instanceId);
    await refresh();
    if PENDING["writes"] == 0 {
        hiddenIds = [];
    }
}

impl usePlanner.setStatus(id: str, status: str) -> None {
    PENDING["writes"] += 1;
    try {
        res = root spawn set_status(id=id, status=status);
        if res.reports {
            replaceItem(res.reports[0]);
        }
    } except Exception as e {
        hiddenIds = [h for h in hiddenIds if h != id];
        fail(e);
    } finally {
        PENDING["writes"] -= 1;
    }
    await settle();
}

"""Checking an item off hides it at once; the write and the reload follow in
the background, and rapid clicks share a single reload."""
impl usePlanner.toggleDone(a: AssignmentView) -> None {
    finishing = a.status != "done";
    if finishing {
        hiddenIds = hiddenIds + [a.id];
        notice = "Nice! “" + a.title + "” is done.";
    }
    await setStatus(a.id, "done" if finishing else "todo");
}

impl usePlanner.markDone(ids: list[str]) -> None {
    if not ids {
        return;
    }
    hiddenIds = hiddenIds + ids;
    PENDING["writes"] += 1;
    try {
        res = root spawn set_status_many(ids=ids, status="done");
        changed = res.reports[0] if res.reports else 0;
        notice = f"Marked {changed} done.";
    } except Exception as e {
        hiddenIds = [h for h in hiddenIds if h not in ids];
        fail(e);
    } finally {
        PENDING["writes"] -= 1;
    }
    await settle();
}

impl usePlanner.setScore(id: str, score: float | None, points: float) -> None {
    try {
        res = root spawn set_score(id=id, score=score, points=points);
        if res.reports {
            replaceItem(res.reports[0]);
            notice = "Score saved - grades updated.";
        }
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.deleteAssignment(id: str) -> None {
    try {
        res = root spawn delete_assignment(id=id);
        if res.reports {
            notice = res.reports[0].message;
        }
        assignments = [a for a in assignments if a.id != id];
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.toggleSubtask(id: str, index: int) -> None {
    try {
        res = root spawn toggle_subtask(id=id, index=index);
        if res.reports {
            replaceItem(res.reports[0]);
        }
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.setSubtasks(id: str, steps: list[str], done: list[bool]) -> None {
    try {
        res = root spawn set_subtasks(id=id, subtasks=steps, done=done);
        if res.reports {
            replaceItem(res.reports[0]);
        }
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.breakdownTask(id: str) -> None {
    busyId = id;
    try {
        res = root spawn breakdown(id=id);
        if res.reports {
            replaceItem(res.reports[0]);
            notice = "Broke it into " + str(len(res.reports[0].subtasks)) + " steps.";
        }
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    } finally {
        busyId = "";
    }
}

impl usePlanner.saveCourse(d: CourseDraft) -> CourseView | None {
    try {
        res = root spawn save_course(
            id=d.id,
            code=d.code,
            name=d.name,
            color=d.color,
            term=d.term,
            instructor=d.instructor,
            canvas_url=d.canvas_url,
            gradescope_url=d.gradescope_url,
            autograder_url=d.autograder_url,
            website_url=d.website_url,
            target=d.target,
            weights=d.weights
        );
        if res.reports {
            saved = res.reports[0];
            notice = "Saved " + saved.code;
            announce_change(instanceId);
        await refresh();
            return saved;
        }
        error = "A course needs a code like “EECS 482”.";
    } except Exception as e {
        fail(e);
    }
    return None;
}

impl usePlanner.deleteCourse(id: str) -> None {
    try {
        res = root spawn delete_course(id=id);
        if res.reports {
            notice = res.reports[0].message;
        }
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.addMeeting(
    course_id: str, kind: str, days: list[int], start: str, end: str, location: str
) -> None {
    if not days {
        error = "Pick at least one day for the meeting.";
        return;
    }
    try {
        res = root spawn add_meeting(
            course_id=course_id,
            kind=kind,
            days=days,
            start=start,
            end=end,
            location=location
        );
        if res.reports {
            notice = "Added " + res.reports[0].kind + " · " + res.reports[0].days_label;
        }
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.deleteMeeting(id: str) -> None {
    try {
        _ = root spawn delete_meeting(id=id);
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.saveSettings(
    name: str, url: str, token: str, feed: str, clear: bool
) -> None {
    try {
        res = root spawn save_settings(
            display_name=name,
            canvas_url=url,
            canvas_token=token,
            canvas_feed_url=feed,
            clear_token=clear
        );
        settings = res.reports[0] if res.reports else settings;
        notice = "Settings saved.";
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.saveCalendar(url: str, clear: bool) -> None {
    try {
        res = root spawn save_calendar(url=url, clear=clear);
        settings = res.reports[0] if res.reports else settings;
        notice = "Google Calendar disconnected." if clear else "Google Calendar saved.";
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.syncCanvas -> None {
    syncBusy = True;
    syncResult = None;
    try {
        res = root spawn sync_canvas();
        syncResult = res.reports[0] if res.reports else None;
        if syncResult is not None {
            if syncResult.ok {
                notice = syncResult.message;
            } else {
                error = syncResult.message;
            }
        }
        announce_change(instanceId);
        await refresh();
        await loadSettings();
    } except Exception as e {
        fail(e);
    } finally {
        syncBusy = False;
    }
}

impl usePlanner.makePlan(hours: float, goal: str, useAi: bool) -> None {
    planBusy = True;
    try {
        res = root spawn study_plan(hours=hours, goal=goal, use_ai=useAi);
        plan = res.reports[0] if res.reports else None;
    } except Exception as e {
        fail(e);
    } finally {
        planBusy = False;
    }
}

impl usePlanner.loadDemo -> None {
    try {
        res = root spawn load_demo();
        if res.reports {
            if res.reports[0].ok {
                notice = res.reports[0].message;
            } else {
                error = res.reports[0].message;
            }
        }
        announce_change(instanceId);
        await refresh();
    } except Exception as e {
        fail(e);
    }
}

impl usePlanner.exportIcs -> str {
    try {
        res = root spawn export_ics(include_done=False);
        return res.reports[0] if res.reports else "";
    } except Exception as e {
        fail(e);
    }
    return "";
}
