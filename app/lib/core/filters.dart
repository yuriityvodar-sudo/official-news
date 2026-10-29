import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../l10n/app_localizations.dart';
import 'countries.dart';
import 'topics.dart';

/// The feed's two filters (#67, #68): where the news come from, and one topic.
///
/// For you (#170, the default since 28 Oct; Yurii agreed on #170): what
/// concerns the reader's own country, asked as `for=` it; or the whole world.
/// The Where pull-down's groups and countries are no longer offered.
///
/// Where (Yurii, 16 Oct): all countries (the default), a group of countries
/// (an official organization: the European Union, G7, G20, NATO), or one
/// country alone. Which countries a group has is the server's rule (`GROUPS`
/// in server/src/api/filters.ts): the app sends `group=<id>` or `country=XX`
/// and never filters on the phone. Both filters are asked of the server
/// (`GET /articles?group=|country=&topic=`), so the pages, the top stories
/// and the "N new" check all follow them.
enum WhereKind { all, group, country, forYou }

@immutable
class FeedWhere {
  const FeedWhere._(this.kind, this.id);

  /// One group, by the server's id (`g7`).
  const FeedWhere.group(String id) : this._(WhereKind.group, id);

  /// One country alone, by its two-letter code (`GB`).
  const FeedWhere.country(String code) : this._(WhereKind.country, code);

  /// Every country: the whole world.
  static const all = FeedWhere._(WhereKind.all, null);

  /// For you (#170): the reader's own country's decisions, the EU's for a
  /// member and the world's that matter (the server's rule), asked as
  /// `for=` the home country ([FeedController.homeCountry]).
  static const forYou = FeedWhere._(WhereKind.forYou, null);

  final WhereKind kind;

  /// The group's id or the country's code; null for every country.
  final String? id;

  bool get isAll => kind == WhereKind.all;
  bool get isForYou => kind == WhereKind.forYou;

  /// What `GET /articles` and `GET /topics` send.
  String? get group => kind == WhereKind.group ? id : null;
  String? get country => kind == WhereKind.country ? id : null;

  /// As saved on the phone: `world`, `foryou`, `group:g7`, `country:GB`.
  String get saved => switch (kind) {
    WhereKind.all => 'world',
    WhereKind.forYou => 'foryou',
    _ => '${kind.name}:$id',
  };

  /// A saved value: `world` is the whole world; anything else is For you,
  /// the default (#170), also nothing saved and a group or a country saved
  /// before For you: the reader can no longer choose them.
  static FeedWhere fromSaved(String? saved) => saved == 'world' ? all : forYou;

  @override
  bool operator ==(Object other) =>
      other is FeedWhere && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => saved;
}

/// A group of countries for the Where menu, as `GET /countries` lists it:
/// the id to send back as `group=`, and its name in the language asked for.
/// The members are the server's to know; the app never filters on them.
class FeedGroup {
  const FeedGroup(this.id, this.name);

  final String id;
  final String name;

  Map<String, String> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is FeedGroup && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A country for the Where menu, as `GET /countries` lists it: a two-letter
/// code with sources, and its name in the language asked for.
class FeedCountry {
  const FeedCountry(this.code, this.name);

  final String code;
  final String name;

  Map<String, String> toJson() => {'code': code, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is FeedCountry && other.code == code && other.name == name;

  @override
  int get hashCode => Object.hash(code, name);
}

/// The Where menu, as `GET /countries` answers: the groups (in the server's
/// fixed order, each listed even when its feed is empty) and the countries
/// with sources (by name in the language). [groups] is null for a server
/// from before the groups: the menu then has every country and the countries.
class WhereMenu {
  const WhereMenu({this.groups, this.countries = const []});

  final List<FeedGroup>? groups;
  final List<FeedCountry> countries;

  /// Whether [where] can be asked of this server: a group it does not list
  /// would be refused (400), or ignored by a server without groups.
  bool offers(FeedWhere where) =>
      where.kind != WhereKind.group ||
      (groups ?? const []).any((g) => g.id == where.id);

  Map<String, Object?> toJson() => {
    'groups': groups == null ? null : [for (final g in groups!) g.toJson()],
    'countries': [for (final c in countries) c.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is WhereMenu &&
      listEquals(other.groups, groups) &&
      listEquals(other.countries, countries);

  @override
  int get hashCode => Object.hash(
    groups == null ? null : Object.hashAll(groups!),
    Object.hashAll(countries),
  );
}

/// The groups the app names itself (ARB files), by the server's ids. The
/// server may list others; they show the server's name.
const groupIds = ['eu', 'g7', 'g20', 'nato'];

/// What a chosen group's chip shows: its short name in the app's language,
/// as in the chips prototype after Yurii's review (16 Oct): the EU as the
/// language abbreviates it (EU, ЄС, ЕС, UE: `filterGroupEUShort`), NATO as
/// the menu names it (NATO, НАТО, OTAN: `groupNato`), G7 and G20 as written
/// in every language. A group the app does not know: its id in capitals.
String groupShortName(String id, AppLocalizations l10n) => switch (id) {
  'eu' => l10n.filterGroupEUShort,
  'nato' => l10n.groupNato,
  _ => id.toUpperCase(),
};

/// Group [id]'s full name in the app's language, for the menu and VoiceOver:
/// the app's own for the groups it knows, so a menu saved in another language
/// is never shown in it; else the server's, from [menu]; else its id in
/// capitals.
String groupName(String id, WhereMenu? menu, AppLocalizations l10n) {
  switch (id) {
    case 'eu':
      return l10n.countryEU;
    case 'g7':
    case 'g20':
      return id.toUpperCase();
    case 'nato':
      return l10n.groupNato;
  }
  for (final g in menu?.groups ?? const <FeedGroup>[]) {
    if (g.id == id) return g.name;
  }
  return id.toUpperCase();
}

/// Country [code]'s name in the app's language ([countryName]); for a code
/// the app does not know yet, the server's, from [menu]; else the code.
String whereCountryName(String code, WhereMenu? menu, AppLocalizations l10n) {
  final own = countryName(code, l10n);
  if (own != code) return own;
  for (final c in menu?.countries ?? const <FeedCountry>[]) {
    if (c.code == code) return c.name;
  }
  return code;
}

/// A topic for the Topics menu, as `GET /topics` lists it: an id from the fixed
/// list and its name in the language asked for.
class FeedTopic {
  const FeedTopic(this.id, this.name);

  final String id;
  final String name;

  Map<String, String> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is FeedTopic && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Topic [id]'s name in the app's language: the app's own for the fixed list,
/// so a chip or a menu saved in another language, or a topic not in the menu
/// now, is never named in another language; else the server's, from [menu];
/// else the id.
String topicName(String id, List<FeedTopic>? menu, AppLocalizations l10n) {
  final own = topicLabel(id, l10n);
  if (own != null) return own;
  for (final t in menu ?? const <FeedTopic>[]) {
    if (t.id == id) return t.name;
  }
  return id;
}
