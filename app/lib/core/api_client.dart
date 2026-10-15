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
  Future<ArticlesPage> fetchArticles({
    String? cursor,
    DateTime? since,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$_baseUrl/articles').replace(
      queryParameters: {
        'limit': '$limit',
        'cursor': ?cursor,
        if (since != null) 'since': since.toUtc().toIso8601String(),
      },
    );
    return ArticlesPage.fromJson(await _getJson(uri));
  }

  /// `GET /articles/:id`.
  Future<Article> fetchArticle(String id) async =>
      Article.fromJson(await _getJson(Uri.parse('$_baseUrl/articles/$id')));

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    // A phone on a weak network should not wait forever; the feed shows its error state instead.
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}
