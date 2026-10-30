import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show max, min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/analytics.dart';
import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/config.dart';
import '../../core/glass.dart';
import '../../core/motion.dart';
import '../../core/sheet.dart';
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

  /// Its own, so a turn keeps its place and state as others come.
  final key = GlobalKey();
}

/// The AI chat about one decision (#146, docs/contract.md): suggested first
/// questions, the answer streamed as it is written, the official link under
/// each answer. It moves as ChatGPT's does (Roman's pick A, 30 Oct): a sheet
/// from the bottom over the article ([show]), whose header folds into the
/// title once the conversation starts; the question asked goes to the top
/// of the screen and its answer is written under it, the screen keeping
/// still, never jumping to the answer's end; a pulsing dot while the agent
/// thinks; the answer's bold and lists shown as such ([_Formatted]). The limit as Claude shows it (variant A of Roman's mockup,
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
    this.scroll,
    this.subscription,
    this.openLink = openOfficialPage,
  });

  /// The chat as a sheet from the bottom, over the article, which steps back
  /// under it as iOS's sheets do, its glass with it ([showSheet]); closed
  /// with its button, or pulled down.
  static Future<void> show(
    BuildContext context,
    Article article, {
    String? firstQuestion,
  }) => showSheet<void>(
    context: context,
    scrollableBuilder: (_, scroll) => ChatScreen(
      article: article,
      firstQuestion: firstQuestion,
      scroll: scroll,
    ),
  );

  final Article article;

  /// Asked at once: the paywall's sample question, once just bought.
  final String? firstQuestion;
  final ApiClient? api;

  /// The sheet's scroll controller ([show]): pulled down at its top, the
  /// conversation closes the sheet.
  final ScrollController? scroll;

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
  late final ScrollController _scroll = widget.scroll ?? ScrollController();
  final _turns = <_Turn>[];

  /// The end of the conversation, before [_room].
  final _end = GlobalKey();

  /// Room under the conversation, so the last question can stand at the top
  /// while its answer is shorter than the screen ([_fit]).
  double _room = 0;
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
    if (widget.scroll == null) _scroll.dispose();
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
    final first = _turns.isEmpty;
    setState(() {
      _problem = null;
      _sending = true;
      _turns.addAll([asked, answer]);
      _field.clear();
    });
    // The first stands at the top as the header folds; a later one is taken there.
    if (!first) _toQuestion();
    _fit();
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
        _fit();
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
    _fit();
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

  /// The last question asked: it stands at the top of the screen.
  _Turn get _lastAsked =>
      _turns.lastWhere((t) => t.reader, orElse: () => _Turn(true));

  /// Where [key]'s widget stands in the conversation, from its top.
  double? _offsetOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box == null || !_scroll.hasClients) return null;
    return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
  }

  /// Sets [_room] once laid out: as much as the screen has left under the
  /// last question and what came after it, none once that fills the screen.
  /// The question then stays at the top while its answer grows into the room.
  void _fit() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final top = _offsetOf(_lastAsked.key);
    final end = _offsetOf(_end);
    if (top == null || end == null || !mounted) return;
    final room = max(0.0, _scroll.position.viewportDimension - (end - top));
    if ((room - _room).abs() > 0.5) setState(() => _room = room);
  });

  /// Takes the last question to the top, once there is room for it there.
  void _toQuestion() => WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final top = _offsetOf(_lastAsked.key);
      if (top == null || !mounted) return;
      final to = clampDouble(top, 0, _scroll.position.maxScrollExtent);
      if (Motion.reduced(context)) return _scroll.jumpTo(to);
      unawaited(
        _scroll.animateTo(
          to,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        ),
      );
    });
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

    final talking = _turns.isNotEmpty;
    final fold = Motion.reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);

    // The title, as the paywall's; once the conversation starts, the decision
    // it is about under it, in the header's place.
    final title = Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Row(
        children: [
          Icon(CupertinoIcons.sparkles, size: 20, color: style.ink),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.aiAgent,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: label,
                  ),
                ),
                AnimatedSize(
                  duration: fold,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: talking
                      ? Text(
                          article.headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: muted),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: l10n.paywallClose,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () => Navigator.of(context).maybePop(),
              child: GlassCircle(
                size: 34,
                child: Icon(
                  CupertinoIcons.xmark,
                  size: 16,
                  color: label,
                  semanticLabel: l10n.paywallClose,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // What the chat is about and the suggested questions, until the first is asked.
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(article.headline, style: news.headline.copyWith(color: label)),
        const SizedBox(height: 4),
        Text(article.source.name, style: TextStyle(fontSize: 13, color: muted)),
        const SizedBox(height: 8),
        Text(l10n.chatNotAdvice, style: TextStyle(fontSize: 12, color: muted)),
        if (_units > 1) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: style.ink.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.doc_text, size: 17, color: style.ink),
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
                color: CupertinoColors.secondarySystemFill.resolveFrom(context),
                borderRadius: BorderRadius.circular(18),
                onPressed: _sending ? null : () => _ask(q),
                child: Text(q, style: TextStyle(fontSize: 15, color: label)),
              ),
          ],
        ),
      ],
    );

    return CupertinoPageScaffold(
      // Material for the default text style (no yellow underline on plain Text).
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Column(
            children: [
              title,
              Expanded(
                // All of it laid out, not a lazy list: the last question must
                // be there to be taken to the top, however far down it is.
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSize(
                        duration: fold,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        onEnd: _fit,
                        child: talking
                            ? const SizedBox(width: double.infinity)
                            : header,
                      ),
                      for (final turn in _turns) ...[
                        SizedBox(height: turn.reader ? 6 : 14),
                        if (turn.reader)
                          Align(
                            key: turn.key,
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
                            _ThinkingDot(color: label)
                          else
                            _Answer(
                              key: turn.key,
                              text: turn.text,
                              style: news.body.copyWith(color: label),
                              onGrow: _fit,
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
                              onPressed: () => widget.openLink(
                                Uri.parse(article.originalUrl),
                              ),
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
                                      article.isEvent
                                          ? '${l10n.readOnWikipedia}, $site'
                                          : l10n.readOfficialDecisionOn(site),
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
                      SizedBox(key: _end),
                      SizedBox(height: _room),
                    ],
                  ),
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

/// While the agent thinks: a dot that breathes, as ChatGPT's does (Roman's
/// pick A, 30 Oct), still with Reduce Motion.
class _ThinkingDot extends StatefulWidget {
  const _ThinkingDot({required this.color});

  final Color color;

  @override
  State<_ThinkingDot> createState() => _ThinkingDotState();
}

class _ThinkingDotState extends State<_ThinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _breath.value = 1;
    } else if (!_breath.isAnimating) {
      unawaited(_breath.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breath = CurvedAnimation(parent: _breath, curve: Curves.easeInOut);
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 26,
        child: FadeTransition(
          opacity: Tween(begin: 0.55, end: 1.0).animate(breath),
          child: ScaleTransition(
            scale: Tween(begin: 0.75, end: 1.1).animate(breath),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An answer as it comes: the text a little behind what has arrived,
/// catching up a few letters a frame, so the words flow in rather than jump
/// in by the piece, as ChatGPT writes; all at once with Reduce Motion.
class _Answer extends StatefulWidget {
  const _Answer({
    super.key,
    required this.text,
    required this.style,
    this.onGrow,
  });

  final String text;
  final TextStyle style;

  /// More of it shows: the room under the conversation is measured again.
  final VoidCallback? onGrow;

  @override
  State<_Answer> createState() => _AnswerState();
}

class _AnswerState extends State<_Answer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  int _shown = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catchUp();
  }

  @override
  void didUpdateWidget(_Answer old) {
    super.didUpdateWidget(old);
    _catchUp();
  }

  void _catchUp() {
    if (Motion.reduced(context)) {
      _ticker.stop();
      _shown = widget.text.length;
      widget.onGrow?.call();
    } else if (_shown < widget.text.length && !_ticker.isActive) {
      unawaited(_ticker.start());
    }
  }

  void _tick(Duration _) {
    final behind = widget.text.length - _shown;
    if (behind <= 0) return _ticker.stop();
    // At least 2 letters a frame (120 a second), more the further behind.
    setState(() => _shown += max(2, (behind / 8).ceil()));
    widget.onGrow?.call();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Formatted(
    widget.text.substring(0, min(_shown, widget.text.length)),
    style: widget.style,
  );
}

/// The little Markdown the model writes, shown as such instead of its marks
/// (Roman, 30 Oct: the answer showed "**"): paragraphs, lists of "-", "*" or
/// "•" and of "1.", "#" headings and **bold**. A "**" not yet closed, as the
/// answer comes, makes what follows bold, as it will be. Anything else
/// stays as written.
class _Formatted extends StatelessWidget {
  const _Formatted(this.text, {required this.style});

  final String text;
  final TextStyle style;

  static final _item = RegExp(r'^\s*(?:[-*•]|(\d+)[.)])\s+(.*)$');
  static final _heading = RegExp(r'^#{1,6}\s+(.*)$');

  TextSpan _inline(String text, TextStyle style) {
    final parts = text.split('**');
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i < parts.length; i++)
          if (parts[i].isNotEmpty)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null,
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Each block, and whether it is a list's item: items stand closer.
    final blocks = <(Widget, bool)>[];
    final lines = <String>[];
    void paragraph() {
      if (lines.isEmpty) return;
      blocks.add((Text.rich(_inline(lines.join('\n'), style)), false));
      lines.clear();
    }

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      final heading = _heading.firstMatch(line);
      final item = _item.firstMatch(line);
      if (line.trim().isEmpty) {
        paragraph();
      } else if (heading != null) {
        paragraph();
        final bold = style.copyWith(fontWeight: FontWeight.w700);
        blocks.add((Text.rich(_inline(heading[1]!, bold)), false));
      } else if (item != null) {
        paragraph();
        final mark = item[1] == null ? '•' : '${item[1]}.';
        blocks.add((
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: mark.length > 1 ? 26 : 18,
                child: Text(mark, style: style),
              ),
              Expanded(child: Text.rich(_inline(item[2]!, style))),
            ],
          ),
          true,
        ));
      } else {
        lines.add(line);
      }
    }
    paragraph();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : (blocks[i].$2 && blocks[i - 1].$2 ? 4 : 10),
            ),
            child: blocks[i].$1,
          ),
      ],
    );
  }
}
