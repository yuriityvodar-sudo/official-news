import 'dart:convert';

import 'package:http/http.dart' as http;

import 'article.dart';
import 'config.dart';
import 'filters.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The AI agent's answer as it is written; the questions left after it,
/// today's and the bought ones together; and how many of the limit one
/// question about this article takes (a long document more than one).
class ChatAnswer {
  const ChatAnswer({required this.text, this.remaining, this.units = 1});

  final Stream<String> text;
  final int? remaining;
  final int units;
}

/// No questions left for today (429): today's come back at [resetsAt]; bought
/// ones would go on at once.
class ChatLimit extends ApiException {
  ChatLimit(this.resetsAt, {this.units = 1}) : super(429, 'Daily limit');

  final DateTime? resetsAt;
  final int units;
}

/// What a subscriber has left for questions about one article (#146):
/// today's, the bought ones (spent after them, never expiring), how many of
/// the limit one question about it takes, and when today's come back.
class ChatStatus {
  const ChatStatus({
    required this.questionsLeft,
    required this.boughtQuestions,
    required this.units,
    this.resetsAt,
  });

  factory ChatStatus.fromJson(Map<String, dynamic> json) => ChatStatus(
    questionsLeft: (json['questionsLeft'] as num?)?.toInt() ?? 0,
    boughtQuestions: (json['boughtQuestions'] as num?)?.toInt() ?? 0,
    units: (json['units'] as num?)?.toInt() ?? 1,
    resetsAt: DateTime.tryParse('${json['resetsAt']}'),
  );

  final int questionsLeft;
  final int boughtQuestions;
  final int units;
  final DateTime? resetsAt;

  int get total => questionsLeft + boughtQuestions;
}

