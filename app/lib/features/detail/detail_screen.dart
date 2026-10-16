import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics.dart';
import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/languages.dart';
import '../../core/news_widgets.dart';
import '../../core/pictures.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';

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

/// Shares [text] with the headline as its subject.
Future<void> shareArticle(Article article, String text, Rect? origin) async {
  await SharePlus.instance.share(
    ShareParams(
      subject: article.headline,
      text: text,
      sharePositionOrigin: origin,
    ),
  );
}

/// Item 4: one official decision (docs/design/mvp.png). The ministry as
/// publisher, the decision type, the headline, the AI summary and the way to
/// the official page. It shows the Article the feed already has; no API call.
class DetailScreen extends StatelessWidget {
  const DetailScreen({
    super.key,
    required this.article,
    this.openLink = openOfficialPage,
    this.share = shareArticle,
  });

  final Article article;
  final OpenLink openLink;
  final ShareArticle share;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final summary = article.summary?.trim();
    final hasSummary = summary != null && summary.isNotEmpty;

    return Scaffold(
      appBar: CupertinoNavigationBar(
        backgroundColor: scheme.surface,
        border: null,
        trailing: Builder(
          builder: (buttonContext) => CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              unawaited(analytics.shared(article));
              share(
                article,
                shareText(article, l10n),
                _originOf(buttonContext),
              );
            },
            child: Icon(
              CupertinoIcons.share,
              color: AppColors.accent,
              semanticLabel: l10n.share,
            ),
          ),
        ),
      ),
      body: _CountsRead(
        article: article,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            _Publisher(article),
            const SizedBox(height: 18),
            KindLabel(article),
            Text(article.headline, style: text.articleHeadline),
            const SizedBox(height: 10),
            Text(_published(article, l10n), style: text.meta),
            if (article.imageUrl != null) _Picture(article.imageUrl!),
            const SizedBox(height: 22),
            if (hasSummary) ...[
              _AiLabel(article),
              const SizedBox(height: 10),
              for (final paragraph in _paragraphs(summary)) ...[
                Text(paragraph, style: text.body),
                const SizedBox(height: 14),
              ],
            ] else
              const _SummaryComing(),
            const SizedBox(height: 14),
            _OfficialLink(
              article: article,
              onTap: () {
                final page = officialPage(article.originalUrl);
                if (page == null) return;
                unawaited(analytics.officialLinkOpened(article));
                openLink(page);
              },
            ),
          ],
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
    final l10n = AppLocalizations.of(context);
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
              // Wraps instead of overflowing: "Official source" is longer in
              // some languages ("Официальный источник"), and at large text sizes.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${countryName(article.country, l10n)} · ',
                    style: text.meta,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.checkmark_seal,
                        size: 15,
                        color: AppColors.verified,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(l10n.officialSource, style: text.meta),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The preview image of the official page, with where it comes from.
class _Picture extends StatelessWidget {
  const _Picture(this.url);

  final String url;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image(
                // The picture the feed card saved, decoded at screen size:
                // official preview images can be several MB.
                image: picture(
                  url,
                  width: (media.size.width * media.devicePixelRatio).round(),
                ),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
