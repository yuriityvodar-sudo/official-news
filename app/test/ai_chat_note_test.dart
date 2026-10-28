import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/push.dart';
import 'package:official_news/features/detail/ai_chat_note.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_messaging.dart';
import 'test_app.dart';

/// "Discuss with AI" opens this note until the chat is built (#141): "Tell me
/// when it's ready" is one tap, counted once per phone, that turns into a
/// checkmark (#160). Nothing to do with notifications.
void main() {
  late List<(String, Map<String, Object>)> events;

  setUp(() {
    events = [];
    analytics = Analytics(
      (name, parameters) async => events.add((name, parameters)),
      (_, _) async {},
    );
  });
  tearDown(() => analytics = Analytics());

  Iterable<Map<String, Object>> sent(String name) =>
      events.where((e) => e.$1 == name).map((e) => e.$2);

  /// The note, with [saved] on the phone.
  Future<SharedPreferences> showNote(
    WidgetTester tester, {
    Map<String, Object> saved = const {},
  }) async {
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(testApp(home: const AiChatNote()));
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('one tap counts the reader once and turns into a checkmark', (
    tester,
  ) async {
    final prefs = await showNote(tester);
    expect(find.text('A chat about each decision'), findsOneWidget);
    expect(find.text("We'll let you know when it's ready"), findsNothing);

    await tester.tap(find.text("Tell me when it's ready"));
    await tester.pumpAndSettle();

    expect(find.text("Tell me when it's ready"), findsNothing);
    expect(find.text("We'll let you know when it's ready"), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
    expect(prefs.getBool(AiChatNote.interestedKey), isTrue);
    expect(sent('ai_chat_interest'), [<String, Object>{}]);
    // No switch and no notifications any more.
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(sent('push_permission'), isEmpty);
  });

  testWidgets('a reader who tapped before sees the checkmark, not the button', (
    tester,
  ) async {
    await showNote(tester, saved: {AiChatNote.interestedKey: true});
    expect(find.text("We'll let you know when it's ready"), findsOneWidget);
    expect(find.text("Tell me when it's ready"), findsNothing);
    // Counted once: opening the note again sends nothing.
    expect(sent('ai_chat_interest'), isEmpty);
  });

  testWidgets('the button and the checkmark in Ukrainian too', (tester) async {
    for (final (language, ask, done) in [
      (
        FeedLanguage.uk,
        'Повідомити про запуск',
        'Повідомимо, щойно буде готово',
      ),
    ]) {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        testApp(language: language, home: const AiChatNote()),
      );
      await tester.pumpAndSettle();
      expect(find.text(ask), findsOneWidget);
      await tester.tap(find.text(ask));
      await tester.pumpAndSettle();
      expect(find.text(done), findsOneWidget);
    }
  });

  test(
    'the earlier switch\'s topic is dropped from phones that took it',
    () async {
      // A phone that switched "Tell me when it's ready" on before #160.
      SharedPreferences.setMockInitialValues({
        'push.topic': 'breaking_en',
        'push.aiChatTopic': 'ai_chat_en',
      });
      final prefs = await SharedPreferences.getInstance();
      final messaging = FakeMessaging(status: PushPermission.granted);
      final push = Push();
      await push.start(messaging, prefs, language: FeedLanguage.en);
      addTearDown(push.stop);
      expect(messaging.calls, contains('unsubscribe ai_chat_en'));
      expect(messaging.calls.where((c) => c.contains('subscribe ai_chat')), [
        'unsubscribe ai_chat_en',
      ]);
      expect(prefs.getString('push.aiChatTopic'), isNull);
      expect(prefs.getString('push.topic'), 'breaking_en');
    },
  );
}
