import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import '../../core/filters.dart';
import '../../core/motion.dart';
import '../../core/topics.dart';
import '../../l10n/app_localizations.dart';

/// The pull-down under the date (#67, #170): what the feed shows, as Garnet
/// and Seal's row of pills will: For you (the default), the whole world, or
/// one topic across the world, busiest first. A grey chip that opens an iOS
/// pull-down menu with a checkmark on the current choice, no counts in it
/// (the chips prototype after Yurii's review, prototype/chips 3d88cf3, 16
/// Oct). It reads "For you" or "The whole world"; a topic shows short, as
/// its icon in [filterRed]. The menu, and VoiceOver, keep the full names;
/// the topics have their icons before their names. The Where pull-down
/// (#68) is gone: no group or country to choose (Yurii, 27 Oct, #170).
class FeedFilterBar extends StatelessWidget {
  const FeedFilterBar({
    super.key,
    required this.where,
    required this.topic,
    required this.topics,
    required this.onChoose,
  });

  /// For you or the whole world.
  final FeedWhere where;

  /// The chosen topic's id, or null.
  final String? topic;

  /// The topics, busiest first; null when the server has none, and the menu
  /// offers For you and the whole world only.
  final List<FeedTopic>? topics;

  /// For you or the whole world with no topic, or the whole world with one.
  final void Function(FeedWhere where, String? topic) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chosen = topic;
    final menu = topics ?? const <FeedTopic>[];
    String name(String id) => topicName(id, topics, l10n);
    final forYou = where.isForYou && chosen == null;
    final shown = forYou ? l10n.feedForYou : l10n.feedWholeWorld;
    _Item topicItem(String id) => _Item(
      name(id),
      id == chosen,
      () => onChoose(FeedWhere.all, id),
      icon: topicIcon(id),
      symbol: topicSymbol(id),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        children: [
          _Pulldown(
            key: const ValueKey('filter-topic'),
            label: shown,
            icon: chosen == null ? null : topicIcon(chosen),
            active: chosen != null,
            semanticLabel: chosen == null
                ? shown
                : l10n.filterTopicChip(name(chosen)),
            sections: [
              [
                _Item(
                  l10n.feedForYou,
                  forYou,
                  () => onChoose(FeedWhere.forYou, null),
                  icon: CupertinoIcons.sparkles,
                  symbol: 'sparkles',
                ),
                _Item(
                  l10n.feedWholeWorld,
                  !forYou && chosen == null,
                  () => onChoose(FeedWhere.all, null),
                  icon: CupertinoIcons.globe,
                  symbol: 'globe',
                ),
              ],
              [
                // The chosen topic stays in the menu, checked, when it has no
                // articles in the feed's 7 days now.
                if (chosen != null && !menu.any((t) => t.id == chosen))
                  topicItem(chosen),
                for (final t in menu) topicItem(t.id),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One item of a chip's menu.
class _Item {
  const _Item(this.title, this.selected, this.onTap, {this.icon, this.symbol});

  final String title;
  final bool selected;
  final VoidCallback onTap;

  /// The icon before its name: a topic's is the one its chip shows once
  /// chosen.
  final IconData? icon;

  /// The same glyph's SF Symbol, for the native menu on iOS.
  final String? symbol;

  Map<String, Object?> get native => {
    'title': title,
    'selected': selected,
    'symbol': symbol,
  };
}

/// The red that says a filter is on: a chosen chip's label, icon and chevron,
/// the menus' checkmark, and the buttons that undo a filter in the empty
/// feed. One red, as in the reviewed chips prototype: on the grey chip it is
/// at least 4.5:1 for 15-pt text (a test checks it): #C41230 in light mode,
/// #FF3B55 in dark, where the brand red #FA2D48 is 4.48:1.
const filterRed = CupertinoDynamicColor.withBrightness(
  color: Color(0xFFC41230),
  darkColor: Color(0xFFFF3B55),
);

/// A rounded grey chip that opens an iOS pull-down menu, like the language
/// menu had before Settings (#46): [label] (or [icon]) and a chevron, both
/// red while [active].
class _Pulldown extends StatefulWidget {
  const _Pulldown({
    super.key,
    required this.label,
    this.icon,
    required this.active,
    required this.semanticLabel,
    required this.sections,
  });

  /// What the chip shows; [icon] instead when there is one.
  final String label;
  final IconData? icon;
  final bool active;

  /// What VoiceOver says for the chip: the full name of the choice.
  final String semanticLabel;

  /// The menu's items in groups, a wide divider between groups; empty groups
  /// are left out.
  final List<List<_Item>> sections;

  @override
  State<_Pulldown> createState() => _PulldownState();
}

class _PulldownState extends State<_Pulldown> {
  AnimationStatus _status = AnimationStatus.dismissed;

  @override
  Widget build(BuildContext context) {
    final fg = widget.active
        ? filterRed.resolveFrom(context)
        : CupertinoColors.label.resolveFrom(context);
    final check = filterRed.resolveFrom(context);
    final iconColour = CupertinoColors.secondaryLabel.resolveFrom(context);
    final sections = widget.sections.where((s) => s.isNotEmpty).toList();
    // The menu stays clear of the status bar and the home indicator, as iOS's
    // own do: a long one (every group and country) scrolls between them. The
    // feed's SafeArea hides those insets from the chip, so they are read from
    // the screen itself.
    final insets = MediaQueryData.fromView(View.of(context)).padding;
    // On iOS the menu is iOS's own (#141): Liquid Glass from iOS 26, the
    // system's animation and haptics. The chip stays Flutter's.
    if (_NativeMenu.available) {
      return _NativeMenu(
        sections: sections,
        label: widget.semanticLabel,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(widthFactor: 1, child: _chip(context, fg)),
        ),
      );
    }
    return CupertinoMenuAnchor(
      overlayPadding: EdgeInsets.fromLTRB(
        8,
        insets.top + 8,
        8,
        insets.bottom + 8,
      ),
      onAnimationStatusChanged: (status) => _status = status,
      menuChildren: [
        for (final (i, section) in sections.indexed) ...[
          if (i > 0) const CupertinoMenuDivider(),
          for (final item in section)
            CupertinoMenuItem(
              onPressed: item.onTap,
              // A topic's icon beside its name: what its chip shows. Items
              // without one keep the same indent (the menu lines them up).
              leading: item.icon == null
                  ? null
                  : Icon(item.icon, size: 17, color: iconColour),
              trailing: item.selected
                  ? Icon(CupertinoIcons.checkmark_alt, color: check)
                  : null,
              // VoiceOver says which one is current.
              child: Semantics(
                selected: item.selected,
                child: Text(item.title),
              ),
            ),
        ],
      ],
      builder: (context, controller, _) => CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        // A tap while the menu is still closing opens it again.
        onPressed: () => _status.isForwardOrCompleted
            ? controller.close()
            : controller.open(),
        child: Semantics(
          label: widget.semanticLabel,
          excludeSemantics: true,
          child: _chip(context, fg),
        ),
      ),
    );
  }

  /// The grey chip: the choice (or its icon) and a chevron, in [fg]. A new
  /// choice rolls in as the old one rolls out, and the chip's width follows
  /// with a spring (#141); with Reduce Motion on, the words only fade.
  Widget _chip(BuildContext context, Color fg) {
    final reduced = Motion.reduced(context);
    return AnimatedSize(
      duration: reduced ? Duration.zero : Motion.slow,
      curve: Motion.spring,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // At the largest text sizes a long label ends in "…" instead
            // of overflowing the chip. An icon sits in a line of text, so
            // the chip is as high as one with a label, and grows with it.
            Flexible(
              child: AnimatedSwitcher(
                duration: Motion.base,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: reduced
                      ? child
                      : SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.4),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                ),
                child: Text.rich(
                  key: ValueKey((widget.label, widget.icon)),
                  widget.icon == null
                      ? TextSpan(text: widget.label)
                      : WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(widget.icon, size: 17, color: fg),
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down, size: 12, color: fg),
          ],
        ),
      ),
    );
  }
}

/// Tests set it to check the native menus' side in Flutter.
@visibleForTesting
bool? debugNativeMenus;

/// iOS's own pull-down menu over a chip (#141): a clear native button on
/// top of [child] opens a UIMenu with [sections] (`MenuView` in the Runner)
/// and tells which item was chosen. VoiceOver hears the native button, named
/// [label]. A change of the items makes a new native button.
class _NativeMenu extends StatefulWidget {
  const _NativeMenu({
    required this.sections,
    required this.label,
    required this.child,
  });

  final List<List<_Item>> sections;
  final String label;
  final Widget child;

  /// The iOS app; tests (macOS) and Android keep the Flutter menu, unless
  /// a test sets [debugNativeMenus].
  static bool get available => debugNativeMenus ?? (!kIsWeb && Platform.isIOS);

  @override
  State<_NativeMenu> createState() => _NativeMenuState();
}

class _NativeMenuState extends State<_NativeMenu> {
  MethodChannel? _channel;

  void _created(int id) {
    _channel = MethodChannel('official_news/menu_$id')
      ..setMethodCallHandler((call) async {
        if (call.method != 'select') return;
        final [section as int, row as int] = call.arguments as List<Object?>;
        widget.sections[section][row].onTap();
      });
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final params = {
      'label': widget.label,
      'sections': [
        for (final section in widget.sections)
          [for (final item in section) item.native],
      ],
    };
    return Stack(
      children: [
        ExcludeSemantics(child: widget.child),
        Positioned.fill(
          child: UiKitView(
            key: ValueKey(params.toString()),
            viewType: 'official_news/menu',
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _created,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            // The touch goes to the native button at once: iOS opens the
            // menu as the finger goes down, which a delayed touch never does.
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
            },
          ),
        ),
      ],
    );
  }
}
