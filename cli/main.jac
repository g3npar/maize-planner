"""planner - the terminal face of Maize Planner.

    jac run cli -- login                       # once
    jac run cli -- today
    jac run cli -- add "eecs482 p3 due fri 11:59pm #ag !!"
    jac run cli -- done 3fa2c1

Every command except login/signup calls the walkers of the `planner`
service app through Jac's typed bridge: `import from core.planner { ... }`
compiles to async stubs that POST to <server>/api/planner/walker/<name>
with the saved token, so the CLI sees exactly the data the web and phone
apps see. (Tip: alias planner="jac run cli --".)
"""

import argparse;
import asyncio;
import getpass;
import json;
import sys;
import webbrowser;
import from pathlib { Path }
import from jaclang.server { sv_client }
import from jaclang.server.bridge {
    BridgeError,
    BridgeRejected,
    BridgeTimeout,
    BridgeUnavailable
}
import from core.planner {
    get_dashboard,
    get_week,
    list_courses,
    list_assignments,
    save_assignment,
    quick_add,
    set_status,
    set_score,
    delete_assignment,
    toggle_subtask,
    breakdown,
    sync_canvas,
    study_plan,
    export_ics,
    load_demo,
    get_settings,
    AssignmentView,
    CourseView,
    Dashboard,
    WeekView,
    SyncResult,
    StudyPlan,
    OpResult,
    SettingsView
}
import from cli.config {
    CliConfig,
    AuthError,
    load_config,
    save_config,
    config_path,
    login,
    signup,
    SERVICE_ROUTE
}
import from cli.render {
    task_line,
    section,
    class_line,
    course_line,
    hex_fg,
    bold,
    dim,
    pad,
    grade_bar,
    set_color,
    truncate
}

glob EXIT_OK: int = 0,
     EXIT_FAIL: int = 1,
     EXIT_USAGE: int = 2,
     EXIT_OFFLINE: int = 3,
     EXIT_AUTH: int = 4;

def warn(text: str) {
    print(text, file=sys.stderr);
}

def to_jsonable(value: any) -> any {
    if isinstance(value, list) {
        return [to_jsonable(v) for v in value];
    }
    if isinstance(value, dict) {
        return {str(k): to_jsonable(v) for (k, v) in value.items()};
    }
    if hasattr(value, "__dict__") {
        return {
            k: to_jsonable(v)
            for (k, v) in vars(value).items()
            if not k.startswith("_")
        };
    }
    return value;
}

