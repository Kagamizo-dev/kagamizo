# QSearch LLC, the research arm; kept separate from Kagamizo while the two run
# separate business operations. Its domain is the Mandarin for "mirror"
# (镜 jìng, 镜子 jìngzi, 镜像 jìngxiàng, 明镜 míngjìng "bright mirror"),
# matching Kagamizo's Japanese one. Once one is bought, declare it under
# identity.domains with these mailboxes.
#
#   admin     account owner, replacing the old Outlook address
#   finance   banking and brokerage
#   legal     registered agent, EIN correspondence
#   research  arXiv and the like
#   dev       GitHub, Gitea
{
  identity.entities.qsearch = {
    legalName = "QSearch LLC";
    kind = "llc";
    vault = "QSearch-LLC";
    domainCandidates = [
      "jingzo.com" # same shape as kagamizo
      "jingzi.com"
      "jingxiang.com"
      "mingjing.com"
      "jingzi.ai"
      "jingxiang.ai"
      "jingzi.io"
      "jingxiang.io"
    ];
  };
}
