import '../../core/article.dart';
import '../../core/topics.dart';
import '../../l10n/app_localizations.dart';
import 'feed_filters.dart';

/// Design option B (#66), prototype: the words B needs that the app's .arb
/// files do not have yet. A prototype may edit only its own files, so they
/// live here; if B is chosen they move into lib/l10n/app_*.arb (one key per
/// topic and `feedRead`) and this file goes.

/// The topic names in the app's five languages, by topic id.
const _topicWords = <String, Map<String, String>>{
  'uk': {
    'foreign-affairs': 'Зовнішня політика',
    'economy': 'Економіка',
    'security-defence': 'Безпека та оборона',
    'health': 'Охорона здоров’я',
    'climate': 'Клімат',
    'trade': 'Торгівля',
    'technology': 'Технології',
    'energy': 'Енергетика',
    'migration': 'Міграція',
    'elections': 'Вибори',
    'human-rights': 'Права людини',
    'science': 'Наука',
  },
  'ru': {
    'foreign-affairs': 'Внешняя политика',
    'economy': 'Экономика',
    'security-defence': 'Безопасность и оборона',
    'health': 'Здравоохранение',
    'climate': 'Климат',
    'trade': 'Торговля',
    'technology': 'Технологии',
    'energy': 'Энергетика',
    'migration': 'Миграция',
    'elections': 'Выборы',
    'human-rights': 'Права человека',
    'science': 'Наука',
  },
  'es': {
    'foreign-affairs': 'Asuntos exteriores',
    'economy': 'Economía',
    'security-defence': 'Seguridad y defensa',
    'health': 'Salud',
    'climate': 'Clima',
    'trade': 'Comercio',
    'technology': 'Tecnología',
    'energy': 'Energía',
    'migration': 'Migración',
    'elections': 'Elecciones',
    'human-rights': 'Derechos humanos',
    'science': 'Ciencia',
  },
  'de': {
    'foreign-affairs': 'Außenpolitik',
    'economy': 'Wirtschaft',
    'security-defence': 'Sicherheit und Verteidigung',
    'health': 'Gesundheit',
    'climate': 'Klima',
    'trade': 'Handel',
    'technology': 'Technologie',
    'energy': 'Energie',
    'migration': 'Migration',
    'elections': 'Wahlen',
    'human-rights': 'Menschenrechte',
    'science': 'Wissenschaft',
  },
};

/// What VoiceOver says after a card already opened.
const _readWord = {
  'en': 'Read',
  'uk': 'Прочитано',
  'ru': 'Прочитано',
  'es': 'Leído',
  'de': 'Gelesen',
};

String _language(AppLocalizations l10n) => l10n.localeName.split('_').first;

/// The article's main topic in the app's language, or null when it has none.
String? bTopicName(Article article, AppLocalizations l10n) {
  if (article.topics.isEmpty) return null;
  final id = article.topics.first;
  final language = _language(l10n);
  if (language == 'en') return topicNames[id] ?? topicLabel(id);
  // An id the app does not know yet: no topic rather than an English one.
  return _topicWords[language]?[id];
}

/// "Read", "Прочитано": VoiceOver's word for a card already opened.
String bReadWord(AppLocalizations l10n) =>
    _readWord[_language(l10n)] ?? _readWord['en']!;
