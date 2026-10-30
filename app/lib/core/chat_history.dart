import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'article.dart';

/// One conversation with the AI agent about one decision, as kept on the
/// phone: the article it is about, the questions and answers, oldest first,
/// and when it last changed.
class ChatConversation {
  const ChatConversation({
    required this.article,
    required this.messages,
    required this.updatedAt,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        article: Article.fromJson(json['article'] as Map<String, dynamic>),
        messages: [
          for (final m in json['messages'] as List? ?? const [])
            if (m is Map<String, dynamic>)
              (m['reader'] == true, '${m['text'] ?? ''}'),
        ],
        updatedAt:
            DateTime.tryParse('${json['updatedAt']}')?.toLocal() ??
            DateTime.now(),
      );

  final Article article;

  /// (the reader's, the text): a question when the reader's, else an answer.
  final List<(bool, String)> messages;
  final DateTime updatedAt;

  /// The last question asked, for the list's second line.
  String get lastQuestion =>
      messages.lastWhere((m) => m.$1, orElse: () => (true, '')).$2;

  Map<String, dynamic> toJson() => {
    'article': article.toJson(),
    'messages': [
      for (final (reader, text) in messages) {'reader': reader, 'text': text},
    ],
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

/// The reader's conversations with the AI agent (#146, Roman's pick B,
/// 30 Oct): kept only on this phone, newest first, never sent anywhere; the
/// app's privacy policy says so (`privacyChat`). At most [max], the oldest
/// dropped first, each with its last [maxMessages] messages: as many as the
/// server takes with a question (docs/contract.md).
class ChatHistory extends ChangeNotifier {
  ChatHistory({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const key = 'chat.conversations';
  static const max = 50;
  static const maxMessages = 20;

  final Future<SharedPreferences> Function() _prefs;
  List<ChatConversation> _all = const [];
  Future<void>? _loading;

  /// Newest first.
  List<ChatConversation> get conversations => _all;

  bool get isEmpty => _all.isEmpty;

  /// Reads what the phone keeps, once; a damaged entry is left out.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final saved = (await _prefs()).getString(key);
    if (saved == null) return;
    try {
      _all = [
        for (final c in jsonDecode(saved) as List)
          if (c is Map<String, dynamic>) ChatConversation.fromJson(c),
      ];
    } catch (_) {
      _all = const [];
    }
    notifyListeners();
  }

  /// The conversation about [articleId], if any.
  ChatConversation? of(String articleId) {
    for (final c in _all) {
      if (c.article.id == articleId) return c;
    }
    return null;
  }

  /// Keeps [messages] as the conversation about [article], now the newest.
  Future<void> save(Article article, List<(bool, String)> messages) async {
    await load();
    final kept = messages.length > maxMessages
        ? messages.sublist(messages.length - maxMessages)
        : messages;
    _all = [
      ChatConversation(
        article: article,
        messages: List.unmodifiable(kept),
        updatedAt: DateTime.now(),
      ),
      ..._all.where((c) => c.article.id != article.id),
    ].take(max).toList();
    await _write();
  }

  Future<void> delete(String articleId) async {
    await load();
    _all = [..._all.where((c) => c.article.id != articleId)];
    await _write();
  }

  Future<void> clear() async {
    await load();
    _all = const [];
    await _write();
  }

  Future<void> _write() async {
    notifyListeners();
    final prefs = await _prefs();
    if (_all.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(
        key,
        jsonEncode([for (final c in _all) c.toJson()]),
      );
    }
  }
}

/// The app's conversations; tests bring their own ([ChatHistory.new]).
final chatHistory = ChatHistory();
