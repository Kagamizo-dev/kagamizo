# Where the bank trades, and when (the owner's criterion, 2026-11-08: the
# bank is international, with something tradable around the clock). Each
# venue: the held account that reaches it (or what is missing), its classes
# of instrument, its weekly sessions in UTC, and whether it is active (traded
# or papered on) or planned. Researched on 2026-11-08 from the venues' own
# pages (each source below); hours are at the current standard time
# (US EST, Europe CET and GMT, Sydney AEDT) and move with daylight saving.
#
#   bank.venues.<v>      the venue
#   bank.treatments.<c>  each class's tax treatment, by the IRS's rules
#   bank.aroundTheClock  whether the bank requires every hour covered
#
#   checks.bank-venues   Lean (./_lean/Venues.lean): every class traded has
#                        a treatment; when required, every hour of the week
#                        has an active venue open
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.bank;
  q = builtins.toJSON;

  # Days 0 Monday .. 6 Sunday; times "HH:MM" UTC.
  minutesOf =
    t:
    let
      p = lib.splitString ":" t;
    in
    lib.toIntBase10 (lib.elemAt p 0) * 60 + lib.toIntBase10 (lib.elemAt p 1);
  # One session from (day, time) to (day, time), across midnights.
  span =
    d0: t0: d1: t1:
    let
      a = d0 * 1440 + minutesOf t0;
      b = d1 * 1440 + minutesOf t1;
    in
    {
      day = d0;
      start = minutesOf t0;
      minutes = if b > a then b - a else b + 10080 - a;
    };
  # The same session on each of several days.
  daily =
    days: t0: t1:
    map (d: span d t0 (if minutesOf t1 > minutesOf t0 then d else d + 1) t1) days;
  weekdays = [
    0
    1
    2
    3
    4
  ];
  allWeek = [ (span 0 "00:00" 0 "00:00") ];

  session = types.submodule {
    options = {
      day = mkOption { type = types.ints.between 0 6; };
      start = mkOption { type = types.ints.between 0 1439; };
      minutes = mkOption { type = types.ints.between 1 10080; };
    };
  };
  classes = [
    "equity"
    "option"
    "event-contract"
    "crypto"
    "crypto-future"
    "future-1256"
    "future-foreign"
    "forex"
  ];
  # The hours of the week (by their first minute) some active venue is
  # open: the same count Lean decides, shown on the Bank card.
  covers = s: m: lib.mod (m + 10080 - lib.mod (s.day * 1440 + s.start) 10080) 10080 < s.minutes;
  coveredHours =
    vs:
    lib.length (
      lib.filter (h: lib.any (v: v.active && lib.any (s: covers s (h * 60)) v.sessions) vs) (
        lib.range 0 167
      )
    );
  venue = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      account = mkOption {
        type = types.nullOr (types.enum (lib.attrNames config.accounts.held));
        default = null;
        description = "The held account that reaches it; null while one is still to be opened.";
      };
      needs = mkOption {
        type = types.str;
        default = "";
        description = "What is missing before it can be used.";
      };
      classes = mkOption { type = types.nonEmptyListOf (types.enum classes); };
      sessions = mkOption { type = types.listOf session; };
      active = mkOption {
        type = types.bool;
        description = "Traded or papered on today; a planned venue does not count toward the hours.";
      };
      source = mkOption { type = types.str; };
    };
  };
