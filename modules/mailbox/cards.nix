# Mailbox cards: handing an agent team a scoped piece of mail (the owner's
# direction, 2026-11-14: mint a card, give it to an agent with an
# instruction, see the result). A card is one address, the senders it
# admits, what its holder may do, and the day it stops.
#
#   mailbox.cards.<c> = {
#     address;   an address on a declared domain. Every domain's catch-all
#                delivers to its automations mailbox (../proton-mail), so a
#                new address costs nothing and needs no change at Proton
#     from;      the sender domains the holder may see; empty is any
#     may;       headers, bodies, draft. No card may send: mail leaves only
#                as a batch the owner approved (./default.nix)
#     holder;    the one team it is handed to
#     until;     the last day it is good for
#     why;
#   }
#
# Where the scope is held: Bridge serves the whole mailbox to the machine,
# so `mailbox read --card C` (./_src/src/cards.rs) is the boundary. It
# writes out only what the card admits, and a holder is given its output,
# never the mailbox.
#
# checks.mailbox-cards (./_lean/Cards.lean): every card's address is
# delivered, no two share one, each holder serves the entity that owns the
# domain, and none may send.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.mailbox.cards;
  q = builtins.toJSON;
  inherit (config.identity.checked) domains;
  agents = config.governance.agents;
  hostOf = address: lib.last (lib.splitString "@" address);
  localOf = address: lib.head (lib.splitString "@" address);
  delivered =
    c:
    let
      d = hostOf c.address;
    in
    domains ? ${d}
    && (
      lib.elem (localOf c.address) domains.${d}.mailboxes || (config.protonMail.catchAll.${d} or "") != ""
    );

  card = types.submodule {
    options = {
      address = mkOption { type = types.strMatching "[a-z0-9][a-z0-9.+-]*@([a-z0-9-]+\\.)+[a-z]{2,}"; };
      from = mkOption {
        type = types.listOf (types.strMatching "([a-z0-9-]+\\.)+[a-z]{2,}");
        default = [ ];
        description = "Sender domains the holder may see (a subdomain of one counts); empty is any.";
      };
      may = mkOption {
        type = types.nonEmptyListOf (
          types.enum [
            "headers"
            "bodies"
            "draft"
            "send"
          ]
        );
      };
      holder = mkOption { type = types.enum (lib.attrNames agents); };
      until = mkOption { type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}"; };
      why = mkOption { type = types.str; };
    };
  };

  facts = ''

    namespace Kagamizo.Mailbox

    def cards : List Card := [${
      lib.concatStringsSep ",\n  " (
        lib.mapAttrsToList (
          n: c:
          "{ name := ${q n}, address := ${q c.address}, delivered := ${lib.boolToString (delivered c)}, owner := ${
            q (domains.${hostOf c.address}.entity or "")
          }, holder := ${q c.holder}, serves := ${q agents.${c.holder}.serves}, may := [${
            lib.concatMapStringsSep ", " (m: ".${m}") c.may
          }] }"
        ) cfg
      )
    }]

    theorem cards_sound : sound cards = true := by
      decide +kernel

    end Kagamizo.Mailbox
  '';
in
{
  options.mailbox.cards = mkOption {
    type = types.attrsOf card;
    default = { };
  };

  config = {
    # The first card: nothing is sent to this address yet, so it hands over
    # no mail until something is pointed at it.
    mailbox.cards.receipts = {
      address = "receipts@jingzo.org";
      may = [
        "headers"
        "bodies"
        "draft"
      ];
      holder = "accounting-jingzo";
      until = "2027-01-31";
      why = "receipts, renewals and bills sent to Jingzo, for the books";
    };

    governance.actions.proton.read-card = {
      effect = "read";
      description = "The mail a mailbox card admits, to a private file: its address, its senders, what it may see";
      command = "mailbox read";
    };

    perSystem =
      { config, ... }:
      {
        checks.mailbox-cards = config.kagamizo.leanCheck {
          name = "mailbox-cards";
          source = ./_lean/Cards.lean;
          inherit facts;
        };
      };
  };
}
