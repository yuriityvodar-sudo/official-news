import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/pictures.dart';

import 'flutter_test_config.dart';

void main() {
  test(
    'the card and the article read the same saved picture, decoded at their own sizes',
    () {
      const url = 'https://www.bundesregierung.de/image.jpg';
      final card = picture(url, width: 540) as ResizeImage;
      final article = picture(url, width: 1179) as ResizeImage;
      expect(card.imageProvider, isA<CachedNetworkImageProvider>());
      expect(card.imageProvider, article.imageProvider);
      expect((card.width, article.width), (540, 1179));
      expect(
        (card.imageProvider as CachedNetworkImageProvider).cacheManager,
        same(pictureCache),
      );
    },
  );

  test('without a size the saved picture is decoded as it is', () {
    expect(picture('https://x/i.jpg'), isA<CachedNetworkImageProvider>());
  });

  testWidgets(
    'the article asks for the picture the card saved, by the same address',
    (tester) async {
      const url = 'https://www.bundesregierung.de/image.jpg';
      for (final width in [540, 1179]) {
        await tester.pumpWidget(Image(image: picture(url, width: width)));
        await tester.pump();
      }
      final asked = (pictureCache as NoPictures).asked;
    expect(asked, isNotEmpty);
    expect(asked, everyElement(url));
    },
  );
}
