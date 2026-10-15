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

  /// The last "load more" failed (offline); the end of the list offers a retry instead of retrying on every scroll.
  bool loadMoreFailed = false;

  /// Bumped by every refresh, so a page that was still loading for an older feed is dropped.
  int _generation = 0;
  bool _disposed = false;

  bool get hasMore => _cursor != null;

  @override
  void notifyListeners() {
    // A request can finish after the screen has gone away.
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Shows the feed saved on the phone at once, then asks for the fresh one.
  Future<void> start() async {
    _store = await _openStore();
    // Articles opened before the store was ready are kept and saved now.
    final stored = _store!.readIds();
    for (final id in readIds.difference(stored)) {
      await _store!.markRead(id);
    }
    readIds = {...stored, ...readIds};
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

  /// The next page; `retry` is the user tapping "Try again" after a failure.
  Future<void> loadMore({bool retry = false}) async {
    final cursor = _cursor;
    if (cursor == null || loadingMore || (loadMoreFailed && !retry)) return;
    final generation = _generation;
    loadingMore = true;
    loadMoreFailed = false;
    notifyListeners();
    try {
      final page = await api.fetchArticles(cursor: cursor);
      if (generation != _generation) {
        return; // a refresh replaced the feed meanwhile
      }
      final known = items.map((a) => a.id).toSet();
      items = [...items, ...page.items.where((a) => !known.contains(a.id))];
      _cursor = page.nextCursor;
    } catch (_) {
      if (generation == _generation) loadMoreFailed = true;
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  /// Counts articles that appeared after the newest one shown (called every few minutes).
  /// Asks by feed position, so one that appeared late is counted too.
  Future<void> checkForNew() async {
    if (items.isEmpty) return;
    final highest = items
        .map((a) => a.feedSeq ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    try {
      final page = highest > 0
          ? await api.fetchArticles(after: highest, limit: 50)
          // A feed saved before the server numbered articles: the older check.
          : await api.fetchArticles(since: items.first.publishedAt, limit: 50);
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
    _generation++;
    loadMoreFailed = false;
    top = page.top;
    items = page.items;
    _cursor = page.nextCursor;
  }
}
