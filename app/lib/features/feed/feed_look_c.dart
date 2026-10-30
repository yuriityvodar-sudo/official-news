import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/news_widgets.dart';
import '../../core/read_mark.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';
import 'feed_topic_tags.dart';

/// Design option C (#66, from the prototype, kept in Settings → Design): "Briefing".
///
/// Text first, like a morning briefing: a compact masthead whose filter bar
/// stays pinned at the top, and one list with every decision on the same
/// grid (no section titles and no numbered top stories since Yurii's review,
/// 16 Oct). A narrow left column holds the time, as a briefing's log
/// ("16:20", "Thu 16:20"). Next to it, three lines answer the reader's three
/// questions: who decided (the country and the whole name of the
/// institution, on up to two lines), what (the headline), and why it matters
/// (one line of the short summary), then the topics as small grey tags (the
/// decision type, which led the summary line until 16 Oct, is on the article
/// screen). A red rule in the margin marks importance 4 and 5.
/// No pictures: many official pages have none, and the ones they have are
/// often a logo.
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

  // One list in the order articles appeared, with no titles and no day
  // headings: an article dated yesterday can appear today. Each item shows
  // its own time.
  @override
  Widget articles(BuildContext context, FeedList list) => SliverPadding(
    // As far under the filters as the first item was under a section title.
    padding: const EdgeInsets.only(top: 6),
    sliver: _list(list),
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

  /// The articles of [list] with a hairline between them, built lazily.
  /// Rows reach the screen's edges, so a pressed row is shaded edge to edge.
  Widget _list(FeedList list) => SliverList.separated(
    itemCount: list.length,
    separatorBuilder: (context, i) => list.line(
      i,
      Padding(
        // The line starts at the text, not at the time.
        padding: EdgeInsets.only(left: 20 + _column(context), right: 20),
        child: const Divider(),
      ),
    ),
    itemBuilder: (context, i) {
      final a = list.articles[i];
      list.shown(i);
      return list.tile(
        i,
        _Item(
          article: a,
          mark: list.markOf(a),
          topics: list.topicsOf(a),
          onTap: () => list.open(i),
        ),
      );
    },
  );
}

