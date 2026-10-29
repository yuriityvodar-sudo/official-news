import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import '../../core/analytics.dart';
import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/feed_store.dart';
import '../../core/home_country.dart';
import '../../core/filters.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import 'feed_look.dart';

/// The feed's state: its language and filters, articles, paging, errors, read
/// articles and the check for new ones. The screen only draws it.
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

  /// What the feed shows: For you (#170, the default) or the whole world, the
  /// choice saved on the phone.
  FeedWhere get where => _where;
  FeedWhere _where = FeedWhere.forYou;

  /// The reader's own country for For you (#170): the one chosen in Settings
  /// → My country, else the phone's ([phoneCountry]); null while none is
  /// known, and For you is then the whole world's feed. Never stored on the
  /// server, which sees it only as `for=`.
  String? get homeCountry => _chosen.value ?? phoneCountry;

  /// The phone's country: its region, else the country `GET /locate` last
  /// gave (kept on the phone).
  String? get phoneCountry => _region ?? _located;
  String? _region;
  String? _located;

  /// The same, to listen to: Settings → My country shows it as `/locate`
  /// answers (Yurii, #206).
  ValueListenable<String?> get phoneCountryChanges => _phone;
  final _phone = ValueNotifier<String?>(null);

  /// The country chosen in Settings → My country, saved on the phone; null
  /// follows the phone.
  ValueListenable<String?> get chosenCountry => _chosen;
  final _chosen = ValueNotifier<String?>(null);

  /// What For you sends as `for=`; null for the whole world, or while the
  /// home country is unknown.
  String? get _forCountry => where.isForYou ? homeCountry : null;

  /// The one topic the feed shows (#67), or null for all topics; saved.
  String? get topic => _topic;
  String? _topic;

  /// Whether the feed shown is narrowed by a topic. For you, the default
  /// feed, is not: it is kept on the phone for its country as the whole
  /// world's is.
  bool get filtered => _topic != null;

  /// The topics: those with articles in the feed's 7 days, the whole world's,
  /// busiest first, named in the feed's language. Null when the server has
  /// none (an older one: the menu offers For you and the whole world only)
  /// or before the first answer on a first launch.
  List<FeedTopic>? get topics => _topics;
  List<FeedTopic>? _topics;

  /// "Top stories": the API's `top`, only on the first page, best first.
  List<Article> top = const [];

  /// The Top stories block above the list (#164, [topStoriesBlock]); empty
  /// when there is none.
  List<Article> get topStories => _topStories;
  List<Article> _topStories = const [];

  /// Every article loaded so far, as the server pages them, newest first
  /// (top articles are in here too, on whichever page they fall).
  List<Article> get items => _items;
  set items(List<Article> value) {
    _items = value;
    _merge();
  }

  List<Article> _items = const [];
  String? _cursor;

  /// What the list under the Top stories block shows ([topStories]): [items]
  /// in the order they arrived in the feed ([oneFeed]), each article once,
  /// so without the block's. With no block, [top] is merged in at its place,
  /// as in the one list of 16 Oct. Worked out once each time they change.
  List<Article> get feed => _feed;
  List<Article> _feed = const [];

  void _merge() {
    _topStories = topStoriesBlock(top);
    final inBlock = {for (final a in _topStories) a.id};
    _feed = [
      for (final a in oneFeed(
        top: _topStories.isEmpty ? top : const [],
        items: _items,
        complete: _cursor == null,
      ))
        if (!inBlock.contains(a.id)) a,
    ];
  }

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

  /// Bumped whenever the shown feed is replaced (a refresh, another language or
  /// filter), so a page that was still loading for the older feed is dropped.
  int _generation = 0;

  /// Bumped each time another feed replaces the shown one: another language,
  /// For you or the whole world, a topic, the home country. Refreshing the
  /// same feed leaves it, so a pull to refresh can tell that the feed it
  /// pulled is still the one shown (#166).
  int get switches => _switches;
  int _switches = 0;
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
    _chosen.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Opens what the phone keeps and reads the language: the one chosen in
  /// Settings or, on the first launch, the phone's (#52), and the filters.
  /// `main` waits for it before the first frame, so no word shows in another
  /// language first and the chips show as they were left; [start] calls it
  /// too. Opens the store once, however often it is called.
  Future<void> open() => _opening ??= _open();
  Future<void>? _opening;

  Future<void> _open() async {
    final store = await _openStore();
    _store = store;
    if (_disposed) return;
    _language.value = store.language(
      phone: FeedLanguage.forPhone(_phoneLanguages()),
    );
    // A group or a country saved before For you reads as For you.
    _where = store.where();
    unawaited(store.dropOldFilters());
    _topic = store.topic();
    // A topic is the whole world's (#170), also one saved with a Where.
    if (_topic != null) _where = FeedWhere.all;
    _region = await readPhoneRegion();
    _located = store.located();
    _phone.value = phoneCountry;
    _chosen.value = store.chosenCountry();
    unawaited(analytics.homeCountry(homeCountry));
    _topics = store.topics(language);
    // Settings → Design (#66): what was chosen, if anything; else the default.
    final design = store.design();
    if (design != null) feedDesign.value = design;
    final weight = store.headlineWeight();
    if (weight != null) headlineWeight.value = weight;
    languageKnown = true;
    notifyListeners();
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
    // Only the unfiltered feed is saved (#67, #68), For you's per country.
    final saved = filtered ? null : _store!.lastPage(language, _forCountry);
    if (saved != null) {
      _show(saved);
      loading = false;
    }
    notifyListeners();
    final fresh = refresh();
    // A phone without a region asks the server where it is (#170), once the
    // feed is on its way; not when a country is chosen in Settings.
    if (_region == null && _chosen.value == null) unawaited(_locate());
    await fresh;
  }

  /// Reads the feed in [lang] from now on: the page saved for it at once, if any,
  /// then the fresh one. Anything still loading for the previous language is dropped.
  /// Saved even when it is the language shown, the phone's on a first launch:
  /// a choice made in Settings wins over the phone's language from then on (#52).
  Future<void> setLanguage(FeedLanguage lang) async {
    unawaited(_store?.saveLanguage(lang));
    if (lang == language) return;
    _language.value = lang;
    // Notifications come in the feed's language (#62).
    unawaited(push.setLanguage(lang));
    // The topics as saved in that language, until the server answers in it;
    // the app names them in it either way.
    _topics = _store?.topics(lang) ?? _topics;
    await _reload();
  }

  /// For you or the whole world, or one topic across the world (#170): the
  /// menu's one choice, as one feed from the top. The topics are the whole
  /// world's either way, so their menu stays.
  Future<void> setFeed(FeedWhere where, {String? topic}) async {
    if (where == _where && topic == _topic) return;
    _where = where;
    _topic = topic;
    unawaited(_store?.saveWhere(where));
    unawaited(_store?.saveTopic(topic));
    _filterChanged();
    await _reload(menus: false);
  }

  /// Settings → My country (#170): a country, or null for the phone's. For
  /// you shows the new country's feed from the top.
  Future<void> setChosenCountry(String? code) async {
    if (code == _chosen.value) return;
    final before = homeCountry;
    _chosen.value = code;
    unawaited(_store?.saveChosenCountry(code));
    // Back to the phone's: without a region, ask the server again, since
    // what it gave before the choice may be old (Yurii, #206).
    if (code == null && _region == null) unawaited(_locate());
    if (homeCountry == before) return;
    unawaited(analytics.homeCountry(homeCountry));
    if (where.isForYou) await _reload(menus: false);
  }

  /// A filter the reader changed, as the filters are now.
  void _filterChanged() =>
      unawaited(analytics.filterChanged(where: where, topic: _topic));

  /// Asks the server where a phone without a region is (#170), kept for the
  /// next launch; For you shows that country's feed once it is known or has
  /// changed. Offline, or a server without `GET /locate`: For you stays as
  /// it was, asked again at the next launch.
  Future<void> _locate() async {
    try {
      final country = await api.locate();
      if (_disposed || country == null || country == _located) return;
      final before = homeCountry;
      _located = country;
      _phone.value = phoneCountry;
      unawaited(_store?.saveLocated(country));
      if (homeCountry == before) return;
      unawaited(analytics.homeCountry(homeCountry));
      if (where.isForYou) await _reload(menus: false, keepShown: true);
    } catch (_) {
      // Not known this time.
    }
  }

  /// Shows another feed (a language or a filter) from the top: the page saved
  /// for it at once, if it has one, then the fresh one, with the topics unless
  /// [menus] is false. Anything still loading for the previous feed is dropped.
  /// With [keepShown] and nothing saved, the feed on screen stays until the
  /// new one arrives (For you for a country just learned, #170: no spinner
  /// over a feed the reader can read; Yurii, #201).
  Future<void> _reload({bool menus = true, bool keepShown = false}) async {
    _switches++;
    final saved = filtered ? null : _store?.lastPage(language, _forCountry);
    final quiet = keepShown && saved == null;
    if (quiet) {
      _generation++;
    } else {
      _show(saved);
      loading = saved == null;
    }
    newCount = 0;
    error = null;
    notifyListeners();
    await (menus ? refresh() : _load(quiet: quiet));
  }

  /// The first page again, and the topics, which the pull does not wait for.
  Future<void> refresh() async {
    final feed = _load();
    unawaited(_loadTopics());
    await feed;
  }

  /// The language the topics were last asked in.
  FeedLanguage? _topicsAsked;

  Future<void> _loadTopics() async {
    final lang = language;
    _topicsAsked = lang;
    try {
      final list = await api.fetchTopics(lang: lang.code);
      // Another language asked meanwhile.
      if (_topicsAsked != lang) return;
      _topics = list;
      unawaited(_store?.saveTopics(lang, list));
    } on ApiException catch (e) {
      if (e.statusCode == 404 && _topicsAsked == lang) _noTopics(lang);
    } on FormatException {
      if (_topicsAsked == lang) _noTopics(lang);
    } catch (_) {
      // Offline: the menu stays as it was.
    } finally {
      notifyListeners();
    }
  }

  /// A server without topics: the Topics chip hides, unless a topic is chosen.
  void _noTopics(FeedLanguage lang) {
    _topics = null;
    unawaited(_store?.saveTopics(lang, null));
  }

  /// The first page, shown in place of the feed. `quiet` keeps the error on screen
  /// while it asks: a check in the background, not a pull the user is watching.
  Future<void> _load({bool quiet = false}) async {
    final generation = _generation;
    final lang = language;
    final topic = _topic;
    final forCountry = _forCountry;
    if (!quiet) {
      error = null;
      notifyListeners();
    }
    try {
      final page = await api.fetchArticles(
        lang: lang.code,
        topic: topic,
        forCountry: forCountry,
      );
      // Another language or filter, or a refresh that finished first, replaced the feed meanwhile.
      if (generation != _generation) return;
      _show(page);
      newCount = 0;
      error = null;
      loading = false;
      // Only the unfiltered feed is kept: the one that opens offline; For
      // you's for its country (#170).
      if (topic == null) {
        unawaited(_store?.saveLastPage(page, lang, forCountry));
      }
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
      final page = await api.fetchArticles(
        cursor: cursor,
        lang: language.code,
        topic: _topic,
        forCountry: _forCountry,
      );
      if (generation != _generation) {
        return; // a refresh, another language or filter replaced the feed meanwhile
      }
      final known = items.map((a) => a.id).toSet();
      _cursor = page.nextCursor;
      items = [...items, ...page.items.where((a) => !known.contains(a.id))];
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
  /// per language, so the check asks in the feed's language, with its filters.
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
    final topic = _topic;
    final forCountry = _forCountry;
    final highest = items
        .map((a) => a.feedSeq ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    try {
      final page = highest > 0
          ? await api.fetchArticles(
              after: highest,
              limit: 50,
              lang: lang,
              topic: topic,
              forCountry: forCountry,
            )
          // A feed saved before the server numbered articles: the older check.
          : await api.fetchArticles(
              since: items.first.publishedAt,
              limit: 50,
              lang: lang,
              topic: topic,
              forCountry: forCountry,
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
    _cursor = page?.nextCursor;
    items = page?.items ?? const [];
  }

  /// Saves the look chosen in Settings → Design (#66) on the phone; Settings
  /// has already switched [feedDesign] to it.
  Future<void> saveDesign(FeedDesign design) async {
    await _store?.saveDesign(design);
  }

  /// Saves the headline weight chosen in Settings → Design (#66) on the
  /// phone; Settings has already switched [headlineWeight] to it.
  Future<void> saveHeadlineWeight(HeadlineWeight weight) async {
    await _store?.saveHeadlineWeight(weight);
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

/// The Top stories block (#164, Yurii 26 Oct): the server's top stories as it
/// ranks them, best first, at most 3; none with fewer than 2, which then show
/// at their place in the list.
List<Article> topStoriesBlock(List<Article> top) =>
    top.length < 2 ? const [] : top.take(3).toList();

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
