# A secretspec secret: what it is and the Proton Pass item title it lives
# under (the vault comes from its profile's or its own `providers`).
description: item: {
  inherit description;
  ref.item = item;
}
