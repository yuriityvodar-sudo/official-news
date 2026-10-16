import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
