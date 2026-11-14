# research-jingzo: grounded data sources, typed

Read CLAUDE.md first. Kind: strategy.

The owner's direction of 2026-11-06: trade only contracts whose outcome is a grounded, published fact, and read the facts from APIs that publish them.

1. `trading.sources.<name>` = { kind (an enum: weather, flight, satellite, climate, economic); url; auth (an enum: none, key); account (null, or a declared account); license; grounds: the contract series it settles; cadence }.
2. Prefer sources that need no account. Candidates:
   - weather: the National Weather Service and Open-Meteo;
   - flights: the OpenSky Network;
   - satellite: NASA FIRMS, NOAA GOES and Copernicus open data.

   Read each one's terms and record them.
3. Lean:
   - every strategy's signals come from declared sources;
   - every contract it trades settles on one of them;
   - every source that needs a key has a declared account and secret.
4. A source that needs a sign-up is a request to the owner, sent as a link (upkeep/account-links).
