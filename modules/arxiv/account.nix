# arXiv: where QSearch publishes. Its query API is open and read-only;
# submitting is a web form, and a new author needs a personal endorsement
# from an established author in the field (arXiv staff cannot give one).
{
  accounts = {
    roles.arxiv = [ "research" ];

    capabilities.arxiv = {
      queryApi = "flag";
      submissionApi = "flag";
      institutionalEndorsement = "flag";
    };

    plans.arxiv.author = {
      checked = "2026-10-21";
      capabilities = {
        # Search and metadata, no sign-in: reports and literature reviews.
        queryApi = {
          value = true;
          source = "https://info.arxiv.org/help/api/index.html";
        };
        # Submissions are made in the web interface by registered authors.
        submissionApi = {
          value = false;
          source = "https://info.arxiv.org/help/submit/index.html";
        };
        # Since 2026-01-21 an institutional address alone no longer endorses
        # a new author; one also needs prior papers in the domain, or a
        # personal endorsement.
        institutionalEndorsement = {
          value = false;
          source = "https://blog.arxiv.org/2026/01/21/attention-authors-updated-endorsement-policy/";
        };
      };
    };

    # Signs up as research@jingzo.com, organization "QSearch LLC", once
    # jingzo.com and its mailboxes are declared (modules/identity/qsearch.nix):
    # a signup's address must be a declared mailbox.
    held.arxiv-qsearch = {
      provider = "arxiv";
      plan = "author";
      owner = "qsearch";
      status = "planned";
    };
  };
}
