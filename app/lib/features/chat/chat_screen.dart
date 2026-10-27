import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/analytics.dart';
import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/motion.dart';
import '../../core/subscription.dart';
import '../../l10n/app_localizations.dart';
import '../detail/detail_screen.dart' show openOfficialPage;
import 'chat_style.dart';
import 'paywall_sheet.dart';

/// One question or answer.
class _Turn {
  _Turn(this.reader, [this.text = '']);

  final bool reader;
  String text;
  bool done = false;
  bool cutOff = false;
}

/// The AI chat about one decision (#146, docs/contract.md): suggested first
/// questions, the answer streamed as it is written, the official link under
/// each answer, how many questions are left today once there are 3 or fewer.
/// Not paid any more (the server's 402): the paywall shows again. Nothing of
/// the conversation is kept: it is gone with the screen.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.article,
    this.firstQuestion,
    this.api,
    this.subscription,
    this.openLink = openOfficialPage,
  });

  final Article article;

  /// Asked at once: the paywall's sample question, once just bought.
  final String? firstQuestion;
  final ApiClient? api;

  /// [chatSubscription] unless a test brings its own.
  final ChatSubscription? subscription;
  final Future<void> Function(Uri) openLink;

  /// Where the chat is: the iOS app (StoreKit), not Android or tests, unless a
  /// test sets [debugAvailable].
  static bool get available => debugAvailable ?? (!kIsWeb && Platform.isIOS);

  @visibleForTesting
  static bool? debugAvailable;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _field = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];
  int? _remaining;
  String? _problem;
  bool _sending = false;

  ChatSubscription get _subscription => widget.subscription ?? chatSubscription;

  @override
  void initState() {
    super.initState();
    final first = widget.firstQuestion;
    if (first != null) unawaited(Future.microtask(() => _ask(first)));
  }

  @override
  void dispose() {
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    final text = question.trim();
    if (text.isEmpty || _sending || !mounted) return;
    final transaction = _subscription.transaction;
    if (transaction == null) {
      await _paywall();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final asked = _Turn(true, text);
    final answer = _Turn(false);
    setState(() {
      _problem = null;
      _sending = true;
      _turns.addAll([asked, answer]);
      _field.clear();
    });
    unawaited(
      analytics.chatQuestion(
        widget.article,
        _turns.where((t) => t.reader).length,
      ),
    );
    try {
      final reply = chatDemo
          ? _demoAnswer()
          : await _api.askChat(
              articleId: widget.article.id,
              lang: Localizations.localeOf(context).languageCode,
              messages: [
                for (final t in _turns)
                  if (t != answer && t.text.isNotEmpty) (t.reader, t.text),
              ],
              transaction: transaction,
            );
      _remaining = reply.remaining;
      await for (final piece in reply.text) {
        if (!mounted) return;
        setState(() => answer.text += piece);
        _toEnd();
      }
      answer.done = true;
    } on ChatLimit catch (limit) {
      _turns.removeLast();
      final at = limit.resetsAt?.toLocal();
      _problem = l10n.chatLimitReached(
        at == null
            ? '00:00'
            : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
      );
    } on ApiException catch (e) {
      _turns.removeLast();
      if (e.statusCode == 402) {
        _turns.removeLast();
        _subscription.lapsed();
        if (mounted) setState(() => _sending = false);
        await _paywall();
        return;
      }
      _problem = l10n.chatUnavailable;
    } catch (_) {
      // Offline, or the answer stopped in the middle.
      if (answer.text.isEmpty) {
        _turns.removeLast();
        _problem = l10n.chatUnavailable;
      } else {
        answer.cutOff = true;
      }
    }
    if (mounted) setState(() => _sending = false);
    _toEnd();
  }

  /// [chatDemo]: the summary, word by word, as an answer would come.
  ChatAnswer _demoAnswer() {
    final words = (widget.article.summary ?? widget.article.headline).split(
      ' ',
    );
    return ChatAnswer(
      text: Stream.periodic(
        const Duration(milliseconds: 40),
        (i) => i == 0 ? words[i] : ' ${words[i]}',
      ).take(words.length),
      remaining: 3,
    );
  }

  Future<void> _paywall() async {
    if (await PaywallSheet.show(context, widget.article) && mounted) {
      setState(() {});
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  });

  /// The question before an answer cut off or refused, asked again.
  void _again() {
    final last = _turns.lastWhere((t) => t.reader, orElse: () => _Turn(true));
    if (last.text.isEmpty) return;
    setState(() {
      if (_turns.isNotEmpty && !_turns.last.reader) _turns.removeLast();
      _turns.remove(last);
    });
    unawaited(_ask(last.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ChatStyle.of(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final muted = CupertinoColors.secondaryLabel.resolveFrom(context);
    final article = widget.article;
    final site = (Uri.tryParse(article.originalUrl)?.host ?? '').replaceFirst(
      RegExp(r'^www\.'),
      '',
    );
    final remaining = _remaining;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(l10n.aiAgent)),
      // Material for the default text style (no yellow underline on plain Text).
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  children: [
                    Text(
                      article.headline,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: label,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      article.source.name,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.chatNotAdvice,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    if (_turns.isEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final q in [
                            l10n.chatSuggestConcernsMe,
                            l10n.chatSuggestWhatChanges,
                            l10n.chatSuggestWhatToDo,
                          ])
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              minimumSize: const Size(44, 44),
                              color: CupertinoColors.secondarySystemFill
                                  .resolveFrom(context),
                              borderRadius: BorderRadius.circular(18),
                              onPressed: _sending ? null : () => _ask(q),
                              child: Text(
                                q,
                                style: TextStyle(fontSize: 15, color: label),
                              ),
                            ),
                        ],
                      ),
                    ],
                    for (final turn in _turns) ...[
                      const SizedBox(height: 14),
                      if (turn.reader)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 300),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: style.fill,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              turn.text,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFFFFFFFF),
                              ),
                            ),
                          ),
                        )
                      else ...[
                        if (turn.text.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: CupertinoActivityIndicator(),
                          )
                        else
                          Text(
                            turn.text,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.45,
                              color: label,
                            ),
                          ),
                        if (turn.cutOff)
                          Text(
                            l10n.chatCutOff,
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        if (turn.done)
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 44),
                            onPressed: () =>
                                widget.openLink(Uri.parse(article.originalUrl)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.arrow_up_right_square,
                                  size: 16,
                                  color: style.ink,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    l10n.readOfficialDecisionOn(site),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: style.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                    if (_problem != null ||
                        (_turns.isNotEmpty && _turns.last.cutOff)) ...[
                      const SizedBox(height: 12),
                      if (_problem != null)
                        Text(
                          _problem!,
                          style: TextStyle(fontSize: 14, color: muted),
                        ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: _sending ? null : _again,
                        child: Text(
                          l10n.tryAgain,
                          style: TextStyle(fontSize: 15, color: style.ink),
                        ),
                      ),
                    ],
                    if (remaining != null && remaining <= 3) ...[
                      const SizedBox(height: 10),
                      Text(
                        l10n.chatRemaining(remaining),
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              // One row at the bottom: the field with its send button.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: CupertinoTextField(
                  controller: _field,
                  placeholder: l10n.chatAsk,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _sending ? null : _ask,
                  padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiarySystemFill.resolveFrom(
                      context,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  suffix: CupertinoButton(
                    padding: const EdgeInsets.only(right: 6),
                    minimumSize: const Size(44, 44),
                    onPressed: _sending
                        ? null
                        : () {
                            Haptics.light();
                            unawaited(_ask(_field.text));
                          },
                    child: Icon(
                      CupertinoIcons.arrow_up_circle_fill,
                      size: 32,
                      color: style.fill,
                      semanticLabel: l10n.chatSend,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
