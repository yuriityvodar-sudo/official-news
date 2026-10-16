import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/news_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';

/// Design option C (#66), prototype: "Briefing".
///
/// Text first, like a morning briefing: a compact masthead whose filter bar
/// stays pinned at the top, Top stories as a numbered list with large
/// numerals, and a dense Latest list without pictures. Every item is the
/// same three lines: the country, the publisher and the time; the headline;
/// one line of the short summary. In Latest a red dot marks importance 4
/// and 5; in Top stories the numeral does. No pictures: many official pages
/// have none, and the ones they have are often the site's logo.
class CLook extends FeedLook {
  @override
  Color background(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  @override
  Widget masthead(BuildContext context, FeedMasthead masthead) =>
      // Pinned: scrolling up slides the date and the name away, and the bar
      // with the filters and the gear stays at the top, over the list.
      SliverResizingHeader(
        minExtentPrototype: _Prototype(_Bar(masthead)),
        maxExtentPrototype: _Prototype(_Masthead(masthead, prototype: true)),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.bottomCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: _Masthead(masthead),
          ),
        ),
      );

  @override
  Widget topStories(BuildContext context, FeedSection top) =>
      SliverMainAxisGroup(
        slivers: [
          _SectionTitle(top.title, top: 20),
          _list(top, numbered: true),
        ],
      );

  // One "Latest" list in the order articles appeared, with no day headings: an
  // article dated yesterday can appear today. Each item shows its own time.
  @override
  Widget latest(BuildContext context, FeedSection latest) =>
      SliverMainAxisGroup(
        slivers: [
          _SectionTitle(latest.title, top: 36),
          _list(latest, numbered: false),
        ],
      );

  @override
  Widget feedEnd(BuildContext context, FeedEnd end) {
    final t = _Styles.of(context);
    final l10n = AppLocalizations.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 56),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: switch (end.state) {
            FeedEndState.failed => CupertinoButton(
              // A 44-pt target and a button role for VoiceOver.
              onPressed: end.retry,
              child: Text(
                l10n.feedLoadMoreFailed,
                textAlign: TextAlign.center,
                style: t.source.copyWith(
                  color: t.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FeedEndState.loading => const CupertinoActivityIndicator(),
            FeedEndState.end => Column(
              children: [
                // The end mark of a printed article.
                Container(width: 8, height: 8, color: t.accent),
                const SizedBox(height: 12),
                Text(
                  l10n.feedEnd,
                  textAlign: TextAlign.center,
                  style: t.summary,
                ),
              ],
            ),
          },
        ),
      ),
    );
  }

  @override
  Widget newPill(
    BuildContext context, {
    required int count,
    required VoidCallback onTap,
  }) => _NewPill(count: count, onTap: onTap);

  /// The articles of [section] with a hairline between them, built lazily.
  Widget _list(FeedSection section, {required bool numbered}) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverList.separated(
      itemCount: section.length,
      separatorBuilder: (context, _) => Padding(
        // Under a numbered item the line starts at the text, not the numeral.
        padding: EdgeInsets.only(left: numbered ? _numeralColumn(context) : 0),
        child: const Divider(),
      ),
      itemBuilder: (context, i) {
        final a = section.articles[i];
        section.shown(i);
        return _Item(
          article: a,
          number: numbered ? i + 1 : null,
          read: section.isRead(a),
          onTap: () => section.open(i),
        );
      },
    ),
  );
}

/// The look's text styles and colours, from the app's colour scheme: black
/// on white, white on black, grey for what is secondary, and red only for
/// the importance dot and the end mark, never for small text.
class _Styles {
  _Styles._(this.ink, this.secondary, this.accent);

