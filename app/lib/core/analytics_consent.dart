import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Whether the reader allows the app's usage statistics (Google Analytics
/// for Firebase): asked once, at the first launch after the splash, and
/// changed in Settings. Nothing is collected or kept on the phone for it
/// until allowed (L1 of the release audit, 4 Nov: in the EU the ePrivacy
/// rule, in Czechia § 89(3) of Act 127/2005, wants it allowed first).
enum AnalyticsConsent { unknown, granted, denied }

/// The reader's answer, as kept on the phone.
final analyticsConsent = ValueNotifier<AnalyticsConsent>(
  AnalyticsConsent.unknown,
);

/// Whether the build has analytics at all, once Firebase has started
/// (`startAnalytics`): without it there is nothing to ask about.
final analyticsAvailable = ValueNotifier<bool>(false);

const _key = 'analytics.consent';

/// Reads the answer kept on the phone.
Future<void> loadAnalyticsConsent() async {
  final kept = (await SharedPreferences.getInstance()).getString(_key);
  analyticsConsent.value = AnalyticsConsent.values.firstWhere(
    (c) => c.name == kept,
    orElse: () => AnalyticsConsent.unknown,
  );
}

/// Keeps [consent] and acts on it at once.
Future<void> setAnalyticsConsent(AnalyticsConsent consent) async {
  analyticsConsent.value = consent;
  await (await SharedPreferences.getInstance()).setString(_key, consent.name);
}

/// Asks once whether the app may send usage statistics, as iOS asks for
/// tracking: a plain alert whose two answers weigh the same, so not allowing
/// is as easy as allowing. Only in a build with analytics, and only while
/// the reader has not answered. A build whose Firebase is still starting is
/// asked once it has.
Future<void> askAnalyticsConsent(BuildContext Function() context) async {
  if (analyticsConsent.value != AnalyticsConsent.unknown) return;
  if (!analyticsAvailable.value) {
    void later() {
      if (!analyticsAvailable.value) return;
      analyticsAvailable.removeListener(later);
      unawaited(askAnalyticsConsent(context));
    }

    analyticsAvailable.addListener(later);
    return;
  }
  final shown = context();
  final l10n = AppLocalizations.of(shown);
  final allowed = await showCupertinoDialog<bool>(
    context: shown,
    builder: (context) => CupertinoAlertDialog(
      title: Text(l10n.analyticsConsentTitle),
      content: Text(l10n.analyticsConsentBody),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.analyticsDontAllow),
        ),
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.analyticsAllow),
        ),
      ],
    ),
  );
  if (allowed == null) return;
  await setAnalyticsConsent(
    allowed ? AnalyticsConsent.granted : AnalyticsConsent.denied,
  );
}
