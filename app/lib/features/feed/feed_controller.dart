import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import '../../core/analytics.dart';
import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/feed_store.dart';
import '../../core/filters.dart';
import '../../core/topics.dart' show topicLabel;

/// The feed's state: its language and filters, articles, paging, errors, read
/// articles and the check for new ones. The screen only draws it.
class FeedController extends ChangeNotifier {
  FeedController({
    ApiClient? api,
    Future<FeedStore> Function()? openStore,
    List<Locale> Function()? phoneLanguages,
    String? Function()? phoneRegion,
  }) : api = api ?? ApiClient(),
       _openStore = openStore ?? FeedStore.open,
       _phoneLanguages = phoneLanguages ?? _systemLanguages,
       _phoneRegion = phoneRegion ?? _systemRegion;

  final ApiClient api;
  final Future<FeedStore> Function() _openStore;
  FeedStore? _store;

  /// The phone's languages, in the order set in its settings; tests pass their own.
  final List<Locale> Function() _phoneLanguages;
  static List<Locale> _systemLanguages() => PlatformDispatcher.instance.locales;

  /// The phone's region ("UA" on a phone set to Ukraine), from its settings,
  /// with no location permission (#68); tests pass their own.
  final String? Function() _phoneRegion;
  static String? _systemRegion() =>
      PlatformDispatcher.instance.locale.countryCode;

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

  /// Global or Local (#68), saved on the phone; Global until Local is chosen.
  /// Local only while there is a country to show ([localCountry]).
  FeedScope get scope => _scope == FeedScope.local && localCountry != null
      ? FeedScope.local
      : FeedScope.global;
  FeedScope _scope = FeedScope.global;

  /// The country Local shows: the one chosen in Settings; until one is, the
  /// phone's region when it has sources, else the first country that has
  /// some. With no list of countries (offline on the first launch, or a
  /// server without `GET /countries`), the phone's region. Null when there is
  /// none: only Global is offered.
  String? get localCountry {
    final chosen = _chosenCountry;
    if (chosen != null) return chosen;
    final region = _phoneRegion()?.toUpperCase();
    final valid = region != null && RegExp(r'^[A-Z]{2}$').hasMatch(region);
    final list = _countries;
    if (list == null) return valid ? region : null;
    if (valid && list.any((c) => c.code == region)) return region;
    return list.isEmpty ? null : list.first.code;
  }

  String? _chosenCountry;

  /// The `country` the feed asks for: Local's country, null for Global.
  String? get feedCountry => scope == FeedScope.local ? localCountry : null;

  /// The one topic the feed shows (#67), or null for all topics; saved.
  String? get topic => _topic;
  String? _topic;

  /// Whether the feed shown is narrowed by Local or a topic.
  bool get filtered => feedCountry != null || _topic != null;

  /// The countries that have sources, named in the feed's language
  /// (`GET /countries`, or the list saved last time); null while unknown.
  List<FeedCountry>? get countries => _countries;
  List<FeedCountry>? _countries;

  /// The Topics menu: the topics with articles in the feed's 7 days under the
  /// Where choice, busiest first, named in the feed's language. Null when the
  /// server has none (an older one: the Topics chip hides) or before the
  /// first answer on a first launch.
  List<FeedTopic>? get topics => _topics;
  List<FeedTopic>? _topics;

  /// Every topic name seen, for a chosen topic that is not in the menu now
  /// (no articles under the other Where choice).
  final Map<String, String> _topicNames = {};

  /// Topic [id]'s name in the feed's language; the English one from the
  /// fixed list until the server has named it.
  String topicName(String id) => _topicNames[id] ?? topicLabel(id);

  /// What Settings shows for Local: the country now and the list to choose
  /// from, kept current as either changes.
  ValueListenable<CountryMenu> get countryChanges => _countryMenu;
  final _countryMenu = ValueNotifier(const CountryMenu());

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

  /// Bumped whenever the shown feed is replaced (a refresh, another language or
  /// filter), so a page that was still loading for the older feed is dropped.
  int _generation = 0;
  bool _disposed = false;

  /// The `country` the first page was last asked with: when the countries
  /// arrive and Local turns out to be another country, the feed loads again.
  String? _askedCountry;

  bool get hasMore => _cursor != null;

  @override
  void notifyListeners() {
    // A request can finish after the screen has gone away.
    if (_disposed) return;
    _countryMenu.value = CountryMenu(
      current: localCountry,
      countries: _countries,
      loading: _countriesLoading != null,
    );
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _language.dispose();
    _countryMenu.dispose();
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
    _scope = store.scope();
    _chosenCountry = store.country();
    _topic = store.topic();
    _countries = store.countries(language);
    _useTopics(store.topics(language));
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
    // The menus as saved in that language, until the server names them in it.
    _countries = _store?.countries(lang) ?? _countries;
    _useTopics(_store?.topics(lang) ?? _topics);
    await _reload();
  }

