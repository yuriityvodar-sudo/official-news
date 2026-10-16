import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/decision_types.dart';
import '../../core/news_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';

/// Design option C (#66), prototype: "Briefing".
///
/// Text first, like a morning briefing: a compact masthead whose filter bar
/// stays pinned at the top, and every decision on the same grid. A narrow
/// left column holds the index: in Top stories a large numeral, with the time
/// under it; in Latest the time alone, as a briefing's log ("16:20", "Thu
/// 16:20"). Next to it, three lines answer the reader's three questions:
/// who decided (the country and the whole name of the institution, on up to
/// two lines), what (the headline), and what kind of act it is and why it
/// matters (the decision type in bold, then the short summary: two lines in
/// Top stories, one in Latest). In Latest a red rule in the margin marks
/// importance 4 and 5; in Top stories the numeral does. No pictures: many
/// official pages have none, and the ones they have are often a logo.
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
  /// Rows reach the screen's edges, so a pressed row is shaded edge to edge.
  Widget _list(FeedSection section, {required bool numbered}) =>
      SliverList.separated(
        itemCount: section.length,
        separatorBuilder: (context, _) => Padding(
          // The line starts at the text, not at the numeral or the time.
          padding: EdgeInsets.only(left: 20 + _column(context), right: 20),
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

  /// The size of the Top stories numerals, and how far they grow with the
  /// reader's text size: the left column is measured from both.
  static const numeralSize = 34.0;
  static const numeralMaxScale = 1.3;

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
    fontSize: numeralSize,
    fontWeight: FontWeight.w700,
    height: 1,
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
  TextStyle headline({bool top = false}) => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _serifFallback,
    fontSize: top ? 20 : 18,
    fontWeight: FontWeight.w700,
    height: 1.22,
    color: ink,
  );

  /// The short summary.
  TextStyle get summary =>
      TextStyle(fontSize: 15, height: 1.3, color: secondary);

  /// "Bill", "Proposal" at the start of the summary: what kind of act it is.
  TextStyle get kind =>
      summary.copyWith(fontWeight: FontWeight.w600, color: ink);
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

/// From the text size "xxxLarge" up: no left column, so the text keeps the
/// whole width.
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13;

/// The width of the left column (the numeral or the time, and a gap): it
/// grows with the text, up to the numeral's own limit; none with large text.
double _column(BuildContext context) => _largeText(context)
    ? 0
    : MediaQuery.textScalerOf(context)
              .clamp(maxScaleFactor: _Styles.numeralMaxScale)
              .scale(_Styles.numeralSize) +
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

/// PROTOTYPE: the two words VoiceOver adds in C. If C is chosen, they move
/// to lib/l10n/app_*.arb (feedImportant, feedOpened) with the other words.
({String important, String opened}) _words(AppLocalizations l10n) =>
    switch (l10n.localeName) {
      'uk' => (important: 'Важливе', opened: 'Відкрито'),
      'ru' => (important: 'Важное', opened: 'Открыто'),
      'es' => (important: 'Importante', opened: 'Abierto'),
      'de' => (important: 'Wichtig', opened: 'Geöffnet'),
      _ => (important: 'Important', opened: 'Opened'),
    };

/// One decision: the left column (numeral and time, or the time); who
/// decided; the headline; the kind of act and the short summary.
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
    final kind = decisionTypeLabel(article.decisionType, l10n);
    final summary = article.shortSummary?.trim() ?? '';
    final stamp = _stamp(article, l10n);
    // Top stories are the most important already: their numeral says so.
    final important = number == null && (article.importance ?? 0) >= 4;
    final n = number;
    final large = _largeText(context);

    // An opened row turns what is black grey and leaves what is grey as it
    // is: every line keeps 5.2:1 or more, where fading kept about 2.2:1.
    TextStyle inked(TextStyle style) =>
        read ? style.copyWith(color: t.secondary) : style;

    // One VoiceOver label, read as sentences: "1. Chamber proposes …. Bill.
    // Brazil, Chamber of Deputies. The Chamber …. 8m ago."
    final spoken = [
      if (n != null) '$n',
      if (important) _words(l10n).important,
      article.headline,
      ?kind,
      '$country, ${article.source.name}',
      if (summary.isNotEmpty) summary,
      feedTime(article, l10n),
      if (read) _words(l10n).opened,
    ].map(_sentence).join(' ');

    final numeral = n == null
        ? null
        : MediaQuery.withClampedTextScaling(
            maxScaleFactor: _Styles.numeralMaxScale,
            child: Text('$n', style: inked(t.numeral)),
          );

    // The time in the left column: never wider than the column, and on the
    // first line's baseline in Latest.
    final column = _column(context);
    final time = large
        ? null
        : MediaQuery.withClampedTextScaling(
            maxScaleFactor: _Styles.numeralMaxScale,
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
    // with the time, and a top story's numeral moves into the country's line
    // to leave the headline the whole width.
    final countryText = TextSpan(
      text: country.toUpperCase(),
      style: inked(t.country),
    );
    final who = large
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (numeral != null) ...[numeral, const SizedBox(width: 12)],
                  Expanded(child: Text.rich(countryText)),
                ],
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
                TextSpan(text: '  ${article.source.name}', style: t.source),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );

    // Importance in Latest: a red rule beside the headline, in the gap of
    // the left column (in the page margin with large text). Not a dot: a dot
    // before a row reads as "unread" on iOS.
    Widget headline = Text(
      article.headline,
      style: inked(t.headline(top: n != null)),
    );
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
            child: ColoredBox(color: read ? t.secondary : t.accent),
          ),
        ],
      );
    }

    // What kind of act, then why it matters: "Proposal · The EU proposes …".
    // The kind says what the headline may not (a proposal is not yet a
    // rule); the summary gets two lines in Top stories, one in Latest.
    final brief = kind == null && summary.isEmpty
        ? null
        : Text.rich(
            TextSpan(
              children: [
                if (kind != null)
                  TextSpan(
                    // Never a line that starts with the dot.
                    text: summary.isEmpty ? kind : '$kind\u00A0· ',
                    style: inked(t.kind),
                  ),
                if (summary.isNotEmpty)
                  TextSpan(text: summary, style: t.summary),
              ],
            ),
            maxLines: n != null ? (large ? 3 : 2) : (large ? 2 : 1),
            overflow: TextOverflow.ellipsis,
          );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        who,
        const SizedBox(height: 4),
        headline,
        if (brief != null) ...[const SizedBox(height: 3), brief],
      ],
    );

    final Widget row;
    if (large) {
      row = body;
    } else if (numeral != null) {
      row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: column,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [numeral, const SizedBox(height: 8), time!],
            ),
          ),
          Expanded(child: body),
        ],
      );
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
