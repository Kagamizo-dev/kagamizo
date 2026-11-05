// A W-9 prefill: the values that go on each line of the IRS Form W-9
// (Rev. March 2024), as the record states them. This is a data sheet, not
// the form: the form itself is filled from it.
#import "common.typ": *

#show: legal-document.with(
  [W-9 prefill: #data.legalName],
  subtitle: [What goes on each line of Form W-9; the form is the IRS's, this is the data],
)

#let disregarded = data.taxClassification == "disregarded"
#let owner-name = if data.organization != none and data.organization.members.len() > 0 {
  data.organization.members.at(0).name
} else { none }

#let line3 = if data.kind == "person" or disregarded {
  [Individual/sole proprietor#if disregarded [ (a single-member LLC disregarded from its owner)]]
} else if data.taxClassification == "s-corp" {
  [Limited liability company; tax classification *S*]
} else if data.taxClassification == "c-corp" {
  [Limited liability company; tax classification *C*]
} else if data.taxClassification == "partnership" {
  [Limited liability company; tax classification *P*]
} else { unset }

#facts(
  ([Line 1, name], if disregarded { val(owner-name) } else { data.legalName }),
  ([Line 2, business name], if disregarded { data.legalName } else { na }),
  ([Line 3a, classification], line3),
  ([Line 3b, flow-through with foreign partners], [No]),
  ([Line 4, exemptions], [None]),
  ([Lines 5–6, address], val(data.addresses.mailing, missing: [private: from Proton Pass, by the owner])),
  ([Line 7, account numbers], [Left to the requester]),
)

== Part I, taxpayer identification number
#if data.kind == "person" [
  The owner's SSN. It lives in Proton Pass and is never rendered: the owner
  enters it on the form.
] else if disregarded [
  A disregarded single-member LLC gives *its owner's* TIN (the form's
  instructions, Part I): the owner's SSN, which lives in Proton Pass and is
  never rendered, or the owner's own EIN if they have one. The LLC's EIN
  (#val(data.ein.value)) is *not* the number to give here.
] else [
  The entity's EIN: #val(data.ein.value).
]

== Part II, certification
Signed by #val(data.controller, missing: data.legalName), dated when signed.
The certification is the form's own text; nothing here changes it.

#v(12pt)
#text(fill: muted, size: 9pt)[
  Classification from #raw("money.tax." + data.entity) (#classification-name(data.taxClassification)).
  Check the current revision of Form W-9 at irs.gov before filing: line
  numbers are the March 2024 revision's.
]
