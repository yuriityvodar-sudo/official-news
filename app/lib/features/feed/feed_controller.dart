import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/feed_store.dart';

/// The feed's state: its language, articles, paging, errors, read articles and
/// the check for new ones. The screen only draws it.
class FeedController extends ChangeNotifier {
  FeedController({ApiClient? api, Future<FeedStore> Function()? openStore})
    : api = api ?? ApiClient(),
      _openStore = openStore ?? FeedStore.open;

  final ApiClient api;
  final Future<FeedStore> Function() _openStore;
  FeedStore? _store;

  /// The language the feed is read in (#46), saved on the phone. Each language is
  /// its own feed on the server: its own order, pages and feed positions.
  FeedLanguage language = FeedLanguage.en;

  /// False until the saved language is read, so the header never shows English first.
  bool languageKnown = false;

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

  /// Bumped whenever the shown feed is replaced (a refresh, another language), so a
  /// page that was still loading for the older feed is dropped.
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
    language = _store!.language();
    languageKnown = true;
    final saved = _store!.lastPage(language);
    if (saved != null) {
      _show(saved);
      loading = false;
    }
    notifyListeners();
    await refresh();
  }

  /// Reads the feed in [lang] from now on: the page saved for it at once, if any,
  /// then the fresh one. Anything still loading for the previous language is dropped.
  Future<void> setLanguage(FeedLanguage lang) async {
    if (lang == language) return;
    language = lang;
    unawaited(_store?.saveLanguage(lang));
    final saved = _store?.lastPage(lang);
    _show(saved);
    newCount = 0;
    error = null;
    loading = saved == null;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() => _load();

  /// The first page, shown in place of the feed. `quiet` keeps the error on screen
  /// while it asks: a check in the background, not a pull the user is watching.
  Future<void> _load({bool quiet = false}) async {
    final generation = _generation;
    final lang = language;
    if (!quiet) {
      error = null;
      notifyListeners();
    }
    try {
      final page = await api.fetchArticles(lang: lang.code);
      // Another language, or a refresh that finished first, replaced the feed meanwhile.
      if (generation != _generation) return;
      _show(page);
      newCount = 0;
      error = null;
      loading = false;
      unawaited(_store?.saveLastPage(page, lang));
    } catch (e) {
      if (generation != _generation) return;
      error = e;
      loading = false;
    } finally {
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
      final page = await api.fetchArticles(cursor: cursor, lang: language.code);
      if (generation != _generation) {
        return; // a refresh or another language replaced the feed meanwhile
      }
      final known = items.map((a) => a.id).toSet();
      items = [...items, ...page.items.where((a) => !known.contains(a.id))];
      _cursor = page.nextCursor;
    } catch (_) {
      if (generation == _generation) loadMoreFailed = true;
    } finally {
      // A replaced feed has already reset it, and may be loading its own next page.
      if (generation == _generation) loadingMore = false;
      notifyListeners();
    }
  }

  /// Counts articles that appeared after the newest one shown (called every few minutes).
  /// Asks by feed position, so one that appeared late is counted too. Positions are
  /// per language, so the check asks in the feed's language.
  ///
  /// An empty feed has nothing to count from and no place to keep: it loads the
  /// first page instead, so the first translations of the day, or the feed after
  /// being offline, appear without a pull.
  Future<void> checkForNew() async {
    if (items.isEmpty) {
      // Still loading: the first page is on its way.
      if (!loading) await _load(quiet: true);
      return;
    }
    final generation = _generation;
    final lang = language.code;
    final highest = items
        .map((a) => a.feedSeq ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    try {
      final page = highest > 0
          ? await api.fetchArticles(after: highest, limit: 50, lang: lang)
          // A feed saved before the server numbered articles: the older check.
          : await api.fetchArticles(
              since: items.first.publishedAt,
              limit: 50,
              lang: lang,
            );
      // The count belongs to the feed it was asked for.
      if (generation != _generation) return;
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

  /// Replaces the shown feed; null leaves it empty (a language with nothing saved yet).
  void _show(ArticlesPage? page) {
    _generation++;
    loadMoreFailed = false;
    loadingMore = false;
    top = page?.top ?? const [];
    items = page?.items ?? const [];
    _cursor = page?.nextCursor;
  }
}
