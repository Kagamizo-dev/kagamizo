# Where each of Mercury's transaction categories lands on a return, for a
# business disregarded into its owner's 1040: Schedule C (Form 1040) Part II,
# by line (https://www.irs.gov/forms-pubs/about-schedule-c-form-1040). A
# category that can be either a business or a personal cost is `review`:
# the report lists it for a decision instead of guessing. On a personal
# account every outflow is personal, whatever its category.
let
  c = line: {
    kind = "schedule-c";
    inherit line;
  };
  review = why: {
    kind = "review";
    inherit why;
  };
  personal = why: {
    kind = "personal";
    inherit why;
  };
  nondeductible = why: {
    kind = "nondeductible";
    inherit why;
  };
in
{
  money.treatment = {
    Advertising = c "8";
    Airlines = c "24a";
    AlcoholAndBars = nondeductible "not a business meal by itself (IRC 274(k)); a business meal is Restaurants";
    BooksAndNewspaper = c "27a";
    CarRental = c "24a";
    Charity = personal "a gift is not a business expense; for an individual it is Schedule A";
    Clothing = personal "ordinary clothing is personal";
    Conferences = c "27a";
    Education = c "27a";
    Electronics = review "equipment: depreciated or expensed (line 13, Form 4562), or supplies (line 22)";
    Entertainment = nondeductible "entertainment is not deductible (IRC 274(a), since 2018)";
    FacilitiesExpenses = c "20b";
    Fees = c "10";
    FoodDelivery = review "a business meal (line 24b, 50%) or personal";
    FuelAndGas = c "9";
    Gambling = personal "not a business expense";
    GovernmentServices = c "23";
    Grocery = personal "groceries are personal";
    GroundTransportation = c "24a";
    Insurance = c "15";
    InternetAndTelephone = c "25";
    Legal = c "17";
    Lodging = c "24a";
    Medical = personal "for an individual, Schedule A or the self-employed health deduction, not Schedule C";
    Memberships = c "27a";
    OfficeSupplies = c "18";
    Other = review "no category: say what it was";
    OtherTravel = c "24a";
    Parking = c "9";
    Political = nondeductible "political spending is not deductible (IRC 162(e))";
    ProfessionalServices = c "17";
    Restaurants = c "24b" // {
      percent = 50;
    };
    Retail = review "supplies (line 22) or personal";
    RideshareAndTaxis = c "24a";
    Shipping = c "18";
    Software = c "18";
    Taxes = review "business taxes and licenses are line 23; federal income tax paid (1040-ES) is a credit on the 1040, not an expense";
    Utilities = c "25";
    VehicleExpenses = c "9";
  };
}
