import '../../l10n/app_localizations.dart';

/// Design option B (#66), prototype: the words B needs that the app's .arb
/// files do not have yet. A prototype may edit only its own files, so they
/// live here; if B is chosen they move into lib/l10n/app_*.arb (`feedRead`)
/// and this file goes. Topic names are the app's own now (`topicName`, shown
/// as the cards' topic tags, feed_topic_tags.dart).

/// What VoiceOver says after a card already opened.
const _readWord = {
  'en': 'Read',
  'uk': 'Прочитано',
  'ru': 'Прочитано',
  'es': 'Leído',
  'de': 'Gelesen',
};

String _language(AppLocalizations l10n) => l10n.localeName.split('_').first;

/// "Read", "Прочитано": VoiceOver's word for a card already opened.
String bReadWord(AppLocalizations l10n) =>
    _readWord[_language(l10n)] ?? _readWord['en']!;
