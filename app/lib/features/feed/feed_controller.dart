import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/feed_store.dart';

/// The feed's state: articles, paging, errors, read articles and the check for
/// new ones. The screen only draws it.
class FeedController extends ChangeNotifier {
  FeedController({ApiClient? api, Future<FeedStore> Function()? openStore})
    : api = api ?? ApiClient(),
      _openStore = openStore ?? FeedStore.open;

  final ApiClient api;
  final Future<FeedStore> Function() _openStore;
  FeedStore? _store;

  /// "Top stories": the API's `top`, only on the first page.
  List<Article> top = const [];

  /// Every article loaded so far, newest first (top articles are in here too).
  List<Article> items = const [];
  String? _cursor;
  Set<String> readIds = {};

  /// True while there is nothing to show yet.
  bool loading = true;
  bool loadingMore = false;

  /// The last refresh failed; the saved or earlier feed may still be shown.
  Object? error;

  /// Newer articles waiting on the server, shown as a pill instead of moving the list.
  int newCount = 0;

  bool get hasMore => _cursor != null;

  /// Shows the feed saved on the phone at once, then asks for the fresh one.
  Future<void> start() async {
    _store = await _openStore();
    readIds = _store!.readIds();
    final saved = _store!.lastPage();
    if (saved != null) {
      _show(saved);
      loading = false;
      notifyListeners();
    }
    await refresh();
  }

  Future<void> refresh() async {
    error = null;
    notifyListeners();
    try {
      final page = await api.fetchArticles();
      _show(page);
      newCount = 0;
      unawaited(_store?.saveLastPage(page));
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (cursor == null || loadingMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await api.fetchArticles(cursor: cursor);
      final known = items.map((a) => a.id).toSet();
      items = [...items, ...page.items.where((a) => !known.contains(a.id))];
      _cursor = page.nextCursor;
    } catch (_) {
      // The cursor stays, so the next scroll to the end tries again.
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  /// Counts articles newer than the newest one shown (called every few minutes).
  Future<void> checkForNew() async {
    if (items.isEmpty) return;
    try {
      final page = await api.fetchArticles(
        since: items.first.publishedAt,
        limit: 50,
      );
      final known = items.map((a) => a.id).toSet();
      final count = page.items.where((a) => !known.contains(a.id)).length;
      if (count != newCount) {
        newCount = count;
        notifyListeners();
      }
    } catch (_) {
      // Offline for a moment: try again at the next check.
    }
  }

  Future<void> markRead(Article article) async {
    if (!readIds.add(article.id)) return;
    notifyListeners();
    await _store?.markRead(article.id);
  }

  void _show(ArticlesPage page) {
    top = page.top;
    items = page.items;
    _cursor = page.nextCursor;
  }
}
