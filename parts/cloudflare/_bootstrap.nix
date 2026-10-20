# Layer 1: mints the token profiles in ./tokens.nix. Applied rarely, by hand,
# with your own root token (one that can create API tokens). Never in CI.
{
  lib,
  cloudflare,
  zoneIds,
  backend,
}:
let
  inherit (cloudflare) tokens;

  # Zone permissions cover every declared zone, account ones the account, and
  # allZones every zone in the account, including ones not declared yet.
  account = "com.cloudflare.api.account.${cloudflare.accountId}";
  resources = {
    zone = lib.genAttrs (map (id: "com.cloudflare.api.account.zone.${id}") zoneIds) (_: "*");
    account.${account} = "*";
    allZones.${account}."com.cloudflare.api.account.zone.*" = "*";
  };

  # Unknown names resolve to a dummy ID so the precondition below can report
  # them, instead of an opaque "invalid index" error.
  groupId = name: "\${lookup(local.permission_ids, ${builtins.toJSON name}, [\"unknown\"])[0]}";

  policy = scope: names: {
    effect = "allow";
    permission_groups = map (name: { id = groupId name; }) names;
    resources = builtins.toJSON resources.${scope};
  };

  token =
    name: profile:
    let
      names = profile.zone ++ profile.account ++ profile.allZones;
    in
    {
      name = "nix-images-${name}";
      expires_on = cloudflare.tokenExpiry;
      policies = lib.mapAttrsToList policy (
        lib.filterAttrs (scope: n: n != [ ] && resources.${scope} != { }) profile
      );
      lifecycle.precondition = {
        condition = "\${length(setsubtract(${builtins.toJSON names}, keys(local.permission_ids))) == 0}";
        error_message = "Unknown Cloudflare permission groups in parts/cloudflare/tokens.nix: \${join(\", \", setsubtract(${builtins.toJSON names}, keys(local.permission_ids)))}";
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
