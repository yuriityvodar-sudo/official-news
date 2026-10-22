import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import '../../core/analytics.dart';
import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/feed_store.dart';
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

  /// What the feed shows from the Where chip (#68): the choice saved on the
  /// phone, every country until another is chosen. Every country, with the
  /// choice kept for later, while this server cannot show it: one without
  /// `GET /countries` ignores `country=` and `group=`, and a group its Where
  /// menu does not list would be refused, or ignored by a server from before
  /// the groups.
  FeedWhere get where {
    final chosen = _where;
    if (chosen.isAll) return chosen;
    if (_noCountries) return FeedWhere.all;
    final menu = _whereMenu;
    return menu == null || menu.offers(chosen) ? chosen : FeedWhere.all;
  }

  FeedWhere _where = FeedWhere.all;

  /// A server without `GET /countries` answered (404, or an answer of
  /// another shape): no Where chip. Saved, so the next launch starts so.
  bool _noCountries = false;

  /// The one topic the feed shows (#67), or null for all topics; saved.
  String? get topic => _topic;
  String? _topic;

  /// Whether the feed shown is narrowed by Where or a topic.
  bool get filtered => !where.isAll || _topic != null;

  /// The Where menu, its groups and countries named in the feed's language
  /// (`GET /countries`, or the menu saved last time); null while unknown, and
  /// for a server without it (the Where chip hides).
  WhereMenu? get whereMenu => _noCountries ? null : _whereMenu;
  WhereMenu? _whereMenu;

  /// The Topics menu: the topics with articles in the feed's 7 days under the
  /// Where choice, busiest first, named in the feed's language. Null when the
  /// server has none (an older one: the Topics chip hides) or before the
  /// first answer on a first launch.
  List<FeedTopic>? get topics => _topics;
  List<FeedTopic>? _topics;

  /// "Top stories": the API's `top`, only on the first page.
  List<Article> top = const [];

  /// Every article loaded so far, as the server pages them, newest first
  /// (top articles are in here too, on whichever page they fall).
  List<Article> get items => _items;
  set items(List<Article> value) {
    _items = value;
    _merge();
  }

  List<Article> _items = const [];
  String? _cursor;

  /// What the feed shows: one list, no sections (Yurii, 16 Oct). [items] and
  /// [top] together, each article once, in the order they arrived in the
  /// feed ([oneFeed]). Worked out once each time they change.
  List<Article> get feed => _feed;
  List<Article> _feed = const [];

  void _merge() =>
      _feed = oneFeed(top: top, items: _items, complete: _cursor == null);
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
  bool _disposed = false;

  /// The Where the first page was last asked with: when the Where menu
  /// arrives and the feed turns out to show another, it loads again.
  FeedWhere? _askedWhere;

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
    // A Local saved by the first filters build reads as every country.
    _where = store.where();
    unawaited(store.dropOldFilters());
    _topic = store.topic();
    _noCountries = store.noCountries();
    _whereMenu = _noCountries ? null : store.whereMenu(language);
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
    // Only the unfiltered feed is saved (#67, #68).
    final saved = filtered ? null : _store!.lastPage(language);
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
    // Notifications come in the feed's language (#62).
    unawaited(push.setLanguage(lang));
    // The menus as saved in that language, until the server answers in it;
    // the app names their groups, countries and topics in it either way.
    if (!_noCountries) _whereMenu = _store?.whereMenu(lang) ?? _whereMenu;
    _topics = _store?.topics(lang) ?? _topics;
    await _reload();
  }

  /// Every country, a group or one country, from the chip (#68): another
  /// feed, from the top, with the topics under it.
  Future<void> setWhere(FeedWhere where) async {
    if (where == _where) return;
    final shown = this.where;
    _where = where;
    unawaited(_store?.saveWhere(where));
    // Every country chosen while a choice the server cannot show was kept:
    // the same feed, now saved as chosen.
    if (this.where == shown) {
      notifyListeners();
      return;
    }
    _filterChanged();
    await _reload();
  }

  /// One topic, or null for all topics, from the chip (#67): another feed,
  /// from the top. The Topics menu stays: it follows the language and the
  /// Where choice only.
  Future<void> setTopic(String? id) async {
    if (id == _topic) return;
    _topic = id;
    unawaited(_store?.saveTopic(id));
    _filterChanged();
    await _reload(menus: false);
  }

  /// A filter the reader changed, as the filters are now.
  void _filterChanged() =>
      unawaited(analytics.filterChanged(where: where, topic: _topic));

  /// Shows another feed (a language or a filter) from the top: the page saved
  /// for it at once, if it has one, then the fresh one, with its menus unless
  /// [menus] is false. Anything still loading for the previous feed is dropped.
  Future<void> _reload({bool menus = true}) async {
    final saved = filtered ? null : _store?.lastPage(language);
    _show(saved);
    newCount = 0;
    error = null;
    loading = saved == null;
    notifyListeners();
    await (menus ? refresh() : _load());
  }

  /// The first page again, and the menus for it, which the pull does not wait for.
  Future<void> refresh() async {
    final feed = _load();
    unawaited(_loadMenus());
    await feed;
  }

  /// The Where menu (once per language), then the Topics menu for the Where
  /// choice. When the Where menu changes what the feed can show, the feed
  /// reloads, with its own menus.
  Future<void> _loadMenus() async {
    if (await _loadWhereMenu()) return;
    await _loadTopics();
  }

  /// The language the Where menu was named in this session; null until then.
  FeedLanguage? _whereMenuLang;
  Future<bool>? _whereMenuLoading;
  FeedLanguage? _whereMenuLoadingLang;

  /// Asks for the Where menu in the feed's language: once per language, and
  /// again after a failure (offline), at the next refresh. True when the feed
  /// shows another Where now and is reloading.
  Future<bool> _loadWhereMenu() {
    final lang = language;
    if (_whereMenuLang == lang) return Future.value(false);
    final loading = _whereMenuLoading;
    if (loading != null && _whereMenuLoadingLang == lang) return loading;
    _whereMenuLoadingLang = lang;
    return _whereMenuLoading = _fetchWhereMenu(lang);
  }

  Future<bool> _fetchWhereMenu(FeedLanguage lang) async {
    try {
      final menu = await api.fetchCountries(lang: lang.code);
      if (lang == language) {
        _whereMenu = menu;
        _whereMenuLang = lang;
        unawaited(_store?.saveWhereMenu(lang, menu));
        if (_noCountries) {
          _noCountries = false;
          unawaited(_store?.saveNoCountries(false));
        }
      }
    } on ApiException catch (e) {
      // A server without countries ignores `country=` and `group=`.
      if (e.statusCode == 404 && lang == language) _serverHasNoCountries(lang);
    } on FormatException {
      if (lang == language) _serverHasNoCountries(lang);
    } catch (_) {
      // Offline: asked again at the next refresh.
    } finally {
      if (_whereMenuLoadingLang == lang) {
        _whereMenuLoading = null;
        _whereMenuLoadingLang = null;
      }
      notifyListeners();
    }
    if (_disposed || lang != language) return false;
    // A feed asked before the answer: a server without countries, or without
    // the chosen group, shows every country; one that lists the group again
    // shows it.
    if (where != _askedWhere) {
      unawaited(_reload());
      return true;
    }
    return false;
  }

  void _serverHasNoCountries(FeedLanguage lang) {
    _whereMenu = null;
    _whereMenuLang = lang;
    _noCountries = true;
    unawaited(_store?.saveNoCountries(true));
  }

  /// The language and Where the Topics menu was last asked for.
  String? _topicsAsked;

  Future<void> _loadTopics() async {
    final lang = language;
    final where = this.where;
    final asked = '${lang.code}/$where';
    _topicsAsked = asked;
    try {
      final list = await api.fetchTopics(
        lang: lang.code,
        country: where.country,
        group: where.group,
      );
      // Another language or Where choice asked meanwhile.
      if (_topicsAsked != asked) return;
      _topics = list;
      unawaited(_store?.saveTopics(lang, list));
    } on ApiException catch (e) {
      if (e.statusCode == 404 && _topicsAsked == asked) _noTopics(lang);
    } on FormatException {
      if (_topicsAsked == asked) _noTopics(lang);
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
    final where = this.where;
    final topic = _topic;
    _askedWhere = where;
    if (!quiet) {
      error = null;
      notifyListeners();
    }
    try {
      final page = await api.fetchArticles(
        lang: lang.code,
        country: where.country,
        group: where.group,
        topic: topic,
      );
      // Another language or filter, or a refresh that finished first, replaced the feed meanwhile.
      if (generation != _generation) return;
      _show(page);
      newCount = 0;
      error = null;
      loading = false;
      // Only the unfiltered feed is kept: the one that opens offline.
      if (where.isAll && topic == null) {
        unawaited(_store?.saveLastPage(page, lang));
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
        country: where.country,
        group: where.group,
        topic: _topic,
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
    final where = this.where;
    final topic = _topic;
    final highest = items
        .map((a) => a.feedSeq ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    try {
      final page = highest > 0
          ? await api.fetchArticles(
              after: highest,
              limit: 50,
              lang: lang,
              country: where.country,
              group: where.group,
              topic: topic,
            )
          // A feed saved before the server numbered articles: the older check.
          : await api.fetchArticles(
              since: items.first.publishedAt,
              limit: 50,
              lang: lang,
              country: where.country,
              group: where.group,
              topic: topic,
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
