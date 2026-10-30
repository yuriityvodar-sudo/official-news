import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/filters.dart';
import '../../core/glass.dart';
import '../../core/motion.dart';
import '../../core/topics.dart';
import '../../l10n/app_localizations.dart';

/// What the feed shows, as a row of pills you swipe sideways (Roman, 26 Oct),
/// as Apple News shows its sections: For you and the whole world first, then
/// each topic across the world with its icon, busiest first, the choices of
/// the other looks' menu ([FeedFilterBar], #170, `handoff/for-you.html`).
///
/// Each pill is glass (Roman's pick 2 of the mockup
/// `handoff/glass-row-and-pull.html`): the feed shows through it, blurred,
/// under a tint of [fill]; the chosen one is glass in the look's colour,
/// glowing. A chosen pill out of view comes to the middle of the row, as in
/// iOS's row: at once when the row appears or its topics come in, gliding
/// when another is chosen. A pill in view stays where it is.
///
/// On iOS the row is iOS's own (Roman, 27 Oct, #166): SwiftUI pills in
/// Liquid Glass from iOS 26, the chosen one a drop of [tint] that flows to
/// the pill tapped (`PillsView` in the Runner), the system's translucent
/// material before iOS 26. Flutter's row stands in until iOS has made its
/// own, and while anything is over the feed (an article growing out of its
/// card, a sheet, the splash), swiped as far as iOS's.
class FeedPills extends StatefulWidget {
  const FeedPills({
    super.key,
    required this.where,
    required this.topic,
    required this.topics,
    required this.onChoose,
    required this.ink,
    required this.fill,
    required this.edge,
    required this.shadow,
    required this.chosen,
    required this.glow,
    required this.tint,
  });

  /// For you or the whole world.
  final FeedWhere where;

  /// The chosen topic's id, or null.
  final String? topic;

  /// The topics, busiest first; null while none are known.
  final List<FeedTopic>? topics;

  /// For you or the whole world with no topic, or the whole world with one.
  final void Function(FeedWhere where, String? topic) onChoose;

  /// A pill's words, the tint of its glass and its edge, and its shadow.
  final Color ink;
  final Color fill;
  final Color edge;
  final List<BoxShadow> shadow;

  /// The chosen pill's fill, and the glow under it.
  final Gradient chosen;
  final Color glow;

  /// The colour of the chosen pill's glass in iOS's row.
  final Color tint;

  /// Where iOS draws the row: the iOS app, not tests (macOS) or Android,
  /// unless a test sets [debugNative].
  static bool get native => debugNative ?? (!kIsWeb && Platform.isIOS);

  @visibleForTesting
  static bool? debugNative;

  /// How tall the row is at the reader's text size: a pill's place at least
  /// 44 points high, the pill as tall as its words need and at least 36
  /// (Yurii, #210), with room above and for the glass's shadow under it.
  static double heightFor(TextScaler scaler) {
    final words = (scaler.scale(_Pill.fontSize) * _Pill.lineHeight)
        .ceilToDouble();
    final pill = math.max(_Pill.height, words + 2 * _Pill.padding);
    return 4 + math.max(44.0, pill) + 10;
  }

  @override
  State<FeedPills> createState() => _FeedPillsState();
}

/// One pill: its key (`pill-for-you`, `pill-world`, `pill-topic-economy`),
/// which is also its id in iOS's row, its name, its icon and the same glyph
/// as an SF Symbol, and what a tap chooses.
typedef _Choice = ({
  String key,
  String name,
  IconData icon,
  String symbol,
  bool isChosen,
  VoidCallback onTap,
});

class _FeedPillsState extends State<FeedPills> {
  final _scroll = ScrollController();
  final _row = GlobalKey();

