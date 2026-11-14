// A summary of the operating agreement's terms as the record states them.
// It is not the agreement: that is the document the entity holds (listed
// below when declared), and this summary never contradicts it.
#import "common.typ": *

#show: legal-document.with(
  [Operating agreement summary: #data.legalName],
  subtitle: [The terms the declarations state; the signed agreement governs],
)

#let org = data.organization
#let agreement = data.documents.filter(d => d.kind == "operating-agreement")

#facts(
  ([Company], data.legalName),
  ([Formed in], state-name(data.formation.state)),
  ([Formed on], val(data.formation.date)),
  ([Filing number], val(data.formation.filingNumber)),
  ([Purpose], val(data.purpose, missing: na)),
  ([Term], [Perpetual, until dissolved under the agreement and the state's act]),
  ([Registered agent], if data.registeredAgent == none { na } else { data.registeredAgent.name }),
  ([Principal office], val(data.addresses.mailing, missing: [as in the agreement])),
)

== Members and capital
#if org == none [ #text(fill: muted)[No organization declared.] ] else [
  #table(
    columns: (1fr, auto, auto),
    stroke: (x: none, y: 0.5pt + muted.lighten(60%)),
    inset: (x: 6pt, y: 5pt),
    table.header([*Member*], [*Entity*], [*Share*]),
    ..org.members.map(m => (m.name, raw(m.entity), [#m.percent%])).flatten(),
  )
  Shares sum to 100% (checked by Lean, modules/legal). Profits, losses and
  distributions follow the shares unless the agreement says otherwise.
]

== Management
#if org == none [ #na ] else if org.management == "member-managed" [
  Member-managed: every member acts for the company, and with one member
  that member alone. There are no managers.
] else [
  Manager-managed: the managers act for the company; the members do not,
  except as the agreement reserves. Managers: #managers-list(org).
]

== Tax
Taxed as #classification-name(data.taxClassification)#if data.taxReturnOf != none [; its activity is reported on #data.taxReturnOf's return].
No election to be taxed otherwise is on file unless a document below says so.

== The agreement itself
#if agreement.len() == 0 [
  #text(fill: warn)[No operating agreement is declared as held. The state's
  default rules apply until one is signed; declare it under
  #raw("legal.records." + data.entity + ".documents") once it exists.]
] else [
  #list(..agreement.map(d => [#d.title#if d.issued != none [, signed #d.issued]; in Proton Pass at #d.vault / #d.item]))
]
