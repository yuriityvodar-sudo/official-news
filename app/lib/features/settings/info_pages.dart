import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// One section of an information page: an optional heading and its paragraphs.
class InfoSection {
  const InfoSection(this.paragraphs, {this.heading});

  final String? heading;
  final List<String> paragraphs;
}

/// An information page in Settings (#64): About, Privacy Policy, Terms of
/// Use, Contact & Support. Plain text in the iOS grouped style, readable
/// without any network call.
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
        previousPageTitle: 'Settings',
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

/// Who publishes the app, as the App Store lists it (Roman, #61 review).
const publisher = 'RS Elite Pro s.r.o., Slovakia';

/// Where readers write to us. Empty until Yurii picks the address (#64);
/// the support page then says to use the App Store page instead.
const supportEmail = '';

const _updated = 'Last updated 16 October 2026';

const aboutSections = [
  InfoSection([
    'Official News shows what governments and international bodies have '
        'decided, in a few calm sentences, with a link to the official page.',
  ]),
  InfoSection([
    'Every decision comes from a verified official website: a government, '
        'a ministry, a parliament or an international body. We never use '
        'media, aggregators or trending lists.',
    'An AI reads the official page and writes the headline and the summary, '
        'and translates them. It can make mistakes, so every article links to '
        'the original, which is the text that counts.',
  ], heading: 'Where the news comes from'),
  InfoSection([
    'Official News is an independent app. It is not affiliated with, '
        'endorsed by or speaking for any government or public body.',
    'Published by $publisher.',
  ], heading: 'Independent'),
];

const privacySections = [
  InfoSection([
    'Official News has no accounts: we do not ask for your name, e-mail '
        'address or phone number, and we do not sell or share personal data '
        'for advertising.',
  ]),
  InfoSection([
    'Your language, the articles you have read, the last feed you saw and '
        'the pictures you have viewed are kept on your phone, so the app opens '
        'quickly and works offline. Deleting the app deletes them.',
  ], heading: 'On your phone'),
  InfoSection([
    'The app loads the news from our server, hosted by Cloudflare. Like any '
        'website, it receives your IP address and basic technical details to '
        'answer the request; we do not use them to identify you.',
    'Article pictures are loaded directly from the official website that '
        'published them, so that website receives your IP address when a '
        'picture loads. Pictures are saved on your phone after the first view.',
    'When you open an official page, it opens in an in-app browser and that '
        "website's own privacy policy applies.",
  ], heading: 'When the app loads news'),
  InfoSection([
    'To understand how the app is used, for example how many people read '
        'which kind of decision, the app sends usage events to Google Analytics '
        'for Firebase: screens opened, articles opened and read, links tapped, '
        'the chosen language, and technical details such as the app version, '
        'device model, country and an app instance ID. It does not use the '
        'advertising identifier and does not track you across other apps.',
  ], heading: 'Analytics'),
  InfoSection([
    'If you turn on notifications, your phone gets a notification token from '
        'Apple and Google Firebase so we can send news alerts. You can turn '
        'notifications off at any time in your phone settings.',
  ], heading: 'Notifications'),
  InfoSection([
    'Summaries and translations are written by AI services (Cloudflare '
        'Workers AI and Groq) from the official texts only. No data about you '
        'is sent to them.',
  ], heading: 'AI'),
  InfoSection([
    'You can ask us what data we hold about you, and ask us to delete it, by '
        'writing to us (see Contact & Support). Under the GDPR you also have '
        'the right to complain to a data protection authority.',
    'Data controller: $publisher.',
  ], heading: 'Your rights'),
  InfoSection([
    'If this policy changes, the new version will be in the app with a new '
        'date.',
  ], heading: 'Changes'),
];

const termsSections = [
  InfoSection([
    'Official News summarizes official decisions for general information. '
        'It is not legal, financial or professional advice.',
    'Summaries and translations are made by AI and can be incomplete or '
        'wrong. Before you rely on a decision, read the official page linked '
        'in every article: that text is the one that counts.',
  ]),
  InfoSection([
    'The official texts belong to their publishers. The app shows a short '
        'summary, the publisher and a link to the original.',
  ], heading: 'Content'),
  InfoSection([
    'The app is not affiliated with any government. It is provided as it is, '
        'without guarantees that it is complete, correct or always available.',
  ], heading: 'No affiliation, no guarantee'),
  InfoSection([
    'Published by $publisher. If these terms change, the new version will be '
        'in the app with a new date.',
  ], heading: 'Publisher'),
];

const supportSections = [
  InfoSection([
    'Found a mistake in a summary, a broken source, or have an idea? We read '
        'every message.',
    'When you report a mistake, the name of the article and the language you '
        'read it in help us find it.',
  ]),
];

/// The "Last updated" line of the policy pages.
const policyUpdated = _updated;

/// The support page's action: an e-mail button, or where to write until there is an address.
Widget supportFooter(BuildContext context, {Future<void> Function(Uri)? open}) {
  if (supportEmail.isEmpty) {
    return Text(
      'You can reach us through the app\'s page in the App Store.',
      style: TextStyle(
        fontSize: 16,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
      ),
    );
  }
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: CupertinoButton.filled(
      color: AppColors.accent,
      onPressed: open == null
          ? null
          : () => open(Uri(scheme: 'mailto', path: supportEmail)),
      child: const Text('Write to us'),
    ),
  );
}
