/// Local (city / municipal / occupational) income-tax rates for major US cities.
///
/// Applied on top of federal + state + FICA. Rates are flat approximations
/// applied to gross taxable wages. For informational use only — actual rates
/// vary by residency, income bracket, occupation and filing status.
class LocalTax {
  final String name;
  final double rate;
  final String? note;
  const LocalTax({required this.name, required this.rate, this.note});
}

/// Map of city-key → LocalTax. The key is referenced by [stateCities].
const Map<String, LocalTax> localTaxes = {
  'NYC': LocalTax(
    name: 'NYC Resident',
    rate: 0.03876,
    note: '3.078–3.876% bracket avg',
  ),
  'Yonkers': LocalTax(name: 'Yonkers', rate: 0.01683),
  'Philadelphia': LocalTax(
    name: 'Philadelphia (Wage Tax)',
    rate: 0.0375,
  ),
  'Pittsburgh': LocalTax(name: 'Pittsburgh', rate: 0.03),
  'Detroit': LocalTax(name: 'Detroit', rate: 0.024),
  'Cleveland': LocalTax(name: 'Cleveland', rate: 0.025),
  'Cincinnati': LocalTax(name: 'Cincinnati', rate: 0.018),
  'Columbus': LocalTax(name: 'Columbus', rate: 0.025),
  'Baltimore': LocalTax(name: 'Baltimore', rate: 0.032),
  'Birmingham': LocalTax(
    name: 'Birmingham (Occupational)',
    rate: 0.01,
  ),
  'St_Louis': LocalTax(name: 'St. Louis', rate: 0.01),
  'Kansas_City': LocalTax(name: 'Kansas City', rate: 0.01),
  'Wilmington': LocalTax(name: 'Wilmington DE', rate: 0.0125),
  'Newark': LocalTax(name: 'Newark', rate: 0.01),
};

/// Cities available per US state (state postal abbreviation → list of city keys).
const Map<String, List<String>> stateCities = {
  'NY': ['NYC', 'Yonkers'],
  'PA': ['Philadelphia', 'Pittsburgh'],
  'MI': ['Detroit'],
  'OH': ['Cleveland', 'Cincinnati', 'Columbus'],
  'MD': ['Baltimore'],
  'AL': ['Birmingham'],
  'MO': ['St_Louis', 'Kansas_City'],
  'DE': ['Wilmington'],
  'NJ': ['Newark'],
};

/// Whether the given US state has at least one city with a local-tax entry.
bool stateHasLocalTax(String stateCode) =>
    stateCities.containsKey(stateCode) && stateCities[stateCode]!.isNotEmpty;
