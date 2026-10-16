import 'package:flutter/foundation.dart' show listEquals;

import '../l10n/app_localizations.dart';
import 'countries.dart';
import 'topics.dart';

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
  const CountryMenu({
    this.current,
    this.countries,
    this.region,
    this.loading = false,
    this.available = true,
  });

  /// The country Local shows; null when there is none to offer.
  final String? current;

  /// Null when the list could not be loaded (offline).
  final List<FeedCountry>? countries;

  /// The phone's region when it can be Local's country, so it stays offered
  /// after another country is chosen, though it has no sources of its own.
  final String? region;

  final bool loading;

  /// False for a server without `GET /countries`, which would ignore
  /// `country=`: the Country row hides, as the Where chip does.
  final bool available;

  /// The countries to choose from: the phone's region and the current one
  /// first when the list does not have them (no sources of their own, or no
  /// list yet), then the list in the server's order.
  List<String> get choices {
    final listed = [for (final c in countries ?? const <FeedCountry>[]) c.code];
    return [
      for (final code in {?region, ?current})
        if (!listed.contains(code)) code,
      ...listed,
    ];
  }

  /// [code]'s name in the app's language: the app's own ([countryName]), so a
  /// list saved in another language is never shown in it; else the server's,
  /// from the list, so a country the app does not know yet is named once the
  /// server lists it; else the code.
  String nameOf(String code, AppLocalizations l10n) {
    if (hasCountryName(code)) return countryName(code, l10n);
    for (final c in countries ?? const <FeedCountry>[]) {
      if (c.code == code) return c.name;
    }
    return code;
  }

  @override
  bool operator ==(Object other) =>
      other is CountryMenu &&
      other.current == current &&
      other.region == region &&
      other.loading == loading &&
      other.available == available &&
      listEquals(other.countries, countries);

  @override
  int get hashCode => Object.hash(
    current,
    region,
    loading,
    available,
    Object.hashAll(countries ?? const []),
  );
}
