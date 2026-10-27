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

/// The native glass, or [plain] where there is none, and while anything is
/// over its screen ([NativeOrPlain]).
class _Glass extends StatelessWidget {
  const _Glass({required this.plain});

  final Widget plain;

  @override
  Widget build(BuildContext context) {
    if (!GlassCircle.native) return plain;
    return NativeOrPlain(
      native: const UiKitView(
        viewType: 'official_news/glass',
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      plain: plain,
    );
  }
}

/// iOS's own [native] view (the glass, the topic pills), or Flutter's [plain]
/// look in its place. iOS draws its views over Flutter, and the glass's
/// shadow reaches past their frame, where Flutter cannot draw over it: under
/// a sheet or the splash it showed through as a faint grey band (Roman, 27
/// Oct). So [plain] stands in while anything is over the screen: another
/// route (a sheet, a page coming in, until it has gone again), or an article
/// growing out of its card, going back into it or shrunk by hand (#141),
/// except on the article itself; and until iOS has made its view ([ready]).
/// Under the splash ([NativeCover]) [native] comes in as the splash fades,
/// as much as the app under it, so nothing changes once it has gone. Both
/// stay in the tree, so each is there again at once.
class NativeOrPlain extends StatefulWidget {
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
  State<NativeOrPlain> createState() => _NativeOrPlainState();
}

class _NativeOrPlainState extends State<NativeOrPlain> {
  /// How far a route over this screen has come in: at rest at the start
  /// once none is, or the last one has gone.
  Animation<double>? _over;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final over = ModalRoute.of(context)?.secondaryAnimation;
    if (over == _over) return;
    _over?.removeStatusListener(_changed);
    _over = over?..addStatusListener(_changed);
  }

  @override
  void dispose() {
    _over?.removeStatusListener(_changed);
    super.dispose();
  }

  void _changed(AnimationStatus _) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final clear =
        widget.ready &&
        (route?.isCurrent ?? true) &&
        (_over?.isDismissed ?? true);
    // The article's own views show while it grows out of its card.
    final zooms = route is! CardZoomRoute;
    final cover = NativeCover.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([?cover, if (zooms) CardZoomRoute.moving]),
      builder: (context, _) {
        final shown = clear && !(zooms && CardZoomRoute.moving.value)
            ? 1 - (cover?.value ?? 0.0)
            : 0.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: shown > 0,
              child: Opacity(opacity: shown > 0 ? 0 : 1, child: widget.plain),
            ),
            IgnorePointer(
              ignoring: shown == 0,
              child: Opacity(opacity: shown, child: widget.native),
            ),
          ],
        );
      },
    );
  }
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
