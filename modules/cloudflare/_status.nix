# status.mirazo.org: the status page (modules/site) served by a Worker, behind
# Cloudflare Access so only the owner sees it (a one-time code mailed to
# their address). The custom domain depends on the Access application, so
# the hostname never answers before Access guards it.
#
# The Worker has two routes:
#   GET /        → the status HTML (the built page from modules/site)
#   GET /api/ci  → GitHub Actions runs for the repository, cached 60 s
{
  accountId,
  zoneId,
  hostname,
  viewers,
  html,
  repoFullName,
}:
let
  script = "kagamizo-status";
  worker = ''
    const HTML = ${builtins.toJSON html};
    const REPO = ${builtins.toJSON repoFullName};

    async function fetchCiRuns() {
      const url = "https://api.github.com/repos/" + REPO + "/actions/runs?per_page=30";
      const resp = await fetch(url, {
        headers: { "User-Agent": "kagamizo-status" },
      });
      if (!resp.ok) {
        return { fetched: new Date().toISOString(), runs: [], error: resp.status };
      }
      const body = await resp.json();
      const runs = (body.workflow_runs || []).map(r => ({
        name: r.name,
        workflow: r.path ? r.path.split("/").pop() : null,
        branch: r.head_branch,
        sha: r.head_sha.substring(0, 7),
        status: r.status,
        conclusion: r.conclusion,
        started: r.run_started_at,
        updated: r.updated_at,
        url: r.html_url,
        number: r.run_number,
      }));
      return { fetched: new Date().toISOString(), runs };
    }

    export default {
      async fetch(request) {
        const url = new URL(request.url);
        if (url.pathname === "/api/ci" && request.method === "GET") {
          const cache = caches.default;
          const cacheKey = new Request(url.toString(), request);
          let cached = await cache.match(cacheKey);
          if (cached) return cached;
          const data = await fetchCiRuns();
          const json = JSON.stringify(data, null, 2);
          const resp = new Response(json, {
            headers: {
              "content-type": "application/json; charset=utf-8",
              "cache-control": "public, max-age=60",
              "x-robots-tag": "noindex",
            },
          });
          // The Workers Cache API stores the response for 60 s.
          await cache.put(cacheKey, resp.clone());
          return resp;
        }
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