in
{
  options.bank = {
    venues = mkOption {
      type = types.attrsOf venue;
      default = { };
    };
    treatments = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };
    aroundTheClock = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the bank requires every hour of the week covered by an active venue (true once a 24/7 venue is active).";
    };
  };

  config = {
    bank.treatments = {
      equity = "capital gains: Form 8949 and Schedule D";
      option = "capital gains: Form 8949 and Schedule D (index options such as SPX are Section 1256 instead)";
      event-contract = "open: no IRS guidance found; the accountants' to settle";
      crypto = "property (IRS Notice 2014-21): Form 8949, reported to the IRS on Form 1099-DA";
      crypto-future = "arguably Section 1256 on a US exchange (Form 6781, 60/40); no IRS guidance found";
      future-1256 = "Section 1256: Form 6781, marked to market, 60% long-term and 40% short-term (US exchanges; ICE Futures Europe by Rev. Rul. 2007-26; Eurex by Rev. Rul. 2013-5)";
      future-foreign = "no IRS ruling for the exchange (OSE, SGX, HKEX, ASX): ordinary capital treatment, not Section 1256";
      forex = "Section 988: ordinary gain or loss";
    };

    bank.venues = {
      public-options = {
        name = "US options on Public";
        account = "public-mirazo";
        classes = [
          "equity"
          "option"
        ];
        sessions = daily weekdays "14:30" "21:00";
        active = true;
        source = "the US regular session, 09:30 to 16:00 New York time";
      };
      kalshi = {
        name = "Kalshi's event contracts on Public";
        account = "public-mirazo";
        classes = [ "event-contract" ];
        # Kalshi itself: always open but Thursday 08:00 to 10:00; Public's own
        # hours for it were not found.
        sessions = [ (span 3 "10:00" 3 "08:00") ];
        active = true;
        source = "https://docs.kalshi.com/getting_started/maintenance_and_pauses";
      };
      public-overnight = {
        name = "Eligible US stocks and ETFs, 24 hours a weekday, on Public";
        account = "public-mirazo";
        classes = [ "equity" ];
        sessions = [ (span 0 "01:00" 5 "01:00") ];
        active = false;
        needs = "the 24-hour session in our order types (equityMarketSession)";
        source = "https://public.com/learn";
      };
      kraken = {
        name = "Kraken: spot crypto and US perpetual futures";
        classes = [
          "crypto"
          "crypto-future"
        ];
        sessions = allWeek;
        active = false;
        needs = "a Kraken account (the owner's sign-up; passkey or authenticator, no SMS), and a key that trades without withdrawals";
        source = "https://docs.kraken.com/exchange/guides/rest/api-keys";
      };
      coinbase = {
        name = "Coinbase Advanced Trade and Coinbase Derivatives";
        classes = [
          "crypto"
          "crypto-future"
        ];
        sessions = allWeek;
        active = false;
        needs = "a Coinbase account (the owner's sign-up; check whether SMS must stay on beside the authenticator), and a view-and-trade key";
        source = "https://docs.cdp.coinbase.com";
      };
      cme = {
        name = "CME Globex futures through IBKR";
        account = "ibkr-jingzo";
        classes = [ "future-1256" ];
        sessions = [ (span 6 "23:00" 0 "22:00") ] ++ daily [ 0 1 2 3 ] "23:00" "22:00";
        active = false;
        needs = "IBKR's Gateway running on the host with its authenticator code in Proton Pass; its session resets nightly";
        source = "https://www.cmegroup.com";
      };
      eurex = {
        name = "Eurex futures (FDAX) through IBKR";
        account = "ibkr-jingzo";
        classes = [ "future-1256" ];
        sessions = daily weekdays "00:10" "21:00";
        active = false;
        needs = "IBKR's Gateway, as for CME";
        source = "https://www.eurex.com";
      };
      ice-europe = {
        name = "ICE Futures Europe (Brent) through IBKR";
        account = "ibkr-jingzo";
        classes = [ "future-1256" ];
        sessions = daily weekdays "01:00" "23:00";
        active = false;
        needs = "IBKR's Gateway, as for CME";
        source = "https://www.ice.com/products/219";
      };
      ose = {
        name = "Osaka Exchange (Nikkei 225 futures) through IBKR";
        account = "ibkr-jingzo";
        classes = [ "future-foreign" ];
        sessions = daily [ 6 0 1 2 3 ] "23:45" "06:45" ++ daily weekdays "08:00" "21:00";
        active = false;
        needs = "IBKR's Gateway, as for CME";
        source = "https://www.jpx.co.jp";
      };
      asx = {
        name = "ASX 24 (SPI 200 futures) through IBKR";
        account = "ibkr-jingzo";
        classes = [ "future-foreign" ];
        sessions = daily [ 6 0 1 2 3 ] "22:50" "05:30" ++ daily weekdays "06:10" "21:00";
        active = false;
        needs = "IBKR's Gateway, as for CME";
        source = "https://www.asx.com.au";
      };
      idealpro = {
        name = "Spot forex on IBKR's IDEALPRO";
        account = "ibkr-jingzo";
        classes = [ "forex" ];
        sessions = [ (span 6 "22:15" 0 "22:00") ] ++ daily [ 0 1 2 3 ] "22:15" "22:00";
        active = false;
        needs = "orders of about \$25,000 or more (smaller ones cost a pip), and IBKR's Gateway";
        source = "https://www.interactivebrokers.com/en/trading/forexOrderSize.php";
      };
    };

    shell.apps.bank.view = lib.mkAfter [
      {
        title = "Venues: ${toString (coveredHours (lib.attrValues cfg.venues))} of the week's 168 hours open now";
        rows = lib.mapAttrsToList (_: v: {
          title = "${v.name}: ${if v.active then "active" else "planned"}";
          detail = "${lib.concatStringsSep ", " (map (c: "${c} (${cfg.treatments.${c}})") v.classes)}${
            lib.optionalString (v.needs != "") "; needs ${v.needs}"
          }";
        }) cfg.venues;
      }
    ];

    perSystem =
      { config, ... }:
      {
        checks.bank-venues = config.kagamizo.leanCheck {
          name = "bank-venues";
          source = ./_lean/Venues.lean;
          facts = ''

            namespace Kagamizo.Venues
            def venues : List Venue := [${
              lib.concatStringsSep ",\n  " (
                lib.mapAttrsToList (
                  n: v:
                  "{ name := ${q n}, classes := ${q v.classes}, active := ${lib.boolToString v.active}, sessions := [${
                    lib.concatMapStringsSep ", " (
                      s: "{ day := ${toString s.day}, start := ${toString s.start}, minutes := ${toString s.minutes} }"
                    ) v.sessions
                  }] }"
                ) cfg.venues
              )
            }]
            def treatments : List String := ${q (lib.attrNames cfg.treatments)}

            theorem venues_sound : sound venues treatments ${lib.boolToString cfg.aroundTheClock} = true := by decide +kernel
            #eval coveredHours venues
            end Kagamizo.Venues
          '';
        };
      };
  };
}
