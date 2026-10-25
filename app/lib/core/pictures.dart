import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'motion.dart';

/// Article pictures saved on the phone (#57): each one is downloaded once from
/// the official site and kept as a file, so the feed card and the article use
/// the same saved picture, also after the app is closed or offline. A picture
/// is kept 7 days after it was last shown (the feed's window), at most 200 of
/// them, the longest unused removed first; iOS may also clear them when space
/// is low, and a missing one is simply downloaded again.
BaseCacheManager pictureCache = CacheManager(
  Config(
    'pictures',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 200,
  ),
);

/// The saved picture at [url], decoded [width] pixels wide when given:
/// official pages often serve 2,000+ px images, so it is decoded near the size
/// shown. Only the decoded copy in memory differs by size; the saved file is one.
ImageProvider picture(String url, {int? width}) => ResizeImage.resizeIfNeeded(
  width,
  null,
  CachedNetworkImageProvider(url, cacheManager: pictureCache),
);

/// The picture as the article screen shows it, decoded at the screen's
/// width. The article screen, the flight to it and the full-screen view all
/// use this one (#141), so it is decoded once; the feed asks for it as an
/// article opens, so it is ready when the flight lands.
ImageProvider screenPicture(BuildContext context, String url) {
  final media = MediaQuery.of(context);
  return picture(
    url,
    width: (media.size.width * media.devicePixelRatio).round(),
  );
}

/// An article's picture that flies between the feed's card, the article
/// screen and the full-screen view (#141), as photos do in Apple's apps.
/// With Reduce Motion on, it does not fly: the screens fade as usual.
class PictureHero extends StatelessWidget {
  const PictureHero({
    super.key,
    required this.articleId,
    required this.url,
    required this.child,
  });

  final String articleId;
  final String url;
  final Widget child;

  static Object tag(String articleId) => 'picture:$articleId';

  @override
  Widget build(BuildContext context) => HeroMode(
    enabled: !Motion.reduced(context),
    child: Hero(
      tag: tag(articleId),
      // The flight draws the screen-sized picture, whatever the card's size,
      // so it fills the box as it grows instead of stretching a thumbnail.
      flightShuttleBuilder: (context, animation, direction, from, to) =>
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: screenPicture(context, url),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
      child: child,
    ),
  );
}
