# Apple: the iPhone's account, iCloud and the App Store. Being left (modules/migration): everything in it moves to Proton, then it closes.
{
  accounts = {
    roles.apple = [ "platform" ];

    capabilities.apple = {
      dataCopy = "flag";
      appSpecificPasswords = "flag";
      passwordExportOnIphone = "flag";
    };

    plans.apple.icloud = {
      # iCloud+ storage
      billing = {
        value = "subscription";
        source = "https://www.apple.com/icloud/";
      };
      checked = "2026-11-01";
      capabilities = {
        # a full copy of the account's data, requested in its own console
        dataCopy = {
          value = true;
          source = "https://privacy.apple.com/";
        };
        # IMAP, CardDAV and CalDAV with an app-specific password
        appSpecificPasswords = {
          value = true;
          source = "https://support.apple.com/en-us/102654";
        };
        # a CSV export needs a Mac; Proton Pass is not a Credential Exchange target
        passwordExportOnIphone = {
          value = false;
          source = "https://proton.me/support/pass-import-safari";
        };
      };
    };

    # Its Apple ID is already a Proton address. Retiring: emptied into
    # Proton (migration.sources.apple-mirazo), then closed.
    held.apple-mirazo = {
      provider = "apple";
      plan = "icloud";
      owner = "mirazo";
      status = "retiring";
      payment.pending = "iCloud+ on the owner's own card, cancelled when the account closes";
      login = {
        item = "Apple";
        email = "zachariah.oshodi@protonmail.com";
      };
    };
  };
}
