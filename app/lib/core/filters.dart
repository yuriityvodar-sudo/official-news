import '../l10n/app_localizations.dart';
import 'topics.dart';

/// What the feed shows (#170, Yurii agreed on #170): For you, the default,
/// or the whole world, each with one topic or every topic (#67). For you is
/// what concerns the reader's own country, asked of the server as `for=`
/// it; the server keeps every filter (`GET /articles?for=&topic=`), so the
/// pages, the top stories and the "N new" check all follow them. A topic is
/// the whole world's.
///
/// The Where pull-down of 16 Oct (#68: all countries, a group of countries,
/// one country) is gone: readers will not pick a country, NATO or G20
/// (Roman, 27 Oct). A group or a country saved before opens For you.
enum FeedWhere {
  /// For you (#170): the reader's own country's decisions, the EU's for a
  /// member and the world's that matter (the server's rule), asked as
  /// `for=` the home country ([FeedController.homeCountry]).
  forYou,

  /// Every country: the whole world.
  all;

  bool get isAll => this == all;
  bool get isForYou => this == forYou;

  /// As saved on the phone: `world` or `foryou`.
  String get saved => isAll ? 'world' : 'foryou';

  /// A saved value: `world` is the whole world; anything else is For you,
  /// the default (#170), also nothing saved and a group or a country saved
  /// before For you: the reader can no longer choose them.
  static FeedWhere fromSaved(String? saved) => saved == 'world' ? all : forYou;
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
