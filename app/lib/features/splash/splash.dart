import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// PROTOTYPE (Yurii, 16 Oct): the splash at app start, three words stacked on
/// a white page (black in dark mode), with a wave that moves from the bottom
/// up. Three styles to compare, chosen in Settings (Prototype → Splash).
///
/// Apple wants the native launch screen static, so iOS shows a plain
/// background (LaunchScreen.storyboard, systemBackground: white, or black in
/// dark mode) and the motion is this Flutter overlay. Its first frame is the
/// same plain background, so nothing jumps or flashes. The feed is built and
/// starts loading under it from the first frame, so the splash never adds
/// waiting; a tap skips it. With Reduce Motion the words stand still for a
/// moment and fade.

/// The splash's words, one per line, as Yurii wrote them (English for now).
/// They live only here, to move into the ARB files when they are translated.
const splashLines = ['only', 'official', 'news'];

enum SplashStyle {
  /// The lines rise into place from below, one after another.
  rise,

  /// Black words; a band of the red accent passes up through them.
  sweep,

  /// Grey letters fill with black from the bottom, behind a wavy edge.
  fill,
}

/// The style shown at start and by Settings → Play. A build can start with
/// another one: `--dart-define=SPLASH=sweep` (or `1`, `2`, `3`).
final splashStyle = ValueNotifier<SplashStyle>(
  splashNamed(const String.fromEnvironment('SPLASH')),
);

/// `rise`, `sweep` or `fill` (or `1`, `2`, `3`), in any case; anything else is
/// [SplashStyle.rise].
SplashStyle splashNamed(String name) {
  final key = name.trim().toLowerCase();
  return switch (key) {
    '1' => SplashStyle.rise,
    '2' => SplashStyle.sweep,
    '3' => SplashStyle.fill,
    _ => SplashStyle.values.asNameMap()[key] ?? SplashStyle.rise,
  };
}

/// How long [style] plays before it fades: its motion, then a short hold.
Duration splashLength(SplashStyle style) => switch (style) {
  SplashStyle.rise => const Duration(milliseconds: 1850),
  SplashStyle.sweep => const Duration(milliseconds: 1950),
  SplashStyle.fill => const Duration(milliseconds: 2000),
};

/// The fade into the app at the end, or after a tap.
const splashFade = Duration(milliseconds: 250);

/// With Reduce Motion: the words stand still this long, then fade.
const splashStill = Duration(milliseconds: 600);

/// Puts the splash over the app: once when the app starts (a cold start; the
/// app coming back from the background keeps its state, so it does not show
/// again), and whenever [play] asks. Goes in `MaterialApp.builder`, so the
/// app's navigator, and the feed in it, are built under it from the first
/// frame.
class SplashHost extends StatefulWidget {
  const SplashHost({super.key, required this.child, this.onStart = true});

  /// The app: the navigator from `MaterialApp.builder`.
  final Widget child;

  /// Shows the splash when the app starts.
  final bool onStart;

  /// Shows the [splashStyle] splash over the app now (Settings → Play).
  static void play(BuildContext context) =>
      context.findAncestorStateOfType<_SplashHostState>()?._play();

  @override
  State<SplashHost> createState() => _SplashHostState();
}

class _SplashHostState extends State<SplashHost> {
  late bool _showing = widget.onStart;

  /// A new splash for each play, so Play during one starts it over.
  int _run = 0;

  void _play() => setState(() {
    _showing = true;
    _run++;
  });

  void _done() {
    if (mounted) setState(() => _showing = false);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // VoiceOver reads the splash while it shows, then the app.
      ExcludeSemantics(excluding: _showing, child: widget.child),
      if (_showing)
        Splash(key: ValueKey(_run), style: splashStyle.value, onDone: _done),
    ],
  );
}

/// One splash: the page, the words and their motion, then a fade. Calls
/// [onDone] once it has faded out.
class Splash extends StatefulWidget {
  const Splash({super.key, required this.style, required this.onDone});

