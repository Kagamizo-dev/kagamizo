# arXiv: where Jingzo publishes. Its query API is open and read-only;
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

    # Organization "QSearch LLC". The verification mail goes to
    # research@jingzo.org, so it waits on jingzo.org's mail being live.
    held.arxiv-jingzo = {
      provider = "arxiv";
      plan = "author";
      owner = "jingzo";
      status = "planned";
      login.item = "arxiv-qsearch";
      signup = {
        url = "https://arxiv.org/user/register";
        handle = "jingzo";
        email = "research@jingzo.org";
        credential = "password";
        findings = [
          {
            fact = "the form asks for a name, an organization and an email tied to it; an unaffiliated author enters Independent";
            source = "https://info.arxiv.org/help/registerhelp.html";
            checked = "2026-10-21";
          }
          {
            fact = "a first submission needs a personal endorsement from an established author in the domain; arXiv staff cannot give one";
            source = "https://blog.arxiv.org/2026/01/21/attention-authors-updated-endorsement-policy/";
            checked = "2026-10-21";
          }
        ];
      };
    };
  };
}
