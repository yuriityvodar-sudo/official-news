import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics.dart';
import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/glass.dart';
import '../../core/languages.dart';
import '../../core/motion.dart';
import '../../core/news_widgets.dart';
import '../../core/card_zoom.dart';
import '../../core/pictures.dart';
import '../../core/push.dart';
import '../../core/subscription.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../chat/chat_consent.dart';
import '../chat/chat_screen.dart';
import '../chat/paywall_sheet.dart';
import 'ai_chat_note.dart';
import 'picture_viewer.dart';

/// Opens the official page; tests pass their own.
typedef OpenLink = Future<void> Function(Uri uri);

/// Opens the system share sheet with [text]; `origin` anchors it on iPad.
/// Tests pass their own.
typedef ShareArticle =
    Future<void> Function(Article article, String text, Rect? origin);

/// The official page in the in-app browser (Safari view on iOS, custom tab on Android).
Future<void> openOfficialPage(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
}

/// The official page without its `#fragment` (the fetcher adds one to tell
/// stages of one bill apart), or null when it is not an http/https page: the
/// link comes from a source site, not from us.
Uri? officialPage(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return uri.removeFragment();
}

/// What is shared: the headline, the short summary and the official link,
/// labelled in the app's language (#52).
String shareText(Article article, AppLocalizations l10n) {
  final summary = article.shortSummary;
  final page = officialPage(article.originalUrl);
  return [
    article.headline,
    if (summary != null && summary.isNotEmpty) summary,
    if (page != null) l10n.shareOfficialSource(page.toString()),
  ].join('\n\n');
}

/// Shares [text] with the headline as its subject; a tap back once it has
/// gone (#141).
Future<void> shareArticle(Article article, String text, Rect? origin) async {
  final result = await SharePlus.instance.share(
    ShareParams(
      subject: article.headline,
      text: text,
      sharePositionOrigin: origin,
    ),
  );
  if (result.status == ShareResultStatus.success) Haptics.success();
}

