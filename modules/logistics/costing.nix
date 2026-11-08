# What a thing should cost, and how a supplier is asked for it (the owner's
# direction, 2026-11-08): the bill of materials, the machine time and the
# labour are worked out first, so every quote is negotiated against a
# should-cost, and quality is part of the request (an inspection plan),
# not a later hope. Requests go to a supplier's own channel: its quoting
# API where it has one, otherwise email from the owner's address.
#
# A rate stays null until a source prices it: labour from ILOSTAT's
# garment-manufacturing wages, materials and machine hours from suppliers'
# quotes. Nothing here is a price we have seen.
let
  pending = unit: {
    inherit unit;
    evidence = "pending";
  };
  labour = {
    unit = "hour";
    source = "https://ilostat.ilo.org/data/";
    evidence = "pending";
  };
in
{
  logistics = {
    quotes = {
      premiumPct = 15;
      incoterm = "DDP";
      inspection = {
        level = "II";
        majorAql = "2.5";
        minorAql = "4.0";
      };
    };

    rates = {
      nylon-500d-m2 = pending "m2";
      polyester-mesh-m2 = pending "m2";
      webbing-25mm-m = pending "m";
      hook-and-loop-25mm-m = pending "m";
      coil-zip-5 = pending "piece";
      buckle-25mm = pending "piece";
      bonded-nylon-thread-m = pending "m";
      care-label = pending "piece";
      cutting-table-hour = pending "hour";
      lockstitch-hour = pending "hour";
      bartack-hour = pending "hour";
      inspection-bench-hour = pending "hour";
      sewing-labour-hour = labour;
      cutting-labour-hour = labour;
      inspection-labour-hour = labour;
    };

    # The vest first: estimates from its specification until a pattern's
    # marker measures the fabric.
    outfit.garments.vest.bom = {
      quantity = 2;
      materials = [
        {
          name = "shell, nylon 500D";
          rate = "nylon-500d-m2";
          qty = 1.2;
          basis = "estimate";
        }
        {
          name = "lining, polyester mesh";
          rate = "polyester-mesh-m2";
          qty = 0.8;
          basis = "estimate";
        }
        {
          name = "PALS webbing, 25 mm";
          rate = "webbing-25mm-m";
          qty = 6;
          basis = "estimate";
        }
        {
          name = "hook-and-loop, 25 mm";
          rate = "hook-and-loop-25mm-m";
          qty = 0.6;
          basis = "estimate";
        }
        {
          name = "coil zips, size 5";
          rate = "coil-zip-5";
          qty = 5;
          basis = "estimate";
        }
        {
          name = "side-release buckles, 25 mm";
          rate = "buckle-25mm";
          qty = 2;
          basis = "estimate";
        }
        {
          name = "bonded nylon thread";
          rate = "bonded-nylon-thread-m";
          qty = 150;
          basis = "estimate";
        }
        {
          name = "care and fibre label (16 CFR 303, ISO 3758)";
          rate = "care-label";
          qty = 1;
          basis = "estimate";
        }
      ];
      operations = [
        {
          name = "cut";
          machine = "cutting-table-hour";
          labour = "cutting-labour-hour";
          minutes = 12;
        }
        {
          name = "sew";
          machine = "lockstitch-hour";
          labour = "sewing-labour-hour";
          minutes = 55;
        }
        {
          name = "bartack the load points";
          machine = "bartack-hour";
          labour = "sewing-labour-hour";
          minutes = 8;
        }
        {
          name = "inspect and pack";
          machine = "inspection-bench-hour";
          labour = "inspection-labour-hour";
          minutes = 6;
        }
      ];
    };
  };
}
