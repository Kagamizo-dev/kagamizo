# Where you are. Coordinates are city centres, public on purpose: the real
# delivery postcode is a secret (SOURCING_DELIVERY_POSTCODE, profile sourcing)
# and a precise position is given per command (--at). travelPerKm and
# unknownShipping are estimates for ranking, not prices anyone quoted.
{
  sourcing = {
    home = "sao-paulo";
    places.sao-paulo = {
      label = "São Paulo, SP";
      lat = -23.5505;
      lon = -46.6333;
      country = "BR";
      locale = "pt-BR";
      currency = "BRL";
      timeZone = "America/Sao_Paulo";
      postalCode = "01001000"; # Praça da Sé
      radiusKm = 8;
      travelPerKm = 2.5; # a ride-hailing trip, roughly
      unknownShipping = 25;
    };
  };
}
