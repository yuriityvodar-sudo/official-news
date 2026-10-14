import 'package:flutter/cupertino.dart';

import '../features/detail/detail_screen.dart';
import '../features/feed/feed_screen.dart';
import 'article.dart';

/// Route names. The detail route receives the Article already loaded in the
/// feed, so opening an article needs no extra API call. iOS-style routes on
/// both platforms: slide in, swipe from the left edge to go back.
abstract final class Routes {
  static const feed = '/';
  static const detail = '/article';
}

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case Routes.detail:
      final article = settings.arguments! as Article;
      return CupertinoPageRoute(
        builder: (_) => DetailScreen(article: article),
        settings: settings,
      );
    case Routes.feed:
    default:
      return CupertinoPageRoute(
        title: 'Today',
        builder: (_) => const FeedScreen(),
        settings: settings,
      );
  }
}
