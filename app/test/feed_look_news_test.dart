import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderClipRect;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/glass.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// The news look's masthead (garnet and seal), with iOS's glass on its
/// buttons.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    feedDesign.value = FeedDesign.garnet;
    GlassCircle.debugNative = true;
  });
  tearDown(() {
    feedDesign.value = FeedDesign.now;
    GlassCircle.debugNative = null;
  });

  testWidgets("the title's clip leaves the gear's glass room for its shadow "
      "under the title's band: cut at the band's foot, it showed as a band "
      'under the buttons (Roman, 30 Oct)', (tester) async {
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
    final controller = FeedController(
      api: ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient(
          (request) async =>
              fakeMenus(request) ??
              http.Response(
                jsonEncode({
                  'items': <Object>[],
                  'nextCursor': null,
                  'top': <Object>[],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(440, 956) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        onGenerateRoute: onGenerateRoute,
        home: FeedScreen(
          controller: controller,
          newCheckEvery: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final glass = find.descendant(
      of: find.byType(GlassCircle),
      matching: find.byType(UiKitView),
    );
    expect(glass, findsWidgets);
    final view = tester.getRect(glass.first);
    final clip = tester.renderObject<RenderClipRect>(
      find.ancestor(of: glass.first, matching: find.byType(ClipRect)).first,
    );
    final band = clip.describeApproximatePaintClip(clip.child!)!;
    expect(
      clip.localToGlobal(band.bottomLeft).dy,
      greaterThanOrEqualTo(view.bottom),
    );
  });
}