  final SplashStyle style;
  final VoidCallback onDone;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with TickerProviderStateMixin {
  /// The splash's own clock, in ms: 0 at the first frame. It moves on by the
  /// time between frames, but by no more than [_maxStep] at once, so a slow
  /// frame (the app's first frames, the feed being built under it) slows the
  /// motion down for a moment instead of skipping it.
  final _ms = ValueNotifier<double>(0);
  late final _clock = createTicker(_tick);
  Duration _last = Duration.zero;
  static const _maxStep = 50.0;

  /// The fade: the words go first, then the page, so they never linger as a
  /// ghost over the feed.
  late final _fade = AnimationController(vsync: this, duration: splashFade);
  late final _wordsOpacity = Tween<double>(begin: 1, end: 0).animate(
    CurvedAnimation(
      parent: _fade,
      curve: const Interval(0, 0.45, curve: Curves.easeOut),
    ),
  );
  late final _pageOpacity = Tween<double>(begin: 1, end: 0).animate(
    CurvedAnimation(
      parent: _fade,
      curve: const Interval(0.3, 1, curve: Curves.easeInOut),
    ),
  );

  bool _started = false;
  bool _still = false;
  bool _fading = false;

  /// How long it plays before it fades.
  int get _length => _still
      ? splashStill.inMilliseconds
      : splashLength(widget.style).inMilliseconds;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // iOS reports Reduce Motion as reduceMotion, not disableAnimations.
    _still =
        MediaQuery.disableAnimationsOf(context) ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    _clock.start();
  }

  void _tick(Duration elapsed) {
    final step = (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    _ms.value += math.min(step, _maxStep);
    if (_ms.value >= _length) _end();
  }

  /// Fades out: at the end, or at once after a tap.
  void _end() {
    if (_fading || !mounted) return;
    setState(() => _fading = true);
    _clock.stop();
    _fade.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _clock.dispose();
    _fade.dispose();
    _ms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Exactly the launch screen's systemBackground, so the first frame matches it.
    final page = dark ? Colors.black : Colors.white;
    final ink = dark ? Colors.white : Colors.black;
    // Sized by the phone's short side, so turning it keeps the same words.
    final side = MediaQuery.sizeOf(context).shortestSide;
    final type = TextStyle(
      fontFamily: 'Georgia',
      fontFamilyFallback: const ['serif'],
      fontSize: math.min(side * 0.19, 96),
      fontWeight: FontWeight.w700,
      height: 1.04,
      letterSpacing: -0.5,
      color: ink,
      decoration: TextDecoration.none,
    );
    final words = ValueListenableBuilder(
      valueListenable: _ms,
      builder: (context, now, _) {
        // At rest, standing still, with Reduce Motion.
        final ms = _still ? double.infinity : now;
        return switch (widget.style) {
          SplashStyle.rise => _Rise(ms: ms, style: type),
          SplashStyle.sweep => _Sweep(ms: ms, style: type),
          SplashStyle.fill => _Fill(
            ms: ms,
            style: type,
            empty: dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
          ),
        };
      },
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: IgnorePointer(
        // While it fades, the app under it already takes taps.
        ignoring: _fading,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _end,
          child: Semantics(
            label: splashLines.join(' '),
            container: true,
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FadeTransition(
                    opacity: _pageOpacity,
                    child: ColoredBox(color: page),
                  ),
                  FadeTransition(
                    opacity: _wordsOpacity,
                    child: Align(
                      // A little above the middle, where the eye puts the centre.
                      alignment: const Alignment(0, -0.1),
                      // Drawn like a logo: the reader's text size does not
                      // grow it past the screen (VoiceOver reads the words).
                      child: MediaQuery.withNoTextScaling(child: words),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [splashLines] stacked and centred, each line drawn by [line].
class _Lines extends StatelessWidget {
  const _Lines({required this.style, this.line});

  final TextStyle style;
  final Widget Function(int index, Widget text)? line;

  /// The room over and under the lines, for type of [size].
  static double inset(double size) => size * 0.2;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: style,
    textAlign: TextAlign.center,
    // Room around the lines for the letters that reach past them ("l", "y"),
    // so the masks and clips of the styles cover whole letters.
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: style.fontSize! * 0.15,
        vertical: inset(style.fontSize!),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, word) in splashLines.indexed)
            line?.call(i, Text(word)) ?? Text(word),
        ],
      ),
    ),
  );
}

/// 0 before [start] ms, 1 after [start] + [length], eased by [curve] between.
double _phase(double ms, double start, double length, [Curve? curve]) {
  final t = ((ms - start) / length).clamp(0.0, 1.0);
  return curve == null ? t : curve.transform(t);
}

/// Every style starts after this many ms of plain page (the launch screen's
/// look), so the app's first, slower frames are behind it when the words move.
const _lead = 100.0;

/// 1 · rise: each line comes up from below into its place, as if from under
/// a fold, "only" first, then "official", then "news", overlapping like a wave.
class _Rise extends StatelessWidget {
  const _Rise({required this.ms, required this.style});

  final double ms;
  final TextStyle style;

  static const _stagger = 180.0;
  static const _length = 1000.0;

  @override
  Widget build(BuildContext context) {
    final size = style.fontSize!;
    return _Lines(
      style: style,
      line: (i, text) {
        final start = _lead + i * _stagger;
        final t = _phase(ms, start, _length, Curves.easeOutCubic);
        final shown = _phase(ms, start, _length * 0.4);
        return ClipRect(
          clipper: _LineWindow(over: size * 0.14, under: size * 0.26),
          child: Opacity(
            opacity: shown,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * size * 1.2),
              child: text,
            ),
          ),
        );
      },
    );
  }
}

