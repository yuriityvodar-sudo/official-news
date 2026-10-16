import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/feed_language.dart';
import '../../core/theme.dart';
import '../detail/detail_screen.dart' show OpenLink, openOfficialPage;
import 'info_pages.dart';

/// Settings (#64): a plain iOS list opened from the button at the top right of
/// the feed, as in Apple's own apps, with black-and-white symbols (Yurii). No
/// login. The feed language lives here, with the pages an App Store app needs.
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
              largeTitle: const Text('Settings'),
              previousPageTitle: 'Today',
              backgroundColor: grouped,
              border: null,
            ),
            SliverList.list(
              children: [
                CupertinoListSection.insetGrouped(
                  header: const _Header('Reading'),
                  children: [
                    ValueListenableBuilder(
                      valueListenable: language,
                      builder: (context, lang, _) => CupertinoListTile(
                        leading: const _Icon(CupertinoIcons.globe),
                        title: const Text('Language'),
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
                    const CupertinoListTile(
                      leading: _Icon(CupertinoIcons.bell),
                      title: Text('Notifications'),
                      additionalInfo: Text('Soon'),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: const _Header('About'),
                  children: [
                    _PageTile(
                      icon: CupertinoIcons.info_circle,
                      title: 'About Official News',
                      route: '/settings/about',
                      page: (_) => const InfoPage(
                        title: 'About',
                        sections: aboutSections,
                      ),
                    ),
                    _PageTile(
                      icon: CupertinoIcons.hand_raised,
                      title: 'Privacy Policy',
                      route: '/settings/privacy',
                      page: (_) => const InfoPage(
                        title: 'Privacy Policy',
                        sections: privacySections,
                        updated: policyUpdated,
                      ),
                    ),
                    _PageTile(
                      icon: CupertinoIcons.doc_text,
                      title: 'Terms of Use',
                      route: '/settings/terms',
                      page: (_) => const InfoPage(
                        title: 'Terms of Use',
                        sections: termsSections,
                        updated: policyUpdated,
                      ),
                    ),
                    _PageTile(
                      icon: CupertinoIcons.envelope,
                      title: 'Contact & Support',
                      route: '/settings/support',
                      page: (context) => InfoPage(
                        title: 'Contact & Support',
                        sections: supportSections,
                        footer: supportFooter(context, open: openLink),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
                  child: Text(
                    'Independent app, not affiliated with any government. '
                    'Summaries are written by AI from official sources; '
                    'every article links to the original.\n\nVersion 0.1.0',
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

/// The feed languages in their own names, a checkmark on the current one.
class _LanguagePage extends StatelessWidget {
  const _LanguagePage({required this.language, required this.onLanguage});

  final ValueListenable<FeedLanguage> language;
  final ValueChanged<FeedLanguage> onLanguage;

  @override
  Widget build(BuildContext context) {
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return CupertinoPageScaffold(
      backgroundColor: grouped,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Language'),
        previousPageTitle: 'Settings',
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
                    'News shows in this language. The app itself is in English for now.',
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
