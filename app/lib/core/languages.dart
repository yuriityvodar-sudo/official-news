import '../l10n/app_localizations.dart';

/// The name of a source's language (docs/sources.csv) as it reads in "Summary
/// by AI · translated from German", in the app's language (#52): the form
/// after "from", so "німецької" in Ukrainian and "Deutschen" in German. An
/// unknown code is shown in capitals, as it is.
String languageName(String code, AppLocalizations l10n) => switch (code) {
  'ar' => l10n.languageAr,
  'de' => l10n.languageDe,
  'en' => l10n.languageEn,
  'es' => l10n.languageEs,
  'fr' => l10n.languageFr,
  'hi' => l10n.languageHi,
  'id' => l10n.languageId,
  'it' => l10n.languageIt,
  'ja' => l10n.languageJa,
  'ko' => l10n.languageKo,
  'pl' => l10n.languagePl,
  'pt' => l10n.languagePt,
  'ru' => l10n.languageRu,
  'tr' => l10n.languageTr,
  'uk' => l10n.languageUk,
  'zh' => l10n.languageZh,
  _ => code.toUpperCase(),
};
