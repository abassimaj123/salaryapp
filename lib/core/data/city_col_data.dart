/// Cost of Living index data — top 55 US cities.
/// Index: 100 = US national average.
/// Source: Numbeo / BLS regional price parity, 2025.
class CityColData {
  CityColData._();

  /// Returns CoL index for [cityName], or 100 (national avg) if unknown.
  static double indexFor(String cityName) => _colIndex[cityName] ?? 100.0;

  /// Adjust [salary] from [fromCity] to [toCity] purchasing power equivalent.
  /// e.g. $100k in NYC is equivalent to $53k in Memphis in purchasing power.
  static double adjust({
    required double salary,
    required String fromCity,
    required String toCity,
  }) {
    final from = indexFor(fromCity);
    final to = indexFor(toCity);
    if (from == 0) return salary;
    return salary * (to / from);
  }

  /// All available city names for dropdown.
  static List<String> get allCities => _colIndex.keys.toList()..sort();

  static const Map<String, double> _colIndex = {
    // California
    'San Francisco, CA': 176,
    'San Jose, CA': 183,
    'Oakland, CA': 172,
    'Los Angeles, CA': 163,
    'San Diego, CA': 160,
    'Sacramento, CA': 130,
    'Fresno, CA': 110,
    // New York
    'New York, NY': 187,
    'Buffalo, NY': 88,
    'Albany, NY': 100,
    // Washington
    'Seattle, WA': 152,
    'Spokane, WA': 94,
    // DC
    'Washington, DC': 165,
    // Massachusetts
    'Boston, MA': 162,
    'Worcester, MA': 118,
    // Hawaii
    'Honolulu, HI': 196,
    // Oregon
    'Portland, OR': 131,
    'Eugene, OR': 112,
    // Colorado
    'Denver, CO': 128,
    'Colorado Springs, CO': 109,
    // Alaska
    'Anchorage, AK': 132,
    // Illinois
    'Chicago, IL': 107,
    'Aurora, IL': 99,
    // New Jersey
    'Newark, NJ': 140,
    // Connecticut
    'Hartford, CT': 115,
    // Maryland
    'Baltimore, MD': 116,
    // Virginia
    'Richmond, VA': 101,
    'Virginia Beach, VA': 100,
    'Arlington, VA': 153,
    // Pennsylvania
    'Philadelphia, PA': 110,
    'Pittsburgh, PA': 91,
    // Texas
    'Austin, TX': 121,
    'Dallas, TX': 107,
    'Houston, TX': 96,
    'San Antonio, TX': 93,
    'Fort Worth, TX': 98,
    'El Paso, TX': 84,
    // Florida
    'Miami, FL': 123,
    'Tampa, FL': 105,
    'Orlando, FL': 100,
    'Jacksonville, FL': 98,
    'Fort Lauderdale, FL': 119,
    // Georgia
    'Atlanta, GA': 105,
    // North Carolina
    'Charlotte, NC': 100,
    'Raleigh, NC': 107,
    // Tennessee
    'Nashville, TN': 113,
    'Memphis, TN': 82,
    // Minnesota
    'Minneapolis, MN': 113,
    // Ohio
    'Columbus, OH': 92,
    'Cleveland, OH': 85,
    'Cincinnati, OH': 91,
    // Michigan
    'Detroit, MI': 94,
    'Grand Rapids, MI': 93,
    // Wisconsin
    'Milwaukee, WI': 97,
    // Missouri
    'Kansas City, MO': 91,
    'St. Louis, MO': 93,
    // Indiana
    'Indianapolis, IN': 91,
    // Pennsylvania
    'Allentown, PA': 99,
    // Nevada
    'Las Vegas, NV': 110,
    // Utah
    'Salt Lake City, UT': 110,
    // Arizona
    'Phoenix, AZ': 103,
    'Tucson, AZ': 96,
    // New Mexico
    'Albuquerque, NM': 92,
    // Oklahoma
    'Oklahoma City, OK': 87,
    // Kansas
    'Wichita, KS': 85,
    // Nebraska
    'Omaha, NE': 92,
    // Iowa
    'Des Moines, IA': 90,
    // Idaho
    'Boise, ID': 111,
    // Maine
    'Portland, ME': 122,
    // Vermont
    'Burlington, VT': 123,
    // New Hampshire
    'Manchester, NH': 117,
    // Rhode Island
    'Providence, RI': 118,
    // National average
    'National Average': 100,
  };
}
