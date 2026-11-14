// "Who we are": the letter a bank or a broker asks for when opening an
// account (know-your-customer): the legal person, its formation, its EIN,
// its registered agent and its officers, signed by the controller.
#import "common.typ": *

#show: legal-document.with(
  [Statement of identity],
  subtitle: [For a bank, broker or counterparty's customer identification],
)

#data.rendered

To whom it may concern,

#if data.kind == "person" [
  I, *#data.legalName*, a natural person, make this statement for the
  purpose of your customer identification. My identity documents are held
  by me and presented on request; no identifier appears in this letter.
] else [
  This letter states who *#data.legalName* is, for the purpose of your
  customer identification.

  == The entity
  #facts(
    ([Legal name], data.legalName),
    ([Entity type], kind-name(data.kind)),
    ([State of formation], state-name(data.formation.state)),
    ([Date of formation], val(data.formation.date)),
    ([State filing number], val(data.formation.filingNumber)),
    ([Employer Identification Number], val(data.ein.value)),
    ([Registered agent], if data.registeredAgent == none { na } else { data.registeredAgent.name }),
    ([Registered office], val(data.addresses.registeredOffice, missing: [as on file with the registered agent])),
    ([Tax classification], classification-name(data.taxClassification)),
  )

  == Business
  #val(data.purpose, missing: na)

  == Ownership and control
  #facts(
    ([Management], if data.organization == none { na } else { management-name(data.organization.management) }),
    ([Beneficial owners], members-list(data.organization)),
    ([Managers], managers-list(data.organization)),
    ([Authorized signer], val(data.controller, missing: na)),
  )

  Each beneficial owner above holds the stated share directly; no other
  person owns 25% or more of the entity or controls it. The authorized
  signer is the person named as controller in the entity's declarations.

  == Documents available on request
  #if data.documents.len() == 0 [ #text(fill: muted)[None declared.] ] else [
    #list(..data.documents.map(d => [#d.title (#document-kind(d.kind)#if d.issued != none [, issued #d.issued])]))
  ]
]

Correspondence goes to #val(data.legalEmail, missing: [the contact on file]).

#block(breakable: false)[
  #v(12pt)
  Sincerely,

  #v(20pt)
  #line(length: 45%, stroke: 0.5pt)
  #val(data.controller, missing: data.legalName) \
  #if data.kind != "person" [#text(fill: muted)[#if data.organization != none and data.organization.management == "member-managed" [Member] else [Manager], #data.legalName]]
]
