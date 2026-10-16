/// English names for the country codes in the source list (docs/sources.csv).
const _names = {
  'AR': 'Argentina',
  'AU': 'Australia',
  'BR': 'Brazil',
  'CA': 'Canada',
  'CN': 'China',
  'CZ': 'Czechia',
  'DE': 'Germany',
  'ES': 'Spain',
  'EU': 'European Union',
  'FR': 'France',
  'GB': 'United Kingdom',
  'ID': 'Indonesia',
  'IN': 'India',
  'IT': 'Italy',
  'JP': 'Japan',
  'KR': 'South Korea',
  'MX': 'Mexico',
  'PL': 'Poland',
  'RU': 'Russia',
  'SA': 'Saudi Arabia',
  'TR': 'Türkiye',
  'UA': 'Ukraine',
  'US': 'United States',
  'ZA': 'South Africa',
};

/// "Germany" for "DE"; an unknown code is shown as it is.
String countryName(String code) => _names[code] ?? code;
