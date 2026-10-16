import 'dart:async';

import 'package:official_news/core/push.dart';

/// Firebase Cloud Messaging as the tests want it: iOS answers [answer] when it
/// asks (only once [question] completes, while one is set); topic changes fail
/// while [failTopics] is set.
class FakeMessaging implements Messaging {
  FakeMessaging({
    this.status = PushPermission.notAsked,
    this.answer = PushPermission.granted,
    this.initial,
  });

  PushPermission status;
  PushPermission answer;
  PushTap? initial;
  bool apnsToken = true;
  Object? failTopics;
  int asked = 0;

  /// iOS's question still on screen: [requestPermission] answers once this
  /// completes.
  Completer<void>? question;
  bool tokenAllowed = false;
  bool banners = false;
  final calls = <String>[];
  final tapEvents = StreamController<PushTap>.broadcast();
  final tokenEvents = StreamController<void>.broadcast();

  @override
  Future<PushPermission> permission() async => status;

  @override
  Future<PushPermission> requestPermission() async {
    asked++;
    await question?.future;
    if (status == PushPermission.notAsked) status = answer;
    return status;
  }

  @override
  Future<void> allowToken() async => tokenAllowed = true;

  @override
  Future<bool> ready() async => apnsToken;

  @override
  Future<void> subscribe(String topic) async {
    calls.add('subscribe $topic');
    if (failTopics != null) throw failTopics!;
  }

  @override
  Future<void> unsubscribe(String topic) async {
    calls.add('unsubscribe $topic');
    if (failTopics != null) throw failTopics!;
  }

  @override
  Future<void> showInForeground() async => banners = true;

  @override
  Future<PushTap?> initialTap() async => initial;

  @override
  Stream<PushTap> get taps => tapEvents.stream;

  @override
  Stream<void> get tokenChanges => tokenEvents.stream;
}
