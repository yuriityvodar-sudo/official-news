import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../core/chat_history.dart';
import '../../core/glass.dart';
import '../../core/news_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'chat_screen.dart';

/// The reader's conversations with the AI agent, as Messages lists its own
/// (Roman's pick B, 30 Oct): the decision's headline, the last question and
/// when, newest first; a row opens the conversation over the list, a swipe
/// deletes it, and "Delete all" deletes them all. They are kept on the phone
/// only ([ChatHistory]), as the note under the list says.
class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key, this.history});

  /// [chatHistory] unless a test brings its own.
  final ChatHistory? history;

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  ChatHistory get _history => widget.history ?? chatHistory;

  @override
  void initState() {
    super.initState();
    unawaited(_history.load());
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    final l10n = AppLocalizations.of(context);
    final muted = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      child: ListenableBuilder(
        listenable: history,
        builder: (context, _) {
          final conversations = history.conversations;
          return CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: Text(l10n.chatHistoryTitle),
              ),
              if (conversations.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      l10n.chatHistoryEmpty,
                      style: TextStyle(fontSize: 15, color: muted),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: CupertinoListSection.insetGrouped(
                    footer: Text(
                      l10n.chatHistoryNote,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                    children: [
                      for (final c in conversations)
                        _Row(
                          key: ValueKey(c.article.id),
                          conversation: c,
                          history: history,
                          onDelete: () =>
                              unawaited(history.delete(c.article.id)),
                        ),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    child: CupertinoButton(
                      onPressed: () => _deleteAll(context, history),
                      child: Text(
                        l10n.chatHistoryDeleteAll,
                        style: TextStyle(
                          fontSize: 16,
                          color: CupertinoColors.destructiveRed.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Asks first, as iOS does before deleting everything.
  Future<void> _deleteAll(BuildContext context, ChatHistory history) async {
    final l10n = AppLocalizations.of(context);
    final sure = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: Text(l10n.chatHistoryDeleteAllConfirm),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheet).pop(true),
            child: Text(l10n.chatHistoryDeleteAll),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheet).pop(false),
          child: Text(l10n.cancel),
        ),
      ),
    );
    if (sure != true) return;
    await history.clear();
    if (context.mounted) Navigator.of(context).maybePop();
  }
}

/// One conversation: the decision's country, its headline, the last
/// question and when; a tap opens it, a swipe to the left deletes it.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.conversation,
    required this.history,
    required this.onDelete,
  });

  final ChatConversation conversation;
  final ChatHistory history;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final muted = CupertinoColors.secondaryLabel.resolveFrom(context);
    final article = conversation.article;
    final place = article.isEvent && article.countries.isNotEmpty
        ? article.countries.first
        : article.country;
    return Dismissible(
      key: ValueKey('delete-${article.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        color: CupertinoColors.destructiveRed.resolveFrom(context),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          CupertinoIcons.trash,
          color: const Color(0xFFFFFFFF),
          semanticLabel: l10n.chatHistoryDelete,
        ),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => ChatScreen.show(context, article, history: history),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemFill.resolveFrom(
                    context,
                  ),
                  shape: BoxShape.circle,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    place,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: label,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      conversation.lastQuestion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                shortWhen(conversation.updatedAt, l10n),
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The feed's button for the Conversations screen, beside its settings
/// button and in its glass: a speech bubble with a 44-pt target.
class ConversationsButton extends StatelessWidget {
  const ConversationsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size(44, 44),
    onPressed: onPressed,
    child: GlassCircle(
      size: 40,
      // No shadow, as the Settings button beside it (Roman, 30 Oct).
      shadow: false,
      child: Icon(
        CupertinoIcons.chat_bubble_2,
        size: 21,
        color: CupertinoColors.label.resolveFrom(context),
        semanticLabel: AppLocalizations.of(context).chatHistoryTitle,
      ),
    ),
  );
}
