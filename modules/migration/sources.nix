# What is left behind, and how (the owner's plan, 2026-11-01). Every byte
# goes to Proton, every dollar to Mercury; each provider's full copy is kept
# whole in Proton Drive under /Archives/<provider>. Tools are pinned and
# mapped before they run (HANDOFF.md, the migration's Phase 0).
let
  archive = provider: {
    export = "human:request-export";
    destination = "proton-drive";
    verify = "the archive's own manifest, stored with it under /Archives/${provider}";
  };
  inventory = how: {
    export = how;
    destination = "inventory";
    verify = "every service found is a declared account (accounts.held) with its fate";
  };
  reDeclared = why: {
    export = "none";
    destination = "re-declared";
    verify = why;
  };
  easySwitch = what: {
    export = "Proton Easy Switch (the owner approves the provider's sign-in)";
    destination = what;
    verify = "Proton's import report against the source's own counts";
  };
in
{
  migration.sources = {
    apple-mirazo = {
      classes = {
        archive = archive "apple";
        mail = {
          export = "imapsync (app-specific password) into Bridge IMAP, label iCloud/<folder>";
          destination = "proton-mail";
          verify = "per-folder message counts and Message-ID sets equal; gaps retried";
        };
        contacts = {
          export = "vdirsyncer (CardDAV) to vCard";
          destination = "proton-contacts";
          verify = "card count and UIDs";
        };
        calendars = {
          export = "vdirsyncer (CalDAV) to ICS";
          destination = "proton-calendar";
          verify = "event count and UIDs per calendar";
        };
        photos = {
          export = "icloudpd (password and 2FA), originals with metadata";
          destination = "proton-drive";
          verify = "asset count and SHA-256 of every file";
        };
        files = {
          export = "rclone iclouddrive";
          destination = "proton-drive";
          verify = "rclone check, source against Proton Drive";
        };
        notes = {
          export = "pyicloud notes, as HTML then Markdown";
          destination = "proton-drive";
          verify = "note count";
        };
        # Kept beside the notes, readable as Markdown (the owner, 2026-11-03).
        reminders = {
          export = "pyicloud reminders, every list as JSON, then Markdown beside the notes";
          destination = "proton-drive";
          verify = "reminder count";
        };
        passwords = reDeclared "every login is a declared account with a new password on a domain address (Roadmap epic 5)";
        passkeys = reDeclared "registered anew per site; Apple's passkeys do not export";
        totp = reDeclared "each site's 2FA re-enrolled into its Proton Pass item";
        health = {
          export = "human:handle-device";
          destination = "proton-drive";
          verify = "export.zip stored with its SHA-256";
        };
        messages = {
          export = "human:handle-device";
          destination = "proton-drive";
          verify = "the device's export stored with its SHA-256";
        };
        subscriptions = inventory "App Store receipts in the mail (no_reply@email.apple.com)";
        purchases = inventory "App Store receipts in the mail";
      };
      dependants = [
        {
          kind = "login";
          what = "the 4 Hide My Email relays (bryanjohnson.com, DuckDuckGo, heb.com, ljsilvers.com; the inventory of 2026-11-03)";
          movedTo = "none: junk, dropped with the account (the owner, 2026-11-03)";
        }
        {
          kind = "login";
          what = "every service signed into with Sign in with Apple";
          movedTo = "a login of its own on a mirazo.org address";
        }
        {
          kind = "2fa";
          what = "Apple devices as trusted 2FA for the Apple ID";
          movedTo = "none once closed";
        }
        {
          kind = "subscription";
          what = "iCloud+ storage";
          movedTo = "cancelled (Proton Unlimited holds the data)";
        }
        {
          kind = "login";
          what = "the phone number's iMessage registration";
          movedTo = "deregistered before the iPhone goes (human:handle-device)";
        }
      ];
    };

    google-mirazo = {
      classes = {
        archive = archive "google";
        mail = easySwitch "proton-mail";
        contacts = easySwitch "proton-contacts";
        calendars = easySwitch "proton-calendar";
        photos = {
          export = "human:request-export";
          destination = "proton-drive";
          verify = "Takeout's photo count and SHA-256 of every file";
        };
        files = {
          export = "human:request-export";
          destination = "proton-drive";
          verify = "rclone check, Takeout against Proton Drive";
        };
        passwords = reDeclared "Google Password Manager's logins re-declared, as for Apple";
        totp = reDeclared "Google Authenticator's codes re-enrolled into Proton Pass";
        subscriptions = inventory "Google's receipts and 'welcome' mail";
      };
      dependants = [
        {
          kind = "login";
          what = "every service signed into with Sign in with Google";
          movedTo = "a login of its own on a mirazo.org address";
        }
        {
          kind = "login";
          what = "every service using oshodi.zach@gmail.com";
          movedTo = "a mirazo.org address";
        }
      ];
    };

    outlook-mirazo = {
      classes = {
        archive = archive "microsoft";
        mail = easySwitch "proton-mail";
        contacts = easySwitch "proton-contacts";
        calendars = easySwitch "proton-calendar";
        subscriptions = inventory "the mailbox's senders";
      };
      dependants = [
        {
          kind = "login";
          what = "every service using zachary.oshodi@outlook.com (Experian among them)";
          movedTo = "a mirazo.org address";
        }
      ];
    };

    outlook-jingzo = {
      classes = {
        archive = archive "microsoft";
        mail = easySwitch "proton-mail";
        subscriptions = inventory "the mailbox's senders";
      };
      dependants = [
        {
          kind = "login";
          what = "Northwest, Public (Jingzo), both IBKR logins, GitHub, Gitea, arXiv: every login made on qsearchllc_wy@outlook.com";
          movedTo = "a jingzo.org address";
        }
      ];
    };

    chase-mirazo = {
      product = "checking";
      classes = {
        statements = {
          export = "human:request-export";
          destination = "proton-drive";
          verify = "one PDF per month for every month online, under /Records/mirazo/chase";
        };
        transactions = {
          export = "human:request-export";
          destination = "ledger";
          verify = "the CSV's running balance reconciles with the statements";
        };
      };
      dependants = [
        {
          kind = "deposit";
          what = "direct deposit";
          movedTo = "mercury-mirazo";
        }
        {
          kind = "autopay";
          what = "Chase Sapphire's payment";
          movedTo = "mercury-mirazo";
        }
        {
          kind = "autopay";
          what = "Amazon Prime Visa's payment";
          movedTo = "mercury-mirazo";
        }
        {
          kind = "autopay";
          what = "every other bill drawn from checking (read off its transactions)";
          movedTo = "each its own Mercury card";
        }
      ];
    };
  };
}
