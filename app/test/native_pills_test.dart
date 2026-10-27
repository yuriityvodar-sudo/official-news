import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/card_zoom.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/glass.dart';
import 'package:official_news/core/topics.dart';
import 'package:official_news/features/feed/feed_topic_pills.dart';

import 'test_app.dart';

/// The native topic pills' side in Flutter (#166): what is sent to iOS's
/// SwiftUI row (PillsView in the Runner), what a tap there does, and when
/// Flutter's own row stands in. The glass itself is checked on a phone.
void main() {
  setUp(() => TopicPills.debugNative = true);
  tearDown(() {
    TopicPills.debugNative = null;
    CardZoomRoute.moving.value = false;
  });

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
    String? topic,
    List<FeedTopic> topics = const [
      FeedTopic('economy', 'Economy'),
      FeedTopic('health', 'Health'),
    ],
    ValueChanged<String?>? onTopic,
  }) => testApp(
    home: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: 58,
        child: TopicPills(
          topic: topic,
          topics: topics,
          onTopic: onTopic ?? (_) {},
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
                of: find.byKey(const ValueKey('topic-pill-all')),
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
      'colour, and a tap there chooses the topic', (tester) async {
    final (rows, _) = recordRows(tester);
    String? chosen = 'none';
    await tester.pumpWidget(pills(onTopic: (t) => chosen = t));
    await tester.pump();

    expect(find.byType(UiKitView), findsOneWidget);
    final [id] = rows.keys.toList();
    expect(rows[id], {
      'pills': [
        {'id': '', 'title': 'All topics', 'symbol': 'sparkles'},
        {'id': 'economy', 'title': 'Economy', 'symbol': 'chart.bar.fill'},
        {'id': 'health', 'title': 'Health', 'symbol': 'staroflife.fill'},
      ],
      'chosen': '',
      'tint': 0xFFC41230,
      'dark': false,
    });

    await fromIos(tester, id, 'select', 'health');
    expect(chosen, 'health');
    await fromIos(tester, id, 'select', '');
    expect(chosen, isNull);
    // VoiceOver hears iOS's buttons, not Flutter's hidden row as well.
    expect(find.bySemanticsLabel('All topics'), findsNothing);
  });

  testWidgets('a topic chosen in Flutter reaches the same row as an update, '
      'so the drop flows to it', (tester) async {
    final (rows, heard) = recordRows(tester);
    await tester.pumpWidget(pills());
    await tester.pump();
    heard.clear();

    await tester.pumpWidget(pills(topic: 'economy'));
    await tester.pump();
    expect(rows, hasLength(1));
    expect(heard.single.method, 'update');
    expect(
      (heard.single.arguments as Map<Object?, Object?>)['chosen'],
      'economy',
    );

    // Nothing changed: nothing sent.
    await tester.pumpWidget(pills(topic: 'economy'));
    await tester.pump();
    expect(heard, hasLength(1));
  });

  testWidgets("Flutter's row stands in until iOS has made its own and while "
      "an article grows out of its card, swiped as far as iOS's", (
    tester,
  ) async {
    final (rows, _) = recordRows(tester);
    await tester.pumpWidget(
      pills(topics: [for (final id in topicIds) FeedTopic(id, id)]),
    );
    expect(shown(tester), (1.0, 0.0));
    await tester.pump();
    expect(shown(tester), (0.0, 1.0));

    // Swiped on iOS, then an article opens from a card.
    final all = find.byKey(const ValueKey('topic-pill-all'));
    final left = tester.getTopLeft(all).dx;
    await fromIos(tester, rows.keys.single, 'scrolled', 120.0);
    CardZoomRoute.moving.value = true;
    await tester.pump();
    expect(shown(tester), (1.0, 0.0));
    expect(tester.getTopLeft(all).dx, left - 120);

    CardZoomRoute.moving.value = false;
    await tester.pump();
    expect(shown(tester), (0.0, 1.0));
  });

  testWidgets("Flutter's row stands in while a sheet is over the feed, "
      'until it has gone again', (tester) async {
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
    expect(shown(tester), (1.0, 0.0));
    await tester.pumpAndSettle();
    expect(shown(tester), (1.0, 0.0));

    // Still under the sheet as it slides away; iOS's again once it has gone.
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(shown(tester), (1.0, 0.0));
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
