import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/pictures.dart';
import 'package:official_news/core/read_mark.dart';
import 'package:official_news/features/feed/feed_look.dart';

/// Tests have no files on a phone: pictures come from a stand-in that has none
/// (each picture shows its empty placeholder, as when a download fails).
///
/// Dates outside a screen use the same date data the app's MaterialApp loads
/// (#52), so a test can format "Saturday 28 March" without pumping a widget.
///
/// Read articles are dimmed, as in the app before the prototype's Read
/// switch (the preview starts with the blue dot): the dot styles have tests
/// of their own (read_style_test.dart).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  pictureCache = NoPictures();
  readStyle.value = ReadStyle.dim;
  await GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  await testMain();
}

class NoPictures extends Fake implements BaseCacheManager {
  final asked = <String>[];

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    asked.add(url);
    return Stream.error(
      HttpExceptionWithStatus(404, 'no pictures in tests', uri: Uri.parse(url)),
    );
  }
}
