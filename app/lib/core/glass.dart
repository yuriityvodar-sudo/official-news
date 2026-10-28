import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;

import 'card_zoom.dart';

/// A round surface of [size] behind a small control, with [child] centred
/// on it: Apple's Liquid Glass on iOS (a native view, `GlassView` in the
/// Runner; real glass from iOS 26, the plain circle before), and the plain
/// circle in the app's own colours everywhere else (Yurii, 20 Oct, #66).
///
/// The native view takes no touches: the control's own gesture, around
/// this widget, gets the tap.
class GlassCircle extends StatelessWidget {
  const GlassCircle({super.key, required this.size, required this.child});

  final double size;
  final Widget child;

  /// Where the native glass is used: the iOS app, not tests (macOS) or
  /// Android, unless a test sets [debugNative].
  static bool get native => debugNative ?? (!kIsWeb && Platform.isIOS);

  @visibleForTesting
  static bool? debugNative;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _Glass(
          plain: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Center(child: child),
      ],
    ),
  );
}

/// A capsule of Liquid Glass behind [child] (#141): the same native view as
/// [GlassCircle], as wide as [child] with [padding] (or as wide as it is
/// given, inside a full-width box), [height] high.
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({
    super.key,
    required this.child,
    this.height = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final Widget child;
  final double height;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      children: [
        Positioned.fill(
          child: _Glass(
            plain: DecoratedBox(
              decoration: ShapeDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ),
        Padding(
          padding: padding,
          child: Center(widthFactor: 1, child: child),
        ),
      ],
    ),
  );
}

/// The native glass, or [plain] where there is none. While an article grows
/// out of its card, goes back into it or is shrunk by hand (#141), the glass
/// of the screen under it shows as [plain]: iOS would draw the native view
/// over the moving article. So does the glass of a screen another route
/// covers (#160): under a sheet its glow showed through as a faint white box.
/// Hidden, not removed, so it is there again at once.
class _Glass extends StatelessWidget {
  const _Glass({required this.plain});

  final Widget plain;

  @override
  Widget build(BuildContext context) {
    if (!GlassCircle.native) return plain;
    const glass = UiKitView(
      viewType: 'official_news/glass',
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    );
    final route = ModalRoute.of(context);
    final covered = !(route?.isCurrent ?? true);
    if (route is CardZoomRoute) return _show(covered, glass);
    return ValueListenableBuilder(
      valueListenable: CardZoomRoute.moving,
      child: glass,
      builder: (context, moving, glass) => _show(covered || moving, glass!),
    );
  }

  /// [plain] when [hidden], else [glass].
  Widget _show(bool hidden, Widget glass) => Stack(
    fit: StackFit.expand,
    children: [
      Opacity(opacity: hidden ? 1 : 0, child: plain),
      Opacity(opacity: hidden ? 0 : 1, child: glass),
    ],
  );
}

/// The top of a screen whose content scrolls under floating buttons (#141):
/// the page's [color] fading out downwards, as iOS 26 softens a scroll edge,
/// so the buttons stay clear over text. Takes no touches.
class ScrollEdgeFade extends StatelessWidget {
  const ScrollEdgeFade({super.key, required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.5, 1],
          colors: [color.withValues(alpha: 0.94), color.withValues(alpha: 0)],
        ),
      ),
    ),
  );
}
