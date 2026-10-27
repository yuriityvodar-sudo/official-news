import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/filters.dart';
import '../../core/glass.dart';
import '../../core/topics.dart';
import '../../l10n/app_localizations.dart';

/// The topics as a row of pills you swipe sideways (Roman, 26 Oct), as Apple
/// News shows its sections: "All topics" first, then each topic with its
/// icon, busiest first.
///
/// On iOS the row is iOS's own (Roman, 27 Oct, #166): SwiftUI pills in
/// Liquid Glass from iOS 26, the chosen one a drop of [tint] that flows to
/// the pill tapped (`PillsView` in the Runner), the system's translucent
/// material before iOS 26. Elsewhere, and on iOS while anything is over the
/// feed (an article growing out of its card, a sheet, the splash), Flutter
/// draws it: each pill glass (Roman's pick 2 of the
/// mockup `handoff/glass-row-and-pull.html`), the feed showing through it,
/// blurred, under a tint of [fill]; the chosen one glass in the look's
/// colour, glowing.
class TopicPills extends StatelessWidget {
  const TopicPills({
    super.key,
    required this.topic,
    required this.topics,
    required this.onTopic,
    required this.ink,
    required this.fill,
    required this.edge,
    required this.shadow,
    required this.chosen,
    required this.glow,
    required this.tint,
  });

  /// The chosen topic's id, or null for all topics.
  final String? topic;

  /// The topics to offer, busiest first; null while none are known.
  final List<FeedTopic>? topics;
  final ValueChanged<String?> onTopic;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final menu = topics ?? const <FeedTopic>[];
    final current = topic;
    final pills = <(String?, String, IconData)>[
      (null, l10n.filterAllTopics, CupertinoIcons.sparkles),
      for (final t in menu)
        (
          t.id,
          topicName(t.id, menu, l10n),
          topicIcons[t.id] ?? CupertinoIcons.tag,
        ),
      // A topic chosen before it left the menu, so it can be cleared.
      if (current != null && !menu.any((t) => t.id == current))
        (
          current,
          topicName(current, menu, l10n),
          topicIcons[current] ?? CupertinoIcons.tag,
        ),
    ];
    Widget row([ScrollController? scroll]) => SingleChildScrollView(
      controller: scroll,
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          for (final (id, name, icon) in pills)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Pill(
                key: ValueKey('topic-pill-${id ?? 'all'}'),
                name: name,
                icon: icon,
                isChosen: id == current,
                ink: ink,
                fill: fill,
                edge: edge,
                shadow: shadow,
                chosen: chosen,
                glow: glow,
                onTap: () => onTopic(id),
              ),
            ),
        ],
      ),
    );
    if (!native) return row();
    return _NativePills(
      pills: [
        for (final (id, name, _) in pills)
          {
            'id': id ?? '',
            'title': name,
            'symbol': id == null ? 'sparkles' : topicSymbol(id),
          },
      ],
      chosen: current ?? '',
      tint: tint,
      onTopic: onTopic,
      fallback: row,
    );
  }
}

/// iOS's row: Flutter sends it the [pills] (id, name and SF Symbol; "" is
/// all topics), the [chosen] one, [tint] and light or dark, and hears which
/// pill was tapped. A swipe sideways and a tap go to iOS; a swipe up or down
/// stays with the feed, as anywhere on it.
///
/// [fallback], the same row drawn by Flutter and swiped as far as iOS's,
/// shows until iOS has made its row, and while anything is over the feed
/// (a sheet, an article growing out of its card: [NativeOrPlain]), since the
/// glass's shadow would show through it, as with the gear's glass
/// (`GlassCircle`).
class _NativePills extends StatefulWidget {
  const _NativePills({
    required this.pills,
    required this.chosen,
    required this.tint,
    required this.onTopic,
    required this.fallback,
  });

  final List<Map<String, String>> pills;
  final String chosen;
  final Color tint;
  final ValueChanged<String?> onTopic;
  final Widget Function(ScrollController scroll) fallback;

  @override
  State<_NativePills> createState() => _NativePillsState();
}

class _NativePillsState extends State<_NativePills> {
  final _scroll = ScrollController();
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
    _scroll.dispose();
    super.dispose();
  }

  /// The same row takes every change, so the drop flows to a topic chosen
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
        switch (call.method) {
          case 'select':
            final topic = call.arguments as String;
            widget.onTopic(topic.isEmpty ? null : topic);
          case 'scrolled' when _scroll.hasClients:
            final position = _scroll.position;
            _scroll.jumpTo(
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
      native: native,
      plain: widget.fallback(_scroll),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.name,
    required this.icon,
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
  final bool isChosen;
  final Color ink;
  final Color fill;
  final Color edge;
  final List<BoxShadow> shadow;
  final Gradient chosen;
  final Color glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isChosen ? const Color(0xFFFFFFFF) : ink;
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isChosen ? null : fill.withValues(alpha: 0.58),
                      gradient: isChosen ? _glassy(chosen) : null,
                      borderRadius: _round,
                      border: Border.all(color: edge),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 6),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
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
