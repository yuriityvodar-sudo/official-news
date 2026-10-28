import 'package:flutter/cupertino.dart';

import '../features/detail/detail_screen.dart';
import '../features/feed/feed_controller.dart';
import '../features/feed/feed_screen.dart';
import '../l10n/app_localizations.dart';
import 'article.dart';

/// Route names. The detail route receives the Article already loaded in the
/// feed, so opening an article needs no extra API call. iOS-style routes on
/// both platforms: slide in, swipe from the left edge to go back. An article
/// opened from its card in the feed grows out of it instead
/// (`CardZoomRoute`, #141).
abstract final class Routes {
  static const feed = '/';
  static const detail = '/article';
}

/// The app's navigator, for what opens a screen from outside one: a tapped
/// notification opens its article (#62).
final appNavigator = GlobalKey<NavigatorState>();

/// The app's routes; the feed shows [feed], the app's own (#52).
Route<dynamic> onGenerateRoute(RouteSettings settings, {FeedController? feed}) {
  switch (settings.name) {
    case Routes.detail:
      final article = settings.arguments! as Article;
      return CupertinoPageRoute(
        builder: (_) => DetailScreen(article: article),
        settings: settings,
      );
    case Routes.feed:
    default:
      return _FeedRoute(
        builder: (_) => FeedScreen(controller: feed),
        settings: settings,
      );
  }
}

/// The feed's route. Its title is the back button on the page opened from it
/// ("< Today"), read when that page opens, so it is in the app's language then.
class _FeedRoute extends CupertinoPageRoute<void> {
  _FeedRoute({required super.builder, super.settings});

  @override
  String? get title {
    final context = navigator?.context;
    return context == null ? null : AppLocalizations.of(context).today;
  }
}
