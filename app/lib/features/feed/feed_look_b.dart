import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';
import 'feed_look_b_cards.dart';

/// Design option B (#66), prototype: cards.
///
/// iOS's grouped grey page with each decision in its own white card (dark
/// grey in dark mode). A card reads top to bottom: who decided (the country
/// and ministry), the serif headline, what it means in three lines (four in
/// Top stories), then the decision type, the topic and when it arrived.
/// Pictures run across the top of their card; a card without one is complete
/// as it is. Top stories are bigger cards. The filters and the settings button
/// stay at the top while reading, so the "N new" pill sits at the bottom.
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

  /// The alternative tried for Top stories: a carousel of cards
  /// (`--dart-define=FEED_B_TOP=carousel`).
  static const _carousel = String.fromEnvironment('FEED_B_TOP') == 'carousel';

  @override
  Widget topStories(BuildContext context, FeedSection top) =>
      SliverMainAxisGroup(
        slivers: [
          _title(context, top.title, first: true),
          if (_carousel)
            SliverToBoxAdapter(child: _Carousel(top))
          else
            _cards(top, kind: BCardKind.top),
        ],
      );

  // One "Latest" list in the order articles arrived, with no day headings: an
  // article dated yesterday can arrive today. Each card shows its own time.
  @override
  Widget latest(BuildContext context, FeedSection latest) =>
      SliverMainAxisGroup(
        slivers: [
          _title(context, latest.title, first: false),
          _cards(latest, kind: BCardKind.latest),
        ],
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

  /// At the bottom of the screen: the top is where B's filters stay pinned,
  /// and a pill there would cover the "All topics" filter and take its taps.
  @override
  Widget newPill(
    BuildContext context, {
    required int count,
    required VoidCallback onTap,
  }) => _AtBottom(
    child: BNewPill(count: count, onTap: onTap),
  );

  /// "Top stories", "Latest": black, not red, with room above so the
  /// sections read as separate.
  Widget _title(BuildContext context, String title, {required bool first}) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(bMargin + 4, first ? 14 : 30, bMargin, 10),
        sliver: SliverToBoxAdapter(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: BStyle.of(context).section,
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.6),
            ),
          ),
        ),
      );

  /// The cards of [section], built as they scroll into view.
  Widget _cards(FeedSection section, {required BCardKind kind}) =>
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: bMargin),
        sliver: SliverList.builder(
          itemCount: section.length,
          itemBuilder: (context, i) {
            final a = section.articles[i];
            section.shown(i);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: BCard(
                article: a,
                read: section.isRead(a),
                kind: kind,
                lead: kind == BCardKind.top && i == 0,
                onTap: () => section.open(i),
              ),
            );
          },
        ),
      );
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

/// [child] at the bottom of the screen, centred, above the home indicator.
///
/// PROTOTYPE: the feed screen places the pill 12 pt below the top of the safe
/// area and lets a look draw only the pill, so this reaches from there to the
/// bottom and puts the pill at its end. Where it holds no pill it lets taps
/// through to the feed. If B is chosen, the screen should place it instead
/// (a `newPillAtBottom` on FeedLook), agreed in the pull request.
class _AtBottom extends StatelessWidget {
  const _AtBottom({required this.child});

  final Widget child;

  /// Where the screen puts the pill: 12 pt below the top of the safe area.
  static const _screenTop = 12.0;

  @override
  Widget build(BuildContext context) {
    // The safe area's top is taken out of the MediaQuery here, so it is read
    // from the screen itself.
    final screen = MediaQueryData.fromView(View.of(context));
    final room =
        MediaQuery.sizeOf(context).height -
        screen.padding.top -
        _screenTop -
        16 -
        MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: math.max(0, room),
      child: Align(alignment: Alignment.bottomCenter, child: child),
    );
  }
}

/// Top stories side by side, swiped one at a time, the next card peeking in.
/// Every card has the carousel's height, worked out from the text size, so the
/// cards are text only: with pictures, a card without one was half empty.
class _Carousel extends StatefulWidget {
  const _Carousel(this.top);

  final FeedSection top;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  PageController? _pages;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scaler = MediaQuery.textScalerOf(context);
    const k = BCardKind.carousel;
    final cardWidth = width - 2 * bMargin - 28;
    // Each page is a card and the gap before it, so a swipe lands on a card's edge.
    final fraction = (cardWidth + bMargin) / width;
    // Made once: the prototype does not follow a change of screen width.
    _pages ??= PageController(viewportFraction: fraction);
    final top = widget.top;
    double lines(double size, double height, int n) =>
        scaler.scale(size) * height * n;
    // The card's own layout, line by line, at its most: who decided, the
    // headline, the summary and the footer (the type tag, and the topic and
    // time under it when they do not fit beside it).
    final large = bLargeText(context);
    final kindTag = scaler.clamp(maxScaleFactor: 2.0).scale(11) * 1.25 + 6;
    final text =
        2 * (large ? 16 : k.padding) +
        lines(13, 1.3, BCardKind.placeLines(large)) +
        8 +
        lines(k.headline, k.headlineHeight, BCardKind.carouselHeadlineLines) +
        6 +
        lines(k.summary, 1.33, k.summaryLines) +
        12 +
        kindTag +
        6 +
        lines(13, 1.3, BCardKind.footerLines(large));
    return SizedBox(
      // Room to spare (a line): the sum above comes out a little short at the
      // largest text sizes.
      height: text + 8 + lines(13, 1.3, 1),
      child: PageView.builder(
        controller: _pages,
        padEnds: false,
        itemCount: top.length,
        itemBuilder: (context, i) {
          final a = top.articles[i];
          return Padding(
            padding: const EdgeInsets.only(left: bMargin),
            child: BCard(
              article: a,
              read: top.isRead(a),
              kind: k,
              onTap: () => top.open(i),
            ),
          );
        },
      ),
    );
  }
}
