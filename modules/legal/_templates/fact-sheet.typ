// The company fact sheet: everything the record states about one entity,
// on one page, with the private values read from Proton Pass at render.
#import "common.typ": *

#show: legal-document.with(
  [Fact sheet: #data.legalName],
  subtitle: [#kind-name(data.kind), #data.status; entity #raw(data.entity) in the declarations],
)

== Identity
#facts(
  ([Legal name], data.legalName),
  ([Kind], kind-name(data.kind)),
  ([Standing], data.status),
  ([Purpose], val(data.purpose, missing: na)),
  ([Domains], if data.domains.len() == 0 { na } else { data.domains.join(", ") }),
  ([Legal contact], val(data.legalEmail, missing: na)),
)

#if data.kind != "person" [
  == Formation
  #facts(
    ([State], state-name(data.formation.state)),
    ([Date], val(data.formation.date)),
    ([Filing number], val(data.formation.filingNumber)),
    ([EIN], val(data.ein.value)),
    ([Registered agent], if data.registeredAgent == none { na } else [#data.registeredAgent.name (account #data.registeredAgent.account)]),
    ([Registered office], val(data.addresses.registeredOffice, missing: na)),
    ([Mailing address], val(data.addresses.mailing, missing: [private: in Proton Pass])),
  )

  == Organization
  #facts(
    ([Management], if data.organization == none { na } else { management-name(data.organization.management) }),
    ([Members], members-list(data.organization)),
    ([Managers], managers-list(data.organization)),
    ([Controller], val(data.controller, missing: na)),
    ([Taxed as], classification-name(data.taxClassification)),
    ([Return filed by], val(data.taxReturnOf, missing: na)),
  )
]

== Documents held
#if data.documents.len() == 0 [
  #text(fill: muted)[None declared.]
] else [
  #table(
    columns: (auto, 1fr, auto, auto),
    stroke: (x: none, y: 0.5pt + muted.lighten(60%)),
    inset: (x: 6pt, y: 5pt),
    table.header([*Kind*], [*Title*], [*Issued*], [*In Proton Pass*]),
    ..data.documents.map(d => (
      document-kind(d.kind),
      d.title,
      val(d.issued, missing: [see the document]),
      [#d.vault / #d.item],
    )).flatten(),
  )
]