  /// The pill last brought into view, where it was in the row, the words'
  /// language and size, and whether the topics were known then: the row
  /// looks again when any of them changes (a topic's new rank, wider words;
  /// Yurii, #210).
  (String, int, Locale, TextScaler, bool)? _shown;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chosen = widget.topic;
    final menu = widget.topics ?? const <FeedTopic>[];
    final forYou = widget.where.isForYou && chosen == null;
    _Choice topicPill(String id) => (
      key: 'pill-topic-$id',
      name: topicName(id, widget.topics, l10n),
      icon: topicIcon(id),
      symbol: topicSymbol(id),
      isChosen: id == chosen,
      onTap: () => widget.onChoose(FeedWhere.all, id),
    );
    final pills = <_Choice>[
      (
        key: 'pill-for-you',
        name: l10n.feedForYou,
        icon: CupertinoIcons.sparkles,
        symbol: 'sparkles',
        isChosen: forYou,
        onTap: () => widget.onChoose(FeedWhere.forYou, null),
      ),
      (
        key: 'pill-world',
        name: l10n.feedWholeWorld,
        icon: CupertinoIcons.globe,
        symbol: 'globe',
        isChosen: !forYou && chosen == null,
        onTap: () => widget.onChoose(FeedWhere.all, null),
      ),
      // The chosen topic stays, chosen, when it has no articles in the
      // feed's 7 days now, as in the menu.
      if (chosen != null && !menu.any((t) => t.id == chosen)) topicPill(chosen),
      for (final t in menu) topicPill(t.id),
    ];
    _showChosen(pills);
    final row = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        key: _row,
        spacing: 8,
        children: [
          for (final pill in pills)
            _Pill(
              key: ValueKey(pill.key),
              name: pill.name,
              icon: pill.icon,
              slot: _Pill.slotFor(pill.symbol),
              isChosen: pill.isChosen,
              ink: widget.ink,
              fill: widget.fill,
              edge: widget.edge,
              shadow: widget.shadow,
              chosen: widget.chosen,
              glow: widget.glow,
              onTap: pill.onTap,
            ),
        ],
      ),
    );
    if (!FeedPills.native) return row;
    return _NativePills(
      pills: [
        for (final pill in pills)
          {
            'id': pill.key,
            'title': pill.name,
            'symbol': pill.symbol,
            'slot': _Pill.slotFor(pill.symbol),
          },
      ],
      chosen: pills.where((pill) => pill.isChosen).firstOrNull?.key ?? '',
      tint: widget.tint,
      onSelect: (id) =>
          pills.where((pill) => pill.key == id).firstOrNull?.onTap(),
      scroll: _scroll,
      fallback: row,
    );
  }

  /// Once the row is laid out, brings the chosen pill to its middle if it is
  /// not wholly in view: a topic chosen before the app was closed can be far
  /// along the row. A pill in view stays where it is.
  void _showChosen(List<_Choice> pills) {
    final index = pills.indexWhere((pill) => pill.isChosen);
    if (index < 0) return;
    final shown = (
      pills[index].key,
      index,
      Localizations.localeOf(context),
      MediaQuery.textScalerOf(context),
      widget.topics != null,
    );
    final before = _shown;
    if (shown == before) return;
    _shown = shown;
    // Another pill chosen in a row already whole: it glides there.
    final glide =
        before != null && before.$1 != shown.$1 && before.$5 && shown.$5;
    final reduced = Motion.reduced(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pill = _pillAt(index);
      if (!mounted || pill == null || !_scroll.hasClients) return;
      final position = _scroll.position;
      final viewport = RenderAbstractViewport.of(pill);
      final inView =
          position.pixels <= viewport.getOffsetToReveal(pill, 0).offset &&
          position.pixels >= viewport.getOffsetToReveal(pill, 1).offset;
      if (inView) return;
      unawaited(
        position.ensureVisible(
          pill,
          alignment: 0.5,
          duration: glide && !reduced ? Motion.slow : Duration.zero,
          curve: Motion.ease,
        ),
      );
    });
  }

  /// The pill at [index] as laid out, or null before the row is.
  RenderBox? _pillAt(int index) {
    final row = _row.currentContext?.findRenderObject();
    if (row is! RenderFlex) return null;
    var pill = row.firstChild;
    for (var i = 0; i < index && pill != null; i++) {
      pill = row.childAfter(pill);
    }
    return pill;
  }
}

/// iOS's row: Flutter sends it the [pills] (id, name and SF Symbol), the
/// [chosen] one's id, [tint] and light or dark, and hears which pill was
/// tapped. A swipe sideways and a tap go to iOS; a swipe up or down stays
/// with the feed, as anywhere on it.
///
/// [fallback], Flutter's own row, shows until iOS has made its row
/// ([NativeOrPlain]); a page or a sheet then covers iOS's row itself, as
/// it does the gear's glass (`GlassCircle`). It is swiped as far as iOS's
/// row ([scroll]).
class _NativePills extends StatefulWidget {
  const _NativePills({
    required this.pills,
    required this.chosen,
    required this.tint,
    required this.onSelect,
    required this.scroll,
    required this.fallback,
  });

  final List<Map<String, Object>> pills;
  final String chosen;
  final Color tint;
  final ValueChanged<String> onSelect;
  final ScrollController scroll;
  final Widget fallback;

  @override
  State<_NativePills> createState() => _NativePillsState();
}

class _NativePillsState extends State<_NativePills> {
  MethodChannel? _channel;

  /// iOS has made its row.
  bool _ready = false;

  /// What iOS's row was last told, so it hears only of a change.
  String? _sent;

