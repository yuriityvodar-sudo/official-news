import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/feed_language.dart';
import '../../core/motion.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../detail/detail_screen.dart' show OpenLink, openOfficialPage;
import '../feed/feed_look.dart';
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
    this.notifications,
    this.openSettingsApp = openAppSettings,
    this.saveDesign,
    this.saveHeadlineWeight,
  });

  /// Settings → Design (#66): saves the look and the headline weight on the
  /// phone (the notifiers change at once either way).
  final ValueChanged<FeedDesign>? saveDesign;
  final ValueChanged<HeadlineWeight>? saveHeadlineWeight;

  /// The feed's language now, and how to change it (the feed reloads in it).
  final ValueListenable<FeedLanguage> language;
  final ValueChanged<FeedLanguage> onLanguage;

  /// Opens a link (the support e-mail); tests pass their own.
  final OpenLink openLink;

  /// The push notifications the Notifications row shows (#62): the app's
  /// own [push] unless a test passes its own.
  final Push? notifications;

  /// Opens the iOS Settings app ([appSettingsPage]); tests pass their own.
  final OpenAppSettings openSettingsApp;

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
                _DesignSection(
                  saveDesign: saveDesign,
                  saveHeadlineWeight: saveHeadlineWeight,
                ),
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
                    _NotificationsTile(
                      push: notifications ?? push,
                      openSettingsApp: openSettingsApp,
                    ),
                    if (showPushCheck) _PushCheckLine(notifications ?? push),
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

/// Design (#66): the feed's look (today's, or the options A, B and C Yurii
/// compared in the prototype, kept to switch between) and how heavy the
/// headlines are. Both are saved on the phone.
class _DesignSection extends StatelessWidget {
  const _DesignSection({this.saveDesign, this.saveHeadlineWeight});

  final ValueChanged<FeedDesign>? saveDesign;
  final ValueChanged<HeadlineWeight>? saveHeadlineWeight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CupertinoListSection.insetGrouped(
      header: _Header(l10n.settingsDesign),
      children: [
        ValueListenableBuilder(
          valueListenable: feedDesign,
          builder: (context, design, _) => CupertinoListTile(
            leading: const _Icon(CupertinoIcons.paintbrush),
            title: Text(l10n.settingsDesign),
            additionalInfo: Icon(
              designIcon(design),
              size: 22,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              semanticLabel: designName(design, l10n),
            ),
            trailing: const CupertinoListTileChevron(),
            onTap: () => _pickDesign(context, design),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: headlineWeight,
          builder: (context, weight, _) => CupertinoListTile(
            leading: const _Icon(CupertinoIcons.textformat),
            title: Text(l10n.settingsHeadlineWeight),
            additionalInfo: Text(headlineWeightName(weight, l10n)),
            trailing: const CupertinoListTileChevron(),
            onTap: () => _pickWeight(context, weight),
          ),
        ),
      ],
    );
  }

  /// The looks as an action sheet of their icons, the current one with a
  /// check mark. Back to the feed to show the new look.
  Future<void> _pickDesign(BuildContext context, FeedDesign current) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (sheet) {
        // The sheet's blue, as its words are drawn.
        final blue = CupertinoColors.systemBlue.resolveFrom(sheet);
        return CupertinoActionSheet(
          title: Text(l10n.settingsDesign),
          actions: [
            for (final d in FeedDesign.values)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  if (d == current) return;
                  Haptics.selection();
                  feedDesign.value = d;
                  saveDesign?.call(d);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Semantics(
                  selected: d == current,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // As wide as the check mark, so the icon stays centred.
                      if (d == current) const SizedBox(width: 28),
                      Icon(
                        designIcon(d),
                        size: 28,
                        color: blue,
                        semanticLabel: designName(d, l10n),
                      ),
                      if (d == current) ...[
                        const SizedBox(width: 8),
                        Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 20,
                          color: blue,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheet).pop(),
            child: Text(l10n.cancel),
          ),
        );
      },
    );
  }

  /// The four weights as an action sheet, the current one marked.
  Future<void> _pickWeight(BuildContext context, HeadlineWeight current) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: Text(l10n.settingsHeadlineWeight),
        actions: [
          for (final w in HeadlineWeight.values)
            CupertinoActionSheetAction(
              isDefaultAction: w == current,
              onPressed: () {
                Navigator.of(sheet).pop();
                if (w == current) return;
                Haptics.selection();
                headlineWeight.value = w;
                saveHeadlineWeight?.call(w);
              },
              child: Text(
                headlineWeightName(w, l10n),
                style: TextStyle(fontWeight: w.weight),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheet).pop(),
          child: Text(l10n.cancel),
        ),
      ),
    );
  }
}

