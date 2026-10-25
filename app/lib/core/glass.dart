import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;

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

  /// Where the native glass is used: the iOS app, not tests (macOS) or Android.
  static bool get native => !kIsWeb && Platform.isIOS;

  /// The native glass while its screen is on top, the plain look while
  /// another route covers it (#160): iOS draws the glass itself, above
  /// Flutter, so under a sheet its glow showed through as a faint white box.
  /// Back on top, the glass returns.
  static bool nativeIn(BuildContext context) =>
      native && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (nativeIn(context))
          const UiKitView(
            viewType: 'official_news/glass',
            hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
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
          child: GlassCircle.nativeIn(context)
              ? const UiKitView(
                  viewType: 'official_news/glass',
                  hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                )
              : DecoratedBox(
                  decoration: ShapeDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    shape: const StadiumBorder(),
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
