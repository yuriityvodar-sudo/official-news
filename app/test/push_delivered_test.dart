import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/push.dart';

/// Notifications received, counted with no id (Yurii, 27 Nov 2026).
void main() {
  test('a notification received tells the server its language and the '
      'platform, and nothing else', () async {
    final sent = <http.Request>[];
    final api = ApiClient(
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        sent.add(request);
        return http.Response('', 204);
      }),
    );
    await reportDelivered({'articleId': '01ABC', 'lang': 'uk'}, api: api);
    expect(sent, hasLength(1));
    expect(sent.single.url.toString(), 'https://api.test/v1/push/delivered');
    expect(jsonDecode(sent.single.body), {'lang': 'uk', 'platform': 'android'});
  });

  test(
    'one without a language, or a server that fails, changes nothing',
    () async {
      var calls = 0;
      final api = ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient((request) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      await reportDelivered({'articleId': '01ABC'}, api: api);
      expect(calls, 0);
      await reportDelivered({'lang': 'en'}, api: api);
      expect(calls, 1);
    },
  );
}
