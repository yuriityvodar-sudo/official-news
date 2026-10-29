import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/feed_language.dart';
import '../../core/motion.dart';
import '../../core/news_widgets.dart';
import '../../core/push.dart';
import '../../core/support.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'settings_screen.dart' show appVersion;

/// Who answers, above our replies; a name, never translated.
const _teamName = 'Outer News';

/// Messages to us (#220), from Settings → Contact & Support → Write to us, or
/// from the notification of our reply. No login: the phone's anonymous id
/// ([supportDevice]) holds the conversation. One message at a time: after
/// sending, the field stays locked until we reply, or the server's
/// `writeAfter` passes.
///
/// The app's type, as in the AI chat: the reader's messages in sans bubbles,
/// our replies in the serif with our name above them.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.api, this.pushToken});

  /// The route's name, from Settings and from a notification alike.
  static const routeName = '/support';

  /// The server; tests pass one with a fake client.
  final ApiClient? api;

  /// The FCM token for the reply's notification ([Push.token]); tests pass
  /// their own.
  final Future<String?> Function()? pushToken;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen>
    with WidgetsBindingObserver {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _field = TextEditingController();

  /// Asked for when the screen opens, so a send rarely waits for it.
  late final Future<String?> _token;

  bool _loading = true;
  bool _loadFailed = false;
  bool _sending = false;
  SupportThread? _thread;

  /// Why the last send did not go through, in the reader's words.
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _token = _askToken();
    _field.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _field.dispose();
    super.dispose();
  }

  /// Back in the app: our reply may have come meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) unawaited(_load());
  }

  /// A `Future<String?>` of its own, whatever type the given one has, so a
  /// timeout can end it with null.
  Future<String?> _askToken() async {
    try {
      return await (widget.pushToken ?? push.token)();
    } catch (error) {
      debugPrint('support: no token: $error');
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _thread == null;
      _loadFailed = false;
    });
    try {
      final thread = await _api.supportThread(await supportDevice());
      if (!mounted) return;
      setState(() {
        _thread = thread;
        _loading = false;
        // A locked conversation says itself when the reader can write again.
        if (thread != null && !thread.canWrite) _notice = null;
      });
    } catch (error) {
      debugPrint('support: not loaded: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        // A conversation already on screen stays; only a first load fails.
        _loadFailed = _thread == null;
      });
    }
  }

  Future<void> _send(AppLocalizations l10n) async {
    final text = _field.text.trim();
    if (text.isEmpty || _sending) return;
    Haptics.light();
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      final device = await supportDevice();
      // Never held up by the token: without one, the reply still shows here.
      final token = await _token.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      final thread = await _api.sendSupport(
        device: device,
        text: text,
        lang: FeedLanguage.fromCode(l10n.localeName).code,
        app: appVersion,
        push: token,
      );
      if (!mounted) return;
      _field.clear();
      setState(() => _thread = thread);
    } on SupportWaiting catch (e) {
      final after = e.writeAfter;
      _notice = after == null
          ? l10n.supportReceived
          : l10n.supportWriteAgainAfter(fullDate(after, l10n));
      unawaited(_load());
    } on SupportLimit catch (e) {
      final at = e.resetsAt;
      _notice = at == null
          ? l10n.supportSendError
          : l10n.supportTooMany(clockTime(at, l10n));
    } catch (error) {
      debugPrint('support: not sent: $error');
      _notice = l10n.supportSendError;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return CupertinoPageScaffold(
      backgroundColor: grouped,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l10n.supportWrite),
        previousPageTitle: l10n.contactSupport,
        backgroundColor: grouped,
        border: null,
      ),
      // Material for the default text style (no yellow underline on plain Text).
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(child: _body(context, l10n)),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.supportLoadError,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: secondary),
              ),
              CupertinoButton(
                onPressed: _load,
                child: Text(
                  l10n.tryAgain,
                  style: const TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final thread = _thread;
    final messages = thread?.messages ?? const <SupportMessage>[];
    final writeAfter = thread?.writeAfter;
    return Column(
      children: [
        Expanded(
          child: ListView(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            // Reversed, so the newest message sits above the field; the
            // notes under it read "received", then when to write again.
            children: [
              if (thread != null && !thread.canWrite && writeAfter != null)
                _Note(l10n.supportWriteAgainAfter(fullDate(writeAfter, l10n))),
              if (thread != null && thread.waiting) _Note(l10n.supportReceived),
              for (final message in messages.reversed)
                _Bubble(message: message),
              if (messages.isEmpty) _Note(l10n.supportIntro),
            ],
          ),
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _notice!,
                style: TextStyle(fontSize: 14, color: secondary),
              ),
            ),
          ),
        if (thread == null || thread.canWrite) _composer(context, l10n),
      ],
    );
  }

  /// The field and Send; a counter once the message nears the limit.
  Widget _composer(BuildContext context, AppLocalizations l10n) {
    final left = supportMaxLength - supportLength(_field.text);
    final empty = _field.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoTextField(
            controller: _field,
            placeholder: l10n.supportPlaceholder,
            minLines: 3,
            maxLines: 8,
            inputFormatters: const [SupportLengthFormatter()],
            enabled: !_sending,
            textCapitalization: TextCapitalization.sentences,
            padding: const EdgeInsets.all(12),
            style: TextStyle(
              fontSize: 16,
              color: CupertinoColors.label.resolveFrom(context),
            ),
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: left <= 200
                    ? Text(
                        l10n.supportCharsLeft(left),
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: empty || _sending ? null : () => _send(l10n),
                child: _sending
                    ? const CupertinoActivityIndicator()
                    : Text(
                        l10n.supportSend,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: empty
                              ? CupertinoColors.tertiaryLabel.resolveFrom(
                                  context,
                                )
                              : AppColors.accent,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A line from the app between the messages: what happens next.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14,
        height: 1.35,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
      ),
    ),
  );
}

/// A message: the reader's in a bubble on the right, ours on the left in the
/// serif under our name. VoiceOver reads who wrote it and when, then the text.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final when =
        '${fullDate(message.at, l10n)}, ${clockTime(message.at, l10n)}';
    final who = message.fromTeam ? _teamName : l10n.supportYou;
    final Widget content;
    if (message.fromTeam) {
      content = Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          // A tint of the accent, in light and dark alike: ours at a glance.
          color: AppColors.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Already in the label VoiceOver reads.
            ExcludeSemantics(
              child: Text(
                _teamName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.text,
              style: NewsText.from(
                context,
              ).body.copyWith(fontSize: 17, color: label),
            ),
          ],
        ),
      );
    } else {
      content = Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            message.text,
            style: const TextStyle(fontSize: 16, color: Color(0xFFFFFFFF)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        container: true,
        label: '$who, $when',
        child: Column(
          crossAxisAlignment: message.fromTeam
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            content,
            const SizedBox(height: 3),
            ExcludeSemantics(
              child: Text(
                when,
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
