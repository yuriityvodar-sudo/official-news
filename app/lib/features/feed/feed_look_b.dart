import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';
import 'feed_look_b_cards.dart';

/// Design option B (#66), prototype: cards.
///
/// iOS's grouped grey page with each decision in its own white card (dark
/// grey in dark mode), one list of cards of one size (no section titles and
/// no bigger top-story cards since Yurii's review, 16 Oct). A card reads top
/// to bottom: who decided (the country and ministry), the serif headline,
/// what it means in three lines, then the decision type, the topic and when
/// it arrived. Pictures run across the top of their card; a card without one
/// is complete as it is. The filters and the settings button stay at the top
/// while reading; the "N new" pill floats just under them.
class BLook extends FeedLook {
  @override
  Color background(BuildContext context) => BStyle.of(context).page;

  @override
  Widget masthead(BuildContext context, FeedMasthead masthead) =>
      // The date and the name scroll away; the filters and the settings
      // button stay pinned at the top. Both sizes are measured from the real
      // contents, so any text size and language fits. At the Accessibility
      // text sizes the filters take two rows, so they scroll away too and
      // the decisions keep the screen.
      SliverResizingHeader(
        minExtentPrototype: bLargeText(context)
            ? null
            : ExcludeSemantics(child: _Toolbar(masthead)),
        maxExtentPrototype: ExcludeSemantics(
          child: _Masthead(masthead, measuring: true),
        ),
        child: _PinnedMasthead(masthead),
      );

  // One list in the order articles arrived, with no titles and no day
  // headings: an article dated yesterday can arrive today. Each card shows
  // its own time.
  @override
  Widget articles(BuildContext context, FeedList list) => SliverPadding(
    // As far under the filters as the first card was under a section title.
    padding: const EdgeInsets.fromLTRB(bMargin, 10, bMargin, 0),
    sliver: SliverList.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final a = list.articles[i];
        list.shown(i);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BCard(
            article: a,
            mark: list.markOf(a),
            topic: list.topic,
            onTap: () => list.open(i),
          ),
        );
      },
    ),
  );

  @override
  Widget feedEnd(BuildContext context, FeedEnd end) {
    final s = BStyle.of(context);
    final l10n = AppLocalizations.of(context);
    final meta = s.footer.copyWith(fontSize: 15);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(bMargin, 12, bMargin, 48),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: switch (end.state) {
            FeedEndState.failed => CupertinoButton(
              // A 44-pt target and a button role for VoiceOver.
              onPressed: end.retry,
              child: Text(
                l10n.feedLoadMoreFailed,
                textAlign: TextAlign.center,
                style: meta.copyWith(color: AppColors.accent),
              ),
            ),
            FeedEndState.loading => const CupertinoActivityIndicator(),
            FeedEndState.end => Text(
              l10n.feedEnd,
              textAlign: TextAlign.center,
              style: meta,
            ),
          },
        ),
      ),
    );
  }

  /// The screen floats it just under the pinned filters, clear of them.
  @override
  Widget newPill(
    BuildContext context, {
    required int count,
    required VoidCallback onTap,
  }) => BNewPill(count: count, onTap: onTap);
}

/// The top of the feed as drawn: the full masthead, of which only the bottom
/// (the toolbar) stays once the page is scrolled; a hairline then marks its
/// edge.
class _PinnedMasthead extends StatelessWidget {
  const _PinnedMasthead(this.masthead);

  final FeedMasthead masthead;

  @override
  Widget build(BuildContext context) {
    final s = BStyle.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final pinned = constraints.maxHeight <= constraints.minHeight + 0.5;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: pinned
                ? Border(bottom: BorderSide(color: s.separator, width: 0.5))
                : null,
          ),
          child: ColoredBox(
            color: s.page,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: _Masthead(masthead),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The date above the app's name, as iOS does, then the toolbar.
class _Masthead extends StatelessWidget {
  const _Masthead(this.masthead, {this.measuring = false});

  final FeedMasthead masthead;

  /// Laid out only to measure the header: the name is drawn without a Text
  /// widget, so the feed has one "Official News" for VoiceOver and for tests.
  final bool measuring;

  @override
  Widget build(BuildContext context) {
    final s = BStyle.of(context);
    // The app's name and date grow with the text size up to 1.4x: at the
    // largest sizes the decisions get the room.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(bMargin + 4, 10, bMargin, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                masthead.date.toUpperCase(),
                style: s.dateline,
                textScaler: scaler,
              ),
              const SizedBox(height: 2),
              // The name is a wordmark: always one line, made smaller on a
              // narrow screen rather than broken in two.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: measuring
                    ? RichText(
                        text: TextSpan(text: masthead.title, style: s.masthead),
                        textScaler: scaler,
                      )
                    : Semantics(
                        header: true,
                        child: Text(
                          masthead.title,
                          style: s.masthead,
                          textScaler: scaler,
                        ),
                      ),
              ),
            ],
          ),
        ),
        _Toolbar(masthead),
      ],
    );
  }
}

/// The filters on the left and the settings button on the right, the gear
/// level with the first row of filters.
class _Toolbar extends StatelessWidget {
  const _Toolbar(this.masthead);

  final FeedMasthead masthead;

  @override
  Widget build(BuildContext context) {
    // The filter bar brings 10 pt of its own above its chips; a chip is its
    // 15-pt label (about 1.2 lines' height in SF) plus 14 pt, in a target at
    // least 36 pt high. The gear's target is 44 pt: centred on the chips'.
    final chip = math.max(
      36.0,
      14 + MediaQuery.textScalerOf(context).scale(15) * 1.2,
    );
    final gearTop = math.max(0.0, 10 + chip / 2 - 22);
    return Padding(
      padding: const EdgeInsets.fromLTRB(bMargin + 4, 0, bMargin - 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: masthead.filterBar),
          const SizedBox(width: 8),
          Padding(
            padding: EdgeInsets.only(top: gearTop),
            child: masthead.settingsButton,
          ),
        ],
      ),
    );
  }
}
