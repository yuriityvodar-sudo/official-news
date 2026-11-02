import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/countries.dart';
import '../../core/glass.dart';
import '../../core/news_widgets.dart';
import '../../core/story.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../detail/detail_screen.dart';
import '../feed/feed_look.dart';
import 'outlet_mark.dart';

/// A story's page (#230, the aggregator; Roman, 1 Nov: variant B of
/// `handoff/stories-app.html`): its country, its headline, and one card per
/// outlet with the outlet's own headline, which opens the outlet's page.
/// Only headlines and links, never an outlet's text, and nothing about them:
/// no heading over the outlets, no footnote (Roman: «такие другорядные
/// тексты нам не нужны»). In the colours of the look it is opened from.
class StoryScreen extends StatelessWidget {
  const StoryScreen({
    super.key,
    required this.story,
    required this.look,
    this.country,
    this.openLink = openOfficialPage,
  });

  /// Its screen in analytics: `story`.
  static const routeName = '/story';

  final Story story;
  final FeedLook look;

  /// The reader's country, whose outlets these are.
  final String? country;
  final OpenLink openLink;

  /// The bar's height under the status bar, as on an article.
  static const _bar = 56.0;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    final padding = MediaQuery.paddingOf(context);
    final page = look.background(context);
    final kind = [
      if (country != null) countryName(country!, l10n),
      l10n.storyKind,
    ].join(' · ').toUpperCase();
    return Scaffold(
      backgroundColor: page,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              padding.top + _bar,
              16,
              48 + padding.bottom,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind,
                      style: text.kindLabel.copyWith(
                        color: look.accent(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      header: true,
                      child: Text(
                        story.title,
                        style: text.articleHeadline.copyWith(
                          fontSize: 29,
                          height: 1.16,
                        ),
                      ),
                    ),
                    // Only when the model wrote it: else it is an outlet's own.
                    if (story.aiTitle) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 15,
                            color: text.meta.color,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              l10n.storyHeadlineByAi,
                              style: text.meta,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final item in story.items) ...[
                _OutletCard(
                  item: item,
                  look: look,
                  onTap: () {
                    final page = officialPage(item.url);
                    if (page != null) unawaited(openLink(page));
                  },
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value:
                  ThemeData.estimateBrightnessForColor(page) == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              child: ScrollEdgeFade(
                height: padding.top + _bar + 8,
                color: page,
              ),
            ),
          ),
          Positioned(
            top: padding.top + 6,
            left: 12,
            child: GlassBarButton(
              compact: false,
              onPressed: () => Navigator.of(context).maybePop(),
              // Its name for VoiceOver (and tests), never shown.
              child: Tooltip(
                message: MaterialLocalizations.of(context).backButtonTooltip,
                triggerMode: TooltipTriggerMode.manual,
                child: Icon(
                  CupertinoIcons.chevron_left,
                  size: 20,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One outlet's headline on the story: the outlet's mark and name, its
/// headline in the article's serif, when, and "Read on …", which opens it.
class _OutletCard extends StatelessWidget {
  const _OutletCard({
    required this.item,
    required this.look,
    required this.onTap,
  });

  final StoryItem item;
  final FeedLook look;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    final accent = look.accent(context);
    final time = timeAgo(item.publishedAt, l10n);
    final read = l10n.readOnSource(item.outlet);
    return Semantics(
      button: true,
      label: '${item.title}. ${item.outlet}, $time. $read',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: look.cardColor(context),
            borderRadius: BorderRadius.circular(look.cardRadius),
            boxShadow: look.cardShadow(context),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    OutletMark(item.outlet, size: 20),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        item.outlet.toUpperCase(),
                        style: text.publisher.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: text.body.copyWith(
                    fontSize: 19,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(time, style: text.meta),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        read,
                        textAlign: TextAlign.end,
                        style: text.meta.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      CupertinoIcons.arrow_up_right,
                      size: 14,
                      color: accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
