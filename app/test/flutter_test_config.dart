import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/pictures.dart';

/// Tests have no files on a phone: pictures come from a stand-in that has none
/// (each picture shows its empty placeholder, as when a download fails).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  pictureCache = NoPictures();
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
