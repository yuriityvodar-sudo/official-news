import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../l10n/app_localizations.dart';

/// While the first page of a feed loads (#141): grey rows in the shape of
/// the feed's, breathing slowly, instead of a spinner on an empty screen,
/// so the reader sees where the news will be. With Reduce Motion on, they
/// stay still. VoiceOver says "Loading the news".
class FeedSkeleton extends StatefulWidget {
  const FeedSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  State<FeedSkeleton> createState() => _FeedSkeletonState();
}

class _FeedSkeletonState extends State<FeedSkeleton>
    with SingleTickerProviderStateMixin {
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    lowerBound: 0.45,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _breath.value = 1;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = CupertinoColors.quaternarySystemFill.resolveFrom(context);
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                bar(0.45, 10),
                bar(0.95, 15),
                bar(0.7, 15),
                bar(0.25, 10),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ],
      ),
    );
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      sliver: SliverToBoxAdapter(
        child: Semantics(
          label: AppLocalizations.of(context).feedLoading,
          excludeSemantics: true,
          child: FadeTransition(
            opacity: _breath,
            child: Column(
              children: [
                for (var i = 0; i < widget.rows; i++) ...[
                  if (i > 0) const Divider(),
                  row,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
