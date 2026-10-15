import 'dart:convert';

import 'package:http/http.dart' as http;

import 'article.dart';
import 'config.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Client for the endpoints in docs/contract.md.
class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? apiUrl;

  final Duration timeout;

  final http.Client _client;
  final String _baseUrl;

  /// `GET /articles`: news from the last 7 days, newest first, 20 per page.
  /// With `lang` (`uk`, `ru`) only the articles translated into it, in that
  /// language's own order; `en` or none is the English feed, without the parameter.
  Future<ArticlesPage> fetchArticles({
    String? cursor,
    DateTime? since,
    int? after,
    int limit = 20,
    String? lang,
  }) async {
    final uri = Uri.parse('$_baseUrl/articles').replace(
      queryParameters: {
        'limit': '$limit',
        'cursor': ?cursor,
        if (since != null) 'since': since.toUtc().toIso8601String(),
        if (after != null) 'after': '$after',
        'lang': ?_langParam(lang),
      },
    );
    return ArticlesPage.fromJson(await _getJson(uri));
  }

  /// `GET /articles/:id`; with `lang`, 404 when it is not translated.
  Future<Article> fetchArticle(String id, {String? lang}) async {
    final uri = Uri.parse('$_baseUrl/articles/$id');
    final param = _langParam(lang);
    return Article.fromJson(
      await _getJson(
        param == null ? uri : uri.replace(queryParameters: {'lang': param}),
      ),
    );
  }

  /// English is the API without `lang`, so its requests stay as they were.
  static String? _langParam(String? lang) =>
      lang == null || lang == 'en' ? null : lang;

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    // A phone on a weak network should not wait forever; the feed shows its error state instead.
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}
