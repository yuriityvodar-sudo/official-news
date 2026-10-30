import '../l10n/app_localizations.dart';
import 'article.dart';

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
  // Sources about the whole world, such as Wikipedia's current events (#230).
  'WW' => l10n.countryWW,
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
/// decisions of their own for (the source list, docs/sources.csv) and the
/// EU's members, whose readers get the EU institutions' decisions too: 42.
/// Russia and Saudi Arabia have names but no sources (#42), so they are not
/// offered.
final homeCountries = {
  ...euMembers,
  ...'AR AU BR CA CN GB ID IN JP KR MX TR UA US ZA'.split(' '),
};

/// [name]'s place in the alphabet of [language], to sort country names as a
/// reader of it expects (Yurii, #206): a letter with a mark beside its own
/// ("Österreich" among the O's, "Bélgica" before "Bulgaria"), and Ukrainian
/// and Russian in their own alphabets' order (І after И, not before А).
String alphabetKey(String name, String language) {
  final alphabet = switch (language) {
    'uk' => 'абвгґдеєжзиіїйклмнопрстуфхцчшщьюя',
    'ru' => 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
    _ => '',
  };
  final key = StringBuffer();
  for (final char in name.toLowerCase().split('')) {
    final place = alphabet.indexOf(char);
    if (place >= 0) {
      key.writeCharCode(0x400 + place);
    } else {
      key.write(_withoutMark[char] ?? char);
    }
  }
  return key.toString();
}

const _withoutMark = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', 'é': 'e', //
  'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', //
  'ó': 'o', 'ô': 'o', 'ö': 'o', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ß': 'ss', //
};

/// The country a card or an article names (#230): the source's; for an
/// event, whose source is the whole world, the country it concerns most, or
/// "World" when the app has no name for it (an event in Yemen).
String placeName(Article article, AppLocalizations l10n) {
  if (article.isEvent && article.countries.isNotEmpty) {
    final code = article.countries.first;
    final name = countryName(code, l10n);
    if (name != code) return name;
  }
  return countryName(article.country, l10n);
}
