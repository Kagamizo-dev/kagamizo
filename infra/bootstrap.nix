# Layer 1: mints the token profiles in ./tokens.nix. Applied rarely, by hand,
# with your own root token (one that can create API tokens). Never in CI.
{
  lib,
  settings,
  tokens,
  backend,
}:
let
  resourceKeys = {
    zone = "com.cloudflare.api.account.zone.${settings.zoneId}";
    account = "com.cloudflare.api.account.${settings.accountId}";
  };

  # Unknown names resolve to a dummy ID so the precondition below can report
  # them, instead of an opaque "invalid index" error.
  groupId = name: "\${lookup(local.permission_ids, ${builtins.toJSON name}, [\"unknown\"])[0]}";

  policy = scope: names: {
    effect = "allow";
    permission_groups = map (name: { id = groupId name; }) names;
    resources = builtins.toJSON { ${resourceKeys.${scope}} = "*"; };
  };

  token =
    name: profile:
    let
      names = profile.zone ++ profile.account;
    in
    {
      name = "nix-images-${name}";
      expires_on = settings.tokenExpiry;
      policies = lib.mapAttrsToList policy (lib.filterAttrs (_: n: n != [ ]) profile);
      lifecycle.precondition = {
        condition = "\${length(setsubtract(${builtins.toJSON names}, keys(local.permission_ids))) == 0}";
        error_message = "Unknown Cloudflare permission groups in infra/tokens.nix: \${join(\", \", setsubtract(${builtins.toJSON names}, keys(local.permission_ids)))}";
      };
    };
in
{
  terraform = backend "bootstrap";
  provider.cloudflare = { };

  data.cloudflare_api_token_permission_groups_list.all = { };
  locals.permission_ids = "\${{ for g in data.cloudflare_api_token_permission_groups_list.all.result : g.name => g.id... }}";

  resource.cloudflare_api_token = lib.mapAttrs token tokens;

  output = lib.mapAttrs (name: _: {
    value = "\${cloudflare_api_token.${name}.value}";
    sensitive = true;
  }) tokens;
}