def print_json(value: any) {
    print(json.dumps(to_jsonable(value), indent=2, `default=str));
}

def clock12(iso: str) -> str {
    if len(iso) < 16 {
        return iso;
    }
    hour = int(iso[11:13]);
    h12 = hour % 12 or 12;
    return f"{h12}:{iso[14:16]} {'AM' if hour < 12 else 'PM'}";
}

def first(reports: list[any]) -> any {
    return reports[0] if reports else None;
}

# ------------------------------------------------------------- parser ----

def build_parser -> argparse.ArgumentParser {
    parser = argparse.ArgumentParser(
        prog="planner",
        description="Maize Planner from your terminal. Talks to the same server as the web and phone apps.",
        epilog="Quick add understands: 'due fri 5pm', 'by 10/5', 'in 3 days', #gs #ag #canvas, ! / !! priority, '20 pts'."
    );
    parser.add_argument("--no-color", action="store_true", help="plain output");
    sub = parser.add_subparsers(dest="command", metavar="<command>", required=True);

    p = sub.add_parser("login", help="sign in and remember the token");
    p.add_argument("--server", `default="", help="server URL (default: saved or http://localhost:8000)");
    p.add_argument("--user", `default="", help="username");
    p.add_argument("--password", `default="", help="password (prompted if omitted)");
    p = sub.add_parser("signup", help="create an account and sign in");
    p.add_argument("--server", `default="");
    p.add_argument("--user", `default="");
    p.add_argument("--password", `default="");
    sub.add_parser("logout", help="forget the saved token");
    sub.add_parser("whoami", help="show server, user and connection status");

    p = sub.add_parser("today", help="what's overdue, due soon, and today's classes");
    p.add_argument("--json", action="store_true");

    p = sub.add_parser("ls", help="list assignments");
    p.add_argument("-c", "--course", `default="", help="course code or id, e.g. 'eecs482'");
    p.add_argument("-s", "--source", `default="", help="canvas | gradescope | autograder | other");
    p.add_argument("-q", "--search", `default="", help="text to match");
    group = p.add_mutually_exclusive_group();
    group.add_argument("--done", action="store_true", help="only finished work");
    group.add_argument("--all", action="store_true", help="open and finished");
    p.add_argument("--json", action="store_true");

    p = sub.add_parser("add", help="add an assignment (plain English or flags)");
    p.add_argument("text", nargs="+", help="e.g. eecs482 project 3 due fri 11:59pm #ag !!");
    p.add_argument("-c", "--course", `default="");
    p.add_argument("-d", "--due", `default="", help="when it's due, e.g. 'fri 5pm' or 2026-10-05T23:59");
    p.add_argument("-s", "--source", `default="");
    p.add_argument("-p", "--priority", `type=int, choices=[1, 2, 3], `default=0);
    p.add_argument("--points", `type=float, `default=0.0);
    p.add_argument("--hours", `type=float, `default=0.0, help="estimated hours");

    for (name, help_text) in [
        ("done", "mark done"),
        ("undo", "mark not done"),
        ("start", "mark in progress")
    ] {
        p = sub.add_parser(name, help=help_text);
        p.add_argument("ids", nargs="+", help="assignment id (the 6-char code from `ls`)");
    }
    p = sub.add_parser("show", help="details, steps and notes for one assignment");
    p.add_argument("id");
    p = sub.add_parser("rm", help="delete an assignment");
    p.add_argument("id");
    p = sub.add_parser("open", help="open an assignment's link (Canvas/Gradescope/Autograder)");
    p.add_argument("id");
    p = sub.add_parser("step", help="toggle a checklist step");
    p.add_argument("id");
    p.add_argument("number", `type=int, help="step number from `show`");
    p = sub.add_parser("breakdown", help="split an assignment into steps (AI when available)");
    p.add_argument("id");
    p = sub.add_parser("score", help="record a grade");
    p.add_argument("id");
    p.add_argument("score", help="points earned, or '-' to clear");
    p.add_argument("--of", `type=float, `default=0.0, help="points possible");

    sub.add_parser("courses", help="classes with open work and grades");
    p = sub.add_parser("week", help="this week's classes and deadlines");
    p.add_argument("--next", `type=int, `default=0, help="weeks ahead (negative = back)");
    sub.add_parser("grades", help="grade breakdown per class");
    sub.add_parser("sync", help="import from Canvas (token set in the web app)");
    p = sub.add_parser("plan", help="plan a study session");
    p.add_argument("--hours", `type=float, `default=3.0);
    p.add_argument("--goal", `default="");
    p.add_argument("--no-ai", action="store_true");
    p = sub.add_parser("ics", help="export deadlines as an .ics calendar");
    p.add_argument("-o", "--output", `default="planner.ics");
    sub.add_parser("demo", help="load a demo semester into an empty account");
    return parser;
}

# ------------------------------------------------------------ helpers ----

def connect(cfg: CliConfig) {
    sv_client.register("planner", cfg.server, route=SERVICE_ROUTE);
    sv_client.set_bearer_token(cfg.token);
}

def looks_offline(detail: str) -> bool {
    text = detail.lower();
    return "connect call failed" in text
        or "connection refused" in text
        or "errno 111" in text
        or "name or service not known" in text
        or "cannot connect" in text;
}

def explain(e: BridgeError, cfg: CliConfig) -> int {
    if isinstance(e, BridgeUnavailable) or looks_offline(str(e.detail or "")) {
        warn(hex_fg("✖", "#ef4444") + f" can't reach the planner server at {cfg.server}");
        warn(dim("  start it with `jac run` in the project folder, or `planner login --server URL`"));
        return EXIT_OFFLINE;
    }
    if isinstance(e, BridgeRejected) {
        warn(hex_fg("✖", "#ef4444") + " the server rejected the request (" + (e.detail or "unauthorized") + ")");
        warn(dim("  sign in again: planner login"));
        return EXIT_AUTH;
    }
    if isinstance(e, BridgeTimeout) {
        warn(hex_fg("✖", "#ef4444") + " the server took too long to answer");
        return EXIT_FAIL;
    }
    warn(hex_fg("✖", "#ef4444") + " " + (e.detail or "request failed"));
    return EXIT_FAIL;
}

def not_found(ref: str) -> int {
    warn(hex_fg("✖", "#ef4444") + f" no assignment matches '{ref}' (use the id shown by `planner ls`)");
    return EXIT_FAIL;
}

# ----------------------------------------------------------- commands ----

def cmd_login(args: any, cfg: CliConfig, create: bool) -> int {
    server = (args.server or cfg.server).rstrip("/");
    user = args.user or input("username: ").strip();
    password = args.password or getpass.getpass("password: ");
    if not user or not password {
        warn("username and password are required");
        return EXIT_USAGE;
    }
    try {
        token = signup(server, user, password) if create else login(server, user, password);
    } except AuthError as e {
        warn(hex_fg("✖", "#ef4444") + " " + e.message);
        return EXIT_AUTH;
    }
    save_config(CliConfig(server=server, username=user, token=token));
    print(hex_fg("✔", "#22c55e") + f" signed in to {server} as {bold(user)}");
    print(dim(f"  token saved to {config_path()}"));
    return EXIT_OK;
}

def cmd_logout(cfg: CliConfig) -> int {
    save_config(CliConfig(server=cfg.server));
    print("signed out");
    return EXIT_OK;
}

async def cmd_whoami(cfg: CliConfig) -> int {
    print(f"server  {cfg.server}");
    print(f"user    {cfg.username or dim('(not signed in)')}");
    if not cfg.token {
        return EXIT_AUTH;
    }
    res = await get_settings();
    st: SettingsView | None = first(res.reports);
    if st is not None {
        print("status  " + hex_fg("connected", "#22c55e"));
        print("canvas  " + (("connected " + (st.token_hint if st.has_token else "(calendar feed)") + (", last sync " + st.last_sync.replace("T", " ") if st.last_sync else "")) if st.has_token or st.has_feed else dim("not connected")));
        print("ai      " + (st.ai_model if st.ai_ready else dim("built-in planner (no API key on server)")));
    }
    return EXIT_OK;
}

async def cmd_today(as_json: bool) -> int {
    res = await get_dashboard();
    d: Dashboard | None = first(res.reports);
    if d is None {
        return EXIT_FAIL;
    }
    if as_json {
        print_json(d);
        return EXIT_OK;
    }
    s = d.stats;
    print(bold(d.greeting) + dim("  ·  " + d.date_label));
    over = hex_fg(f"{s.overdue} overdue", "#ef4444") if s.overdue else dim("0 overdue");
    print(f"{over}  ·  {s.due_today} due today  ·  {s.due_week} in the next 7 days  ·  {s.done_week} done this week");
    print();
    if d.classes_today {
        print(bold("Classes today"));
        for c in d.classes_today {
            print(class_line(c));
        }
        print();
    } elif d.next_class is not None {
        print(bold("Next class") + dim("  " + d.next_class.state));
        print(class_line(d.next_class));
        print();
    }
    groups = [
        ("Overdue", d.overdue, "#ef4444"),
        ("Today", d.today, "#f97316"),
        ("Tomorrow", d.tomorrow, "#eab308"),
        ("This week", d.week, "#60a5fa")
    ];
    shown = False;
    for (title, items, color) in groups {
        if items {
            shown = True;
            print(section(title, len(items), color));
            for a in items {
                print("  " + task_line(a));
            }
            print();
        }
    }
    if not shown {
        print(hex_fg("🎉 nothing due in the next week", "#22c55e"));
        if d.course_count == 0 {
            print(dim("   new here? try `planner demo`, or connect Canvas in the web app's Settings"));
        }
    }
    return EXIT_OK;
}

async def cmd_ls(args: any) -> int {
    status = "done" if args.done else ("all" if args.all else "open");
    res = await list_assignments(
        course=args.course, status=status, source=args.source, search=args.search
    );
    items: list[AssignmentView] = first(res.reports) or [];
    if args.json {
        print_json(items);
        return EXIT_OK;
    }
    if not items {
        print(dim("nothing here" + (" for '" + args.course + "'" if args.course else "")));
        return EXIT_OK;
    }
    for a in items {
        print(task_line(a));
    }
    print(dim(f"\n{len(items)} {'item' if len(items) == 1 else 'items'} · ids work as prefixes: planner done {items[0].short_id[:4]}"));
    return EXIT_OK;
}

async def cmd_add(args: any) -> int {
    text = " ".join(args.text).strip();
    flagged = args.course or args.due or args.source or args.priority or args.points or args.hours;
    a: AssignmentView | None = None;
    if not flagged {
        quick = await quick_add(text=text);
        a = first(quick.reports);
    } else {
        saved = await save_assignment(
            course_id=args.course,
            title=text,
            source=args.source or "other",
            due=args.due,
            priority=args.priority or 2,
            points=args.points,
            est_hours=args.hours
        );
        a = first(saved.reports);
    }
    if a is None {
        warn("nothing added (empty title?)");
        return EXIT_FAIL;
    }
    print(hex_fg("✔", "#22c55e") + " added");
    print("  " + task_line(a));
    if args.course and a.course_code == "Personal" {
        warn(dim(f"  (no class matched '{args.course}' - saved as a personal task)"));
    }
    return EXIT_OK;
}

async def cmd_status(ids: list[str], status: str) -> int {
    code = EXIT_OK;
    for ref in ids {
        res = await set_status(id=ref, status=status);
        a: AssignmentView | None = first(res.reports);
        if a is None {
            code = not_found(ref);
            continue;
        }
        verb = {"done": "done", "todo": "reopened", "doing": "started"}[status];
        mark = hex_fg("✔", "#22c55e") if status == "done" else "•";
        print(f"{mark} {verb}: {a.title} {dim('(' + a.course_code + ')')}");
    }
    return code;
}

async def find_one(ref: str) -> AssignmentView | None {
    res = await list_assignments(course="", status="all", source="", search="");
    items: list[AssignmentView] = first(res.reports) or [];
    want = ref.lower();
    hits = [a for a in items if a.id == want or a.id.startswith(want)];
    return hits[0] if len(hits) == 1 else None;
}

async def cmd_show(ref: str) -> int {
    a = await find_one(ref);
    if a is None {
        return not_found(ref);
    }
    print(task_line(a));
    print();
    rows = [
        ("class", a.course_code),
        ("where", a.source),
        ("status", a.status),
        ("priority", ["", "low", "normal", "high"][a.priority]),
        ("category", a.category or "–"),
        ("points", f"{a.points:g}" if a.points else "–"),
        ("score", f"{a.score:g}" if a.score is not None else "–"),
        ("estimate", f"{a.est_hours:g}h" if a.est_hours else "–"),
        ("link", a.url or "–"),
        ("id", a.id)
    ];
    for (label, value) in rows {
        print(f"  {dim(pad(label, 9))} {value}");
    }
    if a.notes {
        print("\n  " + a.notes.replace("\n", "\n  "));
    }
    if a.subtasks {
        print("\n  " + bold("Steps"));
        for (i, step) in enumerate(a.subtasks) {
            done = i < len(a.subtasks_done) and a.subtasks_done[i];
            box = hex_fg("[x]", "#22c55e") if done else "[ ]";
            print(f"  {i + 1:>2}. {box} {step}");
        }
    }
    return EXIT_OK;
}

async def cmd_rm(ref: str) -> int {
    res = await delete_assignment(id=ref);
    r: OpResult | None = first(res.reports);
    if r is None or not r.ok {
        return not_found(ref);
    }
    print(r.message);
    return EXIT_OK;
}

async def cmd_open(ref: str) -> int {
    a = await find_one(ref);
    if a is None {
        return not_found(ref);
    }
    if not a.url {
        warn("that assignment has no link");
        return EXIT_FAIL;
    }
    print(a.url);
    webbrowser.open(a.url);
    return EXIT_OK;
}

async def cmd_step(ref: str, number: int) -> int {
    res = await toggle_subtask(id=ref, index=number - 1);
    a: AssignmentView | None = first(res.reports);
    if a is None {
        warn("no such assignment or step");
        return EXIT_FAIL;
    }
    return await cmd_show(a.id);
}

async def cmd_breakdown(ref: str) -> int {
    res = await breakdown(id=ref);
    a: AssignmentView | None = first(res.reports);
    if a is None {
        return not_found(ref);
    }
    return await cmd_show(a.id);
}

async def cmd_score(ref: str, raw: str, of: float) -> int {
    value: float | None = None;
    if raw.strip() != "-" {
        try {
            value = float(raw);
        } except ValueError {
            warn("score must be a number, or '-' to clear it");
            return EXIT_USAGE;
        }
    }
    res = await set_score(id=ref, score=value, points=of);
    a: AssignmentView | None = first(res.reports);
    if a is None {
        return not_found(ref);
    }
    shown = f"{a.score:g}/{a.points:g}" if a.score is not None else "cleared";
    print(hex_fg("✔", "#22c55e") + f" {a.title}: {shown}");
    return EXIT_OK;
}

async def cmd_courses -> int {
    res = await list_courses();
    courses: list[CourseView] = first(res.reports) or [];
    if not courses {
        print(dim("no classes yet - add them in the web app, `planner sync`, or `planner demo`"));
        return EXIT_OK;
    }
    for c in courses {
        print(course_line(c));
        for m in c.meetings {
            print(dim(f"           {m.kind:<13}{m.days_label} {m.time_label}" + (f" · {m.location}" if m.location else "")));
        }
    }
    return EXIT_OK;
}

async def cmd_week(offset: int) -> int {
    res = await get_week(offset=offset);
    w: WeekView | None = first(res.reports);
    if w is None {
        return EXIT_FAIL;
    }
    print(bold("Week of " + w.label));
    for day in w.days {
        head = f"{day.weekday} {day.label}";
        print();
        print(hex_fg(bold(head + "  ← today"), "#60a5fa") if day.is_today else bold(head));
        if not day.classes and not day.due {
            print(dim("  free"));
        }
        for s in day.classes {
            print(class_line(s));
        }
        for a in day.due {
            due_at = a.due_label.split(" · ")[-1];
            mark = "✔" if a.status == "done" else "▸";
            print(f"  {pad(hex_fg(mark + ' due ' + due_at, '#f97316'), 18)} {hex_fg(a.course_code, a.course_color)} {truncate(a.title, 50)} {dim(a.short_id)}");
        }
    }
    return EXIT_OK;
}

async def cmd_grades -> int {
    res = await list_courses();
    courses: list[CourseView] = first(res.reports) or [];
    for c in courses {
        g = c.grade;
        current = f"{g.current:.1f}% {g.letter}" if g.current is not None else "no grades yet";
        print(bold(hex_fg(c.code, c.color)) + "  " + current + dim(f"   target {c.target:g}%"));
        for cat in g.categories {
            pct = f"{cat.pct:5.1f}%" if cat.pct is not None else "    –";
            weight = f"{cat.weight:g}%" if cat.weight else "";
            print(f"   {pad(truncate(cat.name, 18), 19)}{pad(weight, 6)}{grade_bar(cat.pct, 16, c.color)} {pct}  " + dim(f"{cat.remaining} left"));
        }
        if g.note {
            print(dim("   → " + g.note));
        }
        print();
    }
    return EXIT_OK;
}

async def cmd_sync -> int {
    print(dim("syncing with Canvas…"));
    res = await sync_canvas();
    r: SyncResult | None = first(res.reports);
    if r is None {
        return EXIT_FAIL;
    }
    if not r.ok {
        warn(hex_fg("✖", "#ef4444") + " " + r.message);
        return EXIT_FAIL;
    }
    print(hex_fg("✔", "#22c55e") + " " + r.message);
    for err in r.errors {
        warn(dim("  " + err));
    }
    return EXIT_OK;
}

async def cmd_plan(hours: float, goal: str, use_ai: bool) -> int {
    res = await study_plan(hours=hours, goal=goal, use_ai=use_ai);
    plan: StudyPlan | None = first(res.reports);
    if plan is None {
        return EXIT_FAIL;
    }
    badge = hex_fg("AI plan", "#a78bfa") if plan.source == "ai" else dim("built-in planner");
    print(badge + "  " + bold(plan.summary));
    if plan.note {
        print(dim(plan.note));
    }
    print();
    for b in plan.blocks {
        start = clock12(b.start);
        end = clock12(b.end);
        print(f"  {bold(pad(start + ' – ' + end, 19))}  {hex_fg(pad(b.course_code, 9), b.color)} {truncate(b.title, 40)}  {dim(str(b.minutes) + 'm')}");
        print(dim(f"                     {b.reason}"));
    }
    if plan.tips {
        print();
        for t in plan.tips {
            print("  💡 " + t);
        }
    }
    return EXIT_OK;
}

async def cmd_ics(output: str) -> int {
    res = await export_ics(include_done=False);
    text: str = first(res.reports) or "";
    Path(output).write_text(text);
    print(hex_fg("✔", "#22c55e") + f" wrote {text.count('BEGIN:VEVENT')} deadlines to {output}");
    return EXIT_OK;
}

async def cmd_demo -> int {
    res = await load_demo();
    r: OpResult | None = first(res.reports);
    if r is None {
        return EXIT_FAIL;
    }
    print((hex_fg("✔", "#22c55e") if r.ok else hex_fg("•", "#eab308")) + " " + r.message);
    return EXIT_OK if r.ok else EXIT_FAIL;
}

# ------------------------------------------------------------ dispatch ----

async def dispatch(args: any, cfg: CliConfig) -> int {
    cmd = args.command;
    if cmd == "today" {
        return await cmd_today(args.json);
    }
    if cmd == "ls" {
        return await cmd_ls(args);
    }
    if cmd == "add" {
        return await cmd_add(args);
    }
    if cmd in ["done", "undo", "start"] {
        return await cmd_status(args.ids, {"done": "done", "undo": "todo", "start": "doing"}[cmd]);
    }
    if cmd == "show" {
        return await cmd_show(args.id);
    }
    if cmd == "rm" {
        return await cmd_rm(args.id);
    }
    if cmd == "open" {
        return await cmd_open(args.id);
    }
    if cmd == "step" {
        return await cmd_step(args.id, args.number);
    }
    if cmd == "breakdown" {
        return await cmd_breakdown(args.id);
    }
    if cmd == "score" {
        return await cmd_score(args.id, args.score, args.of);
    }
    if cmd == "courses" {
        return await cmd_courses();
    }
    if cmd == "week" {
        return await cmd_week(args.next);
    }
    if cmd == "grades" {
        return await cmd_grades();
    }
    if cmd == "sync" {
        return await cmd_sync();
    }
    if cmd == "plan" {
        return await cmd_plan(args.hours, args.goal, not args.no_ai);
    }
    if cmd == "ics" {
        return await cmd_ics(args.output);
    }
    if cmd == "demo" {
        return await cmd_demo();
    }
    if cmd == "whoami" {
        return await cmd_whoami(cfg);
    }
    warn("unknown command " + cmd);
    return EXIT_USAGE;
}

async def main(argv: list[str]) -> int {
    args = build_parser().parse_args(argv);
    if args.no_color {
        set_color(False);
    }
    cfg = load_config();
    if args.command in ["login", "signup"] {
        return cmd_login(args, cfg, args.command == "signup");
    }
    if args.command == "logout" {
        return cmd_logout(cfg);
    }
    if not cfg.token {
        warn("not signed in - run: planner login   (jac run cli -- login)");
        return EXIT_AUTH;
    }
    connect(cfg);
    try {
        return await dispatch(args, cfg);
    } except BridgeError as e {
        return explain(e, cfg);
    }
}

with entry:__main__ {
    try {
        sys.`exit(asyncio.run(main(sys.argv[1:])));
    } except KeyboardInterrupt {
        sys.`exit(130);
    } except BrokenPipeError {
        import os;
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno());
        sys.`exit(0);
    }
}