  /// Global or Local, from the chip (#68): another feed, from the top.
  Future<void> setScope(FeedScope scope) async {
    if (scope == this.scope) return;
    if (scope == FeedScope.local && localCountry == null) return;
    _scope = scope;
    unawaited(_store?.saveScope(scope));
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

  /// Local's country, chosen in Settings (#68). Saved also when it is the one
  /// shown, so Local stops following the phone's region. The feed changes
  /// only while it shows Local.
  Future<void> setCountry(String code) async {
    final shown = feedCountry;
    final changed = code != localCountry;
    _chosenCountry = code;
    unawaited(_store?.saveCountry(code));
    if (changed) _filterChanged();
    if (feedCountry != shown) {
      await _reload();
    } else {
      notifyListeners();
    }
  }

  /// A filter the reader changed, as the filters are now. The country is
  /// Local's, also while Global is shown.
  void _filterChanged() => unawaited(
    analytics.filterChanged(scope: scope, country: localCountry, topic: _topic),
  );

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

  /// The countries for Local (once per language), then the Topics menu for
  /// the Where choice. When the countries move Local to another country, the
  /// feed reloads in it, with its own menus.
  Future<void> _loadMenus() async {
    if (await loadCountries()) return;
    await _loadTopics();
  }

  /// The language the countries were named in this session; null until then.
  FeedLanguage? _countriesLang;
  Future<bool>? _countriesLoading;
  FeedLanguage? _countriesLoadingLang;

  /// Asks for the countries in the feed's language: once per language, and
  /// again after a failure (offline). Settings asks too when it has no list.
  /// True when Local moved to another country and the feed is reloading.
  Future<bool> loadCountries() {
    final lang = language;
    if (_countriesLang == lang) return Future.value(false);
    final loading = _countriesLoading;
    if (loading != null && _countriesLoadingLang == lang) return loading;
    _countriesLoadingLang = lang;
    final load = _fetchCountries(lang);
    _countriesLoading = load;
    notifyListeners();
    return load;
  }

  Future<bool> _fetchCountries(FeedLanguage lang) async {
    try {
      final list = await api.fetchCountries(lang: lang.code);
      if (lang == language) {
        _countries = list;
        _countriesLang = lang;
        unawaited(_store?.saveCountries(lang, list));
      }
    } on ApiException catch (e) {
      // A server without countries: Local follows the phone's region.
      if (e.statusCode == 404 && lang == language) _noCountries(lang);
    } on FormatException {
      if (lang == language) _noCountries(lang);
    } catch (_) {
      // Offline: asked again at the next refresh.
    } finally {
      if (_countriesLoadingLang == lang) {
        _countriesLoading = null;
        _countriesLoadingLang = null;
      }
      notifyListeners();
    }
    if (_disposed || lang != language) return false;
    // The phone's region has no sources, say: Local is another country.
    if (_scope == FeedScope.local && feedCountry != _askedCountry) {
      unawaited(_reload());
      return true;
    }
    return false;
  }

  void _noCountries(FeedLanguage lang) {
    _countries = null;
    _countriesLang = lang;
  }

  /// The language and country the Topics menu was last asked for.
  String? _topicsAsked;

  Future<void> _loadTopics() async {
    final lang = language;
    final country = feedCountry;
    final asked = '${lang.code}/$country';
    _topicsAsked = asked;
    try {
      final list = await api.fetchTopics(lang: lang.code, country: country);
      // Another language or Where choice asked meanwhile.
      if (_topicsAsked != asked) return;
      _useTopics(list);
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

  void _useTopics(List<FeedTopic>? list) {
    _topics = list;
    for (final t in list ?? const <FeedTopic>[]) {
      _topicNames[t.id] = t.name;
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
    final country = feedCountry;
    final topic = _topic;
    _askedCountry = country;
    if (!quiet) {
      error = null;
      notifyListeners();
    }
    try {
      final page = await api.fetchArticles(
        lang: lang.code,
        country: country,
        topic: topic,
      );
      // Another language or filter, or a refresh that finished first, replaced the feed meanwhile.
      if (generation != _generation) return;
      _show(page);
      newCount = 0;
      error = null;
      loading = false;
      // Only the unfiltered feed is kept: the one that opens offline.
      if (country == null && topic == null) {
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
        country: feedCountry,
        topic: _topic,
      );
      if (generation != _generation) {
        return; // a refresh, another language or filter replaced the feed meanwhile
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
    final country = feedCountry;
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
              country: country,
              topic: topic,
            )
          // A feed saved before the server numbered articles: the older check.
          : await api.fetchArticles(
              since: items.first.publishedAt,
              limit: 50,
              lang: lang,
              country: country,
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
    items = page?.items ?? const [];
    _cursor = page?.nextCursor;
  }
}
