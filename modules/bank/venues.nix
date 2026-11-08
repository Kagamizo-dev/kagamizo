# Where the bank trades, and when (the owner's criterion, 2026-11-08: the
# bank is international, with something tradable around the clock). Each
# venue: the held account that reaches it (or what is missing), its classes
# of instrument, its weekly sessions in its exchange's own time zone, and
# whether it is active (traded or papered on) or planned. Researched on
# 2026-11-08 from the venues' own pages (each source below). Sessions turn
# into UTC week by week by each zone's daylight-saving rule (the US, the EU
# and UK, New South Wales; Japan, Singapore and Hong Kong have none), and Lean
# checks seven reference weeks, the ones where the US and Europe disagree
# among them.
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

  # Times "HH:MM" in a zone's local time; days 0 Monday .. 6 Sunday.
  minutesOf =
    t:
    let
      p = lib.splitString ":" t;
    in
    lib.toIntBase10 (lib.elemAt p 0) * 60 + lib.toIntBase10 (lib.elemAt p 1);
  # One session from (day, time) to (day, time) in a zone, across midnights.
  span =
    zone: d0: t0: d1: t1:
    let
      a = d0 * 1440 + minutesOf t0;
      b = d1 * 1440 + minutesOf t1;
    in
    {
      inherit zone;
      day = d0;
      start = minutesOf t0;
      minutes = if b > a then b - a else b + 10080 - a;
    };
  # The same session on each of several days.
  daily =
    zone: days: t0: t1:
    map (d: span zone d t0 (if minutesOf t1 > minutesOf t0 then d else d + 1) t1) days;
  weekdays = [
    0
    1
    2
    3
    4
  ];
  sundayToThursday = [
    6
    0
    1
    2
    3
  ];
  allWeek = [ (span "UTC" 0 "00:00" 0 "00:00") ];

  # Daylight saving, by each region's rule: the US from the second Sunday of
  # March to the first of November; the EU and the UK from the last Sunday of
  # March to the last of October; New South Wales from the first Sunday of
  # October to the first of April; Japan, Singapore and Hong Kong never. A
  # rule changes on a Sunday, so one offset holds for a Monday-to-Sunday week.
  weekday =
    y: m: d:
    let
      t = [
        0
        3
        2
        5
        0
        3
        5
        1
        4
        6
        2
        4
      ];
      y' = if m < 3 then y - 1 else y;
    in
    lib.mod (y' + y' / 4 - y' / 100 + y' / 400 + lib.elemAt t (m - 1) + d) 7;
  daysIn =
    y: m:
    if m == 2 then
      (if (lib.mod y 4 == 0 && lib.mod y 100 != 0) || lib.mod y 400 == 0 then 29 else 28)
    else if
      lib.elem m [
        4
        6
        9
        11
      ]
    then
      30
    else
      31;
  nthSunday =
    y: m: n:
    1 + lib.mod (7 - weekday y m 1) 7 + 7 * (n - 1);
  lastSunday = y: m: daysIn y m - weekday y m (daysIn y m);
  num =
    y: m: d:
    y * 10000 + m * 100 + d;
  dst =
    rule: date:
    let
      p = map lib.toIntBase10 (lib.splitString "-" date);
      y = lib.elemAt p 0;
      at = num y (lib.elemAt p 1) (lib.elemAt p 2);
    in
    if rule == "us" then
      at >= num y 3 (nthSunday y 3 2) && at < num y 11 (nthSunday y 11 1)
    else if rule == "eu" then
      at >= num y 3 (lastSunday y 3) && at < num y 10 (lastSunday y 10)
    else if rule == "au" then
      at >= num y 10 (nthSunday y 10 1) || at < num y 4 (nthSunday y 4 1)
    else
      false;
  # Each zone's offset from UTC in minutes: standard, and its daylight rule.
  zones = {
    "UTC" = [
      0
      "none"
    ];
    "America/New_York" = [
      (-300)
      "us"
    ];
    "America/Chicago" = [
      (-360)
      "us"
    ];
    "Europe/London" = [
      0
      "eu"
    ];
    "Europe/Berlin" = [
      60
      "eu"
    ];
    "Asia/Tokyo" = [
      540
      "none"
    ];
    "Asia/Singapore" = [
      480
      "none"
    ];
    "Asia/Hong_Kong" = [
      480
      "none"
    ];
    "Australia/Sydney" = [
      600
      "au"
    ];
  };
  offset =
    zone: date:
    let
      z = zones.${zone};
    in
    lib.elemAt z 0 + (if dst (lib.elemAt z 1) date then 60 else 0);
  # A session in UTC, for the week of a date.
  utc =
    date: s:
    let
      m = lib.mod (s.day * 1440 + s.start - offset s.zone date + 2 * 10080) 10080;
    in
    {
      day = m / 1440;
      start = lib.mod m 1440;
      inherit (s) minutes;
    };
  # The reference weeks Lean checks (their Mondays): winter, the weeks the US
  # and Europe disagree in March and in October/November, summer, and the
  # week Sydney's daylight time begins.
  weeks = [
    "2026-01-12"
    "2026-03-16"
    "2026-04-13"
    "2026-07-13"
    "2026-10-05"
    "2026-10-26"
    "2026-11-02"
  ];

  # The venues as Lean reads them, their sessions in UTC for one week.
  venuesAt =
    w:
    lib.concatStringsSep ",\n  " (
      lib.mapAttrsToList (
        n: v:
        "{ name := ${q n}, classes := ${q v.classes}, active := ${lib.boolToString v.active}, sessions := [${
          lib.concatMapStringsSep ", " (
            s:
            let
              u = utc w s;
            in
            "{ day := ${toString u.day}, start := ${toString u.start}, minutes := ${toString u.minutes} }"
          ) v.sessions
        }] }"
      ) cfg.venues
    );

  session = types.submodule {
    options = {
      zone = mkOption { type = types.enum (lib.attrNames zones); };
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
    date: vs:
    lib.length (
      lib.filter (h: lib.any (v: v.active && lib.any (s: covers (utc date s) (h * 60)) v.sessions) vs) (
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
        sessions = daily "America/New_York" weekdays "09:30" "16:00";
        active = true;
        source = "the US regular session, 09:30 to 16:00 New York time";
      };
      kalshi = {
        name = "Kalshi's event contracts on Public";
        account = "public-mirazo";
        classes = [ "event-contract" ];
        # Kalshi itself: always open but Thursday 08:00 to 10:00; Public's own
        # hours for it were not found.
        sessions = [ (span "America/New_York" 3 "05:00" 3 "03:00") ];
        active = true;
        source = "https://docs.kalshi.com/getting_started/maintenance_and_pauses";
      };
      public-overnight = {
        name = "Eligible US stocks and ETFs, 24 hours a weekday, on Public";
        account = "public-mirazo";
        classes = [ "equity" ];
        sessions = [ (span "America/New_York" 6 "20:00" 4 "20:00") ];
        active = false;
        needs = "the 24-hour session in our order types (equityMarketSession)";
        source = "https://public.com/learn";
      };
      public-crypto = {
        name = "Crypto on Public, around the clock";
        account = "public-mirazo";
        classes = [ "crypto" ];
        # Always open but a daily pause of about 22:30 to 23:05 UTC (Public's
        # help centre, read from a search snippet; to confirm on the page).
        sessions = daily "UTC" [
          0
          1
          2
          3
          4
          5
          6
        ] "23:05" "22:30";
        active = false;
        needs = "crypto orders in our Public client (the API takes them); fees from 0.60% a trade at low volume; the daily pause confirmed on Public's own page";
        source = "https://public.com/api/docs/changelog";
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
        sessions = daily "America/Chicago" sundayToThursday "17:00" "16:00";
        active = false;
        needs = "IBKR's Gateway running on the host with its authenticator code in Proton Pass; its session resets nightly";
        source = "https://www.cmegroup.com";
      };
      eurex = {
        name = "Eurex futures (FDAX) through IBKR";
        account = "ibkr-jingzo";
        classes = [ "future-1256" ];
        sessions = daily "Europe/Berlin" weekdays "01:10" "22:00";
        active = false;
        needs = "IBKR's Gateway, as for CME";
        source = "https://www.eurex.com";
      };
      ice-europe = {
        name = "ICE Futures Europe (Brent) through IBKR";
        account = "ibkr-jingzo";
        classes = [ "future-1256" ];
        sessions = daily "Europe/London" weekdays "01:00" "23:00";
        active = false;
        needs = "IBKR's Gateway, as for CME";
        source = "https://www.ice.com/products/219";
      };
      ose = {
        name = "Osaka Exchange (Nikkei 225 futures) through IBKR";
        account = "ibkr-jingzo";
        classes = [ "future-foreign" ];
        # The day session and the night session, Tokyo time.
        sessions =
          daily "Asia/Tokyo" weekdays "08:45" "15:45" ++ daily "Asia/Tokyo" weekdays "17:00" "06:00";
        active = false;
        needs = "IBKR's Gateway, as for CME";
        source = "https://www.jpx.co.jp";
      };
      asx = {
        name = "ASX 24 (SPI 200 futures) through IBKR";
        account = "ibkr-jingzo";
        classes = [ "future-foreign" ];
        # The day session and the night session, Sydney time.
        sessions =
          daily "Australia/Sydney" weekdays "09:50" "16:30"
          ++ daily "Australia/Sydney" weekdays "17:10" "08:00";
        active = false;
        needs = "IBKR's Gateway, as for CME";
        source = "https://www.asx.com.au";
      };
      idealpro = {
        name = "Spot forex on IBKR's IDEALPRO";
        account = "ibkr-jingzo";
        classes = [ "forex" ];
        sessions = daily "America/New_York" sundayToThursday "17:15" "17:00";
        active = false;
        needs = "orders of about \$25,000 or more (smaller ones cost a pip), and IBKR's Gateway";
        source = "https://www.interactivebrokers.com/en/trading/forexOrderSize.php";
      };
    };

    shell.apps.bank.view = lib.mkAfter [
      {
        title = "Venues: ${toString (coveredHours cfg.asOf (lib.attrValues cfg.venues))} of the week's 168 hours open, the week of ${cfg.asOf}";
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
            def treatments : List String := ${q (lib.attrNames cfg.treatments)}
            ${lib.concatImapStrings (i: w: ''
              /-- The week of ${w}, in UTC. -/
              def week${toString i} : List Venue := [${venuesAt w}]
              theorem venues_sound_${toString i} : sound week${toString i} treatments ${lib.boolToString cfg.aroundTheClock} = true := by decide +kernel
              #eval coveredHours week${toString i}
            '') weeks}
            end Kagamizo.Venues
          '';
        };
      };
  };
}
