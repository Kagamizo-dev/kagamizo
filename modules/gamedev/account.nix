# Steam: the one testing-and-shipping platform of the game-development
# profile (./default.nix), on a free account of the owner's. Publishing
# goes through Steamworks, which opens only after Steam Direct's one-time
# fee (100 US dollars a product): a capability of the plan, false on the free one
# until the owner pays it (their payment step), and so nothing in the repo
# may demand it yet. Family Sharing is on every account.
#
# Planned, no secret yet: `signup plan` lists it, `signup prepare` makes
# its login item, and the owner does the form on store.steampowered.com.
{
  accounts = {
    capabilities.steam = {
      steamworks = "flag";
      familySharing = "flag";
    };

    plans.steam.free = {
      # A Steam account is free; what costs is each product's Steam Direct fee.
      billing = {
        value = "free";
        source = "https://store.steampowered.com/join/";
      };
      checked = "2026-11-04";
      capabilities = {
        # Steamworks (an app id, builds, store pages) needs the Steam Direct
        # fee, 100 US dollars a product, recouped after 1,000 of adjusted
        # gross revenue: not part of a free account.
        steamworks = {
          value = false;
          source = "https://partner.steamgames.com/steamdirect";
        };
        # Family Sharing: any account may share its library with up to five
        # others on its Steam Family.
        familySharing = {
          value = true;
          source = "https://store.steampowered.com/steam_family_sharing";
        };
      };
    };

    # Yours: testing builds and, once Steamworks is paid for, shipping them.
    held.steam-mirazo = {
      provider = "steam";
      plan = "free";
      owner = "mirazo";
      status = "planned";
      signup = {
        url = "https://store.steampowered.com/join/";
        handle = "mirazo";
        email = "zach@mirazo.org";
        credential = "password";
        findings = [
          {
            fact = "an account is free; publishing needs a Steamworks partner account and Steam Direct's fee of 100 US dollars per product";
            source = "https://partner.steamgames.com/steamdirect";
            checked = "2026-11-04";
          }
          {
            fact = "steamcmd signs in with the account's name and password and asks its Steam Guard code once a device";
            source = "https://developer.valvesoftware.com/wiki/SteamCMD";
            checked = "2026-11-04";
          }
        ];
      };
      login = {
        item = "steam";
        email = "zach@mirazo.org";
      };
    };
  };
}
