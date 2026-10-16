import '../l10n/app_localizations.dart';

/// Country names in the app's language (#52): "Germany", "Німеччина" for
/// "DE". The source countries (docs/sources.csv) and the EU, plus Ukraine and
/// every EU member, so any of them can be Local's country (#68) with its name
/// on the chip, also before `GET /countries` answers or when the region has
/// no sources of its own. The names are the server's (`COUNTRIES` in
/// server/src/api/filters.ts) where it has them.
final Map<String, String Function(AppLocalizations)> _names = {
  'AR': (l) => l.countryAR,
  'AT': (l) => l.countryAT,
  'AU': (l) => l.countryAU,
  'BE': (l) => l.countryBE,
  'BG': (l) => l.countryBG,
  'BR': (l) => l.countryBR,
  'CA': (l) => l.countryCA,
  'CN': (l) => l.countryCN,
  'CY': (l) => l.countryCY,
  'CZ': (l) => l.countryCZ,
  'DE': (l) => l.countryDE,
  'DK': (l) => l.countryDK,
  'EE': (l) => l.countryEE,
  'ES': (l) => l.countryES,
  'EU': (l) => l.countryEU,
  'FI': (l) => l.countryFI,
  'FR': (l) => l.countryFR,
  'GB': (l) => l.countryGB,
  'GR': (l) => l.countryGR,
  'HR': (l) => l.countryHR,
  'HU': (l) => l.countryHU,
  'ID': (l) => l.countryID,
  'IE': (l) => l.countryIE,
  'IN': (l) => l.countryIN,
  'IT': (l) => l.countryIT,
  'JP': (l) => l.countryJP,
  'KR': (l) => l.countryKR,
  'LT': (l) => l.countryLT,
  'LU': (l) => l.countryLU,
  'LV': (l) => l.countryLV,
  'MT': (l) => l.countryMT,
  'MX': (l) => l.countryMX,
  'NL': (l) => l.countryNL,
  'PL': (l) => l.countryPL,
  'PT': (l) => l.countryPT,
  'RO': (l) => l.countryRO,
  'RU': (l) => l.countryRU,
  'SA': (l) => l.countrySA,
  'SE': (l) => l.countrySE,
  'SI': (l) => l.countrySI,
  'SK': (l) => l.countrySK,
  'TR': (l) => l.countryTR,
  'UA': (l) => l.countryUA,
  'US': (l) => l.countryUS,
  'ZA': (l) => l.countryZA,
};

/// [code]'s name in the app's language; an unknown code is shown as it is.
String countryName(String code, AppLocalizations l10n) =>
    _names[code]?.call(l10n) ?? code;

/// Whether the app has a name for [code] in every language.
bool hasCountryName(String code) => _names.containsKey(code);
