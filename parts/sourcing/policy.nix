# How offers are ranked. Stability first: an offer's stability is the worth of
# its inventory signal, decayed by the age of the observation, lowered by
# shallow stock and by prices that wander. Among offers above minStability,
# the most stable wins while it costs at most premiumPct more than the
# cheapest; past that, cost decides.
{
  sourcing = {
    policy = {
      fidelity = {
        fulfilled = 0.95; # the marketplace's own warehouse holds it
        quote = 0.9; # a carrier quoted it just now
        seller-stock = 0.7; # the seller says so
        capability = 0.6; # a registry lists the machine; ask before going
        observed = 0.55; # seen on a shelf, some days ago
        listed = 0.25; # the shop exists
      };
      halfLifeDays = 14;
      minStability = 0.35;
      premiumPct = 15;
      depthFull = 50;
      spreadPenalty = 2;
    };

    watch = {
      creatine = {
        query = "creatina monohidratada 300g";
        maxPrice = 150;
      };
      water = {
        query = "água mineral 5l";
        maxPrice = 20;
      };
    };

    outreach = {
      from = "sourcing@kagamizo.com";
      # The fleet's model (profiles/setup.nix): cheap, multilingual.
      model = "deepseek/deepseek-v4-flash";
      # Proton Bridge's local SMTP. `sourcing send` speaks STARTTLS to it.
      smtp = {
        host = "127.0.0.1";
        port = 1025;
      };
      signature = "Kagamizo\nsourcing@kagamizo.com";
    };
  };
}
