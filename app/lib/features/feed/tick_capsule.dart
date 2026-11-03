import 'package:flutter/cupertino.dart';

import '../../core/glass.dart';
import '../../core/news_widgets.dart';
import '../../core/tick.dart';
import '../../l10n/app_localizations.dart';
import '../chat/chat_style.dart';

/// A tick among the Top stories block's rows (#230, Roman, 3 Nov: variant 1
/// of `handoff/tick-strip.html`, «1-кнопка справа»): a capsule of glass a
/// third of a card's height, the time first in the look's colour, then the
/// model's headline on up to two lines, and the AI's mark on the right. A
/// light insert among the cards, not a card (Roman: «ячейка должна быть
/// тиком в ленте, а не полноценной частью ленты»): no outlets' marks, no
/// caption. The whole capsule opens the AI chat about it ([onTap]); the mark
/// is part of it, not a button of its own.
class TickCapsule extends StatelessWidget {
  const TickCapsule({super.key, required this.tick, required this.onTap});

  final Tick tick;
  final VoidCallback onTap;

  /// Two lines of the headline and the capsule's padding.
  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ChatStyle.of(context);
    final label = CupertinoColors.label.resolveFrom(context);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label:
          '${tick.title}. ${timeAgo(tick.lastSeen, l10n)}. ${l10n.discussWithAi}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassCapsule(
          height: height,
          padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
          shadow: false,
          child: Row(
            children: [
              Expanded(
                // The time first: at the end of a long headline it was cut
                // off (the mockup, 3 Nov).
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: tickTime(tick.lastSeen, l10n),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                          color: style.ink,
                        ),
                      ),
                      const TextSpan(text: '  '),
                      TextSpan(text: tick.title),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: label,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: style.fill,
                  boxShadow: [
                    BoxShadow(
                      color: style.fill.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  size: 17,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tick's time, short, as it stands before its headline: "11m", "2h";
/// "11 мин", "2 ч".
String tickTime(DateTime date, AppLocalizations l10n, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(date);
  return diff.inMinutes < 60
      ? l10n.minutesShort(diff.inMinutes.clamp(1, 59))
      : l10n.hoursShort(diff.inHours);
}