/// Item 4: one official decision (docs/design/mvp.png). The ministry as
/// publisher, the decision type, the headline, the AI summary and the way to
/// the official page. It shows the Article the feed already has; no API call.
///
/// The text scrolls under two floating Liquid Glass buttons, back and share
/// (#141), as in iOS 26's own apps; they get a little smaller while the
/// reader scrolls down, and back to size when they scroll up.
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.article,
    this.top,
    this.topFrom,
    this.background,
    this.openLink = openOfficialPage,
    this.share = shareArticle,
  });

  final Article article;

  /// The card the article opened out of (#141), as its top in place of the
  /// publisher, headline, date and picture: the same card, at the same width
  /// and the same distance from the left as in the feed ([topFrom]), so the
  /// card grows into the article without anything in it changing.
  final Widget? top;
  final Rect? topFrom;

  /// The page's colour: the card's, when the article opened out of one.
  final Color? background;

  final OpenLink openLink;
  final ShareArticle share;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _scroll = ScrollController();

  /// The buttons are smaller: the reader is scrolling down the text.
  bool _compact = false;

  /// The height the buttons take at the top, under the status bar.
  static const _bar = 56.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrolled() {
    final position = _scroll.position;
    final compact = switch (position.userScrollDirection) {
      ScrollDirection.reverse => position.pixels > 40,
      ScrollDirection.forward => false,
      ScrollDirection.idle => _compact && position.pixels > 40,
    };
    if (compact != _compact) setState(() => _compact = compact);
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final summary = article.summary?.trim();
    final hasSummary = summary != null && summary.isNotEmpty;
    final top = widget.top;
    final from = widget.topFrom;
    final page = widget.background ?? scheme.surface;
    // Everything but the card at the top: at the page's margins, coming in
    // around the card as it grows into the article (#141).
    Widget rest(Widget child) => ZoomRest(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    );

    return Scaffold(
      backgroundColor: page,
      body: Stack(
        children: [
          _CountsRead(
            article: article,
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                0,
                padding.top + _bar,
                0,
                48 + padding.bottom,
              ),
              children: [
                if (top != null && from != null) ...[
                  // The card itself, where it stands in the feed.
                  Padding(
                    padding: EdgeInsets.only(left: math.max(0, from.left)),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: from.width,
                        child: ZoomTop(child: top),
                      ),
                    ),
                  ),
                  ...[
                    const SizedBox(height: 12),
                    _Official(article),
                    const SizedBox(height: 14),
                    KindLabel(article),
                    Text(_published(article, l10n), style: text.meta),
                    const SizedBox(height: 22),
                  ].map(rest),
                ] else
                  ...[
                    _Publisher(article),
                    const SizedBox(height: 18),
                    KindLabel(article),
                    Text(article.headline, style: text.articleHeadline),
                    const SizedBox(height: 10),
                    Text(_published(article, l10n), style: text.meta),
                    if (article.imageUrl != null)
                      _Picture(article.imageUrl!, articleId: article.id),
                    const SizedBox(height: 22),
                  ].map(rest),
                ...[
                  if (hasSummary) ...[
                    _AiLabel(article),
                    const SizedBox(height: 10),
                    for (final paragraph in _paragraphs(summary)) ...[
                      Text(paragraph, style: text.body),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 4),
                    _DiscussWithAi(article),
                    const SizedBox(height: 18),
                  ] else
                    const _SummaryComing(),
                  const SizedBox(height: 14),
                  _OfficialLink(
                    article: article,
                    onTap: () {
                      final page = officialPage(article.originalUrl);
                      if (page == null) return;
                      unawaited(analytics.officialLinkOpened(article));
                      widget.openLink(page);
                    },
                  ),
                ].map(rest),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // The status bar's words for the page, set here: a sheet over
            // the article (the paywall) leaves its light ones otherwise.
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value:
                  ThemeData.estimateBrightnessForColor(page) == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              child: ZoomRest(
                child: ScrollEdgeFade(
                  height: padding.top + _bar + 8,
                  color: page,
                ),
              ),
            ),
          ),
          Positioned(
            top: padding.top + 6,
            left: 12,
            right: 12,
            child: ZoomRest(
              child: Row(
                children: [
                  if (ModalRoute.of(context)?.canPop ?? false)
                    _BarButton(
                      compact: _compact,
                      onPressed: () => Navigator.of(context).maybePop(),
                      // Its name for VoiceOver (and tests), never shown.
                      child: Tooltip(
                        message: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        triggerMode: TooltipTriggerMode.manual,
                        child: Icon(
                          CupertinoIcons.chevron_left,
                          size: 20,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Builder(
                    builder: (buttonContext) => _BarButton(
                      compact: _compact,
                      onPressed: () {
                        unawaited(analytics.shared(article));
                        widget.share(
                          article,
                          shareText(article, l10n),
                          _originOf(buttonContext),
                        );
                      },
                      child: Icon(
                        CupertinoIcons.share,
                        size: 20,
                        color: CupertinoColors.label.resolveFrom(context),
                        semanticLabel: l10n.share,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A round Liquid Glass button floating over the article, with a 48-pt
/// target and a light tap back (#141); smaller while [compact].
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.compact,
    required this.onPressed,
    required this.child,
  });

  final bool compact;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: compact && !Motion.reduced(context) ? 0.86 : 1,
    duration: Motion.slow,
    curve: Motion.spring,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 48),
      onPressed: () {
        Haptics.light();
        onPressed();
      },
      // A little larger than 44, as iOS 26's own glass buttons (Yurii, #160).
      child: GlassCircle(size: 48, child: child),
    ),
  );
}

/// "Discuss with AI" under the summary (#133, #141, #146): on iOS the AI chat
/// about this decision, behind its paywall (a subscriber goes straight in);
/// once just bought, the consent and the paywall's sample question follow.
/// Where there is no App Store purchase yet (Android), the note about the
/// chat ([AiChatNote]), with "Tell me when it's ready". Each tap is counted.
class _DiscussWithAi extends StatelessWidget {
  const _DiscussWithAi(this.article);

  final Article article;

  Future<void> _open(BuildContext context) async {
    if (!ChatScreen.available) return AiChatNote.show(context);
    final l10n = AppLocalizations.of(context);
    String? first;
    if (!chatSubscription.active) {
      if (!await PaywallSheet.show(context, article)) return;
      first = l10n.chatSuggestConcernsMe;
    }
    if (!context.mounted || !await ChatConsent.ask(context)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ChatScreen(article: article, firstQuestion: first),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = NewsText.from(context);
    final label = CupertinoColors.label.resolveFrom(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {
        Haptics.light();
        unawaited(analytics.discussAiTapped(article));
        unawaited(_open(context));
      },
      child: SizedBox(
        width: double.infinity,
        child: GlassCapsule(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.sparkles, size: 18, color: label),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.discussWithAi,
                  style: text.publisher.copyWith(color: label),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Counts the article as read once it has been open, with the app in front,
/// for [ArticleReadTimer.after] (#60).
class _CountsRead extends StatefulWidget {
  const _CountsRead({required this.article, required this.child});

  final Article article;
  final Widget child;

  @override
  State<_CountsRead> createState() => _CountsReadState();
}

class _CountsReadState extends State<_CountsRead> {
  late final ArticleReadTimer _timer;

  @override
  void initState() {
    super.initState();
    _timer = ArticleReadTimer(() {
      unawaited(analytics.articleRead(widget.article));
      // The third read makes notifications worth offering (#62).
      unawaited(push.articleRead(widget.article.id));
    });
  }

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Rect? _originOf(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox ? box.localToGlobal(Offset.zero) & box.size : null;
}

/// "14 October 2026, 11:30" ("14 жовтня 2026 р. о 11:30"), or only the day
/// when the source gave no time.
String _published(Article article, AppLocalizations l10n) {
  final date = fullDate(article.publishedAt, l10n);
  if (article.dateOnly) return date;
  return l10n.dateAndTime(date, clockTime(article.publishedAt, l10n));
}

/// The summary's paragraphs: the AI separates them with a blank line.
List<String> _paragraphs(String summary) => summary
    .split(RegExp(r'\n\s*\n'))
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty)
    .toList();

/// The site's name for captions and the link card: "gov.pl".
String _site(String url) =>
    (Uri.tryParse(url)?.host ?? '').replaceFirst(RegExp(r'^www\.'), '');

/// The ministry as the publisher, with the official-source mark.
class _Publisher extends StatelessWidget {
  const _Publisher(this.article);

  final Article article;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.account_balance_outlined,
            size: 22,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.source.name,
                style: text.publisher,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              _Official(article),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Germany · ✓ Official source", under the publisher, or under the card an
/// article opened out of (#141). Wraps instead of overflowing: "Official
/// source" is longer in some languages ("Официальный источник"), and at
/// large text sizes.
class _Official extends StatelessWidget {
  const _Official(this.article);

  final Article article;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${countryName(article.country, l10n)} · ', style: text.meta),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.checkmark_seal,
              size: 15,
              color: AppColors.verified,
            ),
            const SizedBox(width: 3),
            Flexible(child: Text(l10n.officialSource, style: text.meta)),
          ],
        ),
      ],
    );
  }
}

/// The preview image of the official page, with where it comes from. A tap
/// shows it full screen, flying there (#141).
class _Picture extends StatelessWidget {
  const _Picture(this.url, {required this.articleId});

  final String url;
  final String articleId;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            button: true,
            label: AppLocalizations.of(context).pictureFullScreen,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.light();
                Navigator.of(
                  context,
                ).push(PictureViewer.route(url: url, articleId: articleId));
              },
              child: PictureHero(
                articleId: articleId,
                url: url,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image(
                      // The picture the feed card saved, decoded at screen
                      // size: official preview images can be several MB.
                      image: screenPicture(context, url),
                      fit: BoxFit.cover,
                      frameBuilder: fadeInPicture,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).imageCredit(_site(url)),
            style: text.meta.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// "Summary by AI · translated from German" ("Стислий виклад від ШІ · переклад
/// з німецької"): the note is there when the source is in another language than
/// the article is read in, so a Russian source in the Russian feed has none and
/// an English one there has "перевод с английского".
class _AiLabel extends StatelessWidget {
  const _AiLabel(this.article);

  final Article article;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    final source = article.originalLanguage;
    final reading = article.lang ?? 'en';
    final label = source == reading
        ? l10n.summaryByAi
        : l10n.summaryByAiTranslated(languageName(source, l10n));
    return Row(
      children: [
        Icon(Icons.auto_awesome_outlined, size: 15, color: text.meta.color),
        const SizedBox(width: 5),
        Flexible(child: Text(label, style: text.meta)),
      ],
    );
  }
}

/// Shown until the AI has written the summary; the headline is then the original title.
class _SummaryComing extends StatelessWidget {
  const _SummaryComing();

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.clock, size: 18, color: text.meta.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).summaryComing,
              style: text.meta,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Read the official decision": the site and the original title, opening the page.
class _OfficialLink extends StatelessWidget {
  const _OfficialLink({required this.article, required this.onTap});

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: l10n.readOfficialDecisionOn(_site(article.originalUrl)),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.readOfficialDecision, style: text.publisher),
                    const SizedBox(height: 3),
                    Text(
                      '${_site(article.originalUrl)} · ${article.originalTitle}',
                      style: text.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                CupertinoIcons.arrow_up_right_square,
                color: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
