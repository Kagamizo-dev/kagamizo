# The audit over transaction history (./_audit, Rust): what recurs, on which
# account and card it rests, what is paid on several accounts, what fees and
# interest cost, and what must move off the accounts being closed (the
# owner's consolidation onto Mercury, Public and Capital One, 2026-11-08).
#
#   nix run .#bank-audit -- --out FILE --closing chase-mirazo --closing credit-one-mirazo \
#     chase-mirazo=chase.csv:charges-negative capital-one-mirazo=capone.csv ...
#
# Sources are each bank's exported CSV (read by its header row; an unknown
# layout is refused, naming its headers) or the bank-link provider's feed
# as JSON, once one is chosen (./aggregators.nix). The audit goes to a
# private file; only counts and totals are printed. It touches no account.
#
#   checks.bank-audit   the audit's tests: both CSV layouts, merchant
#                       names, recurring, duplicates, fees, what to move
_: {
  perSystem =
    { pkgs, ... }:
    let
      audit = pkgs.rustPlatform.buildRustPackage {
        pname = "bank-audit";
        version = "0.1.0";
        src = ./_audit;
        cargoLock.lockFile = ./_audit/Cargo.lock;
        doCheck = true;
        meta.mainProgram = "bank-audit";
      };
    in
    {
      packages.bank-audit = audit;
      checks.bank-audit = audit;
    };
}
