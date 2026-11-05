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
#   packages.site-research  the homepage with the research papers beside it
#                           (papers/<strategy>.{pdf,html}, ../research/papers.nix),
#                           the bundle a worker serves
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
    "<div class=\"scroll\"><table><thead><tr>${
      lib.concatMapStrings (h: "<th>${esc h}</th>") head
    }</tr></thead><tbody>\n${lib.concatStrings rows}</tbody></table></div>";
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
          :root { --bg:#fbfaf8; --card:#ffffff; --fg:#1d1c1a; --muted:#6b6862; --line:#e4e1db; --accent:#2b5fa8; --gap:#b4441f; --ok:#2f6f4f; --ci-queued:#807060; --ci-inprogress:#3d6eb5; --ci-success:#3d733d; --ci-failure:#8c2d28; --ci-cancelled:#694b37; --ci-skip:#f0ebe3; }
          @media (prefers-color-scheme: dark) { :root { --bg:#151514; --card:#1e1e1c; --fg:#ecebe8; --muted:#a3a09a; --line:#34322f; --accent:#8db4ee; --gap:#ef8a64; --ok:#7fc4a0; --ci-queued:#4d4036; --ci-inprogress:#3264a0; --ci-success:#2d6630; --ci-failure:#6b1f1c; --ci-cancelled:#4d3425; --ci-skip:#20201e; } }
          * { box-sizing:border-box }
          html, body { overflow-x:hidden }
          body { background:var(--bg); color:var(--fg); font:15px/1.5 system-ui, sans-serif; margin:0; }
          a { color:var(--accent); text-decoration:none } a:hover { text-decoration:underline }
          .wrap { display:grid; grid-template-columns:200px minmax(0,1fr); gap:32px; max-width:1240px; margin:0 auto; padding:24px 16px; }
          nav { position:sticky; top:24px; align-self:start; font-size:14px }
          nav b { display:block; color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.06em; margin:16px 0 4px; overflow-wrap:anywhere; word-break:break-word }
          nav a { display:inline-flex; align-items:center; min-width:44px; min-height:44px; justify-content:center; padding:0 12px; color:var(--fg) }
          @media (max-width:800px) { .wrap { grid-template-columns:1fr } nav { position:static; display:flex; flex-wrap:wrap; gap:4px 14px; min-width:0 } nav b { width:100%; margin:8px 0 0; min-width:0 } nav a { justify-content:center } }
          h1 { font-size:24px; margin:0 0 4px } h2 { font-size:17px; margin:36px 0 10px; scroll-margin-top:16px }
          p.lede { color:var(--muted); margin:0 0 20px }
          .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(230px,1fr)); gap:12px }
          .card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px }
          .wide { grid-column:span 2 } @media (max-width:560px) { .wide { grid-column:auto } }
          a.card { display:block; color:var(--fg) } a.card:hover { border-color:var(--accent); text-decoration:none }
          .card h3 { font-size:15px; margin:0 0 2px } .card .sub { color:var(--muted); font-size:13px }
          .card dl { display:grid; grid-template-columns:auto 1fr; gap:2px 10px; margin:8px 0 0; font-size:13px }
          .card dt { color:var(--muted) } .card dd { margin:0; overflow-wrap:anywhere }
          .scroll { overflow-x:auto; max-width:100% }
          table { border-collapse:collapse; width:100%; font-size:13.5px }
          th, td { text-align:left; padding:6px 10px; border-bottom:1px solid var(--line); vertical-align:top }
          th { color:var(--muted); font-weight:600 }
          td, b, code { overflow-wrap:anywhere }
          td:has(+ td), th { white-space:nowrap }
          .gap { color:var(--gap) } .ok { color:var(--ok) }
          .chip { display:inline-block; font-size:11.5px; font-weight:600; padding:1px 7px; border-radius:4px; line-height:1.6; white-space:nowrap; min-width:44px; text-align:center }
          .chip-queued { background:var(--ci-queued); color:#fff }
          .chip-inprogress { background:var(--ci-inprogress); color:#fff }
          .chip-success { background:var(--ci-success); color:#fff }
          .chip-failure { background:var(--ci-failure); color:#fff }
          .chip-cancelled { background:var(--ci-cancelled); color:#fff }
          .chip-skip { background:var(--ci-skip); color:var(--fg) }
          .pipeline-table-wrap { overflow-x:auto }
          .pipeline-table-wrap td { vertical-align:middle }
          .pipeline-run { display:flex; align-items:center; gap:6px; flex-wrap:wrap }
          .pipeline-timeline { display:flex; gap:3px; flex-wrap:wrap }
          .tl-dot { display:inline-block; width:12px; height:12px; border-radius:50%; border:1px solid transparent; flex-shrink:0 }
          .tl-dot:hover { border-color:var(--accent); transform:scale(1.3) }
          @media (max-width:560px) { .pipeline-timeline { gap:4px } .tl-dot { width:20px; height:20px } }
          a.sha-link, a.inline-link { display:inline-flex; min-width:44px; min-height:44px; align-items:center; justify-content:center; box-sizing:border-box; padding:12px 6px; line-height:1.6 }
        </style></head><body><div class="wrap">
        <nav>
          <b>Start</b><a href="#apps">Apps</a><a href="#infra">Infrastructure</a><a href="#research">Research</a><a href="#world">World</a>
          <b>Teams</b><a href="#areas">Who owns what</a>
          <b>Money</b><a href="#cards">Cards</a><a href="#ai">AI keys</a><a href="#credit">Credit lines</a><a href="#tax">Tax</a><a href="#rules">Rules</a>
          <b>Records</b><a href="#entities">Entities</a><a href="#legal">Legal record</a><a href="#domains">Domains</a><a href="#accounts">Accounts</a><a href="#gaps">Gaps</a><a href="#steps">Your steps</a><a href="#migration">Migration</a><a href="#ci">CI</a><a href="#pipelines">Pipelines</a><a href="#catalogs">Catalogs</a>
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
                harness = "DeepSeek Harness: the agents' own workbench, which they extend";
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

        <h2 id="research">Research</h2>
        <p class="lede">One paper per trading strategy, rendered from the declarations and the team's prose (modules/research/papers.nix), stripped to what Lean proves public: the mathematics, the algorithm, the theorems, the backtest method and results.</p>
        ${table [ "Paper" "Strategy" "Stage" "Read" ] (
          lib.mapAttrsToList (
            s: p:
            "<tr>${td p.title}${td s}${
              td top.trading.strategies.${s}.stage
            }<td><a class=\"inline-link\" href=\"papers/${s}.html\">paper</a> · <a class=\"inline-link\" href=\"papers/${s}.pdf\">PDF</a></td></tr>\n"
          ) (lib.filterAttrs (_: p: p.public) top.research.papers)
        )}

        <h2 id="world">World</h2>
        <p class="lede">The digital twin: every module, agent, key and card as a 2D pixel world. Tap or click a thing to open its recipes (JEI-style).</p>
        <div style="width:100%;max-width:780px;height:70vh;min-height:320px;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:var(--card)">
          <iframe src="twin.html" style="width:100%;height:100%;border:none" title="Digital twin world" loading="lazy"></iframe>
        </div>
        <p style="font-size:13px;color:var(--muted);margin-top:6px">A static world — <a class="inline-link" href="twin.html" target="_blank">open full screen</a> to see live agents when <code>window.__twinState</code> is set and for the full phone-optimised view.</p>

        <h2 id="areas">Who owns what</h2>
        <p class="lede">Every area is a mailbox role: one owning team, reviewers that are never the owner, the controller who signs off, and the change classes it may propose. Lean proves the shape (modules/organization).</p>
        ${table [ "Address" "Owner" "Reviewers" "May propose" "Signs off" "Purpose" ] (
          lib.concatLists (
            lib.mapAttrsToList (
              entity: areas:
              lib.mapAttrsToList (
                mailbox: a:
                row [
                  "${mailbox}@${lib.head (lib.attrNames (lib.filterAttrs (_: d: d.entity == entity) domains))}"
                  (if a.owner == null then "the person" else a.owner)
                  (if a.reviewers == [ ] then "—" else lib.concatStringsSep ", " a.reviewers)
                  (if a.changeClasses == [ ] then "—" else lib.concatStringsSep ", " a.changeClasses)
                  a.controller
                  a.purpose
                ]
              ) areas
            ) top.organization.areas
          )
        )}

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

        <h2 id="legal">Legal record</h2>
        <p class="lede">What each entity is on paper (modules/legal): purpose, owners, where it is formed, its registered agent and the documents it holds. Private values (EIN, filing number, dates of formation) live in Proton Pass and are read only when a document is rendered; Lean proves each record complete for its standing.</p>
        <div class="grid">
        ${lib.concatStrings (
          lib.mapAttrsToList (
            e: r:
            let
              o = r.organization;
              dash = v: if v == null then "—" else v;
            in
            ''
              <div class="card wide"><h3>${esc r.legalName}</h3><div class="sub">${esc e}: ${esc r.kind}, ${esc r.status}</div><dl>
                            <dt>Purpose</dt><dd>${esc (dash r.purpose)}</dd>
                            <dt>Organization</dt><dd>${
                              if o == null then
                                "—"
                              else
                                esc "${o.management}: ${
                                  lib.concatMapStringsSep ", " (m: "${m.name} ${toString m.percent}%") o.members
                                }${
                                  lib.optionalString (o.managers != [ ])
                                    "; managers ${lib.concatMapStringsSep ", " (m: m.name) o.managers}"
                                }"
                            }</dd>
                            <dt>State</dt><dd>${
                              if r.formation.state != null then
                                esc r.formation.state
                              else if r.formation.item != null then
                                "in Proton Pass (${esc r.formation.item})"
                              else
                                "—"
                            }</dd>
                            <dt>EIN</dt><dd>${
                              if r.ein.item != null then "in Proton Pass (${esc r.ein.item})" else "—"
                            }</dd>
                            <dt>Registered agent</dt><dd>${
                              if r.registeredAgent == null then
                                "—"
                              else
                                esc "${r.registeredAgent.name} (${r.registeredAgent.account})"
                            }</dd>
                            <dt>Taxed as</dt><dd>${esc (dash r.taxClassification)}</dd>
                            <dt>Documents</dt><dd>${
                              if r.documents == [ ] then
                                "—"
                              else
                                lib.concatMapStringsSep "<br>" (
                                  d: esc "${d.title}${if d.issued == null then "" else ", ${d.issued}"}"
                                ) r.documents
                            }</dd></dl></div>''
          ) top.legal.public
        )}
        </div>

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

        <h2 id="rules">Rules we trade under</h2>
        <p class="lede">Every rule with its source and the day it was read; a typed constraint is decided by Lean against the observed accounts and the declared strategies (modules/compliance).</p>
        ${table
          [
            "Authority"
            "Citation"
            "Title"
            "Applies to"
            "Constraint"
            "Source"
            "Checked"
          ]
          (
            map (
              r:
              row [
                r.authority
                r.citation
                r.title
                r.applies
                r.constraint
                r.source
                (if r.checked == null then "not read" else r.checked)
              ]
            ) top.compliance.index.rows
          )
        }

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

        <h2 id="pipelines">Pipelines</h2>
        <p class="lede">Live CI/CD run status, fetched from GitHub Actions. Shows the latest run on <code>main</code> and on the current working branch, for each declared workflow, plus a timeline of the last 20 runs. Offline or when served from a build: no runs loaded.</p>
        <div id="pipelines-root">
          <p style="color:var(--muted);font-size:13px">Loading CI data…</p>
        </div>
        <script>
        (function(){
          var DECLARED = ${builtins.toJSON (lib.attrNames top.ci.workflows)};
          var BRANCH_HINT = "main";
          var FAIL_MSG = "no runs loaded";

          function chip(status, conclusion) {
            var cls = "pending";
            var label = status;
            if (status === "completed") {
              if (conclusion === "success") { cls = "success"; label = "passed"; }
              else if (conclusion === "failure") { cls = "failure"; label = "failed"; }
              else if (conclusion === "cancelled") { cls = "cancelled"; label = "cancelled"; }
              else if (conclusion === "skipped") { cls = "skip"; label = "skipped"; }
              else if (conclusion === "neutral") { cls = "skip"; label = "neutral"; }
              else { cls = "failure"; label = conclusion || "errored"; }
            } else if (status === "in_progress") { cls = "inprogress"; label = "running"; }
            else if (status === "queued" || status === "waiting") { cls = "queued"; label = "queued"; }
            return "<span class=\"chip chip-" + cls + "\">" + label + "</span>";
          }

          function relTime(iso) {
            if (!iso) return "—";
            var diff = Date.now() - new Date(iso).getTime();
            var sec = Math.floor(diff / 1000);
            if (sec < 60) return "just now";
            var min = Math.floor(sec / 60);
            if (min < 60) return min + "m ago";
            var hr = Math.floor(min / 60);
            if (hr < 24) return hr + "h ago";
            var d = Math.floor(hr / 24);
            if (d < 30) return d + "d ago";
            return new Date(iso).toLocaleDateString();
          }

          function duration(started, updated) {
            if (!started || !updated) return "—";
            var ms = new Date(updated).getTime() - new Date(started).getTime();
            if (ms < 0) return "—";
            var sec = Math.floor(ms / 1000);
            if (sec < 60) return sec + "s";
            var min = Math.floor(sec / 60);
            sec = sec % 60;
            if (min < 60) return min + "m " + sec + "s";
            var hr = Math.floor(min / 60);
            min = min % 60;
            return hr + "h " + min + "m";
          }

          function timelineColor(run) {
            if (run.status === "in_progress") return "var(--ci-inprogress)";
            if (run.status === "queued" || run.status === "waiting") return "var(--ci-queued)";
            if (run.conclusion === "success") return "var(--ci-success)";
            if (run.conclusion === "failure") return "var(--ci-failure)";
            if (run.conclusion === "cancelled") return "var(--ci-cancelled)";
            return "var(--ci-skip)";
          }

          function render(data) {
            var root = document.getElementById("pipelines-root");
            if (!data || !data.runs || data.runs.length === 0) {
              root.innerHTML = "<p style=\"color:var(--muted);font-size:13px\">" + FAIL_MSG + "</p>";
              return;
            }
            var runs = data.runs;
            var byWorkflow = {};
            runs.forEach(function(r){
              var wf = r.workflow || "unknown";
              if (!byWorkflow[wf]) byWorkflow[wf] = [];
              byWorkflow[wf].push(r);
            });
            var byName = {};
            runs.forEach(function(r){
              var n = r.name || r.workflow || "unknown";
              if (!byName[n]) byName[n] = [];
              byName[n].push(r);
            });

            // For each declared workflow find main's latest and branch's latest
            var html = "<div class=\"pipeline-table-wrap\"><table><thead><tr><th>Workflow</th><th>main</th><th>branch</th><th>Timeline</th></tr></thead><tbody>";

            var allDisplay = [];
            DECLARED.forEach(function(wfName){
              var runsFor = byName[wfName] || byWorkflow[wfName] || [];
              allDisplay.push({ name: wfName, runs: runsFor, declared: true });
            });
            // Undeclared workflows from the API
            var seenDeclared = {};
            DECLARED.forEach(function(d){ seenDeclared[d] = true; });
            runs.forEach(function(r){
              var n = r.name || r.workflow || "unknown";
              if (!seenDeclared[n]) {
                seenDeclared[n] = true;
                allDisplay.push({ name: n, runs: byName[n] || byWorkflow[n] || [], declared: false });
              }
            });

            allDisplay.forEach(function(item){
              var runsFor = item.runs;
              // sort descending by number
              runsFor.sort(function(a,b){ return b.number - a.number; });
              var latest = runsFor[0] || null;
              var main = null;
              var branch = null;
              runsFor.forEach(function(r){
                if (r.branch === BRANCH_HINT && !main) main = r;
                if (r.branch !== BRANCH_HINT && !branch) branch = r;
              });
              // timeline: up to 20 most recent runs for this workflow
              var timeline = runsFor.slice(0, 20);

              var nameDisplay = item.name;
              if (!item.declared) nameDisplay += " <span style=\"color:var(--muted);font-size:13px\">(other)</span>";

              function runCell(run) {
                if (!run) return "<td>—</td>";
                var ch = chip(run.status, run.conclusion);
                var dur = duration(run.started, run.updated);
                var rel = relTime(run.updated);
                var shaLink = "<a class=\"sha-link\" href=\"" + run.url + "\">" + run.sha + "</a>";
                return "<td><div class=\"pipeline-run\">" + ch + " <span style=\"color:var(--muted);font-size:13px\">" + shaLink + " " + rel + " · " + dur + "</span></div></td>";
              }

              var timelineHtml = "<div class=\"pipeline-timeline\">";
              timeline.forEach(function(r){
                timelineHtml += "<a href=\"" + r.url + "\" class=\"tl-dot\" style=\"background:" + timelineColor(r) + "\" title=\"" + (r.name || r.workflow) + " #" + r.number + " (" + (r.conclusion || r.status) + ")\"></a>";
              });
              timelineHtml += "</div>";

              html += "<tr><td>" + nameDisplay + "</td>" + runCell(main) + runCell(branch) + "<td>" + timelineHtml + "</td></tr>";
            });

            html += "</tbody></table></div>";
            html += "<p style=\"color:var(--muted);font-size:13px;margin-top:4px\">Fetched " + relTime(data.fetched) + " · " + runs.length + " runs</p>";
            root.innerHTML = html;
          }

          fetch("/api/ci").then(function(r){
            if (!r.ok) throw new Error("HTTP " + r.status);
            return r.json();
          }).then(render).catch(function(){
            render(null);
          });
        })();
        </script>

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
      site =
        pkgs.runCommand "site-status"
          {
            twinWorld = config.packages.twin-world;
          }
          ''
            mkdir $out
            cp ${html} $out/index.html
            cp $twinWorld/twin.html $out/
          '';
      # The homepage with the public papers beside it, where its links point.
      research = pkgs.runCommand "site-research" { } ''
        mkdir -p $out/papers
        cp ${site}/index.html $out/
        for s in $(${lib.getExe pkgs.jq} -r '.[]' ${config.packages.research-papers}/papers/public.json); do
          cp ${config.packages.research-papers}/papers/$s.html ${config.packages.research-papers}/papers/$s.pdf $out/papers/
        done
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
        packages.site-research = research;
        checks.site-status = import ./_check.nix {
          inherit pkgs;
          htmlPath = "${site}/index.html";
          name = "site-status-screenshot";
        };
      };
    };
}
