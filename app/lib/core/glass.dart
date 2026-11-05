import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart' show MethodChannel, StandardMessageCodec;

/// A round surface of [size] behind a small control, with [child] centred
/// on it: Apple's Liquid Glass on iOS (a native view, `GlassView` in the
/// Runner; real glass from iOS 26, the plain circle before), and the plain
/// circle in the app's own colours everywhere else (Yurii, 20 Oct, #66).
///
/// The native view takes no touches: the control's own gesture, around
/// this widget, gets the tap.
class GlassCircle extends StatelessWidget {
  const GlassCircle({
    super.key,
    required this.size,
    required this.child,
    this.shadow = true,
  });

  final double size;
  final Widget child;

  /// Whether iOS's glass casts its shadow: not on the feed's round buttons
  /// (Roman, 30 Oct), where iOS's view is the circle itself, clipped round.
  final bool shadow;

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
          shadow: shadow,
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
/// given, inside a full-width box), [height] high, or as tall as [child]
/// with [padding] without one (the AI chat's field, which grows as it is
/// written in; past 52 points high its corners stop growing, `GlassView`).
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({
    super.key,
    required this.child,
    this.height = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.shadow = true,
  });

  final Widget child;
  final double? height;
  final EdgeInsets padding;

  /// Whether iOS's glass casts its shadow: not among the feed's rows (a
  /// tick, #230), where its room ([glassShadowRoom]) would reach over the
  /// cards beside it.
  final bool shadow;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      children: [
        Positioned.fill(
          child: _Glass(
            shadow: shadow,
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
          child: Center(
            widthFactor: 1,
            heightFactor: height == null ? 1 : null,
            child: child,
          ),
        ),
      ],
    ),
  );
}

/// The native glass, or [plain] where there is none, and while anything is
/// over its screen ([NativeOrPlain]).
class _Glass extends StatelessWidget {
  const _Glass({required this.plain, this.shadow = true});

  final Widget plain;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    if (!GlassCircle.native) return plain;
    // iOS's view is [glassShadowRoom] larger on every side, for the shadow;
    // without one it is the glass itself.
    final room = shadow ? glassShadowRoom : 0.0;
    return NativeOrPlain(
      native: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -room,
            top: -room,
            right: -room,
            bottom: -room,
            child: UiKitView(
              // A new view if the shadow changes: iOS takes it when made.
              key: ValueKey(shadow),
              viewType: 'official_news/glass',
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
              creationParams: {'room': room, 'shadow': shadow},
              creationParamsCodec: const StandardMessageCodec(),
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
/// glass must not clip it closer, or the shadow shows cut off as a band;
/// the feed's round buttons cast none ([GlassCircle.shadow]). The view takes
/// no touches in the room:
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

/// The top of the screen once rows pass under it (#141, Roman, 4 Nov): iOS
/// 26's soft scroll edge, a blur of what is under it that fades out over
/// its last [fade] points, so the rows go softly under the status bar and
/// the title's bar instead of being cut where the screen's safe area
/// starts. iOS's own blur on iOS (a native view, `EdgeView` in the Runner),
/// at [strength] of the material: in full it was too dark (Roman, 4 Nov);
/// the page's [color] fading out the same way elsewhere. Takes no touches.
///
/// It comes in by [shown], which iOS's blur takes as how strong to be, on
/// the channel `official_news/edge_<id>`. Never put it under an [Opacity]:
/// iOS draws a blur under an alpha below 1 wrong or not at all, so behind
/// one it came in with a jump at the end (Roman, 4 Nov: «резкое движение»),
/// and at 0 Flutter takes iOS's view out of the screen altogether.
class GlassEdge extends StatefulWidget {
  const GlassEdge({
    super.key,
    required this.color,
    this.fade = 16,
    this.strength = 0.45,
    this.shown = 1,
  });

  /// The page's colour, where iOS's blur is not used.
  final Color color;

  /// How tall the foot is that fades out.
  final double fade;

  /// How much of iOS's material: 0 is none, 1 all of it.
  final double strength;

  /// How much of the edge there is, 0 to 1: of [strength], for iOS's blur.
  final double shown;

  @override
  State<GlassEdge> createState() => _GlassEdgeState();
}

class _GlassEdgeState extends State<GlassEdge> {
  MethodChannel? _channel;

  /// What iOS's blur was last told.
  double? _sent;

  double get _shown => clampDouble(widget.shown, 0, 1);

  @override
  void didUpdateWidget(GlassEdge old) {
    super.didUpdateWidget(old);
    _send();
  }

  /// A change of a hundredth or more, or the ends, which must be exact.
  void _send() {
    final channel = _channel;
    final shown = _shown;
    final sent = _sent;
    if (channel == null || sent == shown) return;
    if (sent != null && (shown - sent).abs() < 0.01 && shown > 0 && shown < 1) {
      return;
    }
    _sent = shown;
    channel.invokeMethod<void>('shown', shown).ignore();
  }

  void _created(int id) {
    _channel = MethodChannel('official_news/edge_$id');
    // Whatever changed while iOS was making the view.
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final fade = widget.fade;
    final strength = widget.strength;
    final color = widget.color;
    final plain = LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final solid = height > fade ? (height - fade) / height : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, solid, 1],
              colors: [
                color.withValues(alpha: 0.8 * strength + 0.2),
                color.withValues(alpha: 0.8 * strength + 0.2),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        );
      },
    );
    // Flutter's own edge may fade by its alpha.
    final faded = Opacity(opacity: _shown, child: plain);
    return IgnorePointer(
      child: !GlassCircle.native
          ? faded
          : NativeOrPlain(
              native: UiKitView(
                viewType: 'official_news/edge',
                hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                creationParams: {
                  'fade': fade,
                  'strength': strength,
                  'shown': _shown,
                },
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: _created,
              ),
              plain: faded,
            ),
    );
  }
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
