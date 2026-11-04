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
# Served at status.mirazo.org by a Worker behind Cloudflare Access, only to
# the owner (../cloudflare/_status.nix; the owner's go, 2026-11-01).
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
    else if p.fromBalance != null then
      "from its own balance: ${p.fromBalance}"
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
      htmlText = ''
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Kagamizo home</title>
        <style>
          :root { --bg:#fbfaf8; --card:#ffffff; --fg:#1d1c1a; --muted:#6b6862; --line:#e4e1db; --accent:#2b5fa8; --gap:#b4441f; --ok:#2f6f4f; }
          @media (prefers-color-scheme: dark) { :root { --bg:#151514; --card:#1e1e1c; --fg:#ecebe8; --muted:#a3a09a; --line:#34322f; --accent:#8db4ee; --gap:#ef8a64; --ok:#7fc4a0; } }
          * { box-sizing:border-box }
          body { background:var(--bg); color:var(--fg); font:15px/1.5 system-ui, sans-serif; margin:0; }
          a { color:var(--accent); text-decoration:none } a:hover { text-decoration:underline }
          .wrap { display:grid; grid-template-columns:200px minmax(0,1fr); gap:32px; max-width:1240px; margin:0 auto; padding:24px 16px; }
          nav { position:sticky; top:24px; align-self:start; font-size:14px }
          nav b { display:block; color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.06em; margin:16px 0 4px }
          nav a { display:block; padding:3px 0; color:var(--fg) }
          @media (max-width:800px) { .wrap { grid-template-columns:1fr } nav { position:static; display:flex; flex-wrap:wrap; gap:4px 14px } nav b { width:100%; margin:8px 0 0 } }
          h1 { font-size:24px; margin:0 0 4px } h2 { font-size:17px; margin:36px 0 10px; scroll-margin-top:16px }
          p.lede { color:var(--muted); margin:0 0 20px }
          .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(230px,1fr)); gap:12px }
          .card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px }
          .wide { grid-column:span 2 } @media (max-width:560px) { .wide { grid-column:auto } }
          a.card { display:block; color:var(--fg) } a.card:hover { border-color:var(--accent); text-decoration:none }
          .card h3 { font-size:15px; margin:0 0 2px } .card .sub { color:var(--muted); font-size:13px }
          .card dl { display:grid; grid-template-columns:auto 1fr; gap:2px 10px; margin:8px 0 0; font-size:13px }
          .card dt { color:var(--muted) } .card dd { margin:0; overflow-wrap:anywhere }
          table { border-collapse:collapse; width:100%; font-size:13.5px; display:block; overflow-x:auto }
          th, td { text-align:left; padding:6px 10px; border-bottom:1px solid var(--line); vertical-align:top }
          th { color:var(--muted); font-weight:600 }
          td:has(+ td), th { white-space:nowrap }
          .gap { color:var(--gap) } .ok { color:var(--ok) }
        </style></head><body><div class="wrap">
        <nav>
          <b>Start</b><a href="#apps">Apps</a><a href="#infra">Infrastructure</a>
          <b>Money</b><a href="#cards">Cards</a><a href="#ai">AI keys</a><a href="#credit">Credit lines</a><a href="#tax">Tax</a>
          <b>Records</b><a href="#entities">Entities</a><a href="#domains">Domains</a><a href="#accounts">Accounts</a><a href="#gaps">Gaps</a><a href="#steps">Your steps</a><a href="#migration">Migration</a><a href="#ci">CI</a><a href="#catalogs">Catalogs</a>
        </nav>
        <main>
        <h1>Kagamizo</h1>
        <p class="lede">Everything the repository declares, in one place. Generated by modules/site from the declarations; nothing here is written by hand, so what it shows is what the code states.</p>

        <h2 id="apps">Apps</h2>
        <div class="grid">
        ${lib.concatMapStrings (
          s:
          let
            h = "${s.name}.${top.hetzner.host.agents.zone}";
            what =
              {
                agents = "Open WebUI: chat with the open-weight models";
                code = "OpenCode: the coding agent, in the browser";
                chat = "Element: talk to the agent teams (Matrix, one room each)";
              }
              .${s.name};
          in
          ''<a class="card" href="https://${h}/"><h3>${esc h}</h3><div class="sub">${esc what}</div><dl><dt>Runs on</dt><dd>${esc top.hetzner.host.name}, port ${toString s.port}</dd><dt>Reached by</dt><dd>Cloudflare Tunnel, behind Access</dd></dl></a>''
        ) top.hetzner.host.agents.services}
        </div>

        <h2 id="infra">Infrastructure</h2>
        <div class="grid">
          <div class="card"><h3>${esc top.hetzner.host.name}</h3><div class="sub">Hetzner Cloud, NixOS from this repository</div><dl>
            <dt>Type</dt><dd>${esc top.hetzner.host.serverType} in ${esc top.hetzner.host.location}</dd>
            <dt>Budget</dt><dd>''$${toString top.hetzner.monthlyBudgetUsd} a month</dd>
            <dt>Follows</dt><dd>${esc top.hetzner.host.flake}</dd>
            <dt>Upgrades</dt><dd>${esc top.hetzner.host.upgradeAt} UTC</dd>
            <dt>Access</dt><dd>no SSH, no open port</dd></dl></div>
          <div class="card"><h3>Cloudflare</h3><div class="sub">DNS, Access, Tunnel, Workers, R2 (OpenTofu)</div><dl>
            <dt>Zones</dt><dd>${esc (lib.concatStringsSep ", " (lib.attrNames domains))}</dd>
            <dt>Access team</dt><dd>kagamizo.cloudflareaccess.com</dd>
            <dt>Sign-in</dt><dd>one-time code mailed to ${esc (lib.concatStringsSep ", " top.hetzner.host.agents.viewers)}</dd>
            <dt>Build cache</dt><dd>${esc top.cache.host} (R2 ${esc top.cache.bucket})</dd></dl></div>
          <div class="card wide"><h3>Proton</h3><div class="sub">Mail, Drive, Pass: the work suite and the only secret store</div><dl>
            <dt>Vaults</dt><dd>${
              esc (
                lib.concatStringsSep ", " (lib.unique (lib.attrValues top.proton.infraVaults ++ top.proton.vaults))
              )
            }</dd>
            <dt>OpenTofu state</dt><dd>${esc top.proton.infraVaults.state} (statestore)</dd></dl></div>
          <div class="card"><h3>The stack</h3><div class="sub">How every module is built</div><dl>
            <dt>Nix</dt><dd>declares, pins, packages, checks</dd>
            <dt>Lean</dt><dd>states the rules and proves them</dd>
            <dt>Rust</dt><dd>implements against them</dd>
            <dt>Cedar</dt><dd>authorizes every account action</dd>
            <dt>OpenTofu</dt><dd>applies Cloudflare and Hetzner</dd></dl></div>
        </div>

        <h2 id="cards">Mercury cards</h2>
        ${table [ "Card" "Limit" "Pays" "On" "Locked to" "Booked" ] (
          lib.mapAttrsToList (
            n: c:
            row [
              (if c.nickname == null then "kagamizo/${n}" else c.nickname)
              "\$${toString c.limitUsd} ${c.interval}"
              c.why
              c.account
              (if c.merchantLock == null then "—" else c.merchantLock)
              (if c.between == null then "—" else "${c.between.as} for ${c.between.for}")
            ]
          ) top.mercury.cards
        )}

        <h2 id="ai">OpenRouter keys</h2>
        ${table [ "Key" "Cap" "Profile" "For" ] (
          lib.mapAttrsToList (
            n: k:
            row [
              n
              "\$${toString k.limitUsd} ${k.reset}"
              k.profile
              k.why
            ]
          ) top.openrouter.keys
        )}
        <p class="lede">Models: ${esc (lib.concatStringsSep ", " top.openrouter.models)}</p>

        <h2 id="steps">Your steps (the only things done by hand)</h2>
        ${table [ "Step" "Why it is yours" ] (
          lib.mapAttrsToList (
            n: why:
            row [
              n
              why
            ]
          ) top.operations.humanSteps
        )}

        <h2 id="entities">Entities</h2>
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

        <h2 id="domains">Domains</h2>
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

        <h2 id="accounts">Accounts</h2>
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

        <h2 id="gaps" class="${
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

        <h2 id="tax">Tax obligations, ${toString year}</h2>
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

        <h2 id="credit">Credit lines</h2>
        ${table
          [
            "Line"
            "Issuer"
            "Limit"
            "Annual fee"
            "Opened"
            "Paid from"
            "Fate"
          ]
          (
            lib.mapAttrsToList (
              _: l:
              row [
                l.product
                l.account
                (if l.limitUsd == null then "not read" else "\$${toString l.limitUsd}")
                (if l.annualFeeUsd == null then "not read" else "\$${toString l.annualFeeUsd}")
                (if l.opened == null then "not read" else l.opened)
                (if l.autopayFrom == null then "not read" else l.autopayFrom)
                l.fate
              ]
            ) top.money.creditLinesChecked
          )
        }

        <h2 id="migration">Migration</h2>
        ${table [ "Account" "Class" "Into" "State" "How" ] (
          lib.concatLists (
            lib.mapAttrsToList (
              n: src:
              lib.mapAttrsToList (
                c: x:
                row [
                  (n + lib.optionalString (src.product != null) " (${src.product})")
                  c
                  x.destination
                  x.state
                  x.export
                ]
              ) src.classes
            ) top.migration.sources
          )
        )}
        ${table [ "Account" "Depends on it" "Moves to" "Done" ] (
          lib.concatLists (
            lib.mapAttrsToList (
              n: src:
              map (
                d:
                row [
                  n
                  "${d.kind}: ${d.what}"
                  d.movedTo
                  (if d.done then "yes" else "no")
                ]
              ) src.dependants
            ) top.migration.sources
          )
        )}

        <h2 id="ci">CI</h2>
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

        <h2 id="catalogs">Pinned catalogs</h2>
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
        </main></div></body></html>
      '';
      html = pkgs.writeText "index.html" htmlText;
      site = pkgs.runCommand "site-status" { } ''
        mkdir $out
        cp ${html} $out/index.html
      '';
    in
    {
      options.site.statusHtml = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        description = "The status page, for the deployments that serve it (../cloudflare/_status.nix).";
      };
      config = {
        site.statusHtml = htmlText;
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
    };
}
