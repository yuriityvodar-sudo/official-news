import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/feed_language.dart';
import '../../core/filters.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../detail/detail_screen.dart' show OpenLink, openOfficialPage;
import 'info_pages.dart';

/// Settings (#64): a plain iOS list opened from the button at the top right of
/// the feed, as in Apple's own apps, with black-and-white symbols (Yurii). No
/// login. The language lives here, for the news and the app's words alike
/// (#52), and the country the feed's Local shows (#68), with the pages an App
/// Store app needs.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.language,
    required this.onLanguage,
    required this.country,
    required this.onCountry,
    this.openLink = openOfficialPage,
  });

  /// The feed's language now, and how to change it (the feed reloads in it).
  final ValueListenable<FeedLanguage> language;
  final ValueChanged<FeedLanguage> onLanguage;

  /// Local's country now and the countries to choose from, and how to choose
  /// one (the feed reloads in it while it shows Local).
  final ValueListenable<CountryMenu> country;
  final ValueChanged<String> onCountry;

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
                    ValueListenableBuilder(
                      valueListenable: country,
                      builder: (context, menu, _) {
                        final current = menu.current;
                        return CupertinoListTile(
                          leading: const _Icon(CupertinoIcons.location),
                          title: Text(l10n.country),
                          // A long name ("Vereinigte Staaten") is cut, not
                          // pushed past the chevron.
                          additionalInfo: current == null
                              ? null
                              : ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width * 0.4,
                                  ),
                                  child: Text(
                                    menu.nameOf(current, l10n),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                          trailing: const CupertinoListTileChevron(),
                          onTap: () => Navigator.of(context).push(
                            CupertinoPageRoute(
                              settings: const RouteSettings(
                                name: '/settings/country',
                              ),
                              builder: (_) => _CountryPage(
                                country: country,
                                onCountry: onCountry,
                              ),
                            ),
                          ),
                        );
                      },
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
                    '${l10n.settingsFooter}\n\n${l10n.version('0.1.0')}',
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

/// The countries that have sources, in the app's language, a checkmark on the
/// one Local shows (#68): the phone's region until one is chosen here.
class _CountryPage extends StatelessWidget {
  const _CountryPage({required this.country, required this.onCountry});

  final ValueListenable<CountryMenu> country;
  final ValueChanged<String> onCountry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    final note = TextStyle(
      fontSize: 13,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );
    return CupertinoPageScaffold(
      backgroundColor: grouped,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l10n.country),
        previousPageTitle: l10n.settings,
        backgroundColor: grouped,
        border: null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: ValueListenableBuilder(
            valueListenable: country,
            builder: (context, menu, _) {
              final current = menu.current;
              // Without a list (offline), the country shown now stays listed.
              final codes = [
                for (final c in menu.countries ?? const <FeedCountry>[]) c.code,
                if (menu.countries == null && current != null) current,
              ];
              return ListView(
                children: [
                  if (menu.countries == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(36, 20, 36, 0),
                      child: menu.loading
                          ? const CupertinoActivityIndicator()
                          : Text(l10n.countriesLoadFailed, style: note),
                    ),
                  if (codes.isNotEmpty)
                    CupertinoListSection.insetGrouped(
                      footer: Text(
                        l10n.countryFooter(l10n.filterLocal),
                        style: note,
                      ),
                      children: [
                        for (final code in codes)
                          CupertinoListTile(
                            title: Semantics(
                              selected: code == current,
                              child: Text(menu.nameOf(code, l10n)),
                            ),
                            trailing: code == current
                                ? const Icon(
                                    CupertinoIcons.checkmark_alt,
                                    color: AppColors.accent,
                                  )
                                : null,
                            onTap: () => onCountry(code),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
