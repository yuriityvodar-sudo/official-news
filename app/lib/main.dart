import 'dart:async';

import 'package:flutter/material.dart';

import 'core/analytics.dart';
import 'core/router.dart';
import 'core/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Not awaited: the feed shows at once; events before Firebase is up are not sent.
  unawaited(startAnalytics());
  runApp(const OfficialNewsApp());
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
      navigatorObservers: [ScreenViews()],
      initialRoute: Routes.feed,
    );
  }
}