  Map<String, Object?> get _params => {
    'pills': widget.pills,
    'chosen': widget.chosen,
    'tint': widget.tint.toARGB32(),
    'dark': Theme.of(context).brightness == Brightness.dark,
    'room': glassShadowRoom,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(_NativePills old) {
    super.didUpdateWidget(old);
    _update();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  /// The same row takes every change, so the drop flows to a pill chosen
  /// anywhere, instead of a new row appearing. A row already gone misses it.
  void _update() {
    final channel = _channel;
    if (channel == null) return;
    final params = _params;
    final sent = params.toString();
    if (sent == _sent) return;
    _sent = sent;
    channel.invokeMethod<void>('update', params).ignore();
  }

  void _created(int id) {
    _channel = MethodChannel('official_news/pills_$id')
      ..setMethodCallHandler((call) async {
        final scroll = widget.scroll;
        switch (call.method) {
          case 'select':
            widget.onSelect(call.arguments as String);
          case 'scrolled' when scroll.hasClients:
            final position = scroll.position;
            scroll.jumpTo(
              clampDouble(
                (call.arguments as num).toDouble(),
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
            );
        }
      });
    // Anything that changed while iOS was making the row.
    _update();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    final native = UiKitView(
      viewType: 'official_news/pills',
      creationParams: _params,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _created,
      gestureRecognizers: {
        Factory<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
        ),
        Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
      },
    );
    return NativeOrPlain(
      ready: _ready,
      // iOS's row reaches [glassShadowRoom] above and below the row, for the
      // glass's shadow; touches there go to the feed.
      native: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: -glassShadowRoom,
            bottom: -glassShadowRoom,
            child: native,
          ),
        ],
      ),
      plain: widget.fallback,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.name,
    required this.icon,
    required this.slot,
    required this.isChosen,
    required this.ink,
    required this.fill,
    required this.edge,
    required this.shadow,
    required this.chosen,
    required this.glow,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final double slot;
  final bool isChosen;
  final Color ink;
  final Color fill;
  final Color edge;
  final List<BoxShadow> shadow;
  final Gradient chosen;
  final Color glow;
  final VoidCallback onTap;

  /// The pill as iOS's row draws its own (`PillLabel` in the Runner), so
  /// nothing moves when one stands in for the other, as an article opens or
  /// Settings comes over the feed (Roman, 29 Oct): the words in the system
  /// font at 15 points with its own tracking and about its own line height
  /// (the theme's body text has +0.25 and 1.43), 8 points of room above and
  /// under them, edge included, at least 36 high, and the icon in its own
  /// room ([slotFor]).
  static const fontSize = 15.0;
  static const lineHeight = 1.2;
  static const letterSpacing = -0.24;
  static const padding = 8.0;
  static const height = 36.0;

  /// The room an icon gets at the usual text size: as wide as iOS draws its
  /// SF Symbol at the pills' 15 points semibold (measured with AppKit on
  /// macOS 26, 29 Oct), 18 for one not here. iOS's row gives the icon the
  /// same room, both growing with the text size, so no icon runs into the
  /// words and both rows stay as wide (Yurii's review of #218).
  static double slotFor(String symbol) => _slots[symbol] ?? 18;

  static const _slots = <String, double>{
    'sparkles': 17,
    'globe': 19,
    'chart.bar.fill': 24,
    'shield.fill': 17,
    'staroflife.fill': 18,
    'leaf.arrow.circlepath': 19,
    'arrow.right.arrow.left': 19,
    'desktopcomputer': 23,
    'bolt.fill': 15,
    'person.2.fill': 25,
    'checklist': 22,
    'hand.raised.fill': 19,
    'flask.fill': 18,
    'book.fill': 22,
    'hammer.fill': 22,
    'square.grid.2x2': 18,
  };

  @override
  Widget build(BuildContext context) {
    final color = isChosen ? const Color(0xFFFFFFFF) : ink;
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      button: true,
      selected: isChosen,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            // The shadow outside the glass, the blur inside its round edge.
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: _round,
                boxShadow: isChosen
                    ? [
                        BoxShadow(
                          color: glow,
                          blurRadius: 16,
                          spreadRadius: -4,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : shadow,
              ),
              child: ClipRRect(
                borderRadius: _round,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    // The edge's point is part of the room around the words.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: padding - 1,
                    ),
                    decoration: BoxDecoration(
                      color: isChosen ? null : fill.withValues(alpha: 0.58),
                      gradient: isChosen ? _glassy(chosen) : null,
                      borderRadius: _round,
                      border: Border.all(color: edge),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: height - 2 * padding,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: scaler.scale(slot),
                            child: Icon(
                              icon,
                              size: scaler.scale(16),
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                              height: lineHeight,
                              letterSpacing: letterSpacing,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _round = BorderRadius.all(Radius.circular(20));

/// The chosen pill's gradient, a little see-through: coloured glass.
Gradient _glassy(Gradient gradient) => gradient is LinearGradient
    ? LinearGradient(
        begin: gradient.begin,
        end: gradient.end,
        colors: [
          for (final c in gradient.colors) c.withValues(alpha: c.a * 0.88),
        ],
      )
    : gradient;
