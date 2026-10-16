import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/feed_store.dart';

/// The feed's state: its language, articles, paging, errors, read articles and
/// the check for new ones. The screen only draws it.
class FeedController extends ChangeNotifier {
  FeedController({
    ApiClient? api,
    Future<FeedStore> Function()? openStore,
    List<Locale> Function()? phoneLanguages,
  }) : api = api ?? ApiClient(),
       _openStore = openStore ?? FeedStore.open,
       _phoneLanguages = phoneLanguages ?? _systemLanguages;

  final ApiClient api;
  final Future<FeedStore> Function() _openStore;
  FeedStore? _store;

  /// The phone's languages, in the order set in its settings; tests pass their own.
  final List<Locale> Function() _phoneLanguages;
  static List<Locale> _systemLanguages() => PlatformDispatcher.instance.locales;

  /// The language the feed is read in (#46), saved on the phone. Each language is
  /// its own feed on the server, with its own pages, in the English order and
  /// feed positions (release together). The app's own words follow it (#52).
  FeedLanguage get language => _language.value;

  /// The same language to listen to: the app's MaterialApp follows it, so
  /// every word changes at once, and Settings shows it.
  ValueListenable<FeedLanguage> get languageChanges => _language;
  final _language = ValueNotifier(FeedLanguage.en);

  /// False until the saved language is read, so the header never shows English first.
  bool languageKnown = false;

  /// The API's `top`, only on the first page. Not a section of its own any
  /// more (Yurii, 16 Oct): its articles are in [feed] with the rest.
  List<Article> get top => _top;
  List<Article> _top = const [];

  /// Every article loaded so far, as the server pages them, newest first
  /// (top articles are in here too, on whichever page they fall).
  List<Article> get items => _items;
  List<Article> _items = const [];
  String? _cursor;

  /// What the feed shows: one list, no sections (Yurii, 16 Oct). [items] and
  /// [top] together, each article once, in the order they arrived in the
  /// feed ([oneFeed]). Worked out once each time they change.
  List<Article> get feed => _feed;
  List<Article> _feed = const [];

  void _merge() =>
      _feed = oneFeed(top: _top, items: _items, complete: _cursor == null);
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
    _language.dispose();
    super.dispose();
  }

  /// Opens what the phone keeps and reads the language: the one chosen in
  /// Settings or, on the first launch, the phone's (#52). `main` waits for it
  /// before the first frame, so no word shows in another language first;
  /// [start] calls it too. Opens the store once, however often it is called.
  Future<void> open() => _opening ??= _open();
  Future<void>? _opening;

  Future<void> _open() async {
    final store = await _openStore();
    _store = store;
    if (_disposed) return;
    _language.value = store.language(
      phone: FeedLanguage.forPhone(_phoneLanguages()),
    );
    languageKnown = true;
  }

  /// Shows the feed saved on the phone at once, then asks for the fresh one.
  Future<void> start() async {
    await open();
    // Articles opened before the store was ready are kept and saved now.
    final stored = _store!.readIds();
    for (final id in readIds.difference(stored)) {
      await _store!.markRead(id);
    }
    readIds = {...stored, ...readIds};
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
  /// Saved even when it is the language shown, the phone's on a first launch:
  /// a choice made in Settings wins over the phone's language from then on (#52).
  Future<void> setLanguage(FeedLanguage lang) async {
    unawaited(_store?.saveLanguage(lang));
    if (lang == language) return;
    _language.value = lang;
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
      final known = _items.map((a) => a.id).toSet();
      _items = [..._items, ...page.items.where((a) => !known.contains(a.id))];
      _cursor = page.nextCursor;
      _merge();
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
    if (feed.isEmpty) {
      // Still loading: the first page is on its way.
      if (!loading) await _load(quiet: true);
      return;
    }
    final generation = _generation;
    final lang = language.code;
    final highest = feed
        .map((a) => a.feedSeq ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    try {
      final page = highest > 0
          ? await api.fetchArticles(after: highest, limit: 50, lang: lang)
          // A feed saved before the server numbered articles: the older check.
          : await api.fetchArticles(
              since: feed.first.publishedAt,
              limit: 50,
              lang: lang,
            );
      // The count belongs to the feed it was asked for.
      if (generation != _generation) return;
      final known = feed.map((a) => a.id).toSet();
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
    _top = page?.top ?? const [];
    _items = page?.items ?? const [];
    _cursor = page?.nextCursor;
    _merge();
  }
}

/// The feed as one list (Yurii, 16 Oct: no "Top stories" and "Latest"
/// sections): [items] and [top] together, each article once, in the order
/// they arrived in the feed. The highest `feedSeq` first, as Latest was;
/// then any without one (a feed saved before the server numbered articles)
/// by `addedAt`, newest first; otherwise as the server listed them.
///
/// The server lists the top stories in `items` too, on whichever page they
/// fall. While more pages are to come (not [complete]), a top story that
/// would come after the last article loaded waits for its own page, so
/// loading more only ever adds to the end of the list.
List<Article> oneFeed({
  required List<Article> top,
  required List<Article> items,
  required bool complete,
}) {
  final seen = <String>{};
  final all = [
    for (final a in [...items, ...top])
      if (seen.add(a.id)) a,
  ];
  // The place in the server's lists breaks ties, so the order is the same
  // every time (Dart's sort is not stable).
  final place = {for (var i = 0; i < all.length; i++) all[i].id: i};
  int order(Article a, Article b) {
    final c = _arrival(a, b);
    return c != 0 ? c : place[a.id]!.compareTo(place[b.id]!);
  }

  all.sort(order);
  if (complete || items.isEmpty) return all;
  final loaded = items.map((a) => a.id).toSet();
  final last = all.lastWhere((a) => loaded.contains(a.id));
  return [
    for (final a in all)
      if (loaded.contains(a.id) || order(a, last) < 0) a,
  ];
}

/// Which of two articles arrived in the feed later, for [oneFeed]: negative
/// when [a] did, 0 when nothing tells them apart.
int _arrival(Article a, Article b) {
  final (x, y) = (a.feedSeq, b.feedSeq);
  if (x != null && y != null) return y.compareTo(x);
  if (x != null) return -1;
  if (y != null) return 1;
  final (p, q) = (a.addedAt, b.addedAt);
  if (p != null && q != null) return q.compareTo(p);
  if (p != null) return -1;
  if (q != null) return 1;
  return 0;
}
