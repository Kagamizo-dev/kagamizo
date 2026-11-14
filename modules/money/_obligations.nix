# What is owed for a tax year, derived from money.tax and the entities'
# legal records: every form and payment, its due date, and the page that
# states the rule. A date on a weekend moves to the Monday after (federal
# holidays and the District's Emancipation Day are not modelled: a due date
# next to one is to be checked). An obligation whose date depends on a fact
# not yet declared says which fact, rather than guessing.
#
#   money.obligations 2026  -> [ { entity; form; what; due; source; when? } ]
#
# Not owed, stated so it is not looked for: FinCEN's beneficial ownership
# report, from which every company formed in the US is exempt (FinCEN's
# final rule, effective 2026-08-14, adopting its March 2025 interim rule).
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.money;
  entities = config.identity.checked.entities;

  pad = n: if n < 10 then "0${toString n}" else toString n;
  date =
    y: m: d:
    "${toString y}-${pad m}-${pad d}";
  # 0 = Sunday .. 6 = Saturday (Sakamoto's method).
  weekday =
    y: m: d:
    let
      t = [
        0
        3
        2
        5
        0
        3
        5
        1
        4
        6
        2
        4
      ];
      y' = if m < 3 then y - 1 else y;
    in
    lib.mod (y' + y' / 4 - y' / 100 + y' / 400 + lib.elemAt t (m - 1) + d) 7;
  daysIn =
    y: m:
    if m == 2 then
      (if (lib.mod y 4 == 0 && lib.mod y 100 != 0) || lib.mod y 400 == 0 then 29 else 28)
    else if
      lib.elem m [
        4
        6
        9
        11
      ]
    then
      30
    else
      31;
  # A date n days later, rolling into the next month and year.
  later =
    y: m: d: n:
    let
      d' = d + n;
    in
    if d' <= daysIn y m then
      date y m d'
    else if m == 12 then
      date (y + 1) 1 (d' - 31)
    else
      date y (m + 1) (d' - daysIn y m);
  # The next business day on or after a date (weekends only).
  due =
    y: m: d:
    let
      w = weekday y m d;
    in
    if w == 6 then
      later y m d 2
    else if w == 0 then
      later y m d 1
    else
      date y m d;

  irs = {
    f1040 = "https://www.irs.gov/forms-pubs/about-form-1040";
    schC = "https://www.irs.gov/forms-pubs/about-schedule-c-form-1040";
    schSE = "https://www.irs.gov/forms-pubs/about-schedule-se-form-1040";
    es = "https://www.irs.gov/forms-pubs/about-form-1040-es";
    f8949 = "https://www.irs.gov/forms-pubs/about-form-8949";
    f6781 = "https://www.irs.gov/forms-pubs/about-form-6781";
    f4868 = "https://www.irs.gov/pub/irs-pdf/f4868.pdf";
    tc429 = "https://www.irs.gov/taxtopics/tc429";
    p1099 = "https://www.irs.gov/pub/irs-pdf/p1099.pdf";
    fbar = "https://www.fincen.gov/report-foreign-bank-and-financial-accounts";
    penalty = "https://www.irs.gov/payments/failure-to-file-penalty";
  };

  obligations =
    year:
    let
      next = year + 1;
      individuals = lib.attrNames (lib.filterAttrs (_: p: p.classification == "individual") cfg.tax);
      disregarded = lib.filterAttrs (_: p: p.classification == "disregarded") cfg.tax;
      businessesOf = i: lib.attrNames (lib.filterAttrs (e: _: cfg.returnOf e == i) disregarded);
      perIndividual =
        i:
        [
          {
            entity = i;
            form = "Form 1040";
            what = "the ${toString year} individual return, carrying every disregarded business below";
            due = due next 4 15;
            source = irs.f1040;
            penalty = "late filing: 5% of the unpaid tax a month, up to 25% (at least \$525 or the tax if over 60 days late); late payment: 0.5% a month, up to 25%, plus interest (${irs.penalty})";
          }
          {
            entity = i;
            form = "Form 4868";
            what = "the extension: filing moves to October 15, payment does not";
            due = due next 4 15;
            source = irs.f4868;
            when = "more time is needed to file";
          }
          {
            entity = i;
            form = "Section 475(f) election for ${toString next}";
            what = "mark-to-market for a trader in securities, for tax year ${toString next}: a statement by the unextended due date of the ${toString year} return, then Form 3115 with the ${toString next} return and gains on Form 4797; it cannot be made late";
            due = due next 4 15;
            source = irs.tc429;
            when = "the owner elects it (a dated decision, never a default)";
          }
          {
            entity = i;
            form = "W-2s received";
            what = "wages and withholding for ${toString year} from every employer, read into the return; employers send them by January 31, often by email";
            due = due next 1 31;
            source = "https://www.irs.gov/forms-pubs/about-form-w-2";
            when = "wages in the year";
          }
          {
            entity = i;
            form = "1099-B, 1099-INT, 1099-DA received";
            what = "the brokerage's and the banks' information returns for ${toString year}, read into the return (payers send 1099-B by February 15, the others by January 31)";
            due = due next 2 15;
            source = irs.p1099;
          }
          {
            entity = i;
            form = "FinCEN 114 (FBAR)";
            what = "foreign financial accounts over \$10,000 in total at any time in ${toString year}";
            due = due next 4 15;
            source = irs.fbar;
            when = "any foreign account";
          }
          {
            entity = i;
            form = "Form 8949, Schedule D";
            what = "sales of securities and options closed in ${toString year} (from the brokerage's 1099-B)";
            due = due next 4 15;
            source = irs.f8949;
            when = "any brokerage sale in the year";
          }
          {
            entity = i;
            form = "Form 6781";
            what = "Section 1256 contracts (index options such as SPX, futures): marked to market, 60% long-term, 40% short-term";
            due = due next 4 15;
            source = irs.f6781;
            when = "any Section 1256 contract held or closed in the year";
          }
        ]
        ++
          lib.imap1
            (k: md: {
              entity = i;
              form = "Form 1040-ES, payment ${toString k}";
              what = "estimated tax for ${toString year}, if the year's tax after withholding will be \$1,000 or more";
              due = due (lib.elemAt md 0) (lib.elemAt md 1) (lib.elemAt md 2);
              source = irs.es;
              when = "expected tax of \$1,000 or more not covered by withholding";
            })
            [
              [
                year
                4
                15
              ]
              [
                year
                6
                15
              ]
              [
                year
                9
                15
              ]
              [
                next
                1
                15
              ]
            ]
        ++ lib.concatMap (b: [
          {
            entity = b;
            form = "Schedule C (on ${i}'s Form 1040)";
            what = "${entities.${b}.legalName}'s ${toString year} profit or loss, disregarded into ${i}'s return";
            due = due next 4 15;
            source = irs.schC;
          }
          {
            entity = b;
            form = "Schedule SE (on ${i}'s Form 1040)";
            what = "self-employment tax on ${entities.${b}.legalName}'s net business earnings; trading gains are never self-employment income, so they never land here or on Schedule C";
            due = due next 4 15;
            source = irs.schSE;
            when = "net self-employment earnings of \$400 or more";
          }
          {
            entity = b;
            form = "Form 1099-NEC (issued)";
            what = "${entities.${b}.legalName}'s payments to contractors in ${toString year}, filed through IRIS and sent to each";
            due = due next 1 31;
            source = irs.p1099;
            when = "\$2,000 or more paid to one contractor in the year";
          }
        ]) (businessesOf i)
        ++ lib.optional cfg.tax.${i}.residence.stateIncomeTax {
          entity = i;
          form = "state income tax return";
          what = "the state of residence's own return";
          due = null;
          source = irs.f1040;
          when = "money.tax.${i}.residence.state names the state and its due date";
        };
      # Every LLC formed in Wyoming: its annual report and license tax, on
      # the first day of its anniversary month.
      wyoming = lib.concatLists (
        lib.mapAttrsToList (
          e: x:
          let
            l = x.legal;
            formed = l.formed or null;
            month =
              if formed == null then
                null
              else
                lib.toInt (lib.removePrefix "0" (lib.elemAt (lib.splitString "-" formed) 1));
          in
          lib.optional (x.kind == "llc" && l.status == "active") {
            entity = e;
            form = "Wyoming annual report and license tax";
            what = "the greater of \$60 or 0.0002 of the assets it holds in Wyoming (W.S. 17-29-209)";
            due = if month == null || l.jurisdiction != "US-WY" then null else due year month 1;
            source = "https://sos.wyo.gov/Business/AnnualReport.aspx";
            penalty = "delinquent from the second day of the next month; administratively dissolved if not filed within 60 days of the due date (https://sos.wyo.gov/faqs.aspx?root=BUS)";
            when =
              if l.jurisdiction == null then
                "identity.entities.${e}.legal.jurisdiction and formed, read off Northwest's records, decide whether and when"
              else if l.jurisdiction != "US-WY" then
                "formed in ${l.jurisdiction}: that state's own report"
              else
                null;
          }
        ) entities
      );
    in
    lib.concatMap perIndividual individuals ++ wyoming;
in
{
  options.money.obligations = mkOption {
    type = types.functionTo (types.listOf types.attrs);
    readOnly = true;
    default = obligations;
    description = "Every form and payment due for a tax year.";
  };
}
