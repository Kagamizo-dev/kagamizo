# Public's CLI commands as governance actions (`public:<command-words>`),
# typed by what each does. Every command in the pinned CLI's catalog must have
# an effect here, so a CLI bump that adds one fails evaluation until it is
# typed; `brokerage` asks governance-authorize before running any of them.
{ lib, ... }:
let
  commands = lib.attrNames (builtins.fromJSON (builtins.readFile ../catalog/_json/public.json))
    .commands;
  id = lib.replaceStrings [ " " ] [ "-" ];
  byPrefix = [
    {
      prefix = "order place";
      effect = "spend";
    }
    {
      prefix = "order replace";
      effect = "spend";
    }
    {
      prefix = "order cancel";
      effect = "write";
    }
    {
      prefix = "accounts set-default";
      effect = "write";
    }
    {
      prefix = "accounts clear-default";
      effect = "write";
    }
    {
      prefix = "auth status";
      effect = "read";
    }
    {
      prefix = "auth ";
      effect = "session";
    }
    # Quotes, history, portfolio, preflight (which places nothing), tax lots.
    {
      prefix = "";
      effect = "read";
    }
  ];
  effectOf = c: (lib.findFirst (r: lib.hasPrefix r.prefix c) null byPrefix).effect;
in
{
  governance.actions.public =
    lib.listToAttrs (
      map (
        c:
        lib.nameValuePair (id c) {
          effect = effectOf c;
          description = "public ${c}";
          command = "brokerage ${c}";
        }
      ) commands
    )
    // {
      summary = {
        effect = "read";
        description = "Accounts, then the default account's portfolio";
        command = "brokerage summary";
      };
    };
}
