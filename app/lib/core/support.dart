import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// One message of a conversation with us (#220): the reader's or the team's.
class SupportMessage {
  const SupportMessage({
    required this.fromTeam,
    required this.text,
    required this.at,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
    fromTeam: json['from'] == 'team',
    text: '${json['text'] ?? ''}',
    at: DateTime.tryParse('${json['at']}') ?? DateTime.now(),
  );

  final bool fromTeam;
  final String text;
  final DateTime at;
}

/// The phone's conversation with us, as `GET /v1/support/thread` returns it:
/// `waiting` for our reply, `answered` or `closed`; whether the reader can
/// write now, and when they can again if not.
class SupportThread {
  const SupportThread({
    required this.status,
    required this.messages,
    required this.canWrite,
    this.writeAfter,
  });

  factory SupportThread.fromJson(Map<String, dynamic> json) => SupportThread(
    status: '${json['status']}',
    messages: [
      for (final m in json['messages'] as List? ?? const [])
        if (m is Map<String, dynamic>) SupportMessage.fromJson(m),
    ],
    canWrite: json['canWrite'] == true,
    writeAfter: DateTime.tryParse('${json['writeAfter']}'),
  );

  final String status;
  final List<SupportMessage> messages;
  final bool canWrite;
  final DateTime? writeAfter;

  bool get waiting => status == 'waiting';
}

/// 409: the last message is still waiting for our reply; the reader can
/// write again at [writeAfter].
class SupportWaiting extends ApiException {
  SupportWaiting(this.writeAfter) : super(409, 'Waiting for a reply');

  final DateTime? writeAfter;
}

/// 429: too many messages today; more at [resetsAt].
class SupportLimit extends ApiException {
  SupportLimit(this.resetsAt) : super(429, 'Too many today');

  final DateTime? resetsAt;
}

/// The longest message the server takes, after trimming.
const supportMaxLength = 2000;

const _deviceKey = 'support.device';

/// The phone's anonymous id for its conversation with us: 32 random bytes,
/// base64url without padding (43 characters), made once and kept on the
/// phone. Nothing ties it to the reader; the server keeps only its hash.
Future<String> supportDevice([SharedPreferences? prefs]) async {
  final store = prefs ?? await SharedPreferences.getInstance();
  final saved = store.getString(_deviceKey);
  if (saved != null && saved.length == 43) return saved;
  final random = Random.secure();
  final id = base64Url
      .encode([for (var i = 0; i < 32; i++) random.nextInt(256)])
      .replaceAll('=', '');
  await store.setString(_deviceKey, id);
  return id;
}
