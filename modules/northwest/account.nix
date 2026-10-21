# Northwest Registered Agent: the registered agent, state filings and the
# documents served on an entity. It publishes no REST API to its clients;
# it publishes an MCP server with every tool its portal assistant has, behind
# OAuth sign-in to the Northwest account (./session.nix), so the whole
# account is reachable as code. Spending goes through an invoice or a pay
# link, and the policy layer (modules/governance) keeps agents off it.
{
  accounts = {
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

    # QSearch's, already open: its registered agent and filings.
    held.northwest-qsearch = {
      provider = "northwest";
      plan = "registered-agent";
      owner = "qsearch";
      status = "active";
    };
  };
}
