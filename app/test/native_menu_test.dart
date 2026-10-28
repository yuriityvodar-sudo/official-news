import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/features/feed/feed_filters.dart';

import 'test_app.dart';

/// The native menus' side in Flutter (#141): what is sent to iOS's UIMenu
/// (MenuView in the Runner) and what a choice there does. The menu itself is
/// checked on a simulator.
void main() {
  setUp(() => debugNativeMenus = true);
  tearDown(() => debugNativeMenus = null);

  /// The items each native menu was created with, by the view's id.
  Map<int, Map<Object?, Object?>> recordViews(WidgetTester tester) {
    final views = <int, Map<Object?, Object?>>{};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') {
          final args = call.arguments as Map<Object?, Object?>;
          final params = args['params']! as Uint8List;
          views[args['id']! as int] =
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(params),
                  )
                  as Map<Object?, Object?>;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );
    return views;
  }

  Future<void> choose(WidgetTester tester, int view, int section, int row) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'official_news/menu_$view',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('select', [section, row]),
        ),
        (_) {},
      );

  testWidgets('each chip sends its items to iOS, and a choice there filters '
      'the feed', (tester) async {
    final views = recordViews(tester);
    FeedWhere? where;
    String? topic = 'none';
    await tester.pumpWidget(
      testApp(
        home: FeedFilterBar(
          where: FeedWhere.all,
          whereMenu: const WhereMenu(
            groups: [FeedGroup('eu', 'European Union')],
            countries: [FeedCountry('DE', 'Germany')],
          ),
          topic: null,
          topics: const [FeedTopic('economy', 'Economy')],
          onWhere: (w) => where = w,
          onTopic: (t) => topic = t,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(UiKitView), findsNWidgets(2));
    final [whereMenu, topicsMenu] = views.values.toList();
    expect(whereMenu['label'], 'All countries');
    expect(whereMenu['sections'], [
      [
        {'title': 'All countries', 'selected': true, 'symbol': null},
      ],
      [
        {'title': 'European Union', 'selected': false, 'symbol': null},
      ],
      [
        {'title': 'Germany', 'selected': false, 'symbol': null},
      ],
    ]);
    expect((topicsMenu['sections']! as List)[1], [
      {'title': 'Economy', 'selected': false, 'symbol': 'chart.bar.fill'},
    ]);

    final [whereId, topicsId] = views.keys.toList();
    await choose(tester, whereId, 2, 0);
    expect(where, const FeedWhere.country('DE'));
    await choose(tester, topicsId, 1, 0);
    expect(topic, 'economy');

    // VoiceOver hears the native button, not the chip under it as well.
    expect(find.bySemanticsLabel('All countries'), findsNothing);
  });
}
