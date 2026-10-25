import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../core/analytics.dart';
import '../../core/motion.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';

/// What "Discuss with AI" opens until the chat is built (#133, #141): what the
/// chat will do, and "Tell me when it's ready", one notification on the topic
/// `ai_chat_<feed language>` ([Push.notifyAiChat]). The taps on the button and
/// the switches (`ai_chat_notify`) show whether readers want the chat. A
/// working notification, not a placeholder (App Review 2.1).
class AiChatNote extends StatelessWidget {
  const AiChatNote({
    super.key,
    this.scroll,
    this._push,
    this.openSettingsApp = openAppSettings,
  });

  /// The sheet's own, so a drag on the text can close it.
  final ScrollController? scroll;
  final Push? _push;

  /// Where a switch goes while notifications are off: only the iOS Settings
  /// app turns them on again.
  final OpenAppSettings openSettingsApp;

  Push get _target => _push ?? push;

  /// Shows the note as an iOS sheet over the article.
  static Future<void> show(BuildContext context) => showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    scrollableBuilder: (_, scroll) => AiChatNote(scroll: scroll),
  );

  Future<void> _switched(bool on) async {
    Haptics.selection();
    unawaited(analytics.aiChatNotify(on: on));
    // Settings only when they were off before the tap: a reader who has just
    // said "Don't Allow" to iOS's question stays here.
    final wasOff = _target.permission.value == PushPermission.denied;
    // Kept even when notifications are off: turned on in Settings, it subscribes.
    await _target.notifyAiChat(on);
    if (on && wasOff && _target.permission.value == PushPermission.denied) {
      await openSettingsApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = NewsText.from(context);
    return CupertinoPageScaffold(
      child: SafeArea(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
          children: [
            const Icon(
              CupertinoIcons.sparkles,
              size: 44,
              color: AppColors.accent,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.aiChatTitle,
              style: text.articleHeadline,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.aiChatBody,
              style: text.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder(
              valueListenable: _target.permission,
              builder: (context, permission, _) {
                // No push in this build: nothing to switch.
                if (permission == PushPermission.unavailable) {
                  return const SizedBox.shrink();
                }
                return ValueListenableBuilder(
                  valueListenable: _target.aiChat,
                  builder: (context, wanted, _) =>
                      CupertinoListSection.insetGrouped(
                        margin: EdgeInsets.zero,
                        footer: Text(switch (permission) {
                          PushPermission.granted => l10n.aiChatNotifyOnce,
                          PushPermission.denied => l10n.aiChatNotifyOff,
                          _ => l10n.aiChatNotifyAsk,
                        }),
                        children: [
                          CupertinoListTile(
                            title: Text(l10n.aiChatNotify),
                            trailing: CupertinoSwitch(
                              value:
                                  wanted &&
                                  permission == PushPermission.granted,
                              activeTrackColor: AppColors.accent,
                              onChanged: (on) => unawaited(_switched(on)),
                            ),
                          ),
                        ],
                      ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
