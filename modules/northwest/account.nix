# Northwest Registered Agent: the registered agent, state filings and the
# documents served on an entity. It publishes no REST API to its clients;
# it publishes an MCP server with every tool its portal assistant has, behind
# OAuth sign-in to the Northwest account (./session.nix), so the whole
# account is reachable as code. Spending goes through an invoice or a pay
# link, and the policy layer (modules/governance) keeps agents off it.
{
  accounts = {
    roles.northwest = [ "registered-agent" ];

    capabilities.northwest = {
      mcpServer = "flag";
      oauthSessions = "flag";
      companyRecords = "flag";
      filingStatus = "flag";
      documents = "flag";
      invoices = "flag";
      domains = "flag";
      clientApi = "flag";
    };

    plans.northwest.registered-agent = {
      checked = "2026-10-21";
      capabilities = {
        # Streamable HTTP at mcp.northwestregisteredagent.com, the same tools
        # as Bigfoot in the client portal.
        mcpServer = {
          value = true;
          source = "https://www.northwestregisteredagent.com/ai/mcp";
        };
        # Sign-in with the Northwest account; no API keys in config. The
        # public client `mcp-connector` uses PKCE without a secret.
        oauthSessions = {
          value = true;
          source = "https://www.northwestregisteredagent.com/ai/mcp/connect/muse";
        };
        # Companies, entity details, EIN lookup, profile updates.
        companyRecords = {
          value = true;
          source = "https://www.northwestregisteredagent.com/ai/mcp/tools";
        };
        # Formation, annual report and amendment filings; due dates, autopay.
        filingStatus = {
          value = true;
          source = "https://www.northwestregisteredagent.com/ai/mcp/tools";
        };
        # Portal documents (service of process, state mail): list and read.
        documents = {
          value = true;
          source = "https://www.northwestregisteredagent.com/ai/mcp/tools";
        };
        # Open and paid invoices, paying with a saved method, pay links.
        invoices = {
          value = true;
          source = "https://www.northwestregisteredagent.com/ai/mcp/tools";
        };
        domains = {
          value = true;
          source = "https://www.northwestregisteredagent.com/ai/mcp/tools";
        };
        # The public API is offered to wholesale partners, not to clients.
        clientApi = {
          value = false;
          source = "https://www.northwestregisteredagent.com/wholesale";
        };
      };
    };

    # Kagamizo's, to open with its formation order: one Northwest account per
    # entity, so each company's documents and invoices stay apart. After it,
    # the formation, EIN and annual reports are ordered through the server.
    held.northwest-kagamizo = {
      provider = "northwest";
      plan = "registered-agent";
      owner = "kagamizo";
      status = "planned";
      signup = {
        url = "https://www.northwestregisteredagent.com/";
        handle = "kagamizo";
        email = "legal@kagamizo.com";
        credential = "password";
        findings = [
          {
            fact = "the MCP server prices formation, amendment and EIN orders, and checks out as an invoice or a texted pay link";
            source = "https://www.northwestregisteredagent.com/ai/mcp/tools";
            checked = "2026-10-21";
          }
          {
            fact = "a client account is needed before the MCP server can be signed in to";
            source = "https://www.northwestregisteredagent.com/ai/mcp/connect";
            checked = "2026-10-21";
          }
        ];
      };
    };

    # QSearch's, already open: its registered agent and filings.
    held.northwest-qsearch = {
      provider = "northwest";
      plan = "registered-agent";
      owner = "qsearch";
      status = "active";
    };
  };
}
