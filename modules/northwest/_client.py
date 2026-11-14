"""Northwest Registered Agent's MCP server, from the command line.

Northwest publishes no REST API to its clients; it publishes an MCP server
(https://mcp.northwestregisteredagent.com, streamable HTTP) with the same
tools its portal assistant has, behind OAuth on its own identity server. This
client speaks both, with nothing but the standard library:

  login           discover the authorization server (RFC 9728, RFC 8414),
                  register a loopback client when it allows dynamic
                  registration (RFC 7591) or use the public `mcp-connector`
                  client, then PKCE sign-in; prints the approval link to
                  stderr and waits for the 127.0.0.1 callback
  status          whether the stored session still opens the server
  tools           tools/list, every page, as JSON (the catalog's source)
  call TOOL [ARGS-JSON]
                  tools/call; prints the result's content as JSON

The session (endpoints, client id, tokens) is the JSON file named by
NORTHWEST_SESSION_FILE; it is read, refreshed and rewritten in place, and the
wrapper stores it back in Proton Pass. Nothing is printed but results.
"""

import base64
import hashlib
import http.server
import json
import os
import secrets
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

SERVER = os.environ.get("NORTHWEST_MCP_URL", "https://mcp.northwestregisteredagent.com")
PUBLIC_CLIENT = "mcp-connector"
PROTOCOL = "2025-06-18"
SCOPES = "openid offline_access"


def die(msg, code=1):
    print(f"northwest: {msg}", file=sys.stderr)
    sys.exit(code)


def fetch(method, url, body=None, headers=None, form=False):
    headers = dict(headers or {})
    data = None
    if body is not None:
        if form:
            data = urllib.parse.urlencode(body).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def get_json(url):
    status, _, raw = fetch("GET", url, headers={"Accept": "application/json"})
    if status != 200:
        return None
    return json.loads(raw)


# --- session file -----------------------------------------------------------

def session_path():
    p = os.environ.get("NORTHWEST_SESSION_FILE")
    if not p:
        die("NORTHWEST_SESSION_FILE is not set", 2)
    return p


def load():
    try:
        with open(session_path()) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        die("no session; run `northwest login`")


def save(s):
    p = session_path()
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(s, f)


# --- OAuth ------------------------------------------------------------------

def discover():
    base = SERVER.rstrip("/")
    u = urllib.parse.urlsplit(base)
    origin = f"{u.scheme}://{u.netloc}"
    # RFC 9728: the resource names its authorization server.
    meta = get_json(f"{origin}/.well-known/oauth-protected-resource{u.path}") or get_json(
        f"{origin}/.well-known/oauth-protected-resource"
    )
    if not meta or not meta.get("authorization_servers"):
        die(f"{origin} publishes no protected-resource metadata")
    issuer = meta["authorization_servers"][0].rstrip("/")
    i = urllib.parse.urlsplit(issuer)
    iorigin = f"{i.scheme}://{i.netloc}"
    # RFC 8414 first, then OpenID discovery (Keycloak serves both).
    as_meta = (
        get_json(f"{iorigin}/.well-known/oauth-authorization-server{i.path}")
        or get_json(f"{issuer}/.well-known/openid-configuration")
    )
    if not as_meta:
        die(f"{issuer} publishes no authorization server metadata")
    return meta.get("resource", base), as_meta