/// Client for the endpoints in docs/contract.md.
class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    String? sandboxKey,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? apiUrl,
       _sandboxKey = sandboxKey ?? chatSandboxKey;

  final Duration timeout;

  final http.Client _client;
  final String _baseUrl;
  final String _sandboxKey;

  /// The chat's requests are JSON, with Roman's key on his own builds
  /// ([chatSandboxKey]).
  Map<String, String> get _chatHeaders => {
    'content-type': 'application/json',
    if (_sandboxKey.isNotEmpty) 'x-chat-sandbox-key': _sandboxKey,
  };

  /// `GET /articles`: news from the last 7 days, newest first, 20 per page.
  /// With `lang` (`uk`, `ru`, `es`, `de`) only the articles translated into it, in
  /// the English order (release together); `en` or none is the English feed,
  /// without the parameter.
  /// An article that is not in `lang` is dropped here, whatever the server sends
  /// ([ArticlesPage.inLanguage]).
  /// With `country` (two letters, #68) only that country's articles; with
  /// `group` (a group's id from [fetchCountries]) its countries' articles
  /// together, at most one of the two; with `topic` (#67) only that topic's.
  /// Pages, cursors, `after` and `top` all follow them, so every request for
  /// one feed sends the same ones.
  Future<ArticlesPage> fetchArticles({
    String? cursor,
    DateTime? since,
    int? after,
    int limit = 20,
    String? lang,
    String? country,
    String? group,
    String? topic,
  }) async {
    final param = _langParam(lang);
    final uri = Uri.parse('$_baseUrl/articles').replace(
      queryParameters: {
        'limit': '$limit',
        'cursor': ?cursor,
        if (since != null) 'since': since.toUtc().toIso8601String(),
        if (after != null) 'after': '$after',
        'lang': ?param,
        'country': ?country,
        'group': ?group,
        'topic': ?topic,
      },
    );
    final page = ArticlesPage.fromJson(await _getJson(uri));
    return param == null ? page : page.inLanguage(param);
  }

  /// `GET /articles/:id`; with `lang`, 404 when it is not translated, also when
  /// a server without translations answers in English.
  Future<Article> fetchArticle(String id, {String? lang}) async {
    final uri = Uri.parse('$_baseUrl/articles/$id');
    final param = _langParam(lang);
    final article = Article.fromJson(
      await _getJson(
        param == null ? uri : uri.replace(queryParameters: {'lang': param}),
      ),
    );
    if (param != null && article.lang != param) {
      throw ApiException(404, 'Not translated into $param');
    }
    return article;
  }

  /// `GET /topics` (#67): the topics with at least one article in the feed's
  /// 7 days, under `country` or `group` when given, busiest first, named in
  /// `lang`. A server without it answers 404 ([ApiException]); an answer of
  /// another shape is a [FormatException].
  Future<List<FeedTopic>> fetchTopics({
    String? lang,
    String? country,
    String? group,
  }) async {
    final json = await _getJson(
      _withQuery('$_baseUrl/topics', {
        'lang': ?_langParam(lang),
        'country': ?country,
        'group': ?group,
      }),
    );
    return [
      for (final t in _list(json, 'topics'))
        FeedTopic(_string(t, 'id'), _string(t, 'name')),
    ];
  }

  /// `GET /countries` (#68): the Where menu, named in `lang`, in the server's
  /// order: the groups of countries, then the countries that have sources.
  /// A server from before the groups has no `groups`: [WhereMenu.groups] is
  /// null, and the menu has the countries only.
  Future<WhereMenu> fetchCountries({String? lang}) async {
    final json = await _getJson(
      _withQuery('$_baseUrl/countries', {'lang': ?_langParam(lang)}),
    );
    return WhereMenu(
      groups: json['groups'] == null
          ? null
          : [
              for (final g in _list(json, 'groups'))
                FeedGroup(_string(g, 'id'), _string(g, 'name')),
            ],
      countries: [
        for (final c in _list(json, 'countries'))
          FeedCountry(_string(c, 'code'), _string(c, 'name')),
      ],
    );
  }

  static Uri _withQuery(String url, Map<String, String> query) {
    final uri = Uri.parse(url);
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  static List<Map<String, dynamic>> _list(
    Map<String, dynamic> json,
    String key,
  ) {
    final list = json[key];
    if (list is! List) throw FormatException('No "$key" in the answer');
    return [
      for (final item in list)
        if (item is Map<String, dynamic>)
          item
        else
          throw FormatException('An item of "$key" is not an object'),
    ];
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('No "$key" in $json');
    }
    return value;
  }

  /// `POST /v1/chat` (#146): the AI agent's answer about one decision, for a
  /// subscriber. [messages] is the conversation so far, ending with the new
  /// question, as `(fromReader, text)`; [transaction] the subscription's
  /// latest signed transaction. The answer comes as it is written. Throws an
  /// [ApiException] with the server's status: 402 not paid, 404 not in the
  /// feed, 429 today's questions used up ([ChatLimit] with when they come
  /// back), 503 the agent not available.
  Future<ChatAnswer> askChat({
    required String articleId,
    required String lang,
    required List<(bool, String)> messages,
    required String transaction,
  }) async {
    final request = http.Request('POST', Uri.parse('$_baseUrl/v1/chat'))
      ..headers.addAll(_chatHeaders)
      ..body = jsonEncode({
        'articleId': articleId,
        'lang': lang,
        'messages': [
          for (final (reader, text) in messages)
            {'role': reader ? 'user' : 'assistant', 'text': text},
        ],
        'transaction': transaction,
      });
    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      if (response.statusCode == 429) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        throw ChatLimit(
          DateTime.tryParse('${json['resetsAt']}'),
          units: (json['units'] as num?)?.toInt() ?? 1,
        );
      }
      throw ApiException(response.statusCode, body);
    }
    return ChatAnswer(
      text: response.stream.transform(utf8.decoder),
      remaining: int.tryParse(response.headers['x-chat-remaining'] ?? ''),
      units: int.tryParse(response.headers['x-chat-units'] ?? '') ?? 1,
    );
  }

  /// `POST /v1/chat/status` (#146): what is left for questions about
  /// [articleId] before asking. Throws an [ApiException] (402 not paid).
  Future<ChatStatus> chatStatus({
    required String articleId,
    required String transaction,
  }) async => ChatStatus.fromJson(
    await _postJson('/v1/chat/status', {
      'articleId': articleId,
      'transaction': transaction,
    }),
  );

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object> body,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: _chatHeaders,
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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
