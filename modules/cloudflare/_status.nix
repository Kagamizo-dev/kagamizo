# status.mirazo.org: the status page (modules/site) served by a Worker, behind
# Cloudflare Access so only the owner sees it (a one-time code mailed to
# their address). The custom domain depends on the Access application, so
# the hostname never answers before Access guards it.
{
  lib,
  accountId,
  zoneId,
  hostname,
  viewers,
  html,
}:
let
  script = "kagamizo-status";
  worker = ''
    const HTML = ${builtins.toJSON html};
    export default {
      async fetch() {
        return new Response(HTML, {
          headers: {
            "content-type": "text/html; charset=utf-8",
            "cache-control": "no-store",
            "x-robots-tag": "noindex",
            "x-frame-options": "DENY",
          },
        });
      },
    };
  '';
in
{
  resource = {
    cloudflare_workers_script.status = {
      account_id = accountId;
      script_name = script;
      content = worker;
      main_module = "worker.js";
      compatibility_date = "2026-10-01";
    };
    cloudflare_zero_trust_access_policy.status-owner = {
      account_id = accountId;
      name = "status: the owner";
      decision = "allow";
      include = map (e: { email.email = e; }) viewers;
    };
    cloudflare_zero_trust_access_application.status = {
      account_id = accountId;
      type = "self_hosted";
      name = "Kagamizo status";
      domain = hostname;
      session_duration = "24h";
      policies = [
        {
          id = "\${cloudflare_zero_trust_access_policy.status-owner.id}";
          precedence = 1;
        }
      ];
    };
    cloudflare_workers_custom_domain.status = {
      account_id = accountId;
      zone_id = zoneId;
      inherit hostname;
      service = script;
      depends_on = [
        "cloudflare_workers_script.status"
        "cloudflare_zero_trust_access_application.status"
      ];
    };
  };
}
