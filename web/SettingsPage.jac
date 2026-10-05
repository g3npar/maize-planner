"""Settings: Canvas connection, AI status, CLI setup, export, account."""

import from "lucide-react" { Link2, RefreshCw, Sparkles, Terminal, Download, User, Sun, Moon, Monitor, Database }
import from core.state { Planner }

def:pub SettingsPage(
    p: Planner,
    theme: str,
    onTheme: Callable[[str], None],
    onExport: Callable[[], None]
) -> JsxElement {
    has name: str = "",
        url: str = "",
        token: str = "",
        feed: str = "",
        loaded: bool = False;

    can with entry {
        p.loadSettings();
    }
    can with [p.settings] entry {
        if p.settings is not None and not loaded {
            name = p.settings.display_name;
            url = p.settings.canvas_url;
            loaded = True;
        }
    }
    st = p.settings;
    # Set at build time when the UI is hosted apart from the server (GitHub Pages).
    api_base: any = globalThis.__JAC_API_BASE_URL__;
    server = api_base or window.location.origin;
    sync_errors: list[str] = p.syncResult.errors if p.syncResult is not None else [];

    connected = st is not None and (st.has_token or st.has_feed);
    badge = "";
    if st is not None {
        badge = ("Connected " + st.token_hint) if st.has_token else "Calendar feed connected";
    }

    async def save -> None {
        await p.saveSettings(name, url, token, feed, False);
        token = "";
        feed = "";
    }

    async def save_and_sync -> None {
        await p.saveSettings(name, url, token, feed, False);
        token = "";
        feed = "";
        await p.syncCanvas();
    }

    <div className="grid-2">
        <div className="stack" style={{"gap": "20px"}}>
            <div className="card">
                <div className="card-head"><Link2 size={17}/><h2>Canvas</h2>
                    <span className="spacer"></span>
                    {connected and <span className="badge" style={{"--chip": "#16a34a"}}>{badge}</span>}
                </div>
                <div className="stack">
                    <div className="muted small">
                        Connect with your Canvas calendar feed (works everywhere, including UMich) or an access token if your school allows students to make them.
                        The feed imports your courses and every assignment with its due date; a token also brings in points, assignment-group weights, submission status and grades.
                    </div>
                    <div className="field">
                        <label>Calendar feed link {st is not None and st.has_feed and <span className="muted">(leave blank to keep the current one)</span>}</label>
                        <input className="input" type="password" value={feed} placeholder="Canvas → Calendar → Calendar Feed (bottom right) → copy the link" onChange={lambda (e: ChangeEvent) { feed = e.target.value; }}/>
                    </div>
                    <div className="field">
                        <label>Canvas URL</label>
                        <input className="input" value={url} placeholder="https://umich.instructure.com" onChange={lambda (e: ChangeEvent) { url = e.target.value; }}/>
                    </div>
                    <div className="field">
                        <label>Access token <span className="muted">{"(leave blank to keep the current one)" if st is not None and st.has_token else "(optional, used instead of the feed)"}</span></label>
                        <input className="input" type="password" value={token} placeholder="Canvas → Account → Settings → + New Access Token" onChange={lambda (e: ChangeEvent) { token = e.target.value; }}/>
                    </div>
                    <div className="row-flex">
                        <button className="btn primary" disabled={p.syncBusy} onClick={lambda (e: MouseEvent) { save_and_sync(); }}>
                            <RefreshCw size={15} className={"spin" if p.syncBusy else ""}/>{"Syncing…" if p.syncBusy else "Save & sync now"}
                        </button>
                        <button className="btn" onClick={lambda (e: MouseEvent) { save(); }}>Save</button>
                        {connected and <button className="btn danger" onClick={lambda (e: MouseEvent) { p.saveSettings(name, url, "", "", True); }}>Disconnect</button>}
                    </div>
                    {st is not None and st.last_sync and <div className="callout small">
                        <b>Last sync {st.last_sync.replace("T", " ")}</b> · {st.last_sync_summary}
                    </div>}
                    {len(sync_errors) > 0 and <div className="callout warn small">
                        {for err in sync_errors { <div key={err}>{err}</div> }}
                    </div>}
                </div>
            </div>
            <div className="card">
                <div className="card-head"><Sparkles size={17}/><h2>AI assistant</h2></div>
                {st is not None and st.ai_ready and <div className="small">Using <code>{st.ai_model}</code> for study plans and assignment breakdowns.</div>}
                {(st is None or not st.ai_ready) and <div className="stack small">
                    <div>No API key found, so plans and breakdowns use the built-in heuristics (they still work!). To turn on AI, restart the server with a key:</div>
                    <code className="cmd">{"export ANTHROPIC_API_KEY=sk-ant-...   # or OPENAI_API_KEY / GEMINI_API_KEY" + chr(10) + "jac run"}</code>
                </div>}
            </div>
            <div className="card">
                <div className="card-head"><User size={17}/><h2>Profile</h2></div>
                <div className="stack">
                    <div className="field">
                        <label>Display name (used in the greeting)</label>
                        <div className="row-flex" style={{"flexWrap": "nowrap"}}>
                            <input className="input" value={name} placeholder="Your first name" onChange={lambda (e: ChangeEvent) { name = e.target.value; }}/>
                            <button className="btn" onClick={lambda (e: MouseEvent) { save(); }}>Save</button>
                        </div>
                    </div>
                    <div className="field">
                        <label>Theme</label>
                        <div className="seg">
                            {for (key, label) in [("system", "System"), ("light", "Light"), ("dark", "Dark")] {
                                <button key={key} className={"on" if theme == key else ""} onClick={lambda (e: MouseEvent) { onTheme(key); }}>{label}</button>
                            }}
                        </div>
                    </div>
                    <div className="row-flex">
                        <span className="muted small">Signed in as <b>{p.session.username or "you"}</b></span>
                        <span className="grow"></span>
                        <button className="btn danger sm" onClick={lambda (e: MouseEvent) { p.session.logout(); }}>Sign out</button>
                    </div>
                </div>
            </div>
        </div>
        <div className="stack" style={{"gap": "20px"}}>
            <div className="card">
                <div className="card-head"><Terminal size={17}/><h2>Command line</h2></div>
                <div className="stack small">
                    <div>The same planner is scriptable from your terminal. From the project folder:</div>
                    <code className="cmd">{"jac run cli -- login --server " + server + chr(10) + "jac run cli -- today" + chr(10) + "jac run cli -- add \"eecs482 p3 due fri 11:59pm #ag\"" + chr(10) + "jac run cli -- done <id>"}</code>
                    <div className="muted">Tip: <code>alias planner="jac run cli --"</code> then just <code>planner today</code>.</div>
                </div>
            </div>
            <div className="card">
                <div className="card-head"><Download size={17}/><h2>Calendar export</h2></div>
                <div className="stack small">
                    <div>Download every open deadline as an <code>.ics</code> file (with a 24-hour reminder) for Google Calendar, Apple Calendar or Outlook.</div>
                    <div><button className="btn" onClick={lambda (e: MouseEvent) { onExport(); }}><Download size={15}/> Download planner.ics</button></div>
                </div>
            </div>
            <div className="card">
                <div className="card-head"><Database size={17}/><h2>Demo data</h2></div>
                <div className="stack small">
                    <div>Load a realistic semester (three classes, meetings, twelve assignments across Canvas, Gradescope and Autograder) into an empty planner.</div>
                    <div><button className="btn maize" onClick={lambda (e: MouseEvent) { p.loadDemo(); }}>Load demo semester</button></div>
                </div>
            </div>
        </div>
    </div>
}
