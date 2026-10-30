import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart' show ImageFilterLayer;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/glass.dart';
import 'package:official_news/core/sheet.dart';

import 'test_app.dart';

/// The app's sheet (#166): Flutter's own, but the screen under it shrinks
/// through a transform, which iOS's glass follows, never through an image
/// filter, which it does not (the AI chat, TestFlight 55, Roman, 30 Oct).
void main() {
  setUp(() => GlassCircle.debugNative = true);
  tearDown(() => GlassCircle.debugNative = null);

  void fakeViews(WidgetTester tester) {
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
  }

  /// How visible iOS's glass behind [label] is: its view's own fade.
  double glass(WidgetTester tester, String label) {
    final control = find.ancestor(
      of: find.text(label, skipOffstage: false),
      matching: find.byWidgetPredicate(
        (widget) => widget is GlassCapsule || widget is GlassCircle,
        skipOffstage: false,
      ),
    );
    return tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.descendant(
                  of: control,
                  matching: find.byType(UiKitView, skipOffstage: false),
                ),
                matching: find.byType(Opacity, skipOffstage: false),
              )
              .first,
        )
        .opacity;
  }

  /// The image filters painted now.
  Iterable<ImageFilterLayer> filters(WidgetTester tester) =>
      tester.layers.whereType<ImageFilterLayer>();

  Widget screen() => testApp(
    home: const ColoredBox(
      color: Color(0xFFFFFFFF),
      child: Center(child: GlassCapsule(child: Text('Discuss'))),
    ),
  );

  testWidgets("the screen under it shrinks just as under Flutter's own sheet, "
      'but through a transform, never an image filter; the glass on it stays '
      "iOS's", (tester) async {
    fakeViews(tester);
    await tester.pumpWidget(screen());
    final atRest = tester.getRect(find.text('Discuss'));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    // Flutter's own sheet, with the image filter the glass cannot follow.
    unawaited(
      navigator.push(
        CupertinoSheetRoute<void>(scrollableBuilder: (_, _) => const Text('A')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(filters(tester), isNotEmpty);
    final midway = tester.getRect(find.text('Discuss'));
    await tester.pumpAndSettle();
    final under = tester.getRect(find.text('Discuss'));
    expect(under.width, lessThan(atRest.width));
    navigator.pop();
    await tester.pumpAndSettle();

    unawaited(
      navigator.push(
        SheetRoute<void>(scrollableBuilder: (_, _) => const Text('Chat')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(filters(tester), isEmpty);
    expect(tester.getRect(find.text('Discuss')), rectMoreOrLessEquals(midway));
    expect(glass(tester, 'Discuss'), 1);
    await tester.pumpAndSettle();
    expect(find.text('Chat'), findsOneWidget);
    expect(filters(tester), isEmpty);
    expect(tester.getRect(find.text('Discuss')), rectMoreOrLessEquals(under));
    expect(glass(tester, 'Discuss'), 1);

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(filters(tester), isEmpty);
    expect(glass(tester, 'Discuss'), 1);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Discuss')), atRest);
  });

  testWidgets('a sheet under a new sheet moves up and shrinks as in Flutter, '
      'through a transform too; its own glass stays iOS\'s', (tester) async {
    fakeViews(tester);
    await tester.pumpWidget(screen());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    Widget first(BuildContext _, ScrollController _) =>
        const Center(child: GlassCircle(size: 34, child: Text('Close')));

    // Where the first sheet's button ends up under Flutter's own sheets.
    unawaited(
      navigator.push(CupertinoSheetRoute<void>(scrollableBuilder: first)),
    );
    await tester.pumpAndSettle();
    final alone = tester.getRect(find.text('Close'));
    unawaited(
      navigator.push(
        CupertinoSheetRoute<void>(scrollableBuilder: (_, _) => const Text('B')),
      ),
    );
    await tester.pumpAndSettle();
    final under = tester.getRect(find.text('Close'));
    expect(under.width, lessThan(alone.width));
    navigator.pop();
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();

    unawaited(navigator.push(SheetRoute<void>(scrollableBuilder: first)));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Close')), rectMoreOrLessEquals(alone));
    unawaited(
      navigator.push(
        SheetRoute<void>(scrollableBuilder: (_, _) => const Text('Top-up')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(filters(tester), isEmpty);
    await tester.pumpAndSettle();
    expect(filters(tester), isEmpty);
    expect(tester.getRect(find.text('Close')), rectMoreOrLessEquals(under));
    expect(glass(tester, 'Close'), 1);
  });

  testWidgets('showSheet opens it on the root navigator, and gives back what '
      'the sheet closes with', (tester) async {
    await tester.pumpWidget(screen());
    final context = tester.element(find.text('Discuss'));
    final answer = showSheet<bool>(
      context: context,
      scrollableBuilder: (context, _) => CupertinoButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Buy'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      ModalRoute.of(tester.element(find.text('Buy'))),
      isA<SheetRoute<bool>>(),
    );
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });

  test('every sheet in the app opens through showSheet, so none shrinks the '
      'screen under it through a filter', () {
    final flutters = RegExp(
      r'showCupertinoSheet\b|CupertinoSheetRoute\s*<|CupertinoSheetRoute\s*\(',
    );
    final opened = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.endsWith('core/sheet.dart') &&
            flutters.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(opened, isEmpty);
  });
}