  factory _Styles.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Styles._(scheme.onSurface, scheme.onSurfaceVariant, scheme.primary);
  }

  final Color ink;
  final Color secondary;
  final Color accent;

  static const _serif = 'Georgia';
  static const _serifFallback = ['serif'];

  /// "FRIDAY, 16 OCTOBER" above the name.
  TextStyle get date => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: secondary,
  );

  /// "Official News".
  TextStyle get title => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _serifFallback,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: ink,
  );

  /// "TOP STORIES", "LATEST".
  TextStyle get section => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.4,
    color: ink,
  );

  /// The large "1" to "5" of Top stories: Didot, a display face for
  /// figures only (digits need no Cyrillic), in black, not red.
  TextStyle get numeral => TextStyle(
    fontFamily: 'Didot',
    fontFamilyFallback: const [_serif, 'serif'],
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1,
    color: ink,
  );

  /// "BRAZIL" before the publisher.
  TextStyle get country => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: ink,
  );

  /// "Chamber of Deputies", "2h ago".
  TextStyle get source => TextStyle(fontSize: 13, color: secondary);

  /// Georgia, as the app's other headlines: it has Cyrillic (Charter and
  /// Iowan Old Style do not, so Ukrainian fell back to another serif).
  TextStyle headline({bool top = false}) => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _serifFallback,
    fontSize: top ? 20 : 18,
    fontWeight: FontWeight.w700,
    height: 1.22,
    color: ink,
  );

  /// The one line of the short summary.
  TextStyle get summary =>
      TextStyle(fontSize: 15, height: 1.3, color: secondary);
}

/// Lays out [child] only to measure the masthead's sizes: never shown, never
/// read by VoiceOver.
class _Prototype extends StatelessWidget {
  const _Prototype(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: IgnorePointer(child: child));
}

/// The date, the name and the bar. The bar is last, so a pinned masthead
/// that has shrunk shows just the bar.
class _Masthead extends StatelessWidget {
  const _Masthead(this.masthead, {this.prototype = false});

  final FeedMasthead masthead;

  /// Draws the texts as plain RichText, so the measuring copy is not found
  /// as a second "Official News" by tests.
  final bool prototype;

  @override
  Widget build(BuildContext context) {
    final t = _Styles.of(context);
    Widget text(BuildContext context, String data, TextStyle style) => prototype
        ? RichText(
            text: TextSpan(text: data, style: style),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )
        : Text(data, style: style, maxLines: 1);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text(context, masthead.date.toUpperCase(), t.date),
                const SizedBox(height: 2),
                // The name is a logo: it grows a little with the text size,
                // then stays on one line.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Builder(
                      builder: (context) =>
                          text(context, masthead.title, t.title),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Bar(masthead),
        ],
      ),
    );
  }
}

/// The filters and the gear, over a black rule: what stays at the top.
class _Bar extends StatelessWidget {
  const _Bar(this.masthead);

  final FeedMasthead masthead;

  @override
  Widget build(BuildContext context) {
    final t = _Styles.of(context);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                // One row at every text size, sliding sideways when the
                // chips are wider than the screen: a bar that wrapped would
                // take a third of the screen once pinned.
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: ConstrainedBox(
                      // The chips' labels are Flexible: they need a bound.
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: masthead.filterBar,
                    ),
                  ),
                ),
                // The filter bar starts 10 pt down: the gear too, so both
                // stay centred on each other at every text size.
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: masthead.settingsButton,
                ),
              ],
            ),
          ),
          Container(height: 1.5, color: t.ink),
        ],
      ),
    );
  }
}

