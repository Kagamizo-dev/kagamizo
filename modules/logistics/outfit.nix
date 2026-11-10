# The first order (the owner's choice, 2026-11-08): a fully wearable kit.
# A vest with many pockets, modular arm sleeves, a cloak over it all and
# quick-release carabiners: everything worn, never a backpack. Each garment
# is a specification, not a product: the pockets it must have (as the kit's
# slots, ../kit), the fabric it must be, what it must survive and weigh.
# checks.logistics proves the outfit carries every device the kit declares.
#
# Fibres are generic names (ISO 2076, 16 CFR 303); water resistance is the
# hydrostatic head in millimetres (ISO 811); fabric weight in grams per
# square metre (ISO 3801); webbing is PALS, rows 1 inch (25.4 mm) apart.
# Sizes wait on the owner's body measurements (ISO 8559-1), a gap.
{
  logistics = {
    # Where things land. Texas is home (family); the others are chosen by
    # their airports (direct flights, price, transit), a gap until flight
    # data is a typed source.
    regions = [
      "north-america"
      "south-america"
      "europe"
      "asia"
    ];
    hubs = {
      texas = {
        region = "north-america";
        airports = [
          "DFW"
          "IAH"
          "AUS"
        ];
        status = "home";
        why = "The owner's home and family; the US hub";
      };
      sao-paulo = {
        region = "south-america";
        airports = [
          "GRU"
          "VCP"
        ];
        status = "candidate";
        why = "South America's largest airport hub and Mercado Livre's and Correios's heart";
      };
      europe = {
        region = "europe";
        airports = [
          "MAD"
          "LHR"
          "FRA"
          "AMS"
          "IST"
        ];
        status = "candidate";
        why = "To be picked by direct flights to Texas, Sao Paulo and Asia; Madrid leads on Latin America";
      };
      pearl-river-delta = {
        region = "asia";
        airports = [
          "HKG"
          "SZX"
          "CAN"
        ];
        status = "candidate";
        why = "Next to the suppliers (Shenzhen, Guangzhou, Yiwu by rail): inspect, collect and ship from source";
      };
    };

    outfit = {
      # Worn as clothing: no slot holds this but the face itself.
      worn = [ "face" ];
      maxMassG = 3500;
      garments = {
        vest = {
          kind = "vest";
          pockets = {
            chest-pocket = 300;
            inner-pocket-left = 700;
            inner-pocket-right = 700;
          };
          extraPockets = 6;
          massG = 900;
          shell = {
            fibre = "polyamide";
            gsm = 330;
            denier = 500;
          };
          waterColumnMm = 1500;
          closures = [
            "zip"
            "hook-and-loop"
          ];
          attachment = "pals";
          condition = "new-or-secondhand";
          note = "A load-carrying vest that zips closed and fits under the cloak; inner pockets padded for the power bank and keyboard";
        };
        sleeve-left = {
          kind = "sleeve";
          pockets.sleeve-left = 150;
          extraPockets = 2;
          massG = 150;
          shell = {
            fibre = "polyamide";
            gsm = 200;
            denier = 210;
          };
          waterColumnMm = 1000;
          closures = [ "zip" ];
          attachment = "pals";
          condition = "new";
          note = "Forearm sleeve with modular pockets; the NFC tool rides here";
        };
        sleeve-right = {
          kind = "sleeve";
          pockets.sleeve-right = 150;
          extraPockets = 2;
          massG = 150;
          shell = {
            fibre = "polyamide";
            gsm = 200;
            denier = 210;
          };
          waterColumnMm = 1000;
          closures = [ "zip" ];
          attachment = "pals";
          condition = "new";
          note = "Forearm sleeve with modular pockets; the radio receiver rides here";
        };
        trousers = {
          kind = "trousers";
          pockets = {
            trouser-pocket-left = 450;
            trouser-pocket-right = 450;
          };
          extraPockets = 4;
          massG = 700;
          shell = {
            fibre = "polyamide";
            gsm = 220;
            denier = 0;
          };
          waterColumnMm = 800;
          closures = [ "zip" ];
          attachment = "none";
          condition = "new-or-secondhand";
          note = "Cargo trousers with zipped thigh pockets deep enough for the phone and the Pi";
        };
        belt = {
          kind = "belt";
          pockets.belt = 600;
          extraPockets = 2;
          massG = 250;
          shell = {
            fibre = "polyamide";
            gsm = 0;
            denier = 1000;
          };
          waterColumnMm = 0;
          closures = [ "buckle" ];
          attachment = "pals";
          condition = "new";
          note = "A 1.5 inch belt with PALS pouches and two carabiner loops for the gamepad and the Wi-Fi adapter";
        };
        cloak = {
          kind = "cloak";
          pockets = { };
          extraPockets = 2;
          massG = 900;
          shell = {
            fibre = "polyester";
            gsm = 150;
            denier = 75;
          };
          waterColumnMm = 5000;
          closures = [ "snap" ];
          attachment = "none";
          condition = "new-or-secondhand";
          note = "A hooded cloak or poncho over everything, cut long enough to cover the vest and belt";
        };
        carabiners = {
          kind = "hardware";
          pockets = { };
          extraPockets = 0;
          massG = 100;
          shell = {
            fibre = "none";
            gsm = 0;
            denier = 0;
          };
          waterColumnMm = 0;
          closures = [ "quick-release" ];
          attachment = "pals";
          condition = "new";
          note = "Four aluminium accessory carabiners, quick-release, for hanging and unhanging gear in a second (not for climbing)";
        };
      };
    };
  };
}
