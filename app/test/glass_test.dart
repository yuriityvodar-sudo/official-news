import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/glass.dart';

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
}
