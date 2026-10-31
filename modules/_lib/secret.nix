# A secret: what it is, which Proton Pass item holds it (the vault comes from
# its profile's or its own `providers`), and its place on the boundary
# between the owner and automation (../operations):
#
#   secret {
#     kind = "api-token";                   # what it is (operations.secretKinds)
#     issuer = "human:console-credential";  # who produces it: automation:<tool>
#                                           # or human:<step> (operations.humanSteps)
#     needs = [ "approve-sign-in" ];        # human steps an automated issuer
#                                           # waits on (default none)
#     description = "...";
#     item = "hcloud-token";
#     template = "api-credential";          # with field: a custom item made
#     field = "Secret";                     # from that Proton Pass template,
#                                           # read at that field (pass-items.json)
#   }
#
# Without a field, the secret is a note's body: what automation writes.
# The boundary is kept under `boundary`, which ../proton/secretspec.nix
# leaves out of secretspec.toml; ../operations checks it, and Lean proves
# its rules hold for every declared secret.
{
  kind,
  issuer,
  description,
  item,
  needs ? [ ],
  template ? null,
  field ? null,
}:
assert (template == null) == (field == null);
{
  inherit description;
  ref = {
    inherit item;
  }
  // (if field == null then { } else { inherit field; });
  boundary = {
    inherit kind issuer needs;
    store =
      if field == null then
        { at = "note"; }
      else
        {
          at = "field";
          inherit template field;
        };
  };
}