/// "TOP STORIES ──────": a small capital label and a rule to the edge.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.top});

  final String title;
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = _Styles.of(context);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(20, top, 20, 4),
      sliver: SliverToBoxAdapter(
        child: Semantics(
          header: true,
          label: title,
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                // A long label at a large text size wraps before the rule.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.8,
                  ),
                  child: Text(title.toUpperCase(), style: t.section),
                ),
                const SizedBox(width: 10),
                Expanded(child: Container(height: 1, color: t.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// From the text size "xxxLarge" up: one column for everything, so the
/// headline keeps the whole width.
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13;

/// The width of the column of a top story's numeral: it grows with the text,
/// up to the numeral's own limit; none with large text.
double _numeralColumn(BuildContext context) => _largeText(context)
    ? 0
    : MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3).scale(34) +
          10;

/// One decision: country, publisher and time; the headline; one line of the
/// short summary. Top stories carry their number.
class _Item extends StatelessWidget {
  const _Item({
    required this.article,
    required this.number,
    required this.read,
    required this.onTap,
  });

  final Article article;
  final int? number;
  final bool read;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = _Styles.of(context);
    final l10n = AppLocalizations.of(context);
    final country = countryName(article.country, l10n);
    final time = feedTime(article, l10n);
    final summary = article.shortSummary?.trim() ?? '';
    // Top stories are the most important already: their numeral says so.
    final important = number == null && (article.importance ?? 0) >= 4;
    final n = number;

    // One VoiceOver label, read as a sentence: "1. Chamber proposes …
    // Brazil, Chamber of Deputies. The Chamber … 8m ago."
    final spoken = [
      if (n != null) '$n',
      article.headline,
      '$country, ${article.source.name}',
      if (summary.isNotEmpty) summary,
      time,
    ].map(_sentence).join(' ');

    final large = _largeText(context);
    final numeral = n == null
        ? null
        : MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Text('$n', style: dim(t.numeral, read)),
          );
    final countryText = TextSpan(
      text: country.toUpperCase(),
      style: dim(t.country, read),
    );

    // Country first, so it is never the part cut off; the time at the right.
    // With large text the publisher and the time get a line of their own,
    // and a top story's numeral moves into this line to leave the headline
    // the whole width.
    final meta = Row(
      children: [
        if (large && numeral != null) ...[numeral, const SizedBox(width: 12)],
        if (important) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: dim(TextStyle(color: t.accent), read).color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text.rich(
            large
                ? countryText
                : TextSpan(
                    children: [
                      countryText,
                      TextSpan(
                        text: '  ${article.source.name}',
                        style: dim(t.source, read),
                      ),
                    ],
                  ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!large) ...[
          const SizedBox(width: 10),
          Text(time, style: dim(t.source, read)),
        ],
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        meta,
        if (large)
          Text(
            // The time stays in one piece: "2 год тому", not "2 год / тому".
            '${article.source.name} · ${time.replaceAll(' ', '\u00A0')}',
            style: dim(t.source, read),
          ),
        const SizedBox(height: 4),
        Text(article.headline, style: dim(t.headline(top: n != null), read)),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            summary,
            style: dim(t.summary, read),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: numeral == null || large
              ? body
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: _numeralColumn(context), child: numeral),
                    Expanded(child: body),
                  ],
                ),
        ),
      ),
    );
  }

  /// [text] ending in a full stop, for VoiceOver to pause after it.
  static String _sentence(String text) {
    final s = text.trim();
    if (s.isEmpty || '.!?…'.contains(s[s.length - 1])) return s;
    return '$s.';
  }
}

/// "↑ 3 new decisions": a black pill (white in dark mode), with a 44-pt target.
class _NewPill extends StatelessWidget {
  const _NewPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = _Styles.of(context);
    final paper = Theme.of(context).scaffoldBackgroundColor;
    final label = AppLocalizations.of(context).newDecisions(count);
    // The screen puts the pill 12 pt from the top, which is over the pinned
    // filters once the list has scrolled: it moves down to just below the bar
    // (filters 10 pt down, a chip of 36 pt or more with large text, 8 pt and
    // the rule). The space above it lets taps through to the list.
    final chip = math.max(
      36.0,
      MediaQuery.textScalerOf(context).scale(15) * 1.2 + 14,
    );
    return Padding(
      padding: EdgeInsets.only(top: 10 + chip + 8 + 1.5 - 12 + 8),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            // Grows with the text up to twice the size: past that, a few
            // words would fill the screen.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 2,
              child: Builder(
                builder: (context) => Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: t.ink,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.arrow_up,
                        size: MediaQuery.textScalerOf(context).scale(15),
                        color: paper,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: paper,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
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
    );
  }
}