/// A line's own box and some points [over] and [under] it (for "l" and the
/// tail of "y"): the line rises into it from below, unseen until it crosses
/// the bottom.
class _LineWindow extends CustomClipper<Rect> {
  const _LineWindow({required this.over, required this.under});

  final double over;
  final double under;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.width, -over, size.width * 2, size.height + under);

  @override
  bool shouldReclip(_LineWindow old) => old.over != over || old.under != under;
}

/// 2 · sweep: the words come in black, then a band of red light passes up
/// through them, from the bottom line to the top, and leaves them black.
class _Sweep extends StatelessWidget {
  const _Sweep({required this.ms, required this.style});

  final double ms;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final ink = style.color!;
    final shown = _phase(ms, _lead, 400, Curves.easeOut);
    // The band's middle, from just under the words (0 is their bottom) to just over them.
    const half = 0.24;
    final at =
        -half +
        (1 + 2 * half) * _phase(ms, _lead + 200, 1400, Curves.easeInOutSine);
    double stop(double v) => v.clamp(0.0, 1.0);
    return Opacity(
      opacity: shown,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => LinearGradient(
          // Bottom to top, leaning a little, like light passing over the page.
          begin: const Alignment(0.12, 1),
          end: const Alignment(-0.12, -1),
          colors: [ink, ink, AppColors.accent, AppColors.accent, ink, ink],
          stops: [
            0,
            stop(at - half),
            stop(at - half * 0.3),
            stop(at + half * 0.3),
            stop(at + half),
            1,
          ],
        ).createShader(rect),
        child: _Lines(style: style),
      ),
    );
  }
}

/// 3 · fill: the letters show empty (light grey), then fill with black from
/// the bottom up behind a moving wave, like water rising inside them.
class _Fill extends StatelessWidget {
  const _Fill({required this.ms, required this.style, required this.empty});

  final double ms;
  final TextStyle style;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    final shown = _phase(ms, _lead, 300, Curves.easeOut);
    final level = _phase(ms, _lead + 100, 1500, Curves.easeInOutSine);
    final size = style.fontSize!;
    return Opacity(
      opacity: shown,
      child: Stack(
        children: [
          _Lines(style: style.copyWith(color: empty)),
          ClipPath(
            clipper: _Water(
              level: level,
              // The waves keep moving while the level rises; still at rest.
              seconds: ms.isFinite ? ms / 1000 : 0,
              height: size * 0.075,
              length: size * 2.1,
              inset: _Lines.inset(size),
            ),
            child: _Lines(style: style),
          ),
        ],
      ),
    );
  }
}

/// Everything under a wavy water line: [level] 0 is just under the letters,
/// 1 just over them.
class _Water extends CustomClipper<Path> {
  const _Water({
    required this.level,
    required this.seconds,
    required this.height,
    required this.length,
    required this.inset,
  });

  final double level;
  final double seconds;

  /// The waves' height and length, in points.
  final double height;
  final double length;

  /// The empty room over and under the letters ([_Lines.inset]): the water
  /// rises through it unseen, so it is mostly left out.
  final double inset;

  @override
  Path getClip(Size size) {
    if (level >= 1) return Path()..addRect(Offset.zero & size);
    // Crests just under the bottom line at 0, troughs over the "l" at 1.
    final from = size.height - inset + height * 1.35;
    final to = inset - height * 2.2;
    final top = from + (to - from) * level;
    // The waves calm down as the letters fill.
    final wave = height * (1 - 0.4 * level);
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width + 4; x += 4) {
      final a = 2 * math.pi * x / length;
      final y =
          top +
          wave * math.sin(a - seconds * 2 * math.pi * 0.9) +
          wave * 0.35 * math.sin(a * 2.3 + seconds * 2 * math.pi * 0.6);
      path.lineTo(x, y);
    }
    return path
      ..lineTo(size.width + 4, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_Water old) =>
      old.level != level ||
      old.seconds != seconds ||
      old.height != height ||
      old.length != length ||
      old.inset != inset;
}
