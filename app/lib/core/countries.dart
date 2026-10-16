import '../l10n/app_localizations.dart';

/// The name of a country code in the source list (docs/sources.csv), in the
/// app's language (#52): "Germany", "Німеччина" for "DE". An unknown code is
/// shown as it is.
String countryName(String code, AppLocalizations l10n) => switch (code) {
  'AR' => l10n.countryAR,
  'AU' => l10n.countryAU,
  'BR' => l10n.countryBR,
  'CA' => l10n.countryCA,
  'CN' => l10n.countryCN,
  'CZ' => l10n.countryCZ,
  'DE' => l10n.countryDE,
  'EU' => l10n.countryEU,
  'ES' => l10n.countryES,
  'FR' => l10n.countryFR,
  'GB' => l10n.countryGB,
  'ID' => l10n.countryID,
  'IN' => l10n.countryIN,
  'IT' => l10n.countryIT,
  'JP' => l10n.countryJP,
  'KR' => l10n.countryKR,
  'MX' => l10n.countryMX,
  'PL' => l10n.countryPL,
  'RU' => l10n.countryRU,
  'SA' => l10n.countrySA,
  'TR' => l10n.countryTR,
  'UA' => l10n.countryUA,
  'UN' => l10n.countryUN,
  'US' => l10n.countryUS,
  'ZA' => l10n.countryZA,
  _ => code,
};
