/-
The kit module's paper: a solo researcher's devices, carried in their
clothes. Checked by checks.paper-kit (modules/repo/papers.nix).
-/
open Kagamizo.Paper

def paper : Paper := {
  module := "kit",
  title := "A researcher's whole stack in their pockets: the carried kit as a typed loadout, proved to fit, to cover and to last",
  abstract := "The kit module declares the devices the owner carries in the pockets and sleeves of their clothes, each with its slot, mass, volume, power draw, battery and the capabilities it provides, and the capabilities a field day needs. Lean decides, before anything is bought or built, that every slot holds what is in it, that today's owned devices and the proposed additions each cover their requirement, that everything lasts the day on its battery or the shared bank, and that every device that runs software is a target of the Kagamizo shell.",
  authors := ["twin", "upkeep"],
  date := "2026-11-07",
  sections := [
    { kind := .purpose,
      body := "The owner's goal is to be fully mobile as a solo researcher: all of their technology in the pockets and sleeves of their clothes, so the workstation, the lab and the network travel with them. Without a declaration, a kit is a pile of gadgets chosen one at a time, and nobody can say whether it covers what the work needs, whether it fits where it must be carried, or whether it lasts a day away from a socket. This module makes the kit a typed loadout: what is carried, where, and what it gives, with a proof that the loadout meets its requirement. It also keeps purchases honest: an addition is a proposal stated as a specification, and buying one is the owner's decision.",
      cites := ["starner-challenges", "starner-wearable"] },
    { kind := .lifecycle,
      body := "Declared: kit.slots (the clothing's places and what each holds), kit.items (owned devices from their makers' specifications, and proposals as specifications a product must meet), and kit.required.now and .target (the capabilities and hours). Checked: checks.kit on every push. Changed: when the owner buys a proposal, its entry becomes owned with the product's own figures, in a commit of kind code reviewed by twin and upkeep, and the proof must still hold; a new need is a new capability in the closed list. Retired: a device that leaves the kit is deleted, and if a requirement loses its only provider the build fails until something replaces it. Every item that runs software is also a target in modules/shell, so the same shell runs on it.",
      cites := ["dolstra-thesis"] },
    { kind := .pipeline,
      body := "checks.kit renders the slots, the items, the shell's targets and both requirements as Lean facts and decides kit_sound by the kernel. The check runs in CI with every other flake check and in a session before a commit. Nothing in the module deploys: it is a specification that gates the targets it names, and the images those targets are (the Raspberry Pi 5's SD image, the phone's browser installing the web target) are built and checked by their own modules. A failing proof names nothing yet beyond the false proposition; the paper's gaps say how that improves.",
      cites := ["lean4"] },
    { kind := .agents,
      body := "twin owns the kit: the loadout is the physical side of the owner's digital twin, and the twin team proposes changes as specifications with the capability each adds and the slot it takes. upkeep keeps the device targets building: the Pi's image and the shell's web target that the phone installs. review reads every change. No agent buys anything: a proposal's price is quoted for the owner, who decides, and Cedar's base layer forbids agents any spend. The security and reverse-engineering teams are the main users of the radios and the monitor-mode adapter, on the owner's own devices only.",
      cites := ["starner-wearable"] },
    { kind := .tools,
      body := "The module exposes no program of its own: its tool is the check, which turns a shopping question (does this keyboard fit the inner pocket, does the bank last eight hours with the glasses on) into a build that passes or fails. The devices it declares are the tools: the Pixel 9a is the screen, touch, cellular link, camera and GPS; the Raspberry Pi 5 is the machine that serves the shell, a small local model and the research tools to the phone over its tether; the proposals add a power bank, display glasses, a keyboard with a touchpad, a gamepad, a software-defined radio, an NFC and sub-GHz research tool and a Wi-Fi adapter with monitor mode.",
      cites := ["starner-challenges"] },
    { kind := .data,
      body := "The data is the declaration: per item its slot, mass in grams, volume in millilitres, average draw in milliwatts, battery in milliwatt-hours, whether it runs on the shared bank, the capabilities it provides, whether it is owned, whether it runs software, and the source of its figures (the maker's specification for owned devices, the reason for each limit for proposals). The Pixel's figures come from Google's specification (154.7 by 73.3 by 8.9 mm, 186 g, 5100 mAh); the Pi's from Raspberry Pi's product brief, with a field budget of 5 W. Nothing personal is stored, and the repository is public, so the kit's contents are public too; the owner's whereabouts never enter it.",
      cites := ["starner-challenges"] },
    { kind := .design,
      body := "Lean holds the rules (_lean/Kit.lean): fits sums mass and volume per slot; covers asks that every required capability has a provider; lasts gives each item on its own battery the hours it needs and the banked items together the bank's energy; targeted asks that every item that runs software is a shell target; runnable keeps only what can run today, so an owned device on the bank counts only once a bank is carried. sound asks that names are unique, that today's runnable owned items meet the now requirement, and that owned and proposed items together meet the target. Units are natural numbers (grams, millilitres, milliwatts, milliwatt-hours) so the kernel decides it exactly. Proposals are worst cases, so a proof with proposals holds for any product that meets them. Nix types the options with closed enums for slots and capabilities.",
      cites := ["lean4", "dolstra-thesis"] },
    { kind := .guarantees,
      body := "checks.kit decides kit_sound for the declared kit: every slot holds what is in it, both requirements are covered, everything lasts the required hours, and every item that runs software is a target of the shell. The general theorem covers_append proves that adding items never loses a covered capability, so a proposal can only add to what the kit provides. The theorem uncovered proves that a capability no item provides makes its requirement fail, so a missing capability cannot be hidden by any other item. Together they make the loadout's coverage monotone and its gaps visible: the target holds only because the bank, the radios and the keyboard are in it as proposals, and today's requirement holds on the phone alone.",
      cites := ["lean4"] },
    { kind := .performance,
      body := "No perf target is declared for this module. The measured quantity is the kit itself: today the phone alone is runnable and lasts its eight hours at a 1.2 W average (9.6 of its 19.6 Wh); with the proposals, the banked draw is 9.5 W (the Pi, the glasses, the radio and the adapter), 76 Wh over eight hours against a 99 Wh bank, and the carried mass is about 1.6 kg across eight places. What moves it: the Pi's field budget dominates the bank, so a lower-power board or a sleep schedule extends the day, and the bank's specification is held at the cabin limit. A perf target for the field endurance is a gap.",
      cites := ["starner-challenges"] },
    { kind := .priorWork,
      body := "Wearable computing as a research practice goes back to Starner's and the MIT wearables group's argument that a computer carried on the body changes what a researcher can do in the field, Mann set out the wearable computer as a personal system worn continuously, and Starner surveyed its challenges (power and heat, networking, input and display) that this module turns into typed constraints. The kit departs from that work by proving the loadout rather than describing it: the requirement, the fit and the power budget are a declaration that Lean decides, as in Dolstra's purely functional deployment, where a system is a value built from its declaration and checked before it exists.",
      cites := ["starner-wearable", "mann-wearable", "starner-challenges", "dolstra-thesis", "lean4"] },
    { kind := .gaps,
      body := "The figures for owned devices are from their makers' specifications, not weighed or measured on the owner's own units, and draw figures are budgets, not measurements; measuring them on the devices is the next step. The Pi cannot run away from a socket until a power bank is owned. A failing proof does not yet name what failed, as the papers check does; a problems list is planned. Thermal limits (a Pi in a pocket), radio regulations for transmitting tools, and the interfaces between items (which port each uses) are not typed yet. The proposals carry no prices until the owner asks for them, and no item may be bought by an agent.",
      cites := ["starner-challenges"] }
  ],
  citations := [
    { key := "starner-wearable", title := "Wearable computing and contextual awareness", authors := ["Thad Starner"], year := 1999,
      source := .url "https://dspace.mit.edu/handle/1721.1/9543" },
    { key := "starner-challenges", title := "The challenges of wearable computing: Part 1", authors := ["Thad Starner"], year := 2001,
      source := .doi "10.1109/40.946681" },
    { key := "mann-wearable", title := "Wearable computing: a first step toward personal imaging", authors := ["Steve Mann"], year := 1997,
      source := .doi "10.1109/2.566147" },
    { key := "dolstra-thesis", title := "The Purely Functional Software Deployment Model", authors := ["Eelco Dolstra"], year := 2006,
      source := .url "https://edolstra.github.io/pubs/phd-thesis.pdf" },
    { key := "lean4", title := "The Lean 4 Theorem Prover and Programming Language", authors := ["Leonardo de Moura", "Sebastian Ullrich"], year := 2021,
      source := .doi "10.1007/978-3-030-79876-5_37" }
  ],
  theorems := ["covers_append", "uncovered"],
  perf := [],
  checks := ["kit", "paper-kit"],
  packages := [],
  agents := ["twin", "upkeep", "review", "security", "reverse-engineering"]
}