/// A look's icon in Settings → Design, a picture of its layout (Roman,
/// 22 Oct: icons, not the letters A, B and C): today's list, A's newspaper
/// page, B's cards, C's lines of text with no pictures.
IconData designIcon(FeedDesign d) => switch (d) {
  FeedDesign.now => CupertinoIcons.square_list,
  FeedDesign.a => CupertinoIcons.news,
  FeedDesign.b => CupertinoIcons.rectangle_grid_1x2,
  FeedDesign.c => CupertinoIcons.text_alignleft,
};

/// What VoiceOver says for a look's icon: "Now", or "Design B".
String designName(FeedDesign d, AppLocalizations l10n) => switch (d) {
  FeedDesign.now => l10n.settingsDesignNow,
  FeedDesign.a => '${l10n.settingsDesign} A',
  FeedDesign.b => '${l10n.settingsDesign} B',
  FeedDesign.c => '${l10n.settingsDesign} C',
};

/// A weight's name in the app's language.
String headlineWeightName(HeadlineWeight w, AppLocalizations l10n) =>
    switch (w) {
      HeadlineWeight.light => l10n.headlineWeightLight,
      HeadlineWeight.regular => l10n.headlineWeightRegular,
      HeadlineWeight.semibold => l10n.headlineWeightSemibold,
      HeadlineWeight.bold => l10n.headlineWeightBold,
    };

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

/// Notifications (#62), following the phone's answer live:
/// - iOS has not asked: "Turn On" in the accent colour; a tap shows iOS's
///   question (no explanation first: the reader asked for it here).
/// - On or Off: a tap opens the iOS Settings app ([appSettingsPage], meant to
///   land on this app's page), the only place iOS lets an app's notifications
///   be turned on again or off. Back in the app, [Push] reads the permission
///   again and the row follows.
/// - No push in this build (tests, local runs): "Unavailable", no tap.
class _NotificationsTile extends StatelessWidget {
  const _NotificationsTile({required this.push, required this.openSettingsApp});

  final Push push;
  final OpenAppSettings openSettingsApp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: push.permission,
      builder: (context, permission, _) {
        const icon = _Icon(CupertinoIcons.bell);
        final title = Text(l10n.notifications);
        switch (permission) {
          case PushPermission.unavailable:
            return CupertinoListTile(
              leading: icon,
              title: title,
              additionalInfo: Text(l10n.notificationsUnavailable),
            );
          case PushPermission.notAsked:
            return CupertinoListTile(
              leading: icon,
              title: title,
              additionalInfo: Text(
                l10n.notificationsTurnOn,
                style: const TextStyle(color: AppColors.accent),
              ),
              // Not awaited: the row follows [Push.permission] as soon as iOS
              // answers, not after the topic is subscribed.
              onTap: () => unawaited(push.enable(trigger: 'settings')),
            );
          case PushPermission.granted:
          case PushPermission.denied:
            return Semantics(
              hint: l10n.notificationsOpensSettings,
              child: CupertinoListTile(
                leading: icon,
                title: title,
                additionalInfo: Text(
                  permission == PushPermission.granted
                      ? l10n.notificationsOn
                      : l10n.notificationsOff,
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () => unawaited(openSettingsApp()),
              ),
            );
        }
      },
    );
  }
}

/// Whether Settings shows the push check line (#149): TestFlight and debug
/// builds only, never the App Store's.
const showPushCheck =
    kDebugMode || String.fromEnvironment('APP_BUILD') == 'testflight';

/// Under Notifications in TestFlight builds (#149): each step between "On"
/// and a notification on this phone ([Push.check]), in small grey English,
/// since a step that fails is otherwise silent. A tap checks again and copies
/// the FCM token, so a test message can be sent to this phone from the
/// Firebase console.
class _PushCheckLine extends StatefulWidget {
  const _PushCheckLine(this.push);

  final Push push;

  @override
  State<_PushCheckLine> createState() => _PushCheckLineState();
}

class _PushCheckLineState extends State<_PushCheckLine> {
  late Future<PushCheck?> _check = widget.push.check();

  @override
  void initState() {
    super.initState();
    widget.push.permission.addListener(_again);
  }

  @override
  void dispose() {
    widget.push.permission.removeListener(_again);
    super.dispose();
  }

  void _again() {
    final check = widget.push.check();
    // A block: an arrow would hand setState the Future it assigns.
    setState(() {
      _check = check;
    });
  }

  Future<void> _tapped(PushCheck check) async {
    final token = check.fcmToken;
    if (token != null) await Clipboard.setData(ClipboardData(text: token));
    _again();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _check,
    builder: (context, snapshot) {
      final check = snapshot.data;
      if (check == null) return const SizedBox.shrink();
      return CupertinoListTile(
        title: Text(
          check.text,
          maxLines: 6,
          style: TextStyle(
            fontSize: 12,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        onTap: () => unawaited(_tapped(check)),
      );
    },
  );
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