def pkce():
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def login(timeout):
    resource, as_meta = discover()
    got = {}
    done = threading.Event()

    class Callback(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            if urllib.parse.urlsplit(self.path).path == "/callback":
                got.update({k: v[0] for k, v in q.items()})
                done.set()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Northwest: signed in. You can close this page.\n")

        def log_message(self, *a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", 0), Callback)
    redirect = f"http://127.0.0.1:{srv.server_port}/callback"

    client_id = PUBLIC_CLIENT
    reg = as_meta.get("registration_endpoint")
    if reg:
        status, _, raw = fetch(
            "POST",
            reg,
            {
                "client_name": "kagamizo northwest",
                "redirect_uris": [redirect],
                "grant_types": ["authorization_code", "refresh_token"],
                "response_types": ["code"],
                "token_endpoint_auth_method": "none",
                "scope": SCOPES,
            },
        )
        if status in (200, 201):
            client_id = json.loads(raw)["client_id"]
        else:
            print(f"northwest: dynamic registration refused ({status}); using {PUBLIC_CLIENT}", file=sys.stderr)

    verifier, challenge = pkce()
    state = secrets.token_hex(16)
    url = as_meta["authorization_endpoint"] + "?" + urllib.parse.urlencode(
        {
            "client_id": client_id,
            "response_type": "code",
            "redirect_uri": redirect,
            "scope": SCOPES,
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "resource": resource,
        }
    )
    print(f"\nApprove the Northwest sign-in:\n\n  {url}\n", file=sys.stderr)
    print(f"Waiting {timeout}s for {redirect}", file=sys.stderr)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    if not done.wait(timeout):
        srv.shutdown()
        die("timed out waiting for the callback")
    srv.shutdown()
    if got.get("state") != state:
        die("the callback's state does not match this login")
    if "code" not in got:
        die(f"sign-in refused: {got.get('error', 'no code')}")

    status, _, raw = fetch(
        "POST",
        as_meta["token_endpoint"],
        {
            "grant_type": "authorization_code",
            "code": got["code"],
            "redirect_uri": redirect,
            "client_id": client_id,
            "code_verifier": verifier,
            "resource": resource,
        },
        form=True,
    )
    if status != 200:
        die(f"token exchange failed ({status})")
    s = {
        "server": SERVER,
        "resource": resource,
        "token_endpoint": as_meta["token_endpoint"],
        "client_id": client_id,
    }
    s.update(tokens(json.loads(raw)))
    save(s)
    print("northwest: signed in", file=sys.stderr)


def tokens(t):
    out = {"access_token": t["access_token"], "expires_at": int(time.time()) + int(t.get("expires_in", 300))}
    if t.get("refresh_token"):
        out["refresh_token"] = t["refresh_token"]
    return out


def fresh(s):
    """The session with an access token valid for the next minute."""
    if s["expires_at"] - 60 > time.time():
        return s
    if "refresh_token" not in s:
        die("the session expired and has no refresh token; run `northwest login`")
    status, _, raw = fetch(
        "POST",
        s["token_endpoint"],
        {
            "grant_type": "refresh_token",
            "refresh_token": s["refresh_token"],
            "client_id": s["client_id"],
            "resource": s["resource"],
        },
        form=True,
    )
    if status != 200:
        die(f"the session could not be refreshed ({status}); run `northwest login`")
    s.update(tokens(json.loads(raw)))
    save(s)
    return s


# --- MCP over streamable HTTP ----------------------------------------------

class Mcp:
    def __init__(self, s):
        self.s = fresh(s)
        self.session = None
        self.next = 0
        init = self.request(
            "initialize",
            {
                "protocolVersion": PROTOCOL,
                "capabilities": {},
                "clientInfo": {"name": "kagamizo-northwest", "version": "1"},
            },
        )
        self.protocol = init.get("protocolVersion", PROTOCOL)
        self.notify("notifications/initialized")

    def headers(self):
        h = {
            "Authorization": f"Bearer {self.s['access_token']}",
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": getattr(self, "protocol", PROTOCOL),
        }
        if self.session:
            h["Mcp-Session-Id"] = self.session
        return h

    def post(self, msg):
        status, headers, raw = fetch("POST", self.s["server"], msg, self.headers())
        headers = {k.lower(): v for k, v in headers.items()}
        if status == 401:
            die("the server refused the session; run `northwest login`")
        if status >= 400:
            die(f"{msg.get('method')}: HTTP {status}")
        if "mcp-session-id" in headers:
            self.session = headers["mcp-session-id"]
        return headers.get("content-type", ""), raw

    def notify(self, method, params=None):
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        self.post(msg)

    def request(self, method, params):
        self.next += 1
        rid = self.next
        ctype, raw = self.post({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        for reply in self.messages(ctype, raw):
            if reply.get("id") == rid:
                if "error" in reply:
                    die(f"{method}: {reply['error'].get('message', reply['error'])}")
                return reply["result"]
        die(f"{method}: no reply")

    @staticmethod
    def messages(ctype, raw):
        text = raw.decode()
        if ctype.startswith("text/event-stream"):
            data = []
            for line in text.splitlines() + [""]:
                if line.startswith("data:"):
                    data.append(line[5:].lstrip())
                elif not line and data:
                    yield json.loads("\n".join(data))
                    data = []
        elif text.strip():
            body = json.loads(text)
            yield from body if isinstance(body, list) else [body]


def list_tools(m):
    out, cursor = [], None
    while True:
        r = m.request("tools/list", {"cursor": cursor} if cursor else {})
        out += r.get("tools", [])
        cursor = r.get("nextCursor")
        if not cursor:
            return out


def main(argv):
    if not argv:
        die("usage: northwest <login|status|tools|call TOOL [ARGS-JSON]>", 2)
    cmd, rest = argv[0], argv[1:]
    if cmd == "login":
        login(int(os.environ.get("NORTHWEST_LOGIN_TIMEOUT", "600")))
    elif cmd == "status":
        m = Mcp(load())
        print(f"northwest: the session works ({len(list_tools(m))} tools)", file=sys.stderr)
    elif cmd == "tools":
        json.dump(list_tools(Mcp(load())), sys.stdout, indent=2, sort_keys=True)
        print()
    elif cmd == "call":
        if not rest:
            die("usage: northwest call TOOL [ARGS-JSON]", 2)
        args = json.loads(rest[1]) if len(rest) > 1 else {}
        r = Mcp(load()).request("tools/call", {"name": rest[0], "arguments": args})
        json.dump(r.get("structuredContent", r.get("content")), sys.stdout, indent=2)
        print()
        if r.get("isError"):
            sys.exit(1)
    else:
        die(f"unknown command {cmd}", 2)


if __name__ == "__main__":
    main(sys.argv[1:])
