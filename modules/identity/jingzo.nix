# Jingzo, the research arm: QSearch LLC on paper (the EIN, Northwest, the
# state's records), Jingzo everywhere else, after its domain. Kept separate
# from Kagamizo while the two run separate business operations. Its domain is the Mandarin for "mirror"
# (镜 jìng, 镜子 jìngzi, 镜像 jìngxiàng, 明镜 míngjìng "bright mirror") with
# Kagamizo's -zo: jingzo.org, since jingzo.com was taken. Role mailboxes,
# as on kagamizo.com; which service uses which lives in Proton Pass.
{
  identity = {
    entities.jingzo = {
      legalName = "QSearch LLC";
      kind = "llc";
      vault = "QSearch-LLC";
      # Formed before this repo: the state and date are read off Northwest's
      # records (`northwest call get_company_details_tool`) and written here.
      legal = {
        status = "active";
        registeredAgent = "northwest-jingzo";
        ein = "unknown";
      };
    };

    domains."jingzo.org" = {
      entity = "jingzo";
      zoneId = "6e79f3b9333039e6e843b08a75475174";
      registrar = "cloudflare";
      registration = {
        month = "2026-10";
        costUsd = 8.50;
        renewalUsd = 11.20;
      };
      # From Proton's Domain names settings (it has no API for them).
      proton = {
        verification = "8f98c21f96d25746076c2ea834a2c823d41c1116";
        dkimId = "dcv33m3a3qcfza5y3f4dr2fdtxr76nqchvdymk7ckiaoajelyohda";
      };
      mailboxes = [
        "admin" # account owner, replacing the old Outlook address
        "finance" # banking and brokerage
        "legal" # registered agent, EIN correspondence
        "research" # arXiv and the like
        "dev" # GitHub, Gitea
        "automations" # automated mail and signups: routed, not read
      ];
    };
  };
}
