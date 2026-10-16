import 'package:flutter/foundation.dart' show listEquals;

import '../l10n/app_localizations.dart';
import 'countries.dart';

/// The feed's two filters (#67, #68): where the news come from, and one topic.
///
/// Where: [FeedScope.global] (every country, the default) or [FeedScope.local],
/// the reader's country and the blocs it belongs to (the server adds the EU's
/// decisions for EU members). Topic: all, or one of the fixed list. Both are
/// asked of the server (`GET /articles?country=&topic=`), so the pages, the
/// top stories and the "N new" check all follow them.
enum FeedScope {
  global,
  local;

  /// A saved name; anything unknown is [global].
  static FeedScope fromName(String? name) =>
      name == local.name ? local : global;
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

/// A country for Local, as `GET /countries` lists it: a two-letter code with
/// sources, and its name in the language asked for.
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

/// What Settings shows in its Country row and page: the Local country now,
/// the countries that have sources, and whether they are being loaded.
class CountryMenu {
  const CountryMenu({this.current, this.countries, this.loading = false});

  /// The country Local shows; null when there is none to offer.
  final String? current;

  /// Null when the list could not be loaded (offline, or a server without
  /// `GET /countries`).
  final List<FeedCountry>? countries;
  final bool loading;

  /// [code]'s name in the app's language: the server's, from the list, else
  /// the app's own ([countryName]), so a country the app does not know yet is
  /// named once the server lists it.
  String nameOf(String code, AppLocalizations l10n) {
    for (final c in countries ?? const <FeedCountry>[]) {
      if (c.code == code) return c.name;
    }
    return countryName(code, l10n);
  }

  @override
  bool operator ==(Object other) =>
      other is CountryMenu &&
      other.current == current &&
      other.loading == loading &&
      listEquals(other.countries, countries);

  @override
  int get hashCode =>
      Object.hash(current, loading, Object.hashAll(countries ?? const []));
}
