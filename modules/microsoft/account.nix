# Microsoft: the two Outlook.com mailboxes. Being left (modules/migration); the Jingzo one last, once every login on it has moved.
{
  accounts = {
    roles.microsoft = [ "mail" ];

    capabilities.microsoft = {
      mailboxExport = "flag";
      imapBasicAuth = "flag";
    };

    plans.microsoft.outlook-free = {
      # free Outlook.com
      billing = {
        value = "free";
        source = "https://www.microsoft.com/microsoft-365/outlook/email-and-calendar-software-microsoft-outlook";
      };
      checked = "2026-11-01";
      capabilities = {
        # a PST of the mailbox, linked by mail
        mailboxExport = {
          value = true;
          source = "https://support.microsoft.com/office/export-your-mailbox-from-outlook-com";
        };
        # IMAP needs OAuth with a registered app
        imapBasicAuth = {
          value = false;
          source = "https://learn.microsoft.com/exchange/clients-and-mobile-in-exchange-online/deprecation-of-basic-authentication-exchange-online";
        };
      };
    };

    held = {
      outlook-mirazo = {
        provider = "microsoft";
        plan = "outlook-free";
        owner = "mirazo";
        status = "retiring";
        login = {
          item = "Outlook";
          email = "zachary.oshodi@outlook.com";
        };
      };
      # Every Jingzo login was made on it: closed last, once they all moved.
      outlook-jingzo = {
        provider = "microsoft";
        plan = "outlook-free";
        owner = "jingzo";
        status = "retiring";
        login = {
          item = "Email";
          email = "qsearchllc_wy@outlook.com";
        };
      };
    };
  };
}
