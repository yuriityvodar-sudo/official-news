import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show max;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/analytics.dart';
import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/config.dart';
import '../../core/motion.dart';
import '../../core/subscription.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../detail/detail_screen.dart' show openOfficialPage;
import 'chat_style.dart';
import 'paywall_sheet.dart';
import 'topup_sheet.dart';

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
/// each answer. The limit as Claude shows it (variant A of Roman's mockup,
/// 27 Oct): nothing until it is near, then "3 questions left today" over the
/// field; once none are left, a card in the field's place, with when new ones
/// come and "Buy more questions" ([TopUpSheet]). A long document's question
/// takes more of the limit, and the chat says so. Not paid any more (the
/// server's 402): the paywall shows again. Nothing of the conversation is
/// kept: it is gone with the screen.
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
  /// test sets [debugAvailable], and until its release only the builds that
  /// open it ([opened]).
  static bool get available =>
      debugAvailable ?? (!kIsWeb && Platform.isIOS && opened);

  /// Until the chat is released, only the team's builds have it: the demo,
  /// or a build with a key for Sandbox purchases ([chatSandboxKey]), Roman's
  /// own (Roman, 28 Oct) and `testflight` ones, whose testers try it for
  /// free (Roman and Yurii, 29 Oct). A `store` build has neither and keeps
  /// the note until the chat's release is decided.
  static const opened = chatDemo || chatSandboxKey != '';

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
  String? _problem;
  bool _sending = false;

  /// The questions left, today's and the bought ones together; null until known.
  int? _left;

  /// How much of the limit one question about this article takes.
  int _units = 1;

  /// When today's questions come back.
  DateTime? _resetsAt;

  ChatSubscription get _subscription => widget.subscription ?? chatSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
    final first = widget.firstQuestion;
    if (first != null) unawaited(Future.microtask(() => _ask(first)));
  }

  /// What is left, from the server: the card shows at once when nothing is.
  Future<void> _loadStatus() async {
    final transaction = _subscription.transaction;
    if (transaction == null || chatDemo) return;
    try {
      final status = await _api.chatStatus(
        articleId: widget.article.id,
        transaction: transaction,
      );
      if (!mounted) return;
      setState(() {
        _left = status.total;
        _units = status.units;
        _resetsAt = status.resetsAt;
      });
    } catch (_) {
      // Offline, or not paid: the first question says which.
    }
  }

  Future<void> _topUp() async {
    if (await TopUpSheet.show(context, subscription: widget.subscription) &&
        mounted) {
      // [chatDemo] asks no server: what is left is the pack it bought.
      setState(() => _left = chatDemo ? _subscription.boughtQuestions : null);
      await _loadStatus();
    }
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
      _left = reply.remaining;
      _units = reply.units;
      await for (final piece in reply.text) {
        if (!mounted) return;
        setState(() => answer.text += piece);
        _toEnd();
      }
      answer.done = true;
    } on ChatLimit catch (limit) {
      // Not asked: the question goes back into the field, for after a top-up.
      _turns
        ..remove(answer)
        ..remove(asked);
      _field.text = text;
      _left = 0;
      _units = limit.units;
      _resetsAt = limit.resetsAt;
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

  /// [chatDemo]: the summary, word by word, as an answer would come, with one
  /// question fewer left each time from 3, so the line over the field, the
  /// card and the top-up sheet can be seen too.
  ChatAnswer _demoAnswer() {
    final words = (widget.article.summary ?? widget.article.headline).split(
      ' ',
    );
    return ChatAnswer(
      text: Stream.periodic(
        const Duration(milliseconds: 40),
        (i) => i == 0 ? words[i] : ' ${words[i]}',
      ).take(words.length),
      remaining: _left == null ? 3 : max(0, _left! - 1),
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
    final left = _left;
    // Today's questions come back at midnight UTC, the server's day, in the
    // phone's time; without the server's word (the demo), the next one.
    final now = DateTime.now().toUtc();
    final at = (_resetsAt ?? DateTime.utc(now.year, now.month, now.day + 1))
        .toLocal();
    final resets =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    // The app's type (theme.dart), as the paywall: the serif for the
    // decision's headline and the answers, the sans for the reader's
    // questions, buttons, links and labels (Yurii, review of #188).
    final news = NewsText.from(context);

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
                      style: news.headline.copyWith(color: label),
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
                    if (_units > 1) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: style.ink.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.doc_text,
                              size: 17,
                              color: style.ink,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.chatLongDocument(_units),
                                style: TextStyle(fontSize: 13, color: label),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                            style: news.body.copyWith(color: label),
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
                  ],
                ),
              ),
              if (left == 0)
                // Nothing left: the card takes the field's place.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: _OutCard(
                    style: style,
                    resets: resets,
                    onTopUp: _topUp,
                  ),
                )
              else ...[
                if (left != null && left <= 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.clock, size: 15, color: style.ink),
                        const SizedBox(width: 6),
                        Text(
                          l10n.chatRemaining(left),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: style.ink,
                          ),
                        ),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// No questions left for today: when new ones come, or buy more.
class _OutCard extends StatelessWidget {
  const _OutCard({
    required this.style,
    required this.resets,
    required this.onTopUp,
  });

  final ChatStyle style;
  final String resets;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final muted = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: style.fill.withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: -14,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.hourglass, size: 19, color: style.ink),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  l10n.chatOutTitle,
                  textAlign: TextAlign.center,
                  // The card's title in the serif, as the paywall's (#188).
                  style: NewsText.from(context).headline.copyWith(color: label),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.chatOutBody(resets),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.35, color: muted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              color: style.fill,
              borderRadius: BorderRadius.circular(24),
              onPressed: () {
                Haptics.light();
                onTopUp();
              },
              child: Text(
                l10n.chatTopUp,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