/// The look's text styles and colours, from the app's colour scheme: black
/// on white, white on black, grey for what is secondary, and red only for
/// the importance rule and the end mark, never for small text.
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

  /// The left column's width before its gap, and how far it grows with the
  /// reader's text size. It was the size of the Top stories numerals: kept,
  /// so the rows keep the grid they had.
  static const columnSize = 34.0;
  static const columnMaxScale = 1.3;

  /// "FRIDAY, 16 OCTOBER" above the name.
  TextStyle get date => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: secondary,
  );

  /// "Outer News".
  TextStyle get title => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _serifFallback,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: ink,
  );

  /// "BRAZIL" before the institution.
  TextStyle get country => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: ink,
  );

  /// "Chamber of Deputies".
  TextStyle get source => TextStyle(fontSize: 13, color: secondary);

  /// "16:20" in the left column: figures of one width, so times line up.
  TextStyle get time => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: secondary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Georgia, as the app's other headlines: it has Cyrillic (Charter and
  /// Iowan Old Style do not, so Ukrainian fell back to another serif).
  TextStyle get headline => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _serifFallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.22,
    color: ink,
  );

  /// The short summary.
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
  /// as a second "Outer News" by tests.
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
    // The filter bar centres its chips 10 pt plus half a chip down; a chip
    // is its 15-pt label (about 1.2 lines' height in SF) plus 14 pt, and at
    // least 36 pt. The gear's 44-pt target is centred on the same line, at
    // every text size (as B's toolbar does).
    final chip = math.max(
      36.0,
      14 + MediaQuery.textScalerOf(context).scale(15) * 1.2,
    );
    final gearTop = math.max(0.0, 10 + chip / 2 - 22);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Chips(masthead.filterBar)),
                const SizedBox(width: 6),
                Padding(
                  padding: EdgeInsets.only(top: gearTop),
                  child: masthead.buttons,
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

/// The chips in one row at every text size, sliding sideways when they are
/// wider than the screen (a bar that wrapped would take a third of the
/// screen once pinned). They slide out at the screen's edge on the left and
/// stop short of the gear on the right, where they fade while more of them
/// is hidden there.
class _Chips extends StatefulWidget {
  const _Chips(this.child);

  final Widget child;

  @override
  State<_Chips> createState() => _ChipsState();
}

class _ChipsState extends State<_Chips> {
  final _scroll = ScrollController();

  /// Whether some chips are hidden on the right.
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _check() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final p = _scroll.position;
    final more = p.pixels < p.maxScrollExtent - 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final paper = Theme.of(context).scaffoldBackgroundColor;
    return NotificationListener<ScrollMetricsNotification>(
      // Sent after layout, when the chips' width or the text size changes.
      onNotification: (_) {
        _check();
        return false;
      },
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            padding: const EdgeInsets.only(left: 20, right: 8),
            child: ConstrainedBox(
              // The chips' labels are Flexible: they need a bound.
              constraints: const BoxConstraints(maxWidth: 1000),
              child: widget.child,
            ),
          ),
          if (_more)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: 24,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [paper.withValues(alpha: 0), paper],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// From the text size "xxxLarge" up: no left column, so the text keeps the
/// whole width.
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13;

/// The width of the left column (the time, and a gap): it grows with the
/// text, up to its own limit; none with large text.
double _column(BuildContext context) => _largeText(context)
    ? 0
    : MediaQuery.textScalerOf(context)
              .clamp(maxScaleFactor: _Styles.columnMaxScale)
              .scale(_Styles.columnSize) +
          14;

/// When the article appeared in the feed, as a briefing logs it: "16:20"
/// today; the weekday over the time this week ("Thu", "16:20"); the date
/// over the time before that ("9 Oct", "16:20"). The same moment as the other
/// looks' "2h ago", the one the feed is ordered by; the clock needs no new
/// words in any language and does not change while the reader looks at it.
List<String> _stamp(Article article, AppLocalizations l10n) {
  final added = article.addedAt;
  final when = (added ?? article.publishedAt).toLocal();
  final clock = added != null || !article.dateOnly
      ? clockTime(when, l10n)
      : null;
  final today = localDay(DateTime.now());
  // Compared as UTC dates: local midnights are 23 or 25 hours apart on a
  // clock change.
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(when.year, when.month, when.day)).inDays;
  final locale = l10n.localeName == 'en' ? 'en_GB' : l10n.localeName;
  final day = days <= 0
      ? null
      : days < 7
      ? _capitalized(DateFormat.E(locale).format(when))
      : DateFormat.MMMd(locale).format(when);
  final lines = [?day, ?clock];
  return lines.isEmpty ? [l10n.today] : lines;
}

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// The two words VoiceOver adds in C. If C is chosen, they move
/// to lib/l10n/app_*.arb (feedImportant, feedOpened) with the other words.
({String important, String opened}) _words(AppLocalizations l10n) =>
    switch (l10n.localeName) {
      'uk' => (important: 'Важливе', opened: 'Відкрито'),
      'ru' => (important: 'Важное', opened: 'Открыто'),
      'es' => (important: 'Importante', opened: 'Abierto'),
      'de' => (important: 'Wichtig', opened: 'Geöffnet'),
      _ => (important: 'Important', opened: 'Opened'),
    };

/// One decision: the left column (the time); who decided; the headline; the
/// short summary; its topics.
class _Item extends StatelessWidget {
  const _Item({
    required this.article,
    required this.mark,
    required this.topics,
    required this.onTap,
  });

  final Article article;

  /// Opened or not, and how that shows ([ReadStyle]): greyed in Dim, or the
  /// unread dot after the country in the dot styles.
  final ReadMark mark;

  /// The topic tags, in order ([FeedList.topicsOf]).
  final List<String> topics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = _Styles.of(context);
    final read = mark.dimmed;
    final l10n = AppLocalizations.of(context);
    final country = placeName(article, l10n);
    final summary = article.shortSummary?.trim() ?? '';
    final stamp = _stamp(article, l10n);
    final important = (article.importance ?? 0) >= 4;
    final large = _largeText(context);

    // An opened row turns what is black grey and leaves what is grey as it
    // is: every line keeps 5.2:1 or more, where fading kept about 2.2:1.
    TextStyle inked(TextStyle style) =>
        read ? style.copyWith(color: t.secondary) : style;

    // One VoiceOver label, read as sentences: "Important. Chamber proposes
    // …. Brazil, Chamber of Deputies. The Chamber …. Topics: Economy, Trade.
    // 8m ago."
    final spoken = [
      if (important) _words(l10n).important,
      article.headline,
      '$country, ${article.source.name}',
      if (summary.isNotEmpty) summary,
      ?spokenTopics(topics, l10n),
      feedTime(article, l10n),
      if (read) _words(l10n).opened,
      if (mark.unread) l10n.feedUnread,
    ].map(_sentence).join(' ');

    // The time in the left column: never wider than the column, and on the
    // first line's baseline.
    final column = _column(context);
    final time = large
        ? null
        : MediaQuery.withClampedTextScaling(
            maxScaleFactor: _Styles.columnMaxScale,
            child: SizedBox(
              width: column - 10,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(stamp.join('\n'), style: t.time),
              ),
            ),
          );

    // Who decided, in full: the country first, then the institution, on up
    // to two lines. With large text the institution gets a line of its own
    // with the time, to leave the headline the whole width. Note: in
    // the dot styles the unread dot follows the country, its room kept once
    // read.
    final countryText = TextSpan(
      text: country.toUpperCase(),
      style: inked(t.country),
    );
    // Once read, the room between the country and the institution shows a
    // small grey " · ", as B does; after the country alone, nothing.
    InlineSpan dot({bool trailing = false}) => unreadDotSpan(
      context,
      mark,
      fontSize: t.country.fontSize!,
      scaler: MediaQuery.textScalerOf(context),
      separator: trailing ? null : t.source.color,
      trailing: trailing,
    );
    final who = large
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                mark.dots
                    ? TextSpan(children: [countryText, dot(trailing: true)])
                    : countryText,
              ),
              // A time that does not fit starts the next line, with no
              // separator left hanging, and stays in one piece.
              Wrap(
                spacing: 8,
                children: [
                  Text(article.source.name, style: t.source),
                  Text(
                    stamp.join(' ').replaceAll(' ', '\u00A0'),
                    style: t.source,
                  ),
                ],
              ),
            ],
          )
        : Text.rich(
            TextSpan(
              children: [
                countryText,
                if (mark.dots) ...[
                  dot(),
                  TextSpan(text: article.source.name, style: t.source),
                ] else
                  TextSpan(text: '  ${article.source.name}', style: t.source),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );

    // Importance: a red rule beside the headline, in the gap of
    // the left column (in the page margin with large text). Not a dot: a dot
    // before a row reads as "unread" on iOS. Grey once read, in Dim and in
    // the Red style, where red on a row means not opened yet.
    Widget headline = Text(article.headline, style: inked(t.headline));
    if (important) {
      headline = Stack(
        clipBehavior: Clip.none,
        children: [
          headline,
          Positioned(
            left: large ? -12 : -8,
            top: 3,
            bottom: 3,
            width: 3,
            child: ColoredBox(color: mark.greyAccent ? t.secondary : t.accent),
          ),
        ],
      );
    }

    // Why it matters: one line of the summary, two with large text.
    final brief = summary.isEmpty
        ? null
        : Text(
            summary,
            style: t.summary,
            maxLines: large ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        who,
        const SizedBox(height: 4),
        headline,
        if (brief != null) ...[const SizedBox(height: 3), brief],
        // The topics last, as small grey tags: secondary to the three lines
        // above. Grey stays grey on an opened row, as the summary does.
        if (topics.isNotEmpty) ...[
          const SizedBox(height: 6),
          TopicTags(topics, color: t.secondary),
        ],
      ],
    );

    final Widget row;
    if (large) {
      row = body;
    } else {
      row = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(width: column, child: time),
          Expanded(child: body),
        ],
      );
    }

    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: _Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: row,
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

/// A row that shades while it is pressed, as iOS list rows do, and fades
/// out after the tap, so even a quick tap shows it was taken. One colour
/// behind the row, no Opacity layer.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable>
    with SingleTickerProviderStateMixin {
  late final _shade = AnimationController(vsync: this);

  @override
  void dispose() {
    _shade.dispose();
    super.dispose();
  }

  void _fade() =>
      _shade.animateTo(0, duration: const Duration(milliseconds: 350));

  @override
  Widget build(BuildContext context) {
    final ink = _Styles.of(context).ink;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _shade.value = 1,
      onTapCancel: _fade,
      onTap: () {
        _shade.value = 1;
        _fade();
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _shade,
        builder: (context, child) => ColoredBox(
          color: ink.withValues(alpha: 0.1 * _shade.value),
          child: child,
        ),
        child: widget.child,
      ),
    );
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
    // The screen floats it just under the masthead, never on the filters.
    return Semantics(
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
    );
  }
}
