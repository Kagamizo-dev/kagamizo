// Shared by every legal document: the record arrives as one JSON file named
// by `--input data=...` (modules/legal/documents.nix writes it at render
// time, private values included, into a directory that is removed after).
// Nothing here is read from the Nix store but the templates themselves.

#let data = json(sys.inputs.data)

#let accent = rgb("#2b5fa8")
#let warn = rgb("#b4441f")
#let muted = rgb("#6b6862")

#let unset = text(fill: warn)[not in Proton Pass yet]
#let na = text(fill: muted)[—]

// A value, or the marker for one the owner has not pasted yet.
#let val(v, missing: unset) = if v == none or v == "" { missing } else { v }

#let states = (
  "US-AL": "Alabama", "US-AK": "Alaska", "US-AZ": "Arizona", "US-AR": "Arkansas",
  "US-CA": "California", "US-CO": "Colorado", "US-CT": "Connecticut", "US-DE": "Delaware",
  "US-DC": "District of Columbia", "US-FL": "Florida", "US-GA": "Georgia", "US-HI": "Hawaii",
  "US-ID": "Idaho", "US-IL": "Illinois", "US-IN": "Indiana", "US-IA": "Iowa",
  "US-KS": "Kansas", "US-KY": "Kentucky", "US-LA": "Louisiana", "US-ME": "Maine",
  "US-MD": "Maryland", "US-MA": "Massachusetts", "US-MI": "Michigan", "US-MN": "Minnesota",
  "US-MS": "Mississippi", "US-MO": "Missouri", "US-MT": "Montana", "US-NE": "Nebraska",
  "US-NV": "Nevada", "US-NH": "New Hampshire", "US-NJ": "New Jersey", "US-NM": "New Mexico",
  "US-NY": "New York", "US-NC": "North Carolina", "US-ND": "North Dakota", "US-OH": "Ohio",
  "US-OK": "Oklahoma", "US-OR": "Oregon", "US-PA": "Pennsylvania", "US-RI": "Rhode Island",
  "US-SC": "South Carolina", "US-SD": "South Dakota", "US-TN": "Tennessee", "US-TX": "Texas",
  "US-UT": "Utah", "US-VT": "Vermont", "US-VA": "Virginia", "US-WA": "Washington",
  "US-WV": "West Virginia", "US-WI": "Wisconsin", "US-WY": "Wyoming",
)

#let state-name(code) = if code == none { unset } else { states.at(code, default: code) }

#let kind-name(kind) = (
  person: "a natural person",
  llc: "a limited liability company",
  nonprofit: "a nonprofit corporation",
).at(kind, default: kind)

#let management-name(m) = if m == "member-managed" { "member-managed" } else { "manager-managed" }

#let document-kind(k) = (
  formation: "Formation",
  "operating-agreement": "Operating agreement",
  "ein-letter": "EIN letter (CP 575)",
  "agent-acceptance": "Registered agent's acceptance",
  "annual-report": "Annual report",
  other: "Other",
).at(k, default: k)

#let classification-name(c) = if c == none { na } else {
  (
    individual: "an individual",
    disregarded: "a disregarded entity (its owner's return)",
    "s-corp": "an S corporation",
    partnership: "a partnership",
    "c-corp": "a C corporation",
  ).at(c, default: c)
}

// Members and managers as "Name (entity), 100%".
#let members-list(org) = if org == none { na } else {
  org.members.map(m => [#m.name (#m.entity), #m.percent%]).join(", ")
}
#let managers-list(org) = if org == none or org.managers.len() == 0 { na } else {
  org.managers.map(m => [#m.name (#m.entity)]).join(", ")
}

#let facts(..rows) = table(
  columns: (auto, 1fr),
  stroke: none,
  column-gutter: 14pt,
  inset: (x: 0pt, y: 4pt),
  ..rows.pos().map(r => (text(fill: muted)[#r.at(0)], r.at(1))).flatten(),
)

// Page setup and the heading every document shares.
#let legal-document(title, subtitle: none, body) = {
  set page(
    paper: "us-letter",
    margin: (x: 1in, y: 1in),
    footer: context [
      #set text(size: 8pt, fill: muted)
      #data.legalName · #title · rendered #data.rendered from the declarations (modules/legal); private values read from Proton Pass at render time, never stored
      #h(1fr)
      #counter(page).display()
    ],
  )
  set text(size: 11pt)
  set par(justify: true)
  show heading: set text(fill: accent)
  if data.placeholders [
    #block(fill: warn.lighten(80%), inset: 8pt, radius: 4pt, width: 100%)[
      *Placeholder render.* Every private value here is a placeholder: this
      document was rendered without Proton Pass (the build check).
    ]
  ]
  heading(level: 1, title)
  if subtitle != none [ #text(fill: muted, size: 10pt)[#subtitle] ]
  v(8pt)
  body
}
