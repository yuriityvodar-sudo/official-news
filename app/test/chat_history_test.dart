import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/chat_history.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/features/chat/chat_history_screen.dart';
import 'package:official_news/features/chat/chat_screen.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// The conversations with the AI agent kept on the phone (#146, Roman's
/// pick B, 30 Oct): the store, the Conversations screen and its button.

Article _article(String id, String headline, {String country = 'GB'}) =>
    Article.fromJson({
      'id': id,
      'country': country,
      'source': {
        'id': 'src-$id',
        'name': 'Source $id',
        'url': 'https://gov.test',
      },
      'publishedAt': '2026-10-26T08:00:00Z',
      'dateOnly': false,
      'headline': headline,
      'shortSummary': 'Short.',
      'summary': 'Summary.',
      'decisionType': 'law',
      'originalTitle': headline,
      'originalLanguage': 'en',
      'topics': ['economy'],
      'tags': <String>[],
      'importance': 3,
      'imageUrl': null,
      'originalUrl': 'https://gov.test/$id',
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the store', () {
    test(
      'keeps each conversation once, newest first, and reads it back',
      () async {
        final history = ChatHistory();
        await history.save(_article('a', 'A'), [(true, 'Qa'), (false, 'Aa')]);
        await history.save(_article('b', 'B'), [(true, 'Qb'), (false, 'Ab')]);
        await history.save(_article('a', 'A'), [
          (true, 'Qa'),
          (false, 'Aa'),
          (true, 'Qa2'),
          (false, 'Aa2'),
        ]);
        expect(history.conversations.map((c) => c.article.id), ['a', 'b']);
        expect(history.of('a')!.lastQuestion, 'Qa2');

        final again = ChatHistory();
        await again.load();
        expect(again.conversations.map((c) => c.article.id), ['a', 'b']);
        expect(again.of('a')!.messages, hasLength(4));
        expect(again.of('a')!.article.headline, 'A');
      },
    );

    test('keeps at most 50, and the last 20 messages of each', () async {
      final history = ChatHistory();
      for (var i = 0; i < ChatHistory.max + 2; i++) {
        await history.save(_article('$i', 'H$i'), [(true, 'Q'), (false, 'A')]);
      }
      expect(history.conversations, hasLength(ChatHistory.max));
      expect(history.of('0'), isNull);
      expect(history.of('51'), isNotNull);

      await history.save(_article('long', 'Long'), [
        for (var i = 0; i < 15; i++) ...[(true, 'Q$i'), (false, 'A$i')],
      ]);
      expect(history.of('long')!.messages, hasLength(ChatHistory.maxMessages));
      expect(history.of('long')!.messages.first, (true, 'Q5'));
    });

    test(
      'deletes one, or all, from the phone too; a damaged entry is left out',
      () async {
        final history = ChatHistory();
        await history.save(_article('a', 'A'), [(true, 'Q'), (false, 'A')]);
        await history.save(_article('b', 'B'), [(true, 'Q'), (false, 'A')]);
        await history.delete('a');
        expect(history.conversations.map((c) => c.article.id), ['b']);
        await history.clear();
        expect(history.isEmpty, isTrue);
        expect(
          (await SharedPreferences.getInstance()).getString(ChatHistory.key),
          isNull,
        );

        SharedPreferences.setMockInitialValues({ChatHistory.key: 'not json'});
        final damaged = ChatHistory();
        await damaged.load();
        expect(damaged.isEmpty, isTrue);
      },
    );
  });

  group('the Conversations screen', () {
    /// Two conversations on the phone, the newer first, as the store keeps them.
    ChatHistory kept() {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        ChatHistory.key: jsonEncode([
          ChatConversation(
            article: _article('b', 'Newer decision', country: 'CZ'),
            messages: const [(true, 'Second?'), (false, 'No.')],
            updatedAt: now,
          ).toJson(),
          ChatConversation(
            article: _article('a', 'Older decision'),
            messages: const [(true, 'First?'), (false, 'Yes.')],
            updatedAt: now.subtract(const Duration(minutes: 5)),
          ).toJson(),
        ]),
      });
      return ChatHistory();
    }

    testWidgets('lists them newest first, with the last question and when, '
        'says they stay on the phone, and a tap opens one', (tester) async {
      final history = kept();
      await tester.pumpWidget(
        testApp(home: ChatHistoryScreen(history: history)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Conversations'), findsWidgets);
      expect(
        tester.getTopLeft(find.text('Newer decision')).dy,
        lessThan(tester.getTopLeft(find.text('Older decision')).dy),
      );
      expect(find.text('Second?'), findsOneWidget);
      expect(find.text('CZ'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsNWidgets(2));
      expect(
        find.text('Conversations are kept only on this phone.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Newer decision'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('No.'), findsOneWidget);
    });

    testWidgets('a swipe deletes one; Delete all asks first, deletes them all '
        'and goes back', (tester) async {
      final history = kept();
      await tester.pumpWidget(
        testApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => ChatHistoryScreen(history: history),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Older decision'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(history.of('a'), isNull);
      expect(find.text('Older decision'), findsNothing);

      await tester.tap(find.text('Delete all'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all conversations?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoActionSheet),
          matching: find.text('Delete all'),
        ),
      );
      await tester.pumpAndSettle();
      expect(history.isEmpty, isTrue);
      expect(find.byType(ChatHistoryScreen), findsNothing);
    });
  });

  testWidgets("the feed's button for them shows beside Settings only when "
      'the feed gives it a way to open them', (tester) async {
    var opened = 0;
    FeedMasthead masthead(VoidCallback? conversations) => FeedMasthead(
      title: 'Outer News',
      date: 'Friday, 30 October',
      openSettings: () {},
      openConversations: conversations,
      where: FeedWhere.forYou,
      topic: null,
      topics: null,
      onChoose: (_, _) {},
      pull: ValueNotifier(null),
    );

    await tester.pumpWidget(
      testApp(home: Center(child: masthead(null).buttons)),
    );
    expect(find.byIcon(CupertinoIcons.chat_bubble_2), findsNothing);
    expect(find.byIcon(CupertinoIcons.gear_alt), findsOneWidget);

    await tester.pumpWidget(
      testApp(home: Center(child: masthead(() => opened++).buttons)),
    );
    expect(find.bySemanticsLabel('Conversations'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chat_bubble_2));
    expect(opened, 1);
  });
}
