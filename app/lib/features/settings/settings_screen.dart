import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/feed_language.dart';
import '../../core/read_mark.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../detail/detail_screen.dart' show OpenLink, openOfficialPage;
import '../feed/feed_look.dart';
import '../splash/splash.dart';
import 'info_pages.dart';

/// The version shown at the foot of Settings: "0.1.0 (19)" for TestFlight build
/// 19 (`--dart-define=BUILD_NUMBER=` from the TestFlight workflow), "0.1.0" in
/// local runs, so the reader and we know exactly which build is on the phone.
const appVersion = String.fromEnvironment('BUILD_NUMBER') == ''
    ? '0.1.0'
    : '0.1.0 (${String.fromEnvironment('BUILD_NUMBER')})';

/// Settings (#64): a plain iOS list opened from the button at the top right of
/// the feed, as in Apple's own apps, with black-and-white symbols (Yurii). No
/// login. The language lives here, for the news and the app's words alike
/// (#52), with the pages an App Store app needs.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.language,
    required this.onLanguage,
    this.openLink = openOfficialPage,
  });

  /// The feed's language now, and how to change it (the feed reloads in it).
  final ValueListenable<FeedLanguage> language;
  final ValueChanged<FeedLanguage> onLanguage;

  /// Opens a link (the support e-mail); tests pass their own.
  final OpenLink openLink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return CupertinoPageScaffold(
      backgroundColor: grouped,
      // Material for the default text style (no yellow underline on plain Text).
      child: Material(
        type: MaterialType.transparency,
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: Text(l10n.settings),
              previousPageTitle: l10n.today,
              backgroundColor: grouped,
              border: null,
            ),
            SliverList.list(
              children: [
                const _DesignSection(),
                CupertinoListSection.insetGrouped(
                  header: _Header(l10n.settingsReading),
                  children: [
                    ValueListenableBuilder(
                      valueListenable: language,
                      builder: (context, lang, _) => CupertinoListTile(
                        leading: const _Icon(CupertinoIcons.globe),
                        title: Text(l10n.language),
                        additionalInfo: Text(lang.nativeName),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => Navigator.of(context).push(
                          CupertinoPageRoute(
                            settings: const RouteSettings(
                              name: '/settings/language',
                            ),
                            builder: (_) => _LanguagePage(
                              language: language,
                              onLanguage: onLanguage,
                            ),
                          ),
                        ),
                      ),
                    ),
                    CupertinoListTile(
                      leading: const _Icon(CupertinoIcons.bell),
                      title: Text(l10n.notifications),
                      additionalInfo: Text(l10n.soon),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: _Header(l10n.settingsAboutHeader),
                  children: [
                    _PageTile(
                      icon: CupertinoIcons.info_circle,
                      title: l10n.aboutApp,
                      route: '/settings/about',
                      page: (context) {
                        final l10n = AppLocalizations.of(context);
                        return InfoPage(
                          title: l10n.aboutTitle,
                          sections: aboutSections(l10n),
                        );
                      },
                    ),
                    _PageTile(
                      icon: CupertinoIcons.hand_raised,
                      title: l10n.privacyPolicy,
                      route: '/settings/privacy',
                      page: (context) {
                        final l10n = AppLocalizations.of(context);
                        return InfoPage(
                          title: l10n.privacyPolicy,
                          sections: privacySections(l10n),
                          updated: policyUpdatedLine(l10n),
                        );
                      },
                    ),
                    _PageTile(
                      icon: CupertinoIcons.doc_text,
                      title: l10n.termsOfUse,
                      route: '/settings/terms',
                      page: (context) {
                        final l10n = AppLocalizations.of(context);
                        return InfoPage(
                          title: l10n.termsOfUse,
                          sections: termsSections(l10n),
                          updated: policyUpdatedLine(l10n),
                        );
                      },
                    ),
                    _PageTile(
                      icon: CupertinoIcons.envelope,
                      title: l10n.contactSupport,
                      route: '/settings/support',
                      page: (context) {
                        final l10n = AppLocalizations.of(context);
                        return InfoPage(
                          title: l10n.contactSupport,
                          sections: supportSections(l10n),
                          footer: supportFooter(context, open: openLink),
                        );
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
                  child: Text(
                    '${l10n.settingsFooter}\n\n${l10n.version(appVersion)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// PROTOTYPE (#66): switches the feed between today's look and the design
/// options, plays the splash styles, and switches how read articles look, to
/// compare them in one build. English only; not for release.
class _DesignSection extends StatelessWidget {
  const _DesignSection();

  @override
  Widget build(BuildContext context) => CupertinoListSection.insetGrouped(
    header: const _Header('Prototype'),
    children: [
      ValueListenableBuilder(
        valueListenable: feedDesign,
        builder: (context, design, _) => CupertinoListTile(
          leading: const _Icon(CupertinoIcons.paintbrush),
          title: const Text('Design'),
          trailing: CupertinoSlidingSegmentedControl<FeedDesign>(
            groupValue: design,
            onValueChanged: (d) {
              if (d == null || d == design) return;
              feedDesign.value = d;
              // Back to the feed to show the new look, once the segment has slid over.
              Future.delayed(const Duration(milliseconds: 250), () {
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              });
            },
            children: const {
              FeedDesign.now: Text('Now'),
              FeedDesign.a: Text('A'),
              FeedDesign.b: Text('B'),
              FeedDesign.c: Text('C'),
            },
          ),
        ),
      ),
      // The splash at start (Yurii, 16 Oct): pick a style, Play shows it now.
      ValueListenableBuilder(
        valueListenable: splashStyle,
        builder: (context, style, _) => CupertinoListTile(
          leading: const _Icon(CupertinoIcons.sparkles),
          title: const Text('Splash'),
          subtitle: Text(switch (style) {
            SplashStyle.rise => 'rise',
            SplashStyle.riseUp => 'rise, news first',
            SplashStyle.sweep => 'sweep',
            SplashStyle.fill => 'fill',
          }),
          trailing: CupertinoSlidingSegmentedControl<SplashStyle>(
            groupValue: style,
            onValueChanged: (s) {
              if (s != null) splashStyle.value = s;
            },
            children: const {
              SplashStyle.rise: Text('1'),
              SplashStyle.riseUp: Text('1b'),
              SplashStyle.sweep: Text('2'),
              SplashStyle.fill: Text('3'),
            },
          ),
        ),
      ),
      CupertinoListTile(
        leading: const _Icon(CupertinoIcons.play),
        title: const Text('Play'),
        onTap: () {
          SplashHost.play(context);
          // It ends on the feed, as at a cold start: Settings closes under
          // the splash, out of sight (its page covers all from its first
          // frame).
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
      // How read articles look (Yurii, 16 Oct): faded as today, or a blue or
      // red dot on the unread ones instead of the official-source tick.
      ValueListenableBuilder(
        valueListenable: readStyle,
        builder: (context, style, _) => CupertinoListTile(
          leading: const _Icon(CupertinoIcons.eye),
          title: const Text('Read'),
          trailing: CupertinoSlidingSegmentedControl<ReadStyle>(
            groupValue: style,
            onValueChanged: (r) {
              if (r == null || r == style) return;
              readStyle.value = r;
              // Back to the feed to show it, once the segment has slid over.
              Future.delayed(const Duration(milliseconds: 250), () {
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              });
            },
            children: const {
              ReadStyle.dim: Text('Dim'),
              ReadStyle.blue: Text('Blue'),
              ReadStyle.red: Text('Red'),
            },
          ),
        ),
      ),
    ],
  );
}

/// A section header in the iOS grouped-list style: small, grey, upper case.
class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    ),
  );
}

/// A plain symbol in the text colour (black, white in dark mode), as in
/// Apple News' lists (Yurii, 16 Oct).
class _Icon extends StatelessWidget {
  const _Icon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 24, color: CupertinoColors.label.resolveFrom(context));
}

/// A row that opens an information page.
class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.icon,
    required this.title,
    required this.route,
    required this.page,
  });

  final IconData icon;
  final String title;

  /// The route's name, for analytics screen views.
  final String route;
  final WidgetBuilder page;

  @override
  Widget build(BuildContext context) => CupertinoListTile(
    leading: _Icon(icon),
    title: Text(title),
    trailing: const CupertinoListTileChevron(),
    onTap: () => Navigator.of(context).push(
      CupertinoPageRoute(
        settings: RouteSettings(name: route),
        builder: page,
      ),
    ),
  );
}

/// The languages in their own names, a checkmark on the current one. Choosing
/// one redraws this page, and the whole app, in it at once (#52).
class _LanguagePage extends StatelessWidget {
  const _LanguagePage({required this.language, required this.onLanguage});

  final ValueListenable<FeedLanguage> language;
  final ValueChanged<FeedLanguage> onLanguage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return CupertinoPageScaffold(
      backgroundColor: grouped,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l10n.language),
        previousPageTitle: l10n.settings,
        backgroundColor: grouped,
        border: null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: ValueListenableBuilder(
            valueListenable: language,
            builder: (context, current, _) => ListView(
              children: [
                CupertinoListSection.insetGrouped(
                  footer: Text(
                    l10n.languageFooter,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                  children: [
                    for (final lang in FeedLanguage.values)
                      CupertinoListTile(
                        title: Semantics(
                          selected: lang == current,
                          child: Text(lang.nativeName),
                        ),
                        trailing: lang == current
                            ? const Icon(
                                CupertinoIcons.checkmark_alt,
                                color: AppColors.accent,
                              )
                            : null,
                        onTap: () => onLanguage(lang),
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
