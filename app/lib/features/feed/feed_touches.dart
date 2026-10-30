import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/analytics.dart';
import '../../core/article.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../detail/detail_screen.dart';

/// Small things that make the feed answer the reader (#141): what a long
/// press on a card offers, the time of a decision that has just arrived, and
/// the screens shown when there is nothing to show.

/// A long press on a card: its headline and short summary, with what can be
/// done without opening it: share it, open the official page, copy the link.
/// iOS's own action sheet, with a firm tap back as it opens.
Future<void> showArticleActions(BuildContext context, Article article) {
  Haptics.medium();
  final l10n = AppLocalizations.of(context);
  final page = officialPage(article.originalUrl);
  final summary = article.shortSummary?.trim();
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (sheet) {
      void then(VoidCallback action) {
        Navigator.of(sheet).pop();
        action();
      }

      return CupertinoActionSheet(
        title: Text(article.headline, maxLines: 3),
        message: summary == null || summary.isEmpty
            ? null
            : Text(summary, maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => then(() {
              unawaited(analytics.shared(article));
              unawaited(shareArticle(article, shareText(article, l10n), null));
            }),
            child: Text(l10n.share),
          ),
          if (page != null) ...[
            CupertinoActionSheetAction(
              onPressed: () => then(() {
                unawaited(analytics.officialLinkOpened(article));
                unawaited(openOfficialPage(page));
              }),
              child: Text(
                article.isEvent
                    ? l10n.readOnWikipedia
                    : l10n.readOfficialDecision,
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () => then(() {
                unawaited(Clipboard.setData(ClipboardData(text: '$page')));
                Haptics.success();
              }),
              child: Text(l10n.copyLink),
            ),
          ],
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheet).pop(),
          child: Text(l10n.cancel),
        ),
      );
    },
  );
}

/// Whether [article] came into the feed less than an hour ago.
bool isFresh(Article article, {DateTime? now}) {
  final arrived = article.addedAt ?? article.publishedAt;
  final age = (now ?? DateTime.now()).difference(arrived);
  return !age.isNegative && age < const Duration(hours: 1);
}

/// The time of a decision from the last hour (#141), in the accent colour
/// ([color]: Garnet and Seal give their own), fading out and in three times
/// as the card appears and then still, so a fresh decision catches the eye
/// without the feed blinking (a dot would read as the unread mark). Each
/// decision pulses once while the app runs:
/// a row built again (scrolled away and back, back from the article) is
/// still. With Reduce Motion on, it is still from the start.
class FreshTime extends StatefulWidget {
  const FreshTime(
    this.time, {
    super.key,
    required this.articleId,
    required this.style,
    this.color = AppColors.accent,
  });

  final String time;
  final String articleId;
  final TextStyle style;
  final Color color;

  /// The articles whose time has pulsed in this run of the app.
  static final _pulsed = <String>{};

  @visibleForTesting
  static void forgetPulses() => _pulsed.clear();

  @override
  State<FreshTime> createState() => _FreshTimeState();
}

class _FreshTimeState extends State<FreshTime>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  int _beats = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.35,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_beats > 0 || Motion.reduced(context)) return;
    if (FreshTime._pulsed.add(widget.articleId)) unawaited(_beat());
  }

  Future<void> _beat() async {
    while (mounted && _beats < 3) {
      _beats++;
      await _pulse.reverse();
      if (!mounted) return;
      await _pulse.forward();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _pulse,
    child: Text(widget.time, style: widget.style.copyWith(color: widget.color)),
  );
}

/// What the feed says when it has nothing to show (#141): a symbol, the
/// words, and, when there is one, the way out as a button.
class FeedMessage extends StatelessWidget {
  const FeedMessage({
    super.key,
    required this.icon,
    required this.children,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final List<Widget> children;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final grey = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Icon(icon, size: 40, color: grey),
        const SizedBox(height: 14),
        ...children,
        if (action != null) ...[
          const SizedBox(height: 16),
          CupertinoButton.tinted(
            sizeStyle: CupertinoButtonSize.medium,
            onPressed: () {
              Haptics.light();
              onAction?.call();
            },
            child: Text(action!),
          ),
        ],
      ],
    );
  }
}
