import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/news_widgets.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'support_screen.dart';

/// One section of an information page: an optional heading and its paragraphs.
class InfoSection {
  const InfoSection(this.paragraphs, {this.heading});

  final String? heading;
  final List<String> paragraphs;
}

/// An information page in Settings (#64): About, Privacy Policy, Terms of
/// Use, Contact & Support. Plain text in the iOS grouped style, readable
/// without any network call, in the app's language (#52: the text is in
/// lib/l10n/app_*.arb).
class InfoPage extends StatelessWidget {
  const InfoPage({
    super.key,
    required this.title,
    required this.sections,
    this.updated,
    this.footer,
  });

  final String title;
  final List<InfoSection> sections;

  /// "Last updated 16 October 2026", for the policy pages.
  final String? updated;

  /// Something under the text, such as the support button.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      backgroundColor: grouped,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        previousPageTitle: AppLocalizations.of(context).settings,
        backgroundColor: grouped,
        border: null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              if (updated != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    updated!,
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                ),
              for (final section in sections) ...[
                if (section.heading != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Text(
                      section.heading!,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: label,
                      ),
                    ),
                  ),
                for (final paragraph in section.paragraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      paragraph,
                      style: TextStyle(fontSize: 16, height: 1.4, color: label),
                    ),
                  ),
              ],
              ?footer,
            ],
          ),
        ),
      ),
    );
  }
}

/// Who publishes the app, as the App Store lists it (Roman, #61 review). The
/// name is never translated; its country is ([AppLocalizations.publisher]).
const publisherName = 'RS Elite Pro s.r.o.';

/// The publisher's seat, company ID and commercial register file (Roman,
/// 29 Oct, #204; ARES): a Czech company, so Czech law wants them on its
/// pages (§ 435 of the Civil Code), and GDPR in the privacy policy.
const publisherAddress = 'Na Okrouhlíku 2563/31, 182 00 Praha 8';
const publisherId = '29536316';
const publisherFile = 'C 448095';

/// "RS Elite Pro s.r.o., Czech Republic" in the app's language.
String publisher(AppLocalizations l10n) => l10n.publisher(publisherName);

/// The publisher with its seat, company ID and register file, in the app's
/// language: the privacy policy's data controller and the terms' publisher.
String publisherDetails(AppLocalizations l10n) => l10n.publisherDetails(
  publisherName,
  publisherAddress,
  publisherId,
  publisherFile,
);

/// Where readers can also e-mail us (#137): Cloudflare Email Routing forwards
/// it to Yurii (docs/setup.md). Shown under "Write to us", which opens the
/// in-app messages (#220).
const supportEmail = 'support@outernews.app';

/// When the privacy policy and the terms last changed.
final policyUpdated = DateTime(2026, 10, 29);

/// The "Last updated 16 October 2026" line of the policy pages.
String policyUpdatedLine(AppLocalizations l10n) =>
    l10n.lastUpdated(fullDate(policyUpdated, l10n));

List<InfoSection> aboutSections(AppLocalizations l10n) => [
  InfoSection([l10n.aboutIntro]),
  InfoSection([
    l10n.aboutSources1,
    l10n.aboutSources2,
  ], heading: l10n.aboutSourcesHeading),
  InfoSection([
    l10n.aboutIndependent,
    l10n.aboutPublishedBy(publisher(l10n)),
  ], heading: l10n.aboutIndependentHeading),
];

List<InfoSection> privacySections(AppLocalizations l10n) => [
  InfoSection([l10n.privacyIntro]),
  InfoSection([l10n.privacyPhone], heading: l10n.privacyPhoneHeading),
  InfoSection([
    l10n.privacyLoadingServer,
    l10n.privacyLoadingCountry,
    l10n.privacyLoadingPictures,
    l10n.privacyLoadingPages,
  ], heading: l10n.privacyLoadingHeading),
  InfoSection([l10n.privacyAnalytics], heading: l10n.privacyAnalyticsHeading),
  InfoSection([
    l10n.privacyNotifications,
  ], heading: l10n.privacyNotificationsHeading),
  InfoSection([l10n.privacyAi], heading: l10n.privacyAiHeading),
  InfoSection([l10n.privacyChat], heading: l10n.privacyChatHeading),
  InfoSection([l10n.privacySupport], heading: l10n.privacySupportHeading),
  InfoSection([
    l10n.privacyRights(l10n.contactSupport),
    l10n.privacyController(publisherDetails(l10n)),
  ], heading: l10n.privacyRightsHeading),
  InfoSection([l10n.privacyChanges], heading: l10n.privacyChangesHeading),
];

List<InfoSection> termsSections(AppLocalizations l10n) => [
  InfoSection([l10n.termsIntro1, l10n.termsIntro2]),
  InfoSection([l10n.termsContent], heading: l10n.termsContentHeading),
  InfoSection([l10n.termsNoGuarantee], heading: l10n.termsNoGuaranteeHeading),
  InfoSection([l10n.termsSubscription], heading: l10n.termsSubscriptionHeading),
  InfoSection([
    l10n.termsPublisher(publisherDetails(l10n)),
  ], heading: l10n.termsPublisherHeading),
];

List<InfoSection> supportSections(AppLocalizations l10n) => [
  InfoSection([l10n.supportMessages, l10n.supportMistakes]),
];

/// The support page's action (#220): "Write to us" opens the messages
/// screen, with the e-mail address under it, to copy, for a reader who
/// prefers e-mail. [api] is for tests.
Widget supportFooter(BuildContext context, {ApiClient? api}) {
  final l10n = AppLocalizations.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoButton.filled(
          color: AppColors.accent,
          onPressed: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              settings: const RouteSettings(name: SupportScreen.routeName),
              builder: (_) => SupportScreen(api: api),
            ),
          ),
          child: Text(l10n.supportWrite),
        ),
        const SizedBox(height: 12),
        SelectableText(
          l10n.supportOrEmail(supportEmail),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
    ),
  );
}
