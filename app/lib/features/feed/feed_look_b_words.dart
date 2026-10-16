import '../../core/article.dart';
import '../../l10n/app_localizations.dart';
import 'feed_filters.dart';

/// Design option B (#66), prototype: the words B needs that the app's .arb
/// files do not have yet. A prototype may edit only its own files, so they
/// live here; if B is chosen they move into lib/l10n/app_*.arb (`feedRead`)
/// and this file goes. Topic names are the app's own now ([topicName]).

/// What VoiceOver says after a card already opened.
const _readWord = {
  'en': 'Read',
  'uk': 'Прочитано',
  'ru': 'Прочитано',
  'es': 'Leído',
  'de': 'Gelesen',
};

String _language(AppLocalizations l10n) => l10n.localeName.split('_').first;

/// The topic a card names, in the app's language, or null when it has none:
/// [prefer] (the topic the feed is filtered by) when the article has it, so
/// a card never contradicts the Topics chip; otherwise its main topic. The
/// names are the app's (lib/l10n, the same as the Topics menu).
String? bTopicName(Article article, AppLocalizations l10n, {String? prefer}) {
  if (article.topics.isEmpty) return null;
  final id = prefer != null && article.topics.contains(prefer)
      ? prefer
      : article.topics.first;
  final name = topicName(id, l10n);
  // An id the app does not know yet: no topic rather than an English one.
  return name == id && _language(l10n) != 'en' ? null : name;
}

/// "Read", "Прочитано": VoiceOver's word for a card already opened.
String bReadWord(AppLocalizations l10n) =>
    _readWord[_language(l10n)] ?? _readWord['en']!;
