import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme.dart';

void main() {
  runApp(const OfficialNewsApp());
}

class OfficialNewsApp extends StatelessWidget {
  const OfficialNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Official News',
      theme: buildTheme(),
      onGenerateRoute: onGenerateRoute,
      initialRoute: Routes.feed,
    );
  }
}
