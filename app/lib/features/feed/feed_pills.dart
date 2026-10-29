import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';

import '../../core/filters.dart';
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
/// iOS's row of #176: at once when the row appears or its topics come in,
/// gliding when another is chosen. A pill in view stays where it is.
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

  @override
  State<FeedPills> createState() => _FeedPillsState();
}

/// One pill: its key (`pill-for-you`, `pill-world`, `pill-topic-economy`),
/// name and icon, and what a tap chooses.
typedef _Choice = ({
  String key,
  String name,
  IconData icon,
  bool isChosen,
  VoidCallback onTap,
});

class _FeedPillsState extends State<FeedPills> {
  final _scroll = ScrollController();
  final _row = GlobalKey();

  /// The pill last brought into view, and whether the topics were known
  /// then: the row looks again only when either changes.
  (String, bool)? _shown;

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
      isChosen: id == chosen,
      onTap: () => widget.onChoose(FeedWhere.all, id),
    );
    final pills = <_Choice>[
      (
        key: 'pill-for-you',
        name: l10n.feedForYou,
        icon: CupertinoIcons.sparkles,
        isChosen: forYou,
        onTap: () => widget.onChoose(FeedWhere.forYou, null),
      ),
      (
        key: 'pill-world',
        name: l10n.feedWholeWorld,
        icon: CupertinoIcons.globe,
        isChosen: !forYou && chosen == null,
        onTap: () => widget.onChoose(FeedWhere.all, null),
      ),
      // The chosen topic stays, chosen, when it has no articles in the
      // feed's 7 days now, as in the menu.
      if (chosen != null && !menu.any((t) => t.id == chosen)) topicPill(chosen),
      for (final t in menu) topicPill(t.id),
    ];
    _showChosen(pills);
    return SingleChildScrollView(
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
  }

  /// Once the row is laid out, brings the chosen pill to its middle if it is
  /// not wholly in view: a topic chosen before the app was closed can be far
  /// along the row. A pill in view stays where it is.
  void _showChosen(List<_Choice> pills) {
    final index = pills.indexWhere((pill) => pill.isChosen);
    if (index < 0) return;
    final shown = (pills[index].key, widget.topics != null);
    final before = _shown;
    if (shown == before) return;
    _shown = shown;
    // Another pill chosen in a row already whole: it glides there.
    final glide = before != null && before.$2 && shown.$2;
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
