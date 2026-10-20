# Kagamizo LLC (鏡, kagami: mirror). Role mailboxes, not one per service:
# per-service addresses are Proton Pass aliases on the domain and don't count
# toward the seven. Which service uses which address lives in Proton Pass,
# never here: this repo is public.
{
  identity = {
    entities.kagamizo = {
      legalName = "Kagamizo LLC";
      kind = "llc";
      vault = "Kagamizo-LLC";
    };

    domains."kagamizo.com" = {
      entity = "kagamizo";
      zoneId = "2f1f4505269c5d5ea904ca73d379ef99";
      # From Proton's Domain names settings (it has no API for them).
      proton = {
        verification = "11675870bd5ab9f95798ea614579fbb880696a86";
        dkimId = "dvfpp4whqdupmoam2azbjo22lifelhaq46bbtnwdw32zqimgtxubq";
      };
      mailboxes = [
        "zach" # the face of the company
        "admin" # SaaS and tool accounts
        "billing" # invoices and payments
        "legal" # registered agent, state filings, IRS
        "dev" # GitHub and the like
        "automations" # automated mail, events and signups: routed, not read
      ];
    };
  };
}
