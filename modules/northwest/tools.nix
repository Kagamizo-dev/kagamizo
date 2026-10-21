# Northwest's MCP tools as governance actions, each typed by what it does.
# The tool list is the server's (_json/tools.json, rewritten by `northwest
# catalog` from tools/list); the effects are declared here. Reads are known
# by their verb; everything that writes, spends or destroys is named below.
# A tool that is neither fails evaluation, and so does a name below the
# catalog does not list, so a new server tool arrives as a reviewable diff
# and nothing calls it until it is typed.
{ lib, ... }:
let
  catalog = (builtins.fromJSON (builtins.readFile ./_json/tools.json)).tools;
  names = map (t: t.name) catalog;

  # Money leaves, or a filing or plan is committed to: the controller's tap.
  spend = [
    "checkout_cart_tool"
    "checkout_cart_invoice_only_tool"
    "pay_invoice_tool"
    "enable_autopay_tool"
    "create_document_unlock_invoice_tool"
    "create_document_request_tool"
    "save_or_submit_filing_form_tool"
    "save_or_submit_service_form_tool"
    "purchase_compliance_service_tool"
    "activate_monitoring_service_tool"
    "activate_email_hosting_addon_tool"
    "activate_website_hosting_addon_tool"
    "change_email_hosting_plan_tool"
    "change_phone_service_plan_tool"
    "reactivate_email_hosting_tool"
    "reactivate_phone_service_tool"
    "submit_domain_transfer_tool"
  ];
  destroy = [
    "cancel_service_tool"
    "delete_domain_dns_record_tool"
    "delete_domain_forwarding_tool"
    "delete_email_forwarding_tool"
  ];
  # Records, carts and settings: nothing is paid or filed by these alone.
  write = [
    "create_company_tool"
    "update_company_details_tool"
    "update_company_name_tool"
    "apply_filing_field_suggestions_tool"
    "apply_service_field_suggestions_tool"
    "select_product_tool"
    "add_product_to_cart_tool"
    "add_formation_to_cart_tool"
    "add_ein_to_cart_tool"
    "add_amendment_filing_to_cart_tool"
    "add_document_plan_upgrade_to_cart_tool"
    "add_ra_service_to_cart"
    "add_mail_plan_to_cart_tool"
    "add_new_domain_to_cart_tool"
    "add_domain_renewal_to_cart_tool"
    "add_domain_transfer_to_cart_tool"
    "add_email_hosting_to_cart_tool"
    "add_phone_service_to_cart_tool"
    "remove_from_cart_tool"
    "send_invoice_pay_link_sms_tool"
    "update_domain_lock_tool"
    "set_domain_auto_renew_tool"
    "set_domain_privacy_tool"
    "create_domain_for_accounts_stage_tool"
    "create_domain_dns_zone_tool"
    "create_domain_dns_record_tool"
    "update_domain_dns_record_tool"
    "update_domain_nameservers_tool"
    "set_domain_forwarding_tool"
    "update_domain_forwarding_tool"
    "set_bulk_domain_forwarding_tool"
    "create_email_inbox_tool"
    "change_email_inbox_password_tool"
    "create_email_forwarding_tool"
    "update_email_forwarding_tool"
    "reserve_phone_number_tool"
    "update_call_forwarding_tool"
    "update_voicemail_settings_tool"
    "update_cnam_tool"
    "set_phone_app_username_tool"
    "update_phone_settings_tool"
  ];
  readVerbs = [
    "get_"
    "list_"
    "search_"
    "show_"
    "check_"
    "discover_"
    "kb__"
    "company_entity_catalog"
    "open_order_item"
  ];

  effectOf =
    n:
    if lib.elem n spend then
      "spend"
    else if lib.elem n destroy then
      "destroy"
    else if lib.elem n write then
      "write"
    else if lib.any (v: lib.hasPrefix v n) readVerbs then
      "read"
    else
      null;

  untyped = lib.filter (n: effectOf n == null) names;
  unknown = lib.subtractLists names (spend ++ destroy ++ write);
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
          effect = effectOf t.name;
          inherit (t) description;
        }
      ) catalog
    )
    // {
      # The wrapper's own operations on the session.
      login = {
        effect = "session";
        description = "Sign in and store the session";
        command = "northwest login";
      };
      tools = {
        effect = "read";
        description = "List the server's tools";
        command = "northwest tools";
      };
    };
}
