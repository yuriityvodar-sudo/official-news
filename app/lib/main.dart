import 'dart:async';

import 'package:flutter/material.dart';

import 'core/analytics.dart';
import 'core/push.dart';
import 'core/router.dart';
import 'core/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Not awaited: the feed shows at once; events before Firebase is up are not sent.
  unawaited(_startFirebase());
  runApp(const OfficialNewsApp());
}

/// Analytics, then push notifications, which need Firebase too (#62).
Future<void> _startFirebase() async {
  if (await startAnalytics()) await startPush();
}

class OfficialNewsApp extends StatelessWidget {
  const OfficialNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Official News',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      onGenerateRoute: onGenerateRoute,
      navigatorKey: appNavigator,
      navigatorObservers: [ScreenViews(), PushOffer()],
      initialRoute: Routes.feed,
    );
  }
}
