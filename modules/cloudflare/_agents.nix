# The always-on agents on jingzo-host, reached only through Cloudflare:
# a remotely managed tunnel (the host dials out; it opens no port) whose
# routes send each hostname to a service on the host's loopback, each
# hostname behind Access for the declared viewers, its DNS record made only
# after its Access application exists.
#
#   agents.jingzo.org  Open WebUI (localhost:8080)
#   code.jingzo.org    OpenCode's web interface (localhost:4096)
#   harness.jingzo.org  DeepSeek Harness (localhost:4097)
#   chat.jingzo.org    Chat: tuwunel Matrix at 127.0.0.1:6167, Element Web at 8082
#
# The tunnel's token leaves OpenTofu as a sensitive output and goes,
# pass-cli to pass-cli, into the host's vault (host/TUNNEL_TOKEN):
# `infra-tunnel-token` (./infra.nix).
{
  lib,
  accountId,
  zoneId,
  zone,
  viewers,
  services,
}:
let
  hostname = name: "${name}.${zone}";
in
{
  resource = {
    cloudflare_zero_trust_tunnel_cloudflared.agents = {
      account_id = accountId;
      name = "jingzo-host-agents";
      config_src = "cloudflare";
    };
    cloudflare_zero_trust_tunnel_cloudflared_config.agents = {
      account_id = accountId;
      tunnel_id = "\${cloudflare_zero_trust_tunnel_cloudflared.agents.id}";
      # A hostname's path rules come before its catch-all.
      config.ingress =
        lib.concatMap (
          s:
          map (p: {
            hostname = hostname s.name;
            inherit (p) path;
            service = "http://localhost:${toString p.port}";
          }) s.paths
          ++ [
            {
              hostname = hostname s.name;
              service = "http://localhost:${toString s.port}";
            }
          ]
        ) services
        ++ [ { service = "http_status:404"; } ];
    };
    cloudflare_zero_trust_access_policy.agents-owner = {
      account_id = accountId;
      name = "agents: the owner";
      decision = "allow";
      include = map (e: { email.email = e; }) viewers;
    };
    cloudflare_zero_trust_access_application = builtins.listToAttrs (
      map (s: {
        name = "agents-${s.name}";
        value = {
          account_id = accountId;
          type = "self_hosted";
          name = "jingzo-host ${s.name}";
          domain = hostname s.name;
          session_duration = "24h";
          policies = [
            {
              id = "\${cloudflare_zero_trust_access_policy.agents-owner.id}";
              precedence = 1;
            }
          ];
        };
      }) services
    );
    cloudflare_dns_record = builtins.listToAttrs (
      map (s: {
        name = "agents-${s.name}";
        value = {
          zone_id = zoneId;
          name = hostname s.name;
          type = "CNAME";
          content = "\${cloudflare_zero_trust_tunnel_cloudflared.agents.id}.cfargotunnel.com";
          proxied = true;
          ttl = 1;
          comment = "jingzo-host's ${s.name}, through the agents tunnel (modules/cloudflare/_agents.nix)";
          # Never resolvable before Access guards it.
          depends_on = [ "cloudflare_zero_trust_access_application.agents-${s.name}" ];
        };
      }) services
    );
  };
  data.cloudflare_zero_trust_tunnel_cloudflared_token.agents = {
    account_id = accountId;
    tunnel_id = "\${cloudflare_zero_trust_tunnel_cloudflared.agents.id}";
  };
  output.agents_tunnel_token = {
    value = "\${data.cloudflare_zero_trust_tunnel_cloudflared_token.agents.token}";
    sensitive = true;
  };
}
