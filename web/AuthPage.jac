"""Sign in / create account. One account works on web, phone and CLI."""

import from "lucide-react" { CalendarCheck, GraduationCap, Sparkles, Terminal, Smartphone }
import from core.state { Session }

def:pub AuthPage(session: Session) -> JsxElement {
    def submit(e: FormEvent) {
        e.preventDefault();
        session.submit();
    }

    <div className="auth-wrap">
        <div className="auth-art">
            <div className="brand" style={{"padding": "0"}}>
                <div className="brand-mark">M</div>
                <div>
                    <div className="brand-name" style={{"color": "#fff"}}>Maize Planner</div>
                    <div className="brand-sub" style={{"color": "#c7d2fe"}}>Built with Jac</div>
                </div>
            </div>
            <div>
                <h1>
                    Every deadline from <span className="maize">Canvas</span>,{" "}
                    <span className="maize">Gradescope</span> and{" "}
                    <span className="maize">Autograder</span> — in one place.
                </h1>
                <ul>
                    <li><CalendarCheck size={20}/> Your week of classes and due dates at a glance</li>
                    <li><GraduationCap size={20}/> Live grade math: what you need on what's left</li>
                    <li><Sparkles size={20}/> AI study plans that work around your class schedule</li>
                    <li><Smartphone size={20}/> Same planner on your phone</li>
                    <li><Terminal size={20}/> …and in your terminal: <code>planner add "eecs482 p3 due fri"</code></li>
                </ul>
            </div>
            <div className="small" style={{"opacity": "0.7"}}>EECS 449 · Assignment 1</div>
        </div>
        <div className="auth-panel">
            <form className="auth-card" onSubmit={submit}>
                <h2>{"Create your account" if session.signup else "Welcome back"}</h2>
                <p className="muted" style={{"margin": "0"}}>
                    {"One account for the web, phone and CLI." if session.signup else "Sign in to see what's due."}
                </p>
                <div className="field">
                    <label>Username</label>
                    <input
                        className="input"
                        value={session.username}
                        autoFocus={True}
                        autoComplete="username"
                        placeholder="uniqname"
                        onChange={lambda (e: ChangeEvent) { session.setUsername(e.target.value); }}
                    />
                </div>
                <div className="field">
                    <label>Password</label>
                    <input
                        className="input"
                        type="password"
                        value={session.password}
                        autoComplete={"new-password" if session.signup else "current-password"}
                        placeholder="••••••••"
                        onChange={lambda (e: ChangeEvent) { session.setPassword(e.target.value); }}
                    />
                </div>
                {session.error and <div className="error-text">{session.error}</div>}
                <button className="btn primary" type="submit" disabled={session.busy}>
                    {"Working…" if session.busy else ("Create account" if session.signup else "Sign in")}
                </button>
                <button
                    className="btn ghost"
                    type="button"
                    onClick={lambda (e: MouseEvent) { session.toggleMode(); }}
                >
                    {"I already have an account" if session.signup else "New here? Create an account"}
                </button>
            </form>
        </div>
    </div>
}
