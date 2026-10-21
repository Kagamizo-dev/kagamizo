# Northwest's MCP tools as governance actions, each typed by what it does.
# The tool list is the server's own (_json/tools.json, rewritten by
# `northwest catalog` from tools/list); the effects are declared here. A tool
# the catalog names without an effect, or an effect for a tool it does not
# name, fails evaluation, so a new server tool arrives as a reviewable diff
# and nothing calls it until it is typed.
{ lib, ... }:
let
  catalog = (builtins.fromJSON (builtins.readFile ./_json/tools.json)).tools;
  names = map (t: t.name) catalog;

  effects = {
    get_account_summary_tool = "read";
    get_companies_tool = "read";
    get_company_details_tool = "read";
    get_filing_statuses_tool = "read";
    get_annual_reports_tool = "read";
    get_documents_tool = "read";
    get_document_content_tool = "read";
    get_invoices_tool = "read";
    get_refund_status_tool = "read";
    get_registered_agents_tool = "read";
    get_mail_service_plan_details_tool = "read";
    search_domains_tool = "read";
    get_domains_tool = "read";
    get_domain_dns_records_tool = "read";
    update_company_details_tool = "write";
    # Each makes or pays an invoice.
    create_document_unlock_invoice_tool = "spend";
    checkout_cart_invoice_only_tool = "spend";
    pay_invoice_tool = "spend";
    cancel_service_tool = "destroy";
  };

  untyped = lib.subtractLists (lib.attrNames effects) names;
  unknown = lib.subtractLists names (lib.attrNames effects);
in
{
  governance.actions.northwest =
    assert lib.assertMsg (untyped == [ ])
      "modules/northwest/tools.nix: the server has tools with no declared effect: ${lib.concatStringsSep ", " untyped}";
    assert lib.assertMsg (unknown == [ ])
      "modules/northwest/tools.nix: effects declared for tools the server does not list: ${lib.concatStringsSep ", " unknown}";
    lib.listToAttrs (
      map (
        t:
        lib.nameValuePair t.name {
          effect = effects.${t.name};
          inherit (t) description;
        }
      ) catalog
    )
    // {
      # The wrapper's own operations on the session.
      login = {
        effect = "session";
        description = "Sign in and store the session";
        command = "login";
      };
      tools = {
        effect = "read";
        description = "List the server's tools";
        command = "tools";
      };
    };
}
