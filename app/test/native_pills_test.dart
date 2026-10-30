import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/glass.dart';
import 'package:official_news/core/topics.dart';
import 'package:official_news/features/feed/feed_pills.dart';

import 'test_app.dart';

/// The native pills' side in Flutter (#166): what is sent to iOS's SwiftUI
/// row (PillsView in the Runner), what a tap there does, and when Flutter's
/// own row stands in: only until iOS has made its row, never under a page or
/// a sheet (Roman, 30 Oct). The glass itself is checked on a phone.
void main() {
  setUp(() => FeedPills.debugNative = true);
  tearDown(() => FeedPills.debugNative = null);

  /// The params each native row was created with, by the view's id, and
  /// what its channel heard from Flutter afterwards.
  (Map<int, Map<Object?, Object?>>, List<MethodCall>) recordRows(
    WidgetTester tester,
  ) {
    final rows = <int, Map<Object?, Object?>>{};
    final heard = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        final id = args['id']! as int;
        rows[id] =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params']! as Uint8List),
                )
                as Map<Object?, Object?>;
        final channel = MethodChannel('official_news/pills_$id');
        messenger.setMockMethodCallHandler(channel, (call) async {
          heard.add(call);
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );
    return (rows, heard);
  }

  Future<void> fromIos(
    WidgetTester tester,
    int row,
    String method,
    Object? arguments,
  ) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'official_news/pills_$row',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );

  Widget pills({
    FeedWhere where = FeedWhere.forYou,
    String? topic,
    List<FeedTopic> topics = const [
      FeedTopic('economy', 'Economy'),
      FeedTopic('health', 'Health'),
    ],
    void Function(FeedWhere where, String? topic)? onChoose,
  }) => testApp(
    home: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: 58,
        child: FeedPills(
          where: where,
          topic: topic,
          topics: topics,
          onChoose: onChoose ?? (_, _) {},
          ink: const Color(0xFF000000),
          fill: const Color(0xFFFFFFFF),
          edge: const Color(0x8CFFFFFF),
          shadow: const [],
          chosen: const LinearGradient(
            colors: [Color(0xFFC41230), Color(0xFFE4566E)],
          ),
          glow: const Color(0x4DC41230),
          tint: const Color(0xFFC41230),
        ),
      ),
    ),
  );

  /// How much of Flutter's row and of iOS's shows.
  (double, double) shown(WidgetTester tester) => (
    tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('pill-for-you')),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity,
    tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(UiKitView),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity,
  );

  testWidgets('iOS draws the row with the pills, the chosen one and the '
      'colour, and a tap there chooses what the feed shows', (tester) async {
    final (rows, _) = recordRows(tester);
    (FeedWhere, String?)? chosen;
    await tester.pumpWidget(pills(onChoose: (w, t) => chosen = (w, t)));
    // VoiceOver hears Flutter's row while it stands in.
    expect(find.semantics.byLabel('For you'), findsOne);
    await tester.pump();

    expect(find.byType(UiKitView), findsOneWidget);
    final [id] = rows.keys.toList();
    expect(rows[id], {
      // Each icon's room is its SF Symbol's width (Yurii's review of #218).
      'pills': [
        {
          'id': 'pill-for-you',
          'title': 'For you',
          'symbol': 'sparkles',
          'slot': 17.0,
        },
        {
          'id': 'pill-world',
          'title': 'The whole world',
          'symbol': 'globe',
          'slot': 19.0,
        },
        {
          'id': 'pill-topic-economy',
          'title': 'Economy',
          'symbol': 'chart.bar.fill',
          'slot': 24.0,
        },
        {
          'id': 'pill-topic-health',
          'title': 'Health',
          'symbol': 'staroflife.fill',
          'slot': 18.0,
        },
      ],
      'chosen': 'pill-for-you',
      'tint': 0xFFC41230,
      'dark': false,
    });

    // A topic is the whole world's (#170).
    await fromIos(tester, id, 'select', 'pill-topic-health');
    expect(chosen, (FeedWhere.all, 'health'));
    await fromIos(tester, id, 'select', 'pill-world');
    expect(chosen, (FeedWhere.all, null));
    await fromIos(tester, id, 'select', 'pill-for-you');
    expect(chosen, (FeedWhere.forYou, null));
    // VoiceOver hears iOS's buttons, not Flutter's hidden row as well.
    expect(find.semantics.byLabel('For you'), findsNothing);
  });

  testWidgets('what is chosen in Flutter reaches the same row as an update, '
      'so the drop flows to it', (tester) async {
    final (rows, heard) = recordRows(tester);
    await tester.pumpWidget(pills());
    await tester.pump();
    heard.clear();

    await tester.pumpWidget(pills(where: FeedWhere.all, topic: 'economy'));
    await tester.pump();
    expect(rows, hasLength(1));
    expect(heard.single.method, 'update');
    expect(
      (heard.single.arguments as Map<Object?, Object?>)['chosen'],
      'pill-topic-economy',
    );

    // Nothing changed: nothing sent.
    await tester.pumpWidget(pills(where: FeedWhere.all, topic: 'economy'));
    await tester.pump();
    expect(heard, hasLength(1));
  });

  testWidgets("Flutter's row stands in until iOS has made its own, swiped as "
      "far as iOS's", (tester) async {
    final (rows, _) = recordRows(tester);
    await tester.pumpWidget(
      pills(topics: [for (final id in topicIds) FeedTopic(id, id)]),
    );
    expect(shown(tester), (1.0, 0.0));
    await tester.pump();
    expect(shown(tester), (0.0, 1.0));

    final forYou = find.byKey(const ValueKey('pill-for-you'));
    final left = tester.getTopLeft(forYou).dx;
    await fromIos(tester, rows.keys.single, 'scrolled', 120.0);
    expect(tester.getTopLeft(forYou).dx, left - 120);
    expect(shown(tester), (0.0, 1.0));
  });

  testWidgets("iOS's row stays under a sheet, as it comes, stays and goes: the "
      'sheet covers it, nothing stands in (Roman, 30 Oct)', (tester) async {
    recordRows(tester);
    await tester.pumpWidget(pills());
    await tester.pump();
    expect(shown(tester), (0.0, 1.0));

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        CupertinoSheetRoute<void>(
          scrollableBuilder: (_, _) => const Text('Sheet'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(shown(tester), (0.0, 1.0));
    await tester.pumpAndSettle();
    expect(shown(tester), (0.0, 1.0));

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(shown(tester), (0.0, 1.0));
    await tester.pumpAndSettle();
    expect(shown(tester), (0.0, 1.0));
  });

  testWidgets("under the splash iOS's row is hidden, and comes in as much as "
      'the feed does as the splash fades', (tester) async {
    recordRows(tester);
    final cover = ValueNotifier(1.0);
    addTearDown(cover.dispose);
    await tester.pumpWidget(NativeCover(cover: cover, child: pills()));
    await tester.pump();
    expect(shown(tester).$2, 0);

    cover.value = 0.4;
    await tester.pump();
    final (flutter, ios) = shown(tester);
    expect(flutter, 0);
    expect(ios, moreOrLessEquals(0.6));

    cover.value = 0;
    await tester.pump();
    expect(shown(tester), (0.0, 1.0));
  });
}
