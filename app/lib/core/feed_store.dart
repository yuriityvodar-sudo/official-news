import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'article.dart';
import 'feed_language.dart';
import 'filters.dart';

/// What the phone keeps between launches: the feed's language and filters, the
/// last first page of the unfiltered feed in each language, so the app opens
/// instantly (offline too), the articles already opened, shown dimmed (by id,
/// so in every language), and the last menus of topics and countries in each
/// language, so the filters show their names at once.
class FeedStore {
  FeedStore(this._prefs);

  static Future<FeedStore> open() async =>
      FeedStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _pageKey = 'feed.lastPage';
  static const _readKey = 'feed.readIds';
  static const _langKey = 'feed.lang';
  static const _scopeKey = 'feed.scope';
  static const _countryKey = 'feed.country';
  static const _topicKey = 'feed.topic';
  static const _topicsKey = 'feed.topics';
  static const _countriesKey = 'feed.countries';
  static const _maxRead = 500;

  /// English keeps the key it had before there were languages: 'feed.lastPage'.
  static String _pageKeyFor(FeedLanguage lang) =>
      lang == FeedLanguage.en ? _pageKey : '$_pageKey.${lang.code}';

  /// The language chosen in Settings. Until one is chosen (the first launch),
  /// [phone]: the phone's language when the app has it, else English (#52).
  /// That one is not saved, so the app follows the phone until a choice is
  /// made. An unknown saved code reads as English, as before. [phone] has no
  /// default, so no caller reads English for a phone in another language;
  /// [FeedController.language] is the one value the app uses.
  FeedLanguage language({required FeedLanguage phone}) {
    final saved = _prefs.getString(_langKey);
    return saved == null ? phone : FeedLanguage.fromCode(saved);
  }

  Future<void> saveLanguage(FeedLanguage lang) =>
      _prefs.setString(_langKey, lang.code);

  ArticlesPage? lastPage([FeedLanguage lang = FeedLanguage.en]) {
    final raw = _prefs.getString(_pageKeyFor(lang));
    if (raw == null) return null;
    try {
      final page = ArticlesPage.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      // The first draft of #46 saved whatever came back, English too, under
      // 'feed.lastPage.uk' when the server had no translations yet.
      return lang == FeedLanguage.en ? page : page.inLanguage(lang.code);
    } catch (_) {
      return null; // an older or broken copy: start fresh
    }
  }

  Future<void> saveLastPage(
    ArticlesPage page, [
    FeedLanguage lang = FeedLanguage.en,
  ]) => _prefs.setString(_pageKeyFor(lang), jsonEncode(page.toJson()));

  /// Global or Local, Global until one is chosen (#68).
  FeedScope scope() => FeedScope.fromName(_prefs.getString(_scopeKey));

  Future<void> saveScope(FeedScope scope) =>
      _prefs.setString(_scopeKey, scope.name);

  /// The country chosen in Settings for Local; null until one is chosen, and
  /// Local follows the phone's region meanwhile.
  String? country() => _prefs.getString(_countryKey);

  Future<void> saveCountry(String code) => _prefs.setString(_countryKey, code);

  /// The one topic the feed shows, or null for all topics (#67).
  String? topic() => _prefs.getString(_topicKey);

  Future<void> saveTopic(String? id) =>
      id == null ? _prefs.remove(_topicKey) : _prefs.setString(_topicKey, id);

  /// The last Topics menu in [lang], so the chip and its names show at once
  /// on the next launch; null if none was saved.
  List<FeedTopic>? topics(FeedLanguage lang) {
    final raw = _prefs.getString('$_topicsKey.${lang.code}');
    if (raw == null) return null;
    try {
      return [
        for (final t in jsonDecode(raw) as List)
          FeedTopic(t['id'] as String, t['name'] as String),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Null forgets it: a server without topics.
  Future<void> saveTopics(FeedLanguage lang, List<FeedTopic>? list) =>
      list == null
      ? _prefs.remove('$_topicsKey.${lang.code}')
      : _prefs.setString(
          '$_topicsKey.${lang.code}',
          jsonEncode([for (final t in list) t.toJson()]),
        );

  /// The last list of countries in [lang], or null if none was saved.
  List<FeedCountry>? countries(FeedLanguage lang) {
    final raw = _prefs.getString('$_countriesKey.${lang.code}');
    if (raw == null) return null;
    try {
      return [
        for (final c in jsonDecode(raw) as List)
          FeedCountry(c['code'] as String, c['name'] as String),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCountries(FeedLanguage lang, List<FeedCountry> list) =>
      _prefs.setString(
        '$_countriesKey.${lang.code}',
        jsonEncode([for (final c in list) c.toJson()]),
      );

  Set<String> readIds() => (_prefs.getStringList(_readKey) ?? const []).toSet();

  Future<void> markRead(String id) async {
    final ids = _prefs.getStringList(_readKey) ?? <String>[];
    if (ids.contains(id)) return;
    ids.add(id);
    // Only the newest ones matter: the feed shows 7 days.
    await _prefs.setStringList(
      _readKey,
      ids.length > _maxRead ? ids.sublist(ids.length - _maxRead) : ids,
    );
  }
}
