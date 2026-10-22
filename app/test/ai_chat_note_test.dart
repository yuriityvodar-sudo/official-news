import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/push.dart';
import 'package:official_news/features/detail/ai_chat_note.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_messaging.dart';
import 'test_app.dart';

/// "Discuss with AI" opens this note until the chat is built (#141): its
/// switch is a real notification, one topic per feed language.
void main() {
  late List<(String, Map<String, Object>)> events;
  late SharedPreferences prefs;
  late int settingsOpened;

  setUp(() {
    events = [];
    settingsOpened = 0;
    analytics = Analytics(
      (name, parameters) async => events.add((name, parameters)),
      (_, _) async {},
    );
  });
  tearDown(() => analytics = Analytics());

  Iterable<Map<String, Object>> sent(String name) =>
      events.where((e) => e.$1 == name).map((e) => e.$2);

  /// The note over push started with [messaging], the feed read in [language].
  Future<Push> showNote(
    WidgetTester tester,
    FakeMessaging messaging, {
    Map<String, Object> saved = const {},
    FeedLanguage language = FeedLanguage.en,
  }) async {
    SharedPreferences.setMockInitialValues(saved);
    prefs = await SharedPreferences.getInstance();
    final push = Push();
    await push.start(messaging, prefs, language: language);
    addTearDown(push.stop);
    await tester.pumpWidget(
      testApp(
        home: AiChatNote(
          push: push,
          openSettingsApp: () async => settingsOpened++,
        ),
      ),
    );
    return push;
  }

  bool switchedOn(WidgetTester tester) =>
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value;

  testWidgets('not asked yet: the switch asks iOS, and both topics follow', (
    tester,
  ) async {
    final messaging = FakeMessaging();
    await showNote(tester, messaging);
    expect(find.text('A chat about each decision'), findsOneWidget);
    // Says that allowing notifications brings the breaking decisions too.
    expect(find.textContaining('most important decisions'), findsOneWidget);
    expect(switchedOn(tester), isFalse);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();

    expect(messaging.asked, 1);
    expect(messaging.calls, ['subscribe breaking_en', 'subscribe ai_chat_en']);
    expect(prefs.getString('push.aiChatTopic'), 'ai_chat_en');
    expect(switchedOn(tester), isTrue);
    expect(
      find.text('One notification, when the chat is ready.'),
      findsOneWidget,
    );
    expect(sent('ai_chat_notify'), [
      {'state': 'on'},
    ]);
    expect(sent('push_permission'), [
      {'result': 'granted', 'trigger': 'ai_chat'},
    ]);
  });

  testWidgets('allowed: on and off again, the breaking topic stays', (
    tester,
  ) async {
    final messaging = FakeMessaging(status: PushPermission.granted);
    await showNote(tester, messaging);
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();

    expect(messaging.asked, 0);
    expect(messaging.calls, [
      'subscribe breaking_en',
      'subscribe ai_chat_en',
      'unsubscribe ai_chat_en',
    ]);
    expect(prefs.getString('push.aiChatTopic'), isNull);
    expect(prefs.getString('push.topic'), 'breaking_en');
    expect(switchedOn(tester), isFalse);
    expect(sent('ai_chat_notify'), [
      {'state': 'on'},
      {'state': 'off'},
    ]);
  });

  testWidgets('not allowed: the switch opens the Settings app and the wish is '
      'kept for when they are back on', (tester) async {
    final messaging = FakeMessaging(status: PushPermission.denied);
    final push = await showNote(tester, messaging);
    expect(find.textContaining('Settings app'), findsOneWidget);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    expect(messaging.calls, isEmpty);
    expect(switchedOn(tester), isFalse);
    expect(push.aiChat.value, isTrue);

    // Turned on in the Settings app, back in the app.
    messaging.status = PushPermission.granted;
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(messaging.calls, ['subscribe breaking_en', 'subscribe ai_chat_en']);
    expect(switchedOn(tester), isTrue);
  });

  test('the topic moves with the feed language, after a restart too', () async {
    SharedPreferences.setMockInitialValues({
      'push.aiChat': true,
      'push.topic': 'breaking_uk',
      'push.aiChatTopic': 'ai_chat_uk',
    });
    prefs = await SharedPreferences.getInstance();
    final messaging = FakeMessaging(status: PushPermission.granted);
    final push = Push();
    await push.start(messaging, prefs, language: FeedLanguage.uk);
    addTearDown(push.stop);
    expect(push.aiChat.value, isTrue);
    await push.setLanguage(FeedLanguage.de);
    expect(messaging.calls, [
      // A start subscribes once more, in case Firebase lost it.
      'subscribe breaking_uk',
      'subscribe ai_chat_uk',
      'unsubscribe breaking_uk',
      'subscribe breaking_de',
      'unsubscribe ai_chat_uk',
      'subscribe ai_chat_de',
    ]);
    expect(prefs.getString('push.aiChatTopic'), 'ai_chat_de');
  });
}
