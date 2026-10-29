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

  testWidgets('the chip sends its items to iOS, and a choice there filters '
      'the feed', (tester) async {
    final views = recordViews(tester);
    (FeedWhere, String?)? chosen;
    await tester.pumpWidget(
      testApp(
        home: FeedFilterBar(
          where: FeedWhere.forYou,
          topic: null,
          topics: const [FeedTopic('economy', 'Economy')],
          onChoose: (where, topic) => chosen = (where, topic),
        ),
      ),
    );
    await tester.pump();

    // One menu (#170): For you, the whole world, then the topics.
    expect(find.byType(UiKitView), findsOneWidget);
    final [menu] = views.values.toList();
    expect(menu['label'], 'For you');
    expect(menu['sections'], [
      [
        {'title': 'For you', 'selected': true, 'symbol': 'sparkles'},
        {'title': 'The whole world', 'selected': false, 'symbol': 'globe'},
      ],
      [
        {'title': 'Economy', 'selected': false, 'symbol': 'chart.bar.fill'},
      ],
    ]);

    final [id] = views.keys.toList();
    await choose(tester, id, 0, 1);
    expect(chosen, (FeedWhere.all, null));
    await choose(tester, id, 1, 0);
    expect(chosen, (FeedWhere.all, 'economy'));

    // VoiceOver hears the native button, not the chip under it as well.
    expect(find.bySemanticsLabel('For you'), findsNothing);
  });
}
