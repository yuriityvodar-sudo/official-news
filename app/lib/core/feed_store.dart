import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'article.dart';

/// What the phone keeps between launches: the last first page of the feed, so
/// the app opens instantly, and the articles already opened, shown dimmed.
class FeedStore {
  FeedStore(this._prefs);

  static Future<FeedStore> open() async =>
      FeedStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _pageKey = 'feed.lastPage';
  static const _readKey = 'feed.readIds';
  static const _maxRead = 500;

  ArticlesPage? lastPage() {
    final raw = _prefs.getString(_pageKey);
    if (raw == null) return null;
    try {
      return ArticlesPage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // an older or broken copy: start fresh
    }
  }

  Future<void> saveLastPage(ArticlesPage page) =>
      _prefs.setString(_pageKey, jsonEncode(page.toJson()));

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
