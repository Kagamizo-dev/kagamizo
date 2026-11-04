# The end of GitHub's App manifest flow, on jingzo-host
# (../github/agents-app.nix): GitHub sends the owner's browser to
# chat.<zone>/_github/app?code=... (behind Access), this small service
# trades the code for the new App's private key and id, stores them as an
# note in the host's state vault (what automation writes), and shows the owner one
# line. The install step lands here too (installation_id) and is only
# acknowledged: the token minter finds installations by itself.
#
# A few dozen lines of the standard library: no framework, no network but
# api.github.com and Proton Pass.
{
  port,
  item,
  stateVault,
  passCli,
  tokenFile,
}:
{ pkgs, ... }:
let
  python = pkgs.python3;
  handler = pkgs.writeText "github_app_redirect.py" ''
    import json, os, subprocess, sys, urllib.request
    from http.server import BaseHTTPRequestHandler, HTTPServer
    from urllib.parse import urlparse, parse_qs

    VAULT, ITEM = os.environ["VAULT"], os.environ["ITEM"]

    def store(app):
        # A note, as every value automation writes (modules/operations):
        # the App's id and private key, read by github-app-token.
        template = {
            "title": ITEM,
            "note": json.dumps({"id": app["id"], "slug": app["slug"], "client_id": app["client_id"], "pem": app["pem"]}),
        }
        subprocess.run(["pass-cli", "item", "create", "note", "--vault-name", VAULT, "--from-template", "-"],
                       input=json.dumps(template).encode(), check=True, stdout=subprocess.DEVNULL)

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):  # the code never reaches the journal
            pass
        def reply(self, text, status=200):
            body = f"<!doctype html><meta charset=utf-8><title>GitHub App</title><p style='font:16px system-ui;margin:32px'>{text}</p>".encode()
            self.send_response(status); self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
        def do_GET(self):
            u = urlparse(self.path)
            if u.path != "/_github/app":
                return self.reply("nothing here", 404)
            q = parse_qs(u.query)
            if "code" in q:
                req = urllib.request.Request(f"https://api.github.com/app-manifests/{q['code'][0]}/conversions",
                                             method="POST", headers={"Accept": "application/vnd.github+json"})
                with urllib.request.urlopen(req, timeout=30) as r:
                    app = json.load(r)
                store(app)
                return self.reply(f"The App <b>{app['slug']}</b> (id {app['id']}) exists and jingzo-host holds its key. Install it on the repository next: <a href='{app['html_url']}/installations/new'>{app['html_url']}/installations/new</a>")
            if "installation_id" in q:
                return self.reply(f"Installed (installation {q['installation_id'][0]}). The agents can work.")
            return self.reply("no code", 400)

    HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
  '';
in
{
  systemd.services.github-app-redirect = {
    description = "Finishes GitHub's App manifest flow into the host's state vault";
    wantedBy = [ "multi-user.target" ];
    after = [ "agents-secrets.service" ];
    path = [
      passCli
      pkgs.coreutils
    ];
    environment = {
      VAULT = stateVault;
      ITEM = item;
      PROTON_PASS_KEY_PROVIDER = "fs";
      PROTON_PASS_AGENT_REASON = "jingzo-host: store the agents' GitHub App key";
      HOME = "/root";
    };
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 10;
    };
    script = ''
      pass-cli info >/dev/null 2>&1 || pass-cli login --pat "$(cat ${tokenFile})" >/dev/null
      exec ${python}/bin/python3 -I ${handler} ${toString port}
    '';
  };
}
