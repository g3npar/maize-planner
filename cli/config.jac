"""Where the CLI finds the server and who it signs in as.

Config lives in ~/.config/maize-planner/config.json (mode 600):
    {"server": "http://localhost:8000", "username": "...", "token": "..."}
PLANNER_SERVER / PLANNER_TOKEN override it, which is handy for scripts.
Login and signup talk to the server's built-in /user endpoints directly;
everything else goes through the typed walker bridge (see main.jac).
"""

import json;
import os;
import urllib.request;
import urllib.error;
import from pathlib { Path }

glob DEFAULT_SERVER: str = "http://localhost:8000",
     SERVICE_ROUTE: str = "/api/planner";

obj CliConfig {
    has server: str = DEFAULT_SERVER,
        username: str = "",
        token: str = "";
}

def config_path -> Path {
    base = os.environ.get("XDG_CONFIG_HOME", "") or str(Path.home() / ".config");
    return Path(base) / "maize-planner" / "config.json";
}

def load_config -> CliConfig {
    cfg = CliConfig();
    path = config_path();
    if path.exists() {
        try {
            raw = json.loads(path.read_text());
            cfg.server = str(raw.get("server") or DEFAULT_SERVER);
            cfg.username = str(raw.get("username") or "");
            cfg.token = str(raw.get("token") or "");
        } except (ValueError, OSError) {
            cfg = CliConfig();
        }
    }
    env_server = os.environ.get("PLANNER_SERVER", "");
    env_token = os.environ.get("PLANNER_TOKEN", "");
    if env_server {
        cfg.server = env_server;
    }
    if env_token {
        cfg.token = env_token;
    }
    cfg.server = cfg.server.rstrip("/");
    return cfg;
}

def save_config(cfg: CliConfig) {
    path = config_path();
    path.parent.mkdir(parents=True, exist_ok=True);
    path.write_text(
        json.dumps(
            {"server": cfg.server, "username": cfg.username, "token": cfg.token},
            indent=2
        )
    );
    try {
        os.chmod(path, 0o600);
    } except OSError {}
}

obj AuthError(Exception) {
    has message: str = "";
}

def _post_json(url: str, body: dict[str, any]) -> dict[str, any] {
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    );
    try {
        with urllib.request.urlopen(req, timeout=20) as resp {
            return json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        try {
            payload = json.loads(e.read().decode("utf-8"));
        } except ValueError {
            payload = {};
        }
        err = payload.get("error") if isinstance(payload, dict) else None;
        detail = err.get("message") if isinstance(err, dict) else "";
        raise AuthError(message=detail or f"server answered HTTP {e.code}");
    } except urllib.error.URLError as e {
        raise AuthError(
            message=f"can't reach {url.rsplit('/user', 1)[0]} ({str(e.reason)}) - is `jac run` running?"
        );
    }
}

def login(server: str, username: str, password: str) -> str {
    res = _post_json(
        server.rstrip("/") + "/user/login",
        {
            "identity": {"type": "username", "value": username},
            "credential": {"type": "password", "password": password}
        }
    );
    data = res.get("data") if isinstance(res, dict) else None;
    token = data.get("token") if isinstance(data, dict) else None;
    if not token {
        raise AuthError(message="wrong username or password");
    }
    return str(token);
}

def signup(server: str, username: str, password: str) -> str {
    _ = _post_json(
        server.rstrip("/") + "/user/register",
        {
            "identities": [{"type": "username", "value": username}],
            "credential": {"type": "password", "password": password}
        }
    );
    return login(server, username, password);
}
