import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/glass.dart';
import 'package:official_news/features/splash/splash.dart';

import 'test_app.dart';

void main() {
  testWidgets('off iOS (tests, Android) a plain circle; the child centred; '
      'the tap reaches the button around it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      testApp(
        home: Center(
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => taps++,
            child: const GlassCircle(
              size: 36,
              child: Icon(CupertinoIcons.gear_alt, size: 21),
            ),
          ),
        ),
      ),
    );
    expect(GlassCircle.native, isFalse);
    expect(find.byType(UiKitView), findsNothing);
    final box = find.descendant(
      of: find.byType(GlassCircle),
      matching: find.byType(DecoratedBox),
    );
    expect(box, findsOneWidget);
    expect(
      (tester.widget<DecoratedBox>(box).decoration as BoxDecoration).shape,
      BoxShape.circle,
    );
    expect(tester.getSize(find.byType(GlassCircle)), const Size(36, 36));
    expect(
      tester.getCenter(find.byIcon(CupertinoIcons.gear_alt)),
      tester.getCenter(find.byType(GlassCircle)),
    );
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
    expect(taps, 1);
  });

  group('on iOS', () {
    setUp(() => GlassCircle.debugNative = true);
    tearDown(() => GlassCircle.debugNative = null);

    /// How visible iOS's glass is in the capsule: its view's own fade.
    double glass(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(UiKitView, skipOffstage: false),
                matching: find.byType(Opacity, skipOffstage: false),
              )
              .first,
        )
        .opacity;

    Widget capsule() => testApp(
      home: const Center(child: GlassCapsule(child: Text('Discuss'))),
    );

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

    testWidgets('the glass gives way to the plain capsule while a sheet is '
        'over its screen, until the sheet has gone again', (tester) async {
      fakeViews(tester);
      await tester.pumpWidget(capsule());
      expect(glass(tester), 1);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          CupertinoSheetRoute<void>(
            scrollableBuilder: (_, _) => const Text('Paywall'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(glass(tester), 0);
      await tester.pumpAndSettle();
      expect(glass(tester), 0);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(glass(tester), 0);
      await tester.pumpAndSettle();
      expect(glass(tester), 1);
    });

    testWidgets('a popup over its screen hides the glass too', (tester) async {
      fakeViews(tester);
      await tester.pumpWidget(capsule());
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          CupertinoModalPopupRoute<void>(builder: (_) => const Text('Menu')),
        ),
      );
      await tester.pumpAndSettle();
      expect(glass(tester), 0);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(glass(tester), 1);
    });

    testWidgets('under the splash the glass is hidden; it comes in as the '
        'splash fades, and is all there once it has gone', (tester) async {
      fakeViews(tester);
      await tester.pumpWidget(
        testApp(
          home: const SplashHost(
            child: Center(child: GlassCapsule(child: Text('Discuss'))),
          ),
        ),
      );
      expect(glass(tester), 0);
      // A tap skips the splash: it fades out.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(glass(tester), 0);
      await tester.pump(splashFade * 0.6);
      expect(glass(tester), allOf(greaterThan(0), lessThan(1)));
      await tester.pumpAndSettle();
      expect(find.byType(Splash), findsNothing);
      expect(glass(tester), 1);
    });
  });
}
