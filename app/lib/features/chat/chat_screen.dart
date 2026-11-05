import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show max, min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../core/analytics.dart';
import '../../core/api_client.dart';
import '../../core/chat_history.dart';
import '../../core/article.dart';
import '../../core/glass.dart';
import '../../core/motion.dart';
import '../../core/news_widgets.dart';
import '../../core/subscription.dart';
import '../../core/theme.dart';
import '../../core/wide.dart';
import '../../l10n/app_localizations.dart';
import '../detail/ai_chat_note.dart';
import '../detail/detail_screen.dart' show openOfficialPage;
import 'chat_consent.dart';
import 'chat_questions.dart';
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

  /// Kept on the phone from before: shown at once, not written again.
  bool kept = false;

  /// Its own, so a turn keeps its place and state as others come.
  final key = GlobalKey();
}

/// The AI chat about one decision (#146, docs/contract.md): suggested first
/// questions, the answer streamed as it is written, the official link under
/// each answer. Over the whole screen ([show], Roman, 4 Nov), what it is about
/// comes first (Roman's pick C of `handoff/chat-designs.html`, 5 Nov, like
/// Apple Music): the look's colour as a cover with the news's white headline
/// ([_Cover]), folding into a band as the page scrolls, with the agent's name
/// small; a floating glass field, the text going under it. It moves as
/// ChatGPT's does (Roman's pick A, 30 Oct): the first question stays under the
/// cover, a later one goes to the top of the screen; the answer is written
/// under it, the screen keeping still, never jumping to the answer's end; a
/// pulsing dot while the agent thinks; the answer's bold and lists shown as
/// such ([_Formatted]).
///
/// The limit as Claude shows it (variant A of Roman's mockup, 27 Oct):
/// nothing until it is near, then "3 questions left today" over the field;
/// once none are left, a card in the field's place, with when new ones come
/// and "Buy more questions" ([TopUpSheet]). A long document's question takes
/// more of the limit, and the chat says so. Not paid any more (the server's
/// 402): the paywall shows again.
///
/// The conversation is kept on the phone only ([ChatHistory], Roman's pick
/// B, 30 Oct): opened again about the same decision, it goes on where it was
/// left, and the Conversations screen lists them all.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.article,
    this.firstQuestion,
    this.api,
    this.subscription,
    this.history,
    this.openLink = openOfficialPage,
  });

  /// The chat over the whole screen, coming up from the bottom as iOS's
  /// full-screen views do, over the article and the app's bars rather than
  /// as a sheet (Roman, 4 Nov: «чат должен открываться во весь екран»);
  /// closed with its button.
  static Future<void> show(
    BuildContext context,
    Article article, {
    String? firstQuestion,
    ChatHistory? history,
  }) => Navigator.of(context, rootNavigator: true).push<void>(
    CupertinoPageRoute(
      fullscreenDialog: true,
      builder: (_) => ChatScreen(
        article: article,
        firstQuestion: firstQuestion,
        history: history,
      ),
    ),
  );

  /// The chat about [article] as "Discuss with AI" opens it: behind its
  /// paywall (a subscriber goes straight in), with the consent once, and,
  /// once just bought, the paywall's sample question asked at once
  /// ([firstQuestionOf]). Where there is no App Store purchase yet
  /// (Android), the note about the chat ([AiChatNote]). A tick's opens the
  /// same way (#230).
  static Future<void> open(BuildContext context, Article article) async {
    if (!available) return AiChatNote.show(context);
    final l10n = AppLocalizations.of(context);
    String? first;
    if (!chatSubscription.active) {
      if (!await PaywallSheet.show(context, article)) return;
      first = firstQuestionOf(article, l10n);
    }
    if (!context.mounted || !await ChatConsent.ask(context)) return;
    if (!context.mounted) return;
    await show(context, article, firstQuestion: first);
  }

  final Article article;

  /// Asked at once: the paywall's sample question, once just bought.
  final String? firstQuestion;
  final ApiClient? api;

  /// [chatSubscription] unless a test brings its own.
  final ChatSubscription? subscription;

  /// [chatHistory] unless a test brings its own.
  final ChatHistory? history;
  final Future<void> Function(Uri) openLink;

  /// Where the chat is: the iOS app (StoreKit), every build of it, the
  /// `store` one App Review gets too (Roman, 4 Nov: «открыть sandbox для
  /// appreview»), not Android or tests, unless a test sets [debugAvailable].
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

  /// The end of the conversation, before [_room].
  final _end = GlobalKey();

  /// Room under the conversation, so the last question can stand at the top
  /// while its answer is shorter than the screen ([_fit]).
  double _room = 0;

  /// The cover's headline and source: the cover is as tall as they need.
  final _large = GlobalKey();

  /// The band's title: the band is as tall as it is.
  final _title = GlobalKey();

  /// The field and what stands over it.
  final _dock = GlobalKey();

  /// How tall the cover is at rest, and folded into the band ([_measure]).
  double _cover = 300;
  double _band = 0;

  /// Room the field and what stands over it leave at the conversation's foot.
  double _under = 0;

  /// How far under the band a later question stands: flush with it, the
  /// question slipped under the title on the phone (Roman, 30 Oct).
  double get _above => _band + 16;

  /// How far the conversation has scrolled.
  double get _scrolled => _scroll.hasClients ? _scroll.offset : 0;

  /// How far the cover has folded into the band, 0 to 1, as the page scrolls.
  /// A longer kept conversation opens at its last question, the cover folded
  /// from the first frame: nothing folds or jumps (Roman, 30 Oct).
  double get _folded {
    if (!_placed && _asked >= 2) return 1;
    final room = _cover - _band;
    return room <= 0 ? 0 : clampDouble(_scrolled / room, 0, 1);
  }

  /// How far the field stands off the screen's foot: lower than the safe
  /// area, as iOS 26's floating bars do; just over the keyboard.
  double _dockBottom(BuildContext context) =>
      max(MediaQuery.paddingOf(context).bottom - 8, 10);

  /// Whether the conversation stands where it should. A kept one is hidden
  /// until its last question stands in place, a frame or two, and its notice
  /// is gone at once rather than folding: it opened showing the header,
  /// folded it and jumped to the question (Roman, 30 Oct).
  late bool _placed = _history.loaded;

  /// Bumped as a kept conversation comes in: the notice then goes at once
  /// (its AnimatedSize starts anew) instead of folding.
  int _kept = 0;
  String? _problem;
  bool _sending = false;

  /// How much of the week's usage is used, 0 to 100; null until known.
  /// [chatDemo] starts at 70%, so the line over the field shows after a question.
  int? _usedPercent = chatDemo ? 70 : null;

  /// Whether extra usage bought is left, spent once the week's is used up.
  bool _extra = false;

  /// Nothing left, of the week's usage or the extra: the card takes the field's place.
  bool _limitReached = false;

  /// How much of the limit one question about this article takes.
  int _units = 1;

  /// When the week's usage comes back: Monday 00:00 UTC.
  DateTime? _resetsAt;

  ChatSubscription get _subscription => widget.subscription ?? chatSubscription;

  /// A story's country, sent with its id (#230); null for anything else.
  String? get _storyCountry =>
      widget.article.isMediaStory ? widget.article.country : null;

  ChatHistory get _history => widget.history ?? chatHistory;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
    // Read already (the feed reads it for its Conversations button): the
    // kept conversation is there from the first frame, with no header.
    if (_history.loaded) _keep();
    unawaited(_start());
  }

  /// The conversation the phone keeps about this decision, if any, shown at
  /// once at its last question; then the paywall's question, if one came.
  Future<void> _start() async {
    await _history.load();
    if (!mounted) return;
    if (_turns.isEmpty && _history.of(widget.article.id) != null) {
      setState(() {
        _kept++;
        _keep();
      });
    } else if (!_placed) {
      setState(() => _placed = true);
    }
    final first = widget.firstQuestion;
    if (first != null) await _ask(first);
  }

  /// The kept conversation's turns, its last question then taken to the
  /// top unseen ([_placed]).
  void _keep() {
    final saved = _history.of(widget.article.id);
    if (saved == null) return;
    for (final (reader, text) in saved.messages) {
      _turns.add(
        _Turn(reader, text)
          ..done = !reader
          ..kept = true,
      );
    }
    _placed = false;
    _toQuestion(animate: false);
    _fit();
  }

  /// Keeps the conversation on the phone: each question with its answer,
  /// once the answer has come in full.
  Future<void> _save() {
    final kept = <(bool, String)>[];
    for (var i = 0; i + 1 < _turns.length; i++) {
      final (question, answer) = (_turns[i], _turns[i + 1]);
      if (question.reader && !answer.reader && answer.done) {
        kept
          ..add((true, question.text))
          ..add((false, answer.text));
      }
    }
    return _history.save(widget.article, kept);
  }

  /// The week's usage, from the server: the card shows at once when nothing is left.
  Future<void> _loadStatus() async {
    final transaction = _subscription.transaction;
    if (transaction == null || chatDemo) return;
    try {
      final status = await _api.chatStatus(
        articleId: widget.article.id,
        transaction: transaction,
        tick: widget.article.isTick,
        storyCountry: _storyCountry,
      );
      if (!mounted) return;
      setState(() {
        _usedPercent = status.usedPercent;
        _extra = status.extraUsage;
        _limitReached = status.limitReached;
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
      // A pack credited: extra usage is there ([chatDemo] asks no server).
      setState(() {
        _extra = true;
        _limitReached = false;
      });
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
    final first = _turns.isEmpty;
    setState(() {
      _problem = null;
      _sending = true;
      _turns.addAll([asked, answer]);
      _field.clear();
    });
    // The first stands under the cover; a later one is taken to the top.
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
              tick: widget.article.isTick,
              storyCountry: _storyCountry,
              lang: Localizations.localeOf(context).languageCode,
              messages: _recent([
                for (final t in _turns)
                  if (t != answer && t.text.isNotEmpty) (t.reader, t.text),
              ]),
              transaction: transaction,
            );
      _usedPercent = reply.usedPercent ?? _usedPercent;
      _extra = reply.extraUsage ?? _extra;
      _units = reply.units;
      // The week's usage used up and nothing extra: the card, as this answer comes in.
      _limitReached = (_usedPercent ?? 0) >= 100 && !_extra;
      await for (final piece in reply.text) {
        if (!mounted) return;
        setState(() => answer.text += piece);
        _fit();
      }
      answer.done = true;
      unawaited(_save());
    } on ChatLimit catch (limit) {
      // Not asked: the question goes back into the field, for after a top-up.
      _turns
        ..remove(answer)
        ..remove(asked);
      _field.text = text;
      _limitReached = true;
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

  /// [chatDemo]: the summary, word by word, as an answer would come, with 10%
  /// more of the week's usage used each time, from 70%, so the line over the
  /// field, the card and the top-up sheet can be seen too; once a pack is
  /// bought, extra usage is being spent.
  ChatAnswer _demoAnswer() {
    final words = (widget.article.summary ?? widget.article.headline).split(
      ' ',
    );
    return ChatAnswer(
      text: Stream.periodic(
        const Duration(milliseconds: 40),
        (i) => i == 0 ? words[i] : ' ${words[i]}',
      ).take(words.length),
      usedPercent: min(100, (_usedPercent ?? 70) + 10),
      extraUsage: _extra,
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
  /// The keyboard's height counts as screen: a question sent with the return
  /// key closes it, the screen grows, and with only the room it had left
  /// the question slid down from the top (simulator, 30 Oct). The first
  /// question stands under the cover and needs none.
  void _fit() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final top = _offsetOf(_lastAsked.key);
    final end = _offsetOf(_end);
    if (top == null || end == null || !mounted) return;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final room = _asked < 2
        ? 0.0
        : max(
            0.0,
            _scroll.position.viewportDimension +
                keyboard -
                _above -
                _under -
                (end - top),
          );
    if ((room - _room).abs() > 0.5) setState(() => _room = room);
  });

  /// How many questions the conversation has.
  int get _asked => _turns.where((t) => t.reader).length;

  /// Reads how tall the cover, the band and the field are, once laid out.
  void _measure(Duration _) {
    if (!mounted) return;
    final top = MediaQuery.paddingOf(context).top;
    final band = top + (_title.currentContext?.size?.height ?? 38) + 14;
    // The status bar, the agent's row, some air, the words and their foot.
    final cover = max(
      300.0,
      top + 36 + 16 + (_large.currentContext?.size?.height ?? 0) + 20,
    );
    final under =
        (_dock.currentContext?.size?.height ?? 0) + _dockBottom(context) + 24;
    if (band == _band && cover == _cover && under == _under) return;
    setState(() {
      _band = band;
      _cover = cover;
      _under = under;
    });
    _fit();
  }

  /// What the server takes with a question: the last [ChatHistory.maxMessages]
  /// messages, from a question on.
  static List<(bool, String)> _recent(List<(bool, String)> messages) {
    var from = max(0, messages.length - ChatHistory.maxMessages);
    while (from < messages.length - 1 && !messages[from].$1) {
      from++;
    }
    return messages.sublist(from);
  }

  /// Takes the last question to the top, once there is room for it there
  /// (the first stands under the cover, the top of the page), and shows
  /// a kept conversation once it stands there ([_placed]).
  void _toQuestion({bool animate = true}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final top = _offsetOf(_lastAsked.key);
          if (top != null) {
            final to = _asked < 2
                ? 0.0
                : clampDouble(
                    top - _above,
                    0,
                    _scroll.position.maxScrollExtent,
                  );
            if (!animate || Motion.reduced(context)) {
              _scroll.jumpTo(to);
            } else {
              unawaited(
                _scroll.animateTo(
                  to,
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                ),
              );
            }
          }
          if (!_placed) setState(() => _placed = true);
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
    // The week's usage comes back on Monday at 00:00 UTC, the server's week,
    // shown in the phone's time; without the server's word (the demo), the
    // next one.
    final resetsAt = _resetsAt ?? _nextWeek(DateTime.now().toUtc());
    final resetsDay = weekdayName(resetsAt, l10n);
    // Over the field (Roman, 4 Nov): how much of the week's usage is used,
    // from 75%, or that extra usage is being spent; never a count.
    final used = _usedPercent;
    final usage = used == null
        ? null
        : used >= 100 && _extra
        ? l10n.chatUsingExtra
        : used >= 75
        ? l10n.chatUsage(min(used, 100), resetsDay)
        : null;
    // The app's type (theme.dart), as the paywall: the serif for the
    // decision's headline and the answers, the sans for the reader's
    // questions, buttons, links and labels (Yurii, review of #188).
    final news = NewsText.from(context);

    final talking = _turns.isNotEmpty;
    final fold = Motion.reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final page = CupertinoTheme.of(context).scaffoldBackgroundColor;
    final top = MediaQuery.paddingOf(context).top;
    // Until it is measured, the band as two lines of its title make it.
    if (_band == 0) _band = top + 52;
    WidgetsBinding.instance.addPostFrameCallback(_measure);

    // iOS's glass is drawn after everything else in the chat: drawn first, in
    // the sheet the chat was until 4 Nov, whatever Flutter drew after it
    // showed only over iOS's other views, and the chat stayed empty
    // (TestFlight 55, Roman, 30 Oct; `GlassCircle`).
    final close = Semantics(
      button: true,
      label: l10n.paywallClose,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () => Navigator.of(context).maybePop(),
        child: GlassCircle(
          size: 36,
          child: Icon(
            CupertinoIcons.xmark,
            size: 16,
            color: const Color(0xFFFFFFFF),
            semanticLabel: l10n.paywallClose,
          ),
        ),
      ),
    );

    // Until the first question: the notice, and a long document's.
    final note = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.chatNotAdvice,
          style: TextStyle(fontSize: 12.5, height: 1.35, color: muted),
        ),
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
                    l10n.chatLongDocument,
                    style: TextStyle(fontSize: 13, color: label),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    final conversation = Opacity(
      opacity: _placed ? 1 : 0,
      // All of it laid out, not a lazy list: the last question must be there
      // to be taken to the top, however far down it is.
      child: SingleChildScrollView(
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, _cover + 18, 20, _under),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              key: ValueKey(_kept),
              duration: fold,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              onEnd: _fit,
              child: talking ? const SizedBox(width: double.infinity) : note,
            ),
            for (final turn in _turns) ...[
              SizedBox(
                height: !turn.reader
                    ? 16
                    : identical(turn, _turns.first)
                    ? 0
                    : 30,
              ),
              if (turn.reader)
                Align(
                  key: turn.key,
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      // A tint of the cover's colour.
                      color: style.ink.withValues(alpha: dark ? 0.24 : 0.12),
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: Text(
                      turn.text,
                      style: TextStyle(
                        fontSize: 16.5,
                        height: 1.3,
                        color: label,
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
                    atOnce: turn.kept,
                  ),
                if (turn.cutOff)
                  Text(
                    l10n.chatCutOff,
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                // The media's news has no official page: its outlets are in the header.
                if (turn.done && !article.isMedia)
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
                            article.isStory
                                ? '${l10n.readOnSource(article.source.name)}, $site'
                                : article.isEvent
                                ? '${l10n.readOnWikipedia}, $site'
                                : l10n.readOfficialDecisionOn(site),
                            style: TextStyle(fontSize: 14, color: style.ink),
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
                Text(_problem!, style: TextStyle(fontSize: 14, color: muted)),
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
    );

    // The field and what stands over it, floating: the conversation goes under.
    final dock = Column(
      key: _dock,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The suggested questions, by the thumb, until the first is asked.
        if (!talking && !_limitReached)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final q in suggestedQuestions(article, l10n))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: _sending ? null : () => _ask(q),
                        child: _GlassLift(
                          dark: dark,
                          blur: 12,
                          drop: 4,
                          child: GlassCapsule(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shadow: false,
                            child: Text(
                              q,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: label,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_limitReached)
          // Nothing left: the card takes the field's place.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _OutCard(
              style: style,
              day: resetsDay,
              time: clockTime(resetsAt, l10n),
              onTopUp: _topUp,
            ),
          )
        else ...[
          if (usage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _GlassLift(
                dark: dark,
                blur: 12,
                drop: 4,
                child: GlassCapsule(
                  height: null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  shadow: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        used! >= 100
                            ? CupertinoIcons.plus_circle
                            : CupertinoIcons.clock,
                        size: 14,
                        color: label.withValues(alpha: 0.62),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          usage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: label.withValues(alpha: 0.62),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // One row at the bottom: the field with its send button.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _GlassLift(
              dark: dark,
              child: GlassCapsule(
                height: null,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoTextField(
                    controller: _field,
                    placeholder: l10n.chatAsk,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sending ? null : _ask,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    padding: const EdgeInsets.fromLTRB(18, 15, 6, 15),
                    decoration: null,
                    style: TextStyle(fontSize: 17, color: label),
                    cursorColor: style.ink,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    suffix: ListenableBuilder(
                      listenable: _field,
                      builder: (context, _) => _Send(
                        style: style,
                        label: l10n.chatSend,
                        onPressed: _field.text.trim().isEmpty || _sending
                            ? null
                            : () {
                                Haptics.light();
                                FocusScope.of(context).unfocus();
                                unawaited(_ask(_field.text));
                              },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    // In a wide window, a column in the middle (#137); the cover and the
    // field's fade across the whole window.
    Widget column(Widget child) => ReadableWidth(
      maxWidth: chatWidth,
      child: SafeArea(top: false, bottom: false, child: child),
    );

    return CupertinoPageScaffold(
      // The status bar's words on the cover, white in both themes; the chat
      // covers the status bar, so a sheet it was opened from (Conversations)
      // leaves its own otherwise.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        // Material for the default text style (no yellow underline on plain Text).
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(child: column(conversation)),
              // The text fades out towards the field, never cut off at it, and
              // goes on under it: a white wall behind iOS's glass left it
              // nothing to bend, and it looked flat (Roman, 5 Nov).
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: max(150, _under + 36),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: const [0, 0.17, 0.52, 1],
                        colors: [
                          page.withValues(alpha: 0.92),
                          page.withValues(alpha: 0.72),
                          page.withValues(alpha: 0.38),
                          page.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Takes no touches: a drag on it moves the page.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _scroll,
                    builder: (context, _) {
                      final folded = _folded;
                      return _Cover(
                        style: style,
                        folded: folded,
                        height: _cover - (_cover - _band) * folded,
                        agent: l10n.aiAgent,
                        headline: article.headline,
                        source: article.source.name,
                        large: _large,
                        title: _title,
                      );
                    },
                  ),
                ),
              ),
              Positioned.fill(
                child: column(
                  Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: _dockBottom(context),
                        child: dock,
                      ),
                      Positioned(top: top - 4, right: 10, child: close),
                    ],
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

/// The top of the chat: the look's colour, deepening, with the news's white
/// headline and its source, and the agent's name small over them (Roman's
/// pick C, 5 Nov, like Apple Music). It folds into a band, [folded] of the way
/// and [height] tall: the words go up and fade, the headline on up to three
/// lines takes their place, as on one it was cut short and read as nothing
/// (Roman, 30 Oct).
class _Cover extends StatelessWidget {
  const _Cover({
    required this.style,
    required this.folded,
    required this.height,
    required this.agent,
    required this.headline,
    required this.source,
    required this.large,
    required this.title,
  });

  final ChatStyle style;
  final double folded;
  final double height;
  final String agent;
  final String headline;
  final String source;

  /// On the headline and its source at rest, and on the band's title: how
  /// tall they are sets the cover's and the band's height.
  final Key large;
  final Key title;

  static const _white = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final news = NewsText.from(context);
    final radius = BorderRadius.vertical(
      bottom: Radius.circular(30 - 6 * folded),
    );
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: const Alignment(-0.26, -1),
          end: const Alignment(0.26, 1),
          colors: style.cover,
          stops: const [0, 0.62, 1],
        ),
        // A glow in its own colour, under what is filled with it (`NewsLook`).
        boxShadow: [
          BoxShadow(
            color: style.fill.withValues(alpha: 0.7),
            blurRadius: 44,
            spreadRadius: -22,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Light from the top corner.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.76, -1.1),
                  radius: 1.2,
                  colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
                  stops: [0, 0.62],
                ),
              ),
            ),
            // The agent's mark, huge and faint, gone once folded.
            Positioned(
              right: -52,
              bottom: -52,
              child: Transform.rotate(
                angle: -0.21,
                child: Icon(
                  CupertinoIcons.sparkles,
                  size: 240,
                  color: _white.withValues(alpha: 0.1 * (1 - folded)),
                ),
              ),
            ),
            ReadableWidth(
              maxWidth: chatWidth,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Stack(
                  children: [
                    // Who answers, small, beside the close button: what the
                    // chat is about comes first (Roman, 5 Nov).
                    Positioned(
                      left: 20,
                      top: MediaQuery.paddingOf(context).top,
                      child: Opacity(
                        opacity: clampDouble(1 - folded * 2.4, 0, 1),
                        alwaysIncludeSemantics: true,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 36),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                CupertinoIcons.sparkles,
                                size: 16,
                                color: _white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                agent,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _white.withValues(alpha: 0.86),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: Opacity(
                        opacity: clampDouble(1 - folded * 1.7, 0, 1),
                        alwaysIncludeSemantics: true,
                        child: Column(
                          key: large,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // As big as in the article.
                            Semantics(
                              header: true,
                              child: Text(
                                headline,
                                style: news.articleHeadline.copyWith(
                                  color: _white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              source,
                              style: TextStyle(
                                fontSize: 14,
                                color: _white.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // The big one is what VoiceOver reads.
                    Positioned(
                      left: 20,
                      right: 58,
                      bottom: 14,
                      child: ExcludeSemantics(
                        child: Opacity(
                          opacity: clampDouble((folded - 0.62) / 0.38, 0, 1),
                          child: Text(
                            key: title,
                            headline,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: news.headline.copyWith(
                              fontSize: 15.5,
                              height: 1.24,
                              fontWeight: FontWeight.w700,
                              color: _white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Under a capsule of iOS's glass on the chat's white page, where the glass
/// alone has nothing to bend and hardly shows (Roman, 5 Nov: «glass pill»): a
/// thin edge, which the glass makes a faint body of, and a soft shadow.
class _GlassLift extends StatelessWidget {
  const _GlassLift({
    required this.dark,
    required this.child,
    this.blur = 24,
    this.drop = 8,
  });

  final bool dark;
  final Widget child;
  final double blur;
  final double drop;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: dark ? const Color(0x0FFFFFFF) : const Color(0x12000000),
          spreadRadius: 0.5,
        ),
        BoxShadow(
          color: dark ? const Color(0x8C000000) : const Color(0x2E000000),
          blurRadius: blur,
          spreadRadius: -drop,
          offset: Offset(0, drop),
        ),
      ],
    ),
    child: child,
  );
}

/// The send button: grey until there is something to send, as Messages'.
class _Send extends StatelessWidget {
  const _Send({
    required this.style,
    required this.label,
    required this.onPressed,
  });

  final ChatStyle style;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ready = onPressed != null;
    return CupertinoButton(
      padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // A glow in its own colour, under what is filled with it (`NewsLook`).
          boxShadow: [
            BoxShadow(
              color: ready
                  ? style.fill.withValues(alpha: 0.55)
                  : style.fill.withValues(alpha: 0),
              blurRadius: 14,
              spreadRadius: -4,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 200),
          tween: ColorTween(
            end: ready
                ? style.fill
                : CupertinoColors.systemGrey3.resolveFrom(context),
          ),
          builder: (context, color, _) => Icon(
            CupertinoIcons.arrow_up_circle_fill,
            size: 36,
            color: color,
            semanticLabel: label,
          ),
        ),
      ),
    );
  }
}

/// The next Monday at 00:00 UTC after [now], in UTC: when the week's usage
/// comes back, as the server counts the week.
DateTime _nextWeek(DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  return today.add(Duration(days: DateTime.daysPerWeek + 1 - today.weekday));
}

/// No usage left this week: when the week's comes back, or get more.
class _OutCard extends StatelessWidget {
  const _OutCard({
    required this.style,
    required this.day,
    required this.time,
    required this.onTopUp,
  });

  final ChatStyle style;

  /// When the week's usage comes back, in the phone's time: its weekday and its time.
  final String day;
  final String time;
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
            l10n.chatOutBody(day, time),
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
    this.atOnce = false,
  });

  final String text;
  final TextStyle style;

  /// More of it shows: the room under the conversation is measured again.
  final VoidCallback? onGrow;

  /// All of it at once: an answer kept on the phone from before.
  final bool atOnce;

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
    if (widget.atOnce || Motion.reduced(context)) {
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
