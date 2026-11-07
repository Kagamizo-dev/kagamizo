/-
The security module's paper: penetration testing of our own surfaces only.
Checked by checks.paper-security (modules/repo/papers.nix).
-/
open Kagamizo.Paper

def paper : Paper := {
  module := "security",
  title := "Penetration testing of our own surfaces only: a typed scope, a probe effect in Cedar, and scanners carried in a pocket",
  abstract := "The security module declares everything of ours that can be tested (the server, every hostname behind Access, the status page, the repository, the device images and the phone) and lets it be tested only through the account that hosts it, by a penetration-tester agent serving that account's entity, with a new governance effect, probe. Cedar refuses any other probe exactly as it refuses any other read; Lean proves every hostname in scope lies under its owner's own domain and every probe grant has an asset to test. The scanners are pinned and carried on the Yoga and the Pi.",
  authors := ["security"],
  date := "2026-11-07",
  sections := [
    { kind := .purpose,
      body := "The owner wants penetration testing as one of the kit's capabilities, and the security team's charter is to find weaknesses before anyone else does. Testing is the one activity whose whole risk is its target: the same scan is a defence on our own server and an attack on anyone else's. The business takes no client work, so the only legitimate targets are our own, and this module makes that a property of the build rather than a promise: an asset outside the scope cannot be declared, a probe outside it is refused by the same authorization layer that guards every other action, and the scanners are pinned so what runs is what was reviewed.",
      cites := ["nist-800-115"] },
    { kind := .lifecycle,
      body := "Declared: security.scope lists the assets, the hostnames of jingzo-host's services derived from hetzner.host.agents so a new service is in scope the moment it exists; security.tools lists the scanners and the images that carry them. Built: the testers (security-jingzo and security-mirazo, one per entity whose accounts host online assets) are generated with probe grants on exactly those accounts; the probes are typed actions (hetzner probe-host, cloudflare probe-hostname). Run: by hand from the kit or the Yoga today; scheduled runs on jingzo-host that write typed findings are the security team's backlog. Changed: a change of kind code, reviewed by review and upkeep, with the owner's sign-off for security checks. Retired: an asset removed from the scope loses its grant in the same evaluation.",
      cites := ["nist-800-115"] },
    { kind := .pipeline,
      body := "checks.security-scope decides scope_sound in Lean over the scope, the domains and their entities, the accounts and their owners, and every probe grant. governance-cedar compiles the testers and the probe actions into the Cedar policy and runs its generated tests, which now include a probe case for every agent on every account: a tester may probe its own entity's account, no other agent may, and nobody probes another entity's account. lean-governance types the effect. The images that carry the scanners (the Yoga's live USB and the Pi's SD image) build them from nixpkgs at the pinned revision, and checks.shell confirms ZAP's command is on the Yoga's PATH.",
      cites := ["cedar"] },
    { kind := .agents,
      body := "security owns the module: its penetration tester persona runs as the two tester agents, security-jingzo for the server's account and security-mirazo for the Cloudflare account that carries the hostnames, each serving only that entity, as Cedar requires. They run scanners, not models, so they take no share of any key. governance.problems refuses a probe grant to any agent that is not a penetration tester. review and upkeep review every change to the scope or the tools, and the owner signs off security checks through the security-check lifecycle. No agent spends, destroys or signs in; probe adds testing, nothing else.",
      cites := ["cedar"] },
    { kind := .tools,
      body := "The scanners, pinned from nixpkgs: nmap for which ports and services an asset exposes; nuclei for known weaknesses of web services from a pinned template set; testssl.sh for every hostname's TLS; trivy for known vulnerabilities in an image's packages and the repository's dependencies; gitleaks for secrets in the repository's history; and OWASP ZAP, with a screen, on the Yoga. All but ZAP are also on the Raspberry Pi, so the kit carries them. The two probe actions are the only ways to point them at an online asset under governance: probe-host for the server, probe-hostname for a hostname behind Access with the tester's service token.",
      cites := ["nist-800-115"] },
    { kind := .data,
      body := "The scope is public declaration: the server's name, the hostnames (which are public DNS names), the repository's name and the names of images and devices; no address, credential or finding is stored in the repository. Findings, once the scheduled runner exists, are typed records (severity, asset, rule, evidence) written on the host and raised as security-labelled issues without secrets in them. The scanners' own data (nuclei's templates, trivy's vulnerability database) is fetched by the scanner at run time; pinning those datasets by hash is a gap.",
      cites := ["nist-800-115"] },
    { kind := .design,
      body := "The design reuses the authorization the repository already has instead of building a second one. Cedar's resources are accounts and an agent acts only on accounts of the entity it serves; an online asset is hosted by an account, so testing it is an action on that account with a new effect, probe, granted only to penetration testers. The scope's Lean file adds what Cedar cannot see: assetOk asks that an online asset names an account we hold, that a hostname lies under a domain of the entity that owns it (underDomain over identity's domains), and that a probed asset has a probe grant on its account; sound also asks the converse, that every probe grant has a probed asset on its account, so no grant reaches further than the scope.",
      cites := ["cedar", "lean4"] },
    { kind := .guarantees,
      body := "checks.security-scope decides scope_sound for the declared scope. The theorem hostname_is_ours proves that any hostname that passes assetOk lies under a domain of its own entity, so a third party's hostname can never pass, whatever is declared later. Cedar's generated tests prove, for every agent and every account, that probe is allowed only by a grant on the agent's own entity's account, and lean-governance's allowed_grant_never_spends still holds with probe among the effects an agent may hold: probing never brings spending, destroying or signing in with it.",
      cites := ["cedar", "lean4"] },
    { kind := .performance,
      body := "No perf target is declared for this module yet. What matters is coverage and time to finding: today the scope covers the server, five hostnames behind Access (one per service of jingzo-host), the status page, the repository, both images and the phone, and the scanners run by hand. The scheduled runner will set the cadence (a daily light pass of nmap, testssl and nuclei; a weekly ZAP baseline) and record each run's duration and findings, so a perf target can hold the time from a weakness appearing to its issue being opened.",
      cites := ["nist-800-115"] },
    { kind := .priorWork,
      body := "NIST SP 800-115 lays out security testing as planning, discovery, attack and reporting under rules of engagement agreed before anything runs; this module turns the rules of engagement into a typed scope that the build enforces. Cedar, designed with its semantics modelled and proved in Lean, gives authorization that is analysable rather than ad hoc, which is why the probe effect lives in the same policy as every other action. Lean 4 decides the scope's soundness by the kernel, as the rest of the repository's rules are decided.",
      cites := ["nist-800-115", "cedar", "lean4"] },
    { kind := .gaps,
      body := "The scheduled runner is not built: a Rust tool that, for each probed asset, asks governance-authorize, runs the pinned scanners with fixed arguments and writes typed findings, a timer on jingzo-host, and findings raised as issues; it is the security team's pipeline backlog item. The scanners' datasets (nuclei templates, trivy's database) are fetched at run time, not pinned. Radio testing of the phone and the kit (the SDR, NFC and Wi-Fi proposals in modules/kit) waits on that hardware. The testers' Access service tokens for probing hostnames are not yet minted.",
      cites := ["nist-800-115"] }
  ],
  citations := [
    { key := "nist-800-115", title := "Technical Guide to Information Security Testing and Assessment (NIST SP 800-115)", authors := ["Karen Scarfone", "Murugiah Souppaya", "Amanda Cody", "Angela Orebaugh"], year := 2008,
      source := .doi "10.6028/NIST.SP.800-115" },
    { key := "cedar", title := "Cedar: A New Language for Expressive, Fast, Safe, and Analyzable Authorization", authors := ["Joseph W. Cutler", "Craig Disselkoen", "Aaron Eline", "Shaobo He", "Kyle Headley", "Michael Hicks", "Kesha Hietala", "Eleftherios Ioannidis", "John Kastner", "Anwar Mamat", "Darin McAdams", "Matt McCutchen", "Neha Rungta", "Emina Torlak", "Andrew Wells"], year := 2024,
      source := .arxiv "2403.04651" },
    { key := "lean4", title := "The Lean 4 Theorem Prover and Programming Language", authors := ["Leonardo de Moura", "Sebastian Ullrich"], year := 2021,
      source := .doi "10.1007/978-3-030-79876-5_37" }
  ],
  theorems := ["hostname_is_ours"],
  perf := [],
  checks := ["security-scope", "paper-security", "governance-cedar", "lean-governance", "shell"],
  packages := [],
  agents := ["security", "review", "upkeep"]
}
