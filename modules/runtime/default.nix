# Where the wrappers run, declared: nothing they see comes from outside Nix
# except what is named here. The cloud session's container is a host the
# repo does not define (its image is Anthropic's), so it is treated as
# untrusted: every wrapper starts from an empty environment (`env -i`,
# ../_lib/frozen.nix) and gets exactly the variables below.
#
#   runtime.host.home         the session's home, where pass-cli keeps its
#                             session (its XDG data folder)
#   runtime.host.passThrough  the only variables taken from the host, by
#                             name: its egress proxy and that proxy's CA
#   runtime.caller            the environment every wrapper runs with,
#                             derived from the two above
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.runtime;
  absolute = types.strMatching "/[A-Za-z0-9._/-]*[A-Za-z0-9._-]";
in
{
  options.runtime = {
    host = {
      home = mkOption {
        type = absolute;
        description = "The session's HOME; pass-cli's session is under its XDG data folder.";
      };
      passThrough = mkOption {
        type = types.listOf (
          types.enum [
            "HTTPS_PROXY"
            "https_proxy"
            "NO_PROXY"
            "no_proxy"
            "SSL_CERT_FILE"
            "NIX_SSL_CERT_FILE"
            "CURL_CA_BUNDLE"
            "REQUESTS_CA_BUNDLE"
            "GIT_SSL_CAINFO"
          ]
        );
        description = "Variables taken from the host by name (values are the host's): its proxy and CA.";
      };
    };
    caller = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      description = "Every declared variable a wrapper runs with, but PATH (the wrapper's own closure).";
    };
  };

  config.runtime = {
    host = {
      home = "/root";
      passThrough = [
        "HTTPS_PROXY"
        "https_proxy"
        "NO_PROXY"
        "no_proxy"
        "SSL_CERT_FILE"
        "NIX_SSL_CERT_FILE"
        "CURL_CA_BUNDLE"
        "REQUESTS_CA_BUNDLE"
        "GIT_SSL_CAINFO"
      ];
    };
    caller = {
      HOME = cfg.host.home;
      XDG_CONFIG_HOME = "${cfg.host.home}/.config";
      XDG_DATA_HOME = "${cfg.host.home}/.local/share";
      XDG_CACHE_HOME = "${cfg.host.home}/.cache";
      XDG_STATE_HOME = "${cfg.host.home}/.local/state";
      # The kernel keyring is not there in a container; the key is a file
      # in the (ephemeral) home.
      PROTON_PASS_KEY_PROVIDER = "fs";
      LANG = "C.UTF-8";
      # Private working folders (mktemp) go here, never a default.
      TMPDIR = "/tmp";
    };
  };
}
