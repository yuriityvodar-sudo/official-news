import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'article.dart';
import 'feed_design.dart';
import 'feed_language.dart';
import 'filters.dart';
import 'theme.dart';

/// What the phone keeps between launches: the feed's language and filters, the
/// last first page of the unfiltered feed in each language, so the app opens
/// instantly (offline too), the articles already opened, shown dimmed (by id,
/// so in every language), and the last Where and Topics menus in each
/// language, so the filters show their names at once.
class FeedStore {
  FeedStore(this._prefs);

  static Future<FeedStore> open() async =>
      FeedStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _pageKey = 'feed.lastPage';
  static const _readKey = 'feed.readIds';
  static const _langKey = 'feed.lang';
  static const _whereKey = 'feed.where';
  static const _topicKey = 'feed.topic';
  static const _topicsKey = 'feed.topics';
  static const _whereMenuKey = 'feed.whereMenu';
  static const _noCountriesKey = 'feed.noCountries';
  static const _designKey = 'feed.design';
  static const _headlineWeightKey = 'feed.headlineWeight';
  static const _locatedKey = 'feed.located';

  /// What the first filters build (Global / Local, 16 Oct) kept: its Local
  /// country and its list of countries per language. Local is gone, so the
  /// feed opens on every country; [dropOldFilters] removes them.
  static const _oldKeys = ['feed.scope', 'feed.country'];
  static const _oldPrefix = 'feed.countries.';
  static const _maxRead = 500;

  /// English keeps the key it had before there were languages: 'feed.lastPage'.
  /// For you's page for a country has its own (#170): 'feed.lastPage.for.CZ'.
  static String _pageKeyFor(FeedLanguage lang, [String? forCountry]) {
    final key = lang == FeedLanguage.en ? _pageKey : '$_pageKey.${lang.code}';
    return forCountry == null ? key : '$key.for.$forCountry';
  }

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

  ArticlesPage? lastPage([
    FeedLanguage lang = FeedLanguage.en,
    String? forCountry,
  ]) {
    final raw = _prefs.getString(_pageKeyFor(lang, forCountry));
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
    String? forCountry,
  ]) => _prefs.setString(
    _pageKeyFor(lang, forCountry),
    jsonEncode(page.toJson()),
  );

  /// For you or the whole world (#170): For you until the whole world is
  /// chosen. For you, the default, is not saved.
  FeedWhere where() => FeedWhere.fromSaved(_prefs.getString(_whereKey));

  Future<void> saveWhere(FeedWhere where) => where.isForYou
      ? _prefs.remove(_whereKey)
      : _prefs.setString(_whereKey, where.saved);

  /// The country `GET /locate` last gave for a phone without a region
  /// (#170), kept for the next launch; null until it gave one.
  String? located() => _prefs.getString(_locatedKey);

  Future<void> saveLocated(String country) =>
      _prefs.setString(_locatedKey, country);

  /// Forgets the Global / Local choice of the first filters build: a saved
  /// Local reads as every country ([where] never reads it).
  Future<void> dropOldFilters() async {
    for (final key in _prefs.getKeys().toList()) {
      if (_oldKeys.contains(key) || key.startsWith(_oldPrefix)) {
        await _prefs.remove(key);
      }
    }
  }

  /// The look chosen in Settings → Design (#66), or null until one is chosen
  /// (the app then keeps its default, or a build's `--dart-define`). Today's
  /// look is saved too once chosen, so the choice wins over a build's start.
  FeedDesign? design() {
    final saved = _prefs.getString(_designKey);
    return saved == null ? null : designNamed(saved);
  }

  Future<void> saveDesign(FeedDesign design) =>
      _prefs.setString(_designKey, design.name);

  /// The headline weight chosen in Settings → Design (#66), or null until
  /// one is chosen; bold is saved too once chosen, as [saveDesign] does.
  HeadlineWeight? headlineWeight() {
    final saved = _prefs.getString(_headlineWeightKey);
    return saved == null ? null : headlineWeightNamed(saved);
  }

  Future<void> saveHeadlineWeight(HeadlineWeight weight) =>
      _prefs.setString(_headlineWeightKey, weight.name);

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

  /// The last Where menu in [lang], or null if none was saved.
  WhereMenu? whereMenu(FeedLanguage lang) {
    final raw = _prefs.getString('$_whereMenuKey.${lang.code}');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final groups = json['groups'] as List?;
      return WhereMenu(
        groups: groups == null
            ? null
            : [
                for (final g in groups)
                  FeedGroup(g['id'] as String, g['name'] as String),
              ],
        countries: [
          for (final c in json['countries'] as List)
            FeedCountry(c['code'] as String, c['name'] as String),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWhereMenu(FeedLanguage lang, WhereMenu menu) => _prefs
      .setString('$_whereMenuKey.${lang.code}', jsonEncode(menu.toJson()));

  /// True once a server without `GET /countries` answered (404), so the next
  /// launch hides the Where chip from the start (such a server ignores
  /// `country=` and `group=`); false again once it lists them.
  bool noCountries() => _prefs.getBool(_noCountriesKey) ?? false;

  Future<void> saveNoCountries(bool none) => none
      ? _prefs.setBool(_noCountriesKey, true)
      : _prefs.remove(_noCountriesKey);

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
