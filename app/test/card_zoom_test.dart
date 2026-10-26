import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/card_zoom.dart';
import 'package:official_news/core/glass.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/detail/detail_screen.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// Where the card sits on the 800 x 600 test screen.
const _card = Rect.fromLTWH(20, 200, 300, 100);

/// A card at [_card] that opens a long article out of itself. Both screens
/// have a glass button: 'Gear' under the article, 'Back' on it. The card's
/// headline, 'Card', and its picture fly to the article's 'Headline' and
/// picture.
Widget _host() => testApp(
  home: Builder(
    builder: (context) => Stack(
      children: [
        const Positioned(
          top: 20,
          right: 20,
          child: GlassCircle(size: 44, child: Text('Gear')),
        ),
        Positioned.fromRect(
          rect: _card,
          child: ZoomSource(
            id: 'a1',
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                CardZoomRoute<void>(
                  from: ZoomSource.rectOf('a1')!,
                  background: const Color(0xFFFFFFFF),
                  sourceId: 'a1',
                  builder: (_) => ColoredBox(
                    color: const Color(0xFFFFFFFF),
                    child: ListView(
                      children: [
                        const GlassCircle(size: 44, child: Text('Back')),
                        const ZoomPart(
                          id: 'a1',
                          piece: ZoomPiece.headline,
                          child: Text(
                            'Headline',
                            style: TextStyle(fontSize: 28),
                          ),
                        ),
                        const ZoomPart(
                          id: 'a1',
                          piece: ZoomPiece.picture,
                          radius: BorderRadius.all(Radius.circular(12)),
                          child: SizedBox(
                            key: ValueKey('article picture'),
                            height: 100,
                            child: ColoredBox(color: Color(0xFF44AA66)),
                          ),
                        ),
                        for (var i = 0; i < 40; i++)
                          SizedBox(height: 60, child: Text('Line $i')),
                      ],
                    ),
                  ),
                ),
              ),
              child: const ColoredBox(
                color: Color(0xFF2266AA),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ZoomPart(
                      id: 'a1',
                      piece: ZoomPiece.headline,
                      child: Text('Card', style: TextStyle(fontSize: 14)),
                    ),
                    Spacer(),
                    ZoomPart(
                      id: 'a1',
                      piece: ZoomPiece.picture,
                      radius: BorderRadius.all(Radius.circular(4)),
                      child: SizedBox(
                        key: ValueKey('card picture'),
                        width: 60,
                        height: 60,
                        child: ColoredBox(color: Color(0xFFAA4422)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  ),
);

/// The box the article is drawn in while it grows or shrinks.
Rect _box(WidgetTester tester) => tester.getRect(find.byType(FittedBox));

/// How visible the card in the feed is.
double _cardOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(
        of: find.byType(ZoomSource),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

/// How visible the article is in its box.
double _pageShown(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: find.byType(FittedBox), matching: find.byType(Opacity)),
    )
    .opacity;

/// Whether [element] is a piece in its place, in the card or the article.
bool _inPlace(Element element) {
  var inPlace = false;
  element.visitAncestorElements((ancestor) {
    inPlace = ancestor.widget is ZoomPart;
    return !inPlace;
  });
  return inPlace;
}

/// [finder]'s widget in its place ([ZoomPart]), or drawn in flight.
Finder _placed(Finder finder) => find.byElementPredicate(
  (e) => finder.evaluate().contains(e) && _inPlace(e),
);
Finder _flying(Finder finder) => find.byElementPredicate(
  (e) => finder.evaluate().contains(e) && !_inPlace(e),
);

/// What draws the piece of [finder] in its place: nothing while it flies.
RenderObject _place(WidgetTester tester, Finder finder) => tester.renderObject(
  find.ancestor(of: _placed(finder), matching: find.byType(ZoomPart)),
);

Future<void> _openArticle(WidgetTester tester) async {
  await tester.pumpWidget(_host());
  await tester.tap(find.text('Card'));
  await tester.pumpAndSettle();
  expect(find.text('Line 0'), findsOneWidget);
}

bool _isOpen(WidgetTester tester) =>
    find.text('Line 0').evaluate().isNotEmpty &&
    _box(tester) == const Rect.fromLTWH(0, 0, 800, 600);

Map<String, dynamic> _article(String id) => {
  'id': id,
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': 'Decision $id',
  'shortSummary': null,
  'summary': 'Summary $id',
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': <String>[],
  'tags': <String>[],
  'importance': 3,
  'imageUrl': null,
  'originalUrl': 'https://www.bundesregierung.de/$id',
};

/// The feed with three articles; [pushed] collects the routes it opens.
Future<void> _pumpFeed(WidgetTester tester, List<Route<dynamic>> pushed) async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(
    baseUrl: 'https://api.test',
    client: MockClient((request) async {
      if (!request.url.path.startsWith('/articles')) {
        return http.Response('{"error":"Not found"}', 404);
      }
      final query = request.url.queryParameters;
      final newer = query.containsKey('since') || query.containsKey('after');
      return http.Response(
        jsonEncode({
          'items': newer
              ? <Object>[]
              : [
                  for (final id in ['a1', 'a2', 'a3']) _article(id),
                ],
          'nextCursor': null,
          'top': <Object>[],
        }),
        200,
      );
    }),
  );
  await tester.pumpWidget(
    testApp(
      onGenerateRoute: onGenerateRoute,
      navigatorObservers: [_Pushed(pushed)],
      home: FeedScreen(
        controller: FeedController(api: api),
        newCheckEvery: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _Pushed extends NavigatorObserver {
  _Pushed(this.routes);

  final List<Route<dynamic>> routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

void main() {
  testWidgets('the article grows out of its card and goes back into it', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('Card'));
    // Its first frame is built offstage, for heroes to measure: the card
    // stays meanwhile, its place is not empty.
    await tester.pump();
    expect(_cardOpacity(tester), 1);
    await tester.pump();
    // It starts as the card.
    expect(_box(tester), rectMoreOrLessEquals(_card, epsilon: 0.5));
    expect(_cardOpacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 250));
    final growing = _box(tester);
    expect(growing.width, greaterThan(_card.width));
    expect(growing.width, lessThan(800));
    // Covered by the article now: hidden, so it goes back into an empty place.
    expect(_cardOpacity(tester), 0);

    await tester.pumpAndSettle();
    expect(_isOpen(tester), isTrue);
    // The feed is not drawn under the open article.
    expect(find.text('Card'), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_box(tester).width, lessThan(800));
    await tester.pumpAndSettle();
    expect(find.text('Line 0'), findsNothing);
    expect(_cardOpacity(tester), 1);
  });

  testWidgets('the headline and the picture fly from the card to the '
      'article, growing; neither place draws them meanwhile', (tester) async {
    final card = find.text('Card');
    final headline = find.text('Headline');
    final cardPicture = find.byKey(const ValueKey('card picture'));
    await tester.pumpWidget(_host());
    final cardHeadlineAt = tester.getRect(card);
    final cardPictureAt = tester.getRect(cardPicture);

    await tester.tap(card);
    await tester.pump();
    await tester.pump();
    // They start where they are in the card, drawn in flight, not in place.
    expect(
      tester.getRect(_flying(card)),
      rectMoreOrLessEquals(cardHeadlineAt, epsilon: 0.5),
    );
    expect(
      tester.getRect(_flying(cardPicture)),
      rectMoreOrLessEquals(cardPictureAt, epsilon: 0.5),
    );
    expect(_place(tester, card), paintsNothing);
    expect(_place(tester, headline), paintsNothing);
    expect(_pageShown(tester), 0);

    await tester.pump(const Duration(milliseconds: 100));
    // On the way: bigger, the card's words turning into the article's.
    expect(
      tester.getRect(_flying(card)).height,
      greaterThan(cardHeadlineAt.height),
    );
    expect(_flying(headline), findsOneWidget);
    final picture = tester.getRect(_flying(cardPicture));
    expect(picture.width, allOf(greaterThan(60), lessThan(800)));
    expect(_place(tester, card), paintsNothing);
    expect(_place(tester, headline), paintsNothing);

    await tester.pumpAndSettle();
    // Landed: in its place in the article, nothing in flight.
    expect(_flying(headline), findsNothing);
    expect(_flying(cardPicture), findsNothing);
    expect(_place(tester, headline), paints..paragraph());
    expect(_pageShown(tester), 1);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_flying(card), findsOneWidget);
    expect(_place(tester, headline), paintsNothing);
    // The rest of the article is gone by now.
    expect(_pageShown(tester), lessThan(1));

    await tester.pumpAndSettle();
    expect(_flying(card), findsNothing);
    expect(_place(tester, card), paints..paragraph());
    expect(_cardOpacity(tester), 1);
  });

  testWidgets('a piece scrolled out of the article does not fly back: it '
      'goes with the article, and the card keeps its own', (tester) async {
    await _openArticle(tester);
    await tester.drag(find.text('Line 5'), const Offset(0, -400));
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(5, 300), const Offset(320, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_flying(find.text('Headline')), findsNothing);
    expect(_flying(find.text('Card')), findsNothing);
    expect(_place(tester, find.text('Card')), paints..paragraph());
    await tester.pumpAndSettle();
    expect(find.text('Headline'), findsNothing);
  });

  testWidgets('a pull down at the top shrinks it under the finger; let go '
      'early, it opens again, far enough, it goes back into its card', (
    tester,
  ) async {
    await _openArticle(tester);

    final pull = await tester.startGesture(
      tester.getCenter(find.text('Line 2')),
    );
    await pull.moveBy(const Offset(0, 20));
    await pull.moveBy(const Offset(0, 50));
    await tester.pump();
    expect(_box(tester).width, lessThan(800));
    // The feed shows under it while it is shrunk.
    expect(find.byType(ZoomSource), findsOneWidget);
    await pull.up();
    await tester.pumpAndSettle();
    expect(_isOpen(tester), isTrue);
    expect(find.text('Card'), findsNothing);

    await tester.drag(find.text('Line 2'), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.text('Line 0'), findsNothing);
    expect(_cardOpacity(tester), 1);
  });

  testWidgets(
    'on iOS the text does not bounce down at the top: the whole article '
    'follows the finger',
    (tester) async {
      await _openArticle(tester);
      final list = tester.state<ScrollableState>(find.byType(Scrollable));
      final pull = await tester.startGesture(
        tester.getCenter(find.text('Line 2')),
      );
      await pull.moveBy(const Offset(0, 20));
      await pull.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(list.position.pixels, 0);
      expect(_box(tester).center.dy, greaterThan(300));
      await pull.up();
      await tester.pumpAndSettle();
      expect(find.text('Line 0'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a swipe from the left edge closes it, as iOS goes back; a '
      'short one does not', (tester) async {
    await _openArticle(tester);

    await tester.dragFrom(const Offset(5, 300), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(_isOpen(tester), isTrue);

    await tester.dragFrom(const Offset(5, 300), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(find.text('Line 0'), findsNothing);
    expect(_cardOpacity(tester), 1);
  });

  testWidgets('a scroll inside the article does not shrink it', (tester) async {
    await _openArticle(tester);
    await tester.drag(find.text('Line 5'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Line 0'), findsNothing);
    expect(_box(tester), const Rect.fromLTWH(0, 0, 800, 600));
  });

  testWidgets('with Reduce Motion on, the article fades in, nothing grows', (
    tester,
  ) async {
    _reduceMotion(tester);
    await tester.pumpWidget(_host());
    await tester.tap(find.text('Card'));
    await tester.pump();
    expect(find.byType(FittedBox), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Line 0'), findsOneWidget);
  });

  testWidgets('the native glass under the moving article is drawn plainly '
      'meanwhile; the article keeps its own', (tester) async {
    GlassCircle.debugNative = true;
    addTearDown(() => GlassCircle.debugNative = null);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (_) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );

    /// How visible the native view of the glass around [label] is.
    double native(String label) {
      final circle = find.ancestor(
        of: find.text(label, skipOffstage: false),
        matching: find.byType(GlassCircle, skipOffstage: false),
      );
      final view = find.descendant(
        of: circle,
        matching: find.byType(UiKitView, skipOffstage: false),
      );
      // Only the glass's own fade, not the article's as it grows.
      final fade = find.ancestor(
        of: view,
        matching: find.descendant(
          of: circle,
          matching: find.byType(Opacity, skipOffstage: false),
        ),
      );
      return fade.evaluate().isEmpty
          ? 1
          : tester.widget<Opacity>(fade.first).opacity;
    }

    await tester.pumpWidget(_host());
    expect(native('Gear'), 1);

    await tester.tap(find.text('Card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(CardZoomRoute.moving.value, isTrue);
    expect(native('Gear'), 0);
    expect(native('Back'), 1);

    await tester.pumpAndSettle();
    expect(CardZoomRoute.moving.value, isFalse);
    expect(native('Gear'), 1);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(native('Gear'), 0);
    await tester.pumpAndSettle();
    expect(native('Gear'), 1);
    expect(CardZoomRoute.moving.value, isFalse);
  });

  group('the feed', () {
    testWidgets('opens an article out of its card', (tester) async {
      final pushed = <Route<dynamic>>[];
      await _pumpFeed(tester, pushed);
      final card = tester.getRect(
        find.byWidgetPredicate((w) => w is ZoomSource && w.id == 'a2'),
      );

      await tester.tap(find.text('Decision a2'));
      await tester.pump();
      await tester.pump();
      // The card's headline flies to the article's.
      expect(_flying(find.text('Decision a2')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_flying(find.text('Decision a2')), findsNothing);
      final route = pushed.last as CardZoomRoute<void>;
      expect(route.from, card);
      expect(route.sourceId, 'a2');
      expect(route.settings.name, Routes.detail);
      expect(find.byType(DetailScreen), findsOneWidget);
      expect(find.text('Summary a2'), findsOneWidget);
    });

    testWidgets('with Reduce Motion on, opens it as before', (tester) async {
      _reduceMotion(tester);
      final pushed = <Route<dynamic>>[];
      await _pumpFeed(tester, pushed);
      await tester.tap(find.text('Decision a2'));
      await tester.pumpAndSettle();
      expect(pushed.last, isA<CupertinoPageRoute<dynamic>>());
      expect(find.text('Summary a2'), findsOneWidget);
    });
  });
}
