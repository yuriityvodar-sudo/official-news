import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';

/// Before the first question to the AI agent, once (#146; App Store guideline
/// 5.1.2): what is sent and to whom, and what Apple may hear about a refund,
/// with Allow and Not Now. Kept on the phone (`chat.consent`).
abstract final class ChatConsent {
  static const _key = 'chat.consent';

  static Future<bool> given() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  static Future<void> withdraw() async =>
      (await SharedPreferences.getInstance()).remove(_key);

  /// True when given before, or allowed now.
  static Future<bool> ask(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key) ?? false) return true;
    if (!context.mounted) return false;
    final l10n = AppLocalizations.of(context);
    final allowed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.chatConsentTitle),
        content: Text(l10n.chatConsentBody),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.pushOfferNotNow),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.chatConsentAllow),
          ),
        ],
      ),
    );
    if (allowed != true) return false;
    await prefs.setBool(_key, true);
    return true;
  }
}
