import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How the app moves and taps back (#141): one place for durations, curves
/// and haptics, so every feed look and screen behaves the same.
///
/// With Reduce Motion on (iOS Settings → Accessibility → Motion), nothing
/// scales, slides or flies: [reduced] is true and the widgets here only fade.
abstract final class Motion {
  /// A press, a fade of a small thing.
  static const fast = Duration(milliseconds: 120);

  /// A picture or a card appearing.
  static const base = Duration(milliseconds: 250);

  /// Something crossing the screen: a sheet, a pill sliding in.
  static const slow = Duration(milliseconds: 420);

  /// Released: a quick spring with a slight overshoot, as iOS buttons do.
  static const spring = Cubic(0.34, 1.4, 0.64, 1);

  /// Arriving or leaving without bounce.
  static const ease = Curves.easeOutCubic;

  /// How small a card gets while it is held.
  static const pressedScale = 0.97;

  /// True when the reader asked the phone for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// The phone's taptic engine, on iOS only: Android phones vary too much for
/// these to feel the same, and tests run on the desktop. Tests switch it on
/// with [enabled] to check what a gesture plays.
abstract final class Haptics {
  static bool enabled = !kIsWeb && Platform.isIOS;

  /// A card or a button pressed.
  static void light() => _play(HapticFeedback.lightImpact);

  /// Pull to refresh, past the point where letting go refreshes.
  static void medium() => _play(HapticFeedback.mediumImpact);

  /// A choice in a menu or a picker.
  static void selection() => _play(HapticFeedback.selectionClick);

  /// Something done: an article shared.
  static void success() => _play(HapticFeedback.successNotification);

  /// Something failed: no connection.
  static void warning() => _play(HapticFeedback.warningNotification);

  static void _play(Future<void> Function() feedback) {
    if (enabled) feedback();
  }
}

/// [child] shrinks a little while it is held and springs back when let go
/// (#141), as cards do in Apple's apps. It takes no tap itself: the row's
/// own gesture inside it still gets the tap, and a scroll that starts on it
/// cancels the press, like the row's highlight. A long press, held past
/// the tap, calls [onLongPress].
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.onLongPress});

  final Widget child;
  final VoidCallback? onLongPress;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    // Both this detector and the row's report the press after the same
    // short wait; the row wins the tap, and this one is cancelled then.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: reduced ? null : (_) => _press(true),
      onTapUp: reduced ? null : (_) => _press(false),
      onTapCancel: reduced ? null : () => _press(false),
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _press(false);
              widget.onLongPress!();
            },
      child: reduced
          ? widget.child
          : AnimatedScale(
              scale: _pressed ? Motion.pressedScale : 1,
              duration: _pressed ? Motion.fast : Motion.slow,
              curve: _pressed ? Motion.ease : Motion.spring,
              child: widget.child,
            ),
    );
  }
}

/// [child] fades in and rises a few points, [delay] after it is first built,
/// when [animate] is true: the first rows of a feed that has just loaded
/// arrive one after another (#141). With Reduce Motion on, it only fades.
/// Always in the tree, animated or not, so a row keeps its state when the
/// feed stops animating.
class Arrive extends StatefulWidget {
  const Arrive({
    super.key,
    required this.child,
    this.animate = true,
    this.delay = Duration.zero,
  });

  final Widget child;
  final bool animate;
  final Duration delay;

  /// Off in tests (flutter_test_config.dart): they check where rows end up,
  /// not how they get there; motion_test.dart switches it back on.
  static bool enabled = true;

  @override
  State<Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<Arrive> {
  late bool _shown = !widget.animate || !Arrive.enabled;
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (!_shown) {
      _wait = Timer(widget.delay, () => setState(() => _shown = true));
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rise = Motion.reduced(context) ? 0.0 : 0.1;
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: Motion.base,
      curve: Motion.ease,
      // VoiceOver hears a row while it arrives too.
      alwaysIncludeSemantics: true,
      child: AnimatedSlide(
        // A tenth of its own height: a row rises 10 to 15 points.
        offset: _shown ? Offset.zero : Offset(0, rise),
        duration: Motion.slow,
        curve: Motion.ease,
        child: widget.child,
      ),
    );
  }
}

/// [child] grows from nothing to its height with a spring and fades in,
/// [delay] after [animate] turns true: a decision that has just come in
/// springs into the top of the feed and pushes the others down (#141). With
/// Reduce Motion on, it only fades. Always in the tree, like [Arrive]; off
/// in tests with it ([Arrive.enabled]).
class GrowIn extends StatefulWidget {
  const GrowIn({
    super.key,
    required this.child,
    this.animate = false,
    this.delay = Duration.zero,
  });

  final Widget child;
  final bool animate;
  final Duration delay;

  @override
  State<GrowIn> createState() => _GrowInState();
}

class _GrowInState extends State<GrowIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );
  late final _size = CurvedAnimation(parent: _controller, curve: Motion.spring);
  late final _fade = CurvedAnimation(parent: _controller, curve: Motion.ease);
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _start();
  }

  @override
  void didUpdateWidget(GrowIn old) {
    super.didUpdateWidget(old);
    // Rows have no keys: a row already built can be given a new decision.
    if (widget.animate && !old.animate) _start();
  }

  void _start() {
    if (!Arrive.enabled) return;
    _wait?.cancel();
    _controller.value = 0;
    _wait = Timer(widget.delay, () {
      if (mounted) unawaited(_controller.forward());
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    _size.dispose();
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Clipped only while it is shorter than itself: a clip left on cut a
  /// card's shadow to the card's own box, a band with square corners under
  /// every card in the feed (Roman, build 54, 30 Oct).
  @override
  Widget build(BuildContext context) {
    final size = Motion.reduced(context) ? kAlwaysCompleteAnimation : _size;
    return AnimatedBuilder(
      animation: size,
      builder: (context, child) => ClipRect(
        clipBehavior: size.value < 1 ? Clip.hardEdge : Clip.none,
        child: Align(
          // Its bottom first, as if it slid down from above the others.
          alignment: Alignment.bottomCenter,
          heightFactor: size.value < 0 ? 0 : size.value,
          child: child,
        ),
      ),
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}

/// For `Image.frameBuilder`: a picture that has to be loaded fades in
/// instead of popping up; one already in memory shows at once.
Widget fadeInPicture(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: Motion.base,
    curve: Motion.ease,
    child: child,
  );
}
