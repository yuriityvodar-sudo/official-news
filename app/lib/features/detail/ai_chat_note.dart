import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/analytics.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';

/// What "Discuss with AI" opens until the chat is built (#133, #141): what the
/// chat will do, and "Tell me when it's ready", one tap that turns into a
/// checkmark and stays so on the phone (#160). It has nothing to do with
/// notifications: the taps on "Discuss with AI" (`discuss_ai_tap`) and on this
/// button (`ai_chat_interest`, once per phone) show how many readers want the
/// chat. When it ships, the app says so itself.
class AiChatNote extends StatefulWidget {
  const AiChatNote({super.key, this.scroll});

  /// The sheet's own, so a drag on the text can close it.
  final ScrollController? scroll;

  /// On the phone once the reader tapped "Tell me when it's ready".
  static const interestedKey = 'aiChat.interested';

  /// Shows the note as an iOS sheet over the article.
  static Future<void> show(BuildContext context) => showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    scrollableBuilder: (_, scroll) => AiChatNote(scroll: scroll),
  );

  @override
  State<AiChatNote> createState() => _AiChatNoteState();
}

class _AiChatNoteState extends State<AiChatNote> {
  /// Whether the reader tapped the button before; null until the phone says.
  bool? _interested;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _interested = prefs.getBool(AiChatNote.interestedKey) ?? false;
    });
  }

  /// Counted once per phone: the checkmark stays, there is nothing to undo.
  Future<void> _tapped() async {
    Haptics.success();
    setState(() {
      _interested = true;
    });
    unawaited(analytics.aiChatInterest());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AiChatNote.interestedKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = NewsText.from(context);
    final grouped = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return CupertinoPageScaffold(
      // The grouped background of Settings, light and dark (#160).
      backgroundColor: grouped,
      // The sheet has no Scaffold above it: without a Material its text falls
      // back to Flutter's warning style, yellow double underlines in bold (#160).
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: ListView(
            controller: widget.scroll,
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
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: Motion.base,
                child: switch (_interested) {
                  null => const SizedBox(height: _height),
                  false => SizedBox(
                    key: const ValueKey('ask'),
                    width: double.infinity,
                    height: _height,
                    child: CupertinoButton.filled(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(_height / 2),
                      onPressed: () => unawaited(_tapped()),
                      child: Text(l10n.aiChatNotify),
                    ),
                  ),
                  true => _Interested(l10n.aiChatInterested),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The button's height, and the checkmark's, so nothing jumps.
  static const _height = 50.0;
}

/// The button after the tap: a checkmark and "We'll let you know when it's
/// ready", where the button was.
class _Interested extends StatelessWidget {
  const _Interested(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('interested'),
    height: _AiChatNoteState._height,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: ShapeDecoration(
      color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
      shape: const StadiumBorder(),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          CupertinoIcons.checkmark_circle_fill,
          size: 20,
          color: AppColors.accent,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              color: CupertinoColors.label.resolveFrom(context),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
