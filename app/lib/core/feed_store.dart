import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'article.dart';
import 'feed_language.dart';

/// What the phone keeps between launches: the feed's language, the last first
/// page in each language, so the app opens instantly, and the articles already
/// opened, shown dimmed (by id, so in every language).
class FeedStore {
  FeedStore(this._prefs);

  static Future<FeedStore> open() async =>
      FeedStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _pageKey = 'feed.lastPage';
  static const _readKey = 'feed.readIds';
  static const _langKey = 'feed.lang';
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
