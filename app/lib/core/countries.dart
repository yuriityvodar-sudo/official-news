import '../l10n/app_localizations.dart';

/// The name of a country code in the source list (docs/sources.csv), or of
/// another EU member, in the app's language (#52): "Germany", "Німеччина" for "DE". An unknown code is
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
  'US' => l10n.countryUS,
  'ZA' => l10n.countryZA,
  // The other EU members, for Settings → My country (#170).
  'AT' => l10n.countryAT,
  'BE' => l10n.countryBE,
  'BG' => l10n.countryBG,
  'CY' => l10n.countryCY,
  'DK' => l10n.countryDK,
  'EE' => l10n.countryEE,
  'FI' => l10n.countryFI,
  'GR' => l10n.countryGR,
  'HR' => l10n.countryHR,
  'HU' => l10n.countryHU,
  'IE' => l10n.countryIE,
  'LT' => l10n.countryLT,
  'LU' => l10n.countryLU,
  'LV' => l10n.countryLV,
  'MT' => l10n.countryMT,
  'NL' => l10n.countryNL,
  'PT' => l10n.countryPT,
  'RO' => l10n.countryRO,
  'SE' => l10n.countrySE,
  'SI' => l10n.countrySI,
  'SK' => l10n.countrySK,
  _ => code,
};

/// The EU's 27 members, as the server's `EU_MEMBERS` (server/src/api/filters.ts):
/// For you gives them the EU institutions' decisions too (#170).
final euMembers =
    ('AT BE BG CY CZ DE DK EE ES FI FR GR HR HU IE IT LT LU LV MT NL PL PT RO '
            'SE SI SK')
        .split(' ')
        .toSet();

/// The countries Settings → My country offers (#170): those For you can show
/// decisions of their own for (the source list) and the EU's members, whose
/// readers get the EU institutions' decisions too.
final homeCountries = {
  ...euMembers,
  ...'AR AU BR CA CN GB ID IN JP KR MX RU SA TR UA US ZA'.split(' '),
};
