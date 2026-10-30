import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart' show StandardMessageCodec;

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

/// The native glass, or [plain] where there is none, and while anything is
/// over its screen ([NativeOrPlain]).
class _Glass extends StatelessWidget {
  const _Glass({required this.plain});

  final Widget plain;

  @override
  Widget build(BuildContext context) {
    if (!GlassCircle.native) return plain;
    return NativeOrPlain(
      // iOS's view is [glassShadowRoom] larger on every side, for the shadow.
      native: const Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -glassShadowRoom,
            top: -glassShadowRoom,
            right: -glassShadowRoom,
            bottom: -glassShadowRoom,
            child: UiKitView(
              viewType: 'official_news/glass',
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
              creationParams: {'room': glassShadowRoom},
              creationParamsCodec: StandardMessageCodec(),
            ),
          ),
        ],
      ),
      plain: plain,
    );
  }
}

/// Room around iOS's glass for its shadow, inside iOS's own view
/// (`GlassView`, `PillsView` in the Runner), which draws nothing past its
/// frame: Flutter draws a page or a sheet over a native view only within
/// its frame ([NativeOrPlain]). Liquid Glass's shadow is wide: with 10
/// points it was cut off in a visible band along the pills (build 50,
/// Roman, 30 Oct). Under the Settings button the shadow is still 3 of 255
/// darker than the page 30 points down, halving about every 8 points, so by
/// 56 it is gone (measured on the simulator, 30 Oct). Whatever holds the
/// glass must not clip it closer (the news look's masthead leaves this room
/// under its title's band). The view takes no touches in the room:
/// Flutter hit-tests a box only inside its own size, and the view reaches
/// past it.
const double glassShadowRoom = 56;

/// iOS's own [native] view (the glass, the topic pills), or Flutter's [plain]
/// look in its place until iOS has made its view ([ready]). Under the splash
/// ([NativeCover]) [native] comes in as the splash fades, as much as the app
/// under it, so nothing changes once it has gone. Both stay in the tree.
///
/// A page, a sheet or an article growing out of its card covers [native] as
/// it covers Flutter's own views: iOS's views draw nothing past their frame
/// (the glass's shadow has room inside it, [glassShadowRoom]), and Flutter
/// draws over a native view within its frame. Until 30 Oct [plain] stood in
/// whenever anything was over the screen, since the shadow showed through
/// under a sheet (Roman, 27 Oct); its icons, text and flat look then took the
/// glass's place each time a page opened (Roman, 30 Oct).
class NativeOrPlain extends StatelessWidget {
  const NativeOrPlain({
    super.key,
    required this.native,
    required this.plain,
    this.ready = true,
  });

  final Widget native;
  final Widget plain;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final cover = NativeCover.of(context);
    if (!ready || cover == null) return _layers(ready ? 1 : 0);
    return ValueListenableBuilder<double>(
      valueListenable: cover,
      builder: (context, value, _) => _layers(1 - value),
    );
  }

  /// [native] shown as much as [shown], [plain] only while it is not.
  Widget _layers(double shown) => Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.none,
    children: [
      IgnorePointer(
        ignoring: shown > 0,
        child: Opacity(opacity: shown > 0 ? 0 : 1, child: plain),
      ),
      IgnorePointer(
        ignoring: shown == 0,
        child: Opacity(opacity: shown, child: native),
      ),
    ],
  );
}

/// Something of Flutter's over the whole app (the splash, `SplashHost`):
/// [cover] is how much of the app it hides, 1 while it shows, down to 0 as
/// it fades. iOS's own views under it show only as much as the app does
/// ([NativeOrPlain]).
class NativeCover extends InheritedWidget {
  const NativeCover({super.key, required this.cover, required super.child});

  final ValueListenable<double> cover;

  static ValueListenable<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NativeCover>()?.cover;

  @override
  bool updateShouldNotify(NativeCover old) => old.cover != cover;
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
