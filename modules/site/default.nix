# The sites, generated from the declarations: nothing on them is written by
# hand, so what they show is what the repository states.
#
#   packages.site-status    the owner's status page (for status.mirazo.org,
#                           behind Cloudflare Access once deployed): every
#                           entity and domain, every account with its plan,
#                           billing, payment, login and credential, the open
#                           Gaps (payments not yet declared), this year's tax
#                           obligations, the CI workflows and every catalog's
#                           pinned version
#   checks.site-status      renders it in the pinned Chromium and keeps the
#                           screenshot (site-status/status.png in the build)
#
# Deploying is applying infrastructure (a Pages project, DNS, an Access
# policy): not done until the owner says go (HANDOFF.md).
{ lib, config, ... }:
let
  top = config;
  inherit (config.identity.checked) entities domains;
  held = config.accounts.held;
  plans = config.accounts.plans;
  esc = lib.replaceStrings [ "&" "<" ">" "\"" ] [ "&amp;" "&lt;" "&gt;" "&quot;" ];
  td = s: "<td>${esc (toString s)}</td>";
  row = cells: "<tr>${lib.concatMapStrings td cells}</tr>\n";
  table =
    head: rows:
    "<table><thead><tr>${
      lib.concatMapStrings (h: "<th>${esc h}</th>") head
    }</tr></thead><tbody>\n${lib.concatStrings rows}</tbody></table>";
  paymentOf =
    a:
    let
      p = a.payment;
    in
    if p == null then
      "free"
    else if p.mercuryCard != null then
      "Mercury card ${p.mercuryCard}"
    else if p.ownerCard != null then
      "owner's ${p.ownerCard.issuer} card${
        lib.optionalString (p.ownerCard.lockedTo != null) ", locked to ${p.ownerCard.lockedTo}"
      }, until Mercury card ${p.ownerCard.replacedBy}"
    else if p.waived != null then
      "waived: ${p.waived.because}"
    else
      "GAP: ${p.pending}";
  year = 2026;
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      gaps = lib.filterAttrs (_: a: a.payment != null && a.payment.pending != null) held;
      html = pkgs.writeText "index.html" ''
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Kagamizo status</title>
        <style>
          :root { --bg:#fbfaf8; --fg:#1d1c1a; --muted:#6b6862; --line:#e4e1db; --gap:#b4441f; --ok:#2f6f4f; }
          @media (prefers-color-scheme: dark) { :root { --bg:#151514; --fg:#ecebe8; --muted:#a3a09a; --line:#34322f; --gap:#ef8a64; --ok:#7fc4a0; } }
          body { background:var(--bg); color:var(--fg); font:15px/1.5 system-ui, sans-serif; margin:0 auto; max-width:1100px; padding:24px 16px; }
          h1 { font-size:22px; margin:0 0 4px } h2 { font-size:17px; margin:32px 0 8px; }
          p.lede { color:var(--muted); margin:0 0 16px }
          table { border-collapse:collapse; width:100%; font-size:13.5px; display:block; overflow-x:auto }
          th, td { text-align:left; padding:6px 10px; border-bottom:1px solid var(--line); vertical-align:top }
          th { color:var(--muted); font-weight:600 }
          td:has(+ td), th { white-space:nowrap }
          .gap { color:var(--gap) } .ok { color:var(--ok) }
        </style></head><body>
        <h1>Kagamizo status</h1>
        <p class="lede">Generated from the repository's declarations by modules/site; nothing here is written by hand.</p>

        <h2>Entities</h2>
        ${table
          [
            "Entity"
            "Legal name"
            "Kind"
            "Status"
            "Jurisdiction"
            "Taxed as"
            "Return"
          ]
          (
            lib.mapAttrsToList (
              e: x:
              row [
                e
                x.legalName
                x.kind
                x.legal.status
                (if x.legal.jurisdiction == null then "—" else x.legal.jurisdiction)
                (top.money.tax.${e}.classification or "—")
                (if top.money.tax ? ${e} then top.money.returnOf e else "—")
              ]
            ) entities
          )
        }

        <h2>Domains</h2>
        ${table [ "Domain" "Entity" "Registrar" "Mailboxes" ] (
          lib.mapAttrsToList (
            d: x:
            row [
              d
              x.entity
              x.registrar
              (lib.concatStringsSep ", " x.mailboxes)
            ]
          ) domains
        )}

        <h2>Accounts</h2>
        ${table
          [
            "Account"
            "Provider"
            "Plan"
            "Owner"
            "Status"
            "Billing"
            "Paid by"
            "Login"
            "Credential"
          ]
          (
            lib.mapAttrsToList (
              n: a:
              row [
                n
                a.provider
                a.plan
                a.owner
                a.status
                plans.${a.provider}.${a.plan}.billing.value
                (paymentOf a)
                (if a.login.email == null then "—" else a.login.email)
                (if a.credential == null then "—" else "${a.credential.template} (${a.credential.item})")
              ]
            ) held
          )
        }

        <h2 class="${
          if gaps == { } then "ok" else "gap"
        }">Gaps: payments not declared (${toString (lib.length (lib.attrNames gaps))})</h2>
        ${table [ "Account" "What is missing" ] (
          lib.mapAttrsToList (
            n: a:
            row [
              n
              a.payment.pending
            ]
          ) gaps
        )}

        <h2>Tax obligations, ${toString year}</h2>
        ${table [ "Due" "Entity" "Form" "When" ] (
          map
            (
              o:
              row [
                (if o.due == null then "not yet known" else o.due)
                o.entity
                o.form
                (o.when or "always")
              ]
            )
            (
              lib.sort (a: b: (if a.due == null then "9" else a.due) < (if b.due == null then "9" else b.due)) (
                top.money.obligations year
              )
            )
        )}

        <h2>CI</h2>
        ${table [ "Workflow" "Jobs" "Rendered for" ] (
          lib.mapAttrsToList (
            w: wf:
            row [
              w
              (lib.concatStringsSep ", " (lib.attrNames wf.jobs))
              (lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: h: h.enable) top.ci.hosts)))
            ]
          ) top.ci.workflows
        )}

        <h2>Pinned catalogs</h2>
        ${table [ "Catalog" "From" "Version" ] (
          lib.mapAttrsToList (
            n: s:
            row [
              n
              s.from
              s.version
            ]
          ) config.catalog.sources
        )}
        </body></html>
      '';
      site = pkgs.runCommand "site-status" { } ''
        mkdir $out
        cp ${html} $out/index.html
      '';
    in
    {
      packages.site-status = site;
      checks.site-status =
        pkgs.runCommand "site-status-screenshot"
          {
            nativeBuildInputs = [ pkgs.chromium ];
          }
          ''
            export HOME=$TMPDIR FONTCONFIG_FILE=${
              pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; }
            }
            mkdir $out
            chromium --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
              --window-size=1200,2600 --screenshot=$out/status.png file://${site}/index.html 2>/dev/null
            test -s $out/status.png
            cp ${site}/index.html $out/
          '';
    };
}
