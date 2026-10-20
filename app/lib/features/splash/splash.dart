import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// The splash at app start (#66, Yurii, 16 Oct): three words stacked on
/// a white page (black in dark mode), with a wave that moves from the bottom
/// up. Four styles were compared in the prototype; 1b is the one shown
/// (Yurii, 20 Oct), the others stay for a build's `--dart-define=SPLASH`.
///
/// Apple wants the native launch screen static, so iOS shows a plain
/// background (LaunchScreen.storyboard, systemBackground: white, or black in
/// dark mode) and the motion is this Flutter overlay. Its first frame is the
/// same plain background, so nothing jumps or flashes. The feed is built and
/// starts loading under it from the first frame, so the splash never adds
/// waiting; any touch skips it, and it ends at once when the app is left
/// while it plays. With Reduce Motion the words fade in, stand still for a
/// moment and fade out.

/// The splash's words, one per line, as Yurii wrote them (English for now).
/// They live only here, to move into the ARB files when they are translated.
const splashLines = ['only', 'official', 'news'];

enum SplashStyle {
  /// The lines rise into place from below, one after another: "only" first.
  rise,

  /// The same, the other way round: "news" first, so the wave runs up, as
  /// the other two do (1b, to compare).
  riseUp,

  /// Black words; a band of the red accent passes up through them.
  sweep,

  /// Grey letters fill with black from the bottom, behind a wavy edge.
  fill,
}

/// The style shown at start: 1b, "news" first (Yurii's pick, 20 Oct). A build
/// can start with another one: `--dart-define=SPLASH=sweep` (or `riseup`, `fill`, or `1`,
/// `1b`, `2`, `3`).
final splashStyle = ValueNotifier<SplashStyle>(
  splashNamed(const String.fromEnvironment('SPLASH')),
);

/// `rise`, `riseup`, `sweep` or `fill` (or `1`, `1b`, `2`, `3`), in any case;
/// anything else is [SplashStyle.riseUp].
SplashStyle splashNamed(String name) {
  final key = name.trim().toLowerCase();
  return switch (key) {
    '1' => SplashStyle.rise,
    '1b' => SplashStyle.riseUp,
    '2' => SplashStyle.sweep,
    '3' => SplashStyle.fill,
    _ => SplashStyle.values.firstWhere(
      (style) => style.name.toLowerCase() == key,
      orElse: () => SplashStyle.riseUp,
    ),
  };
}

/// How long [style] plays before it fades: its motion, then a short hold
/// (about a third of a second).
Duration splashLength(SplashStyle style) => switch (style) {
  SplashStyle.rise || SplashStyle.riseUp => const Duration(milliseconds: 1850),
  SplashStyle.sweep => const Duration(milliseconds: 1950),
  SplashStyle.fill => const Duration(milliseconds: 1850),
};

/// The fade into the app at the end, or after a touch.
const splashFade = Duration(milliseconds: 250);

/// With Reduce Motion: the words fade in (in [_stillIn]), stand still, and
/// fade out after this long.
const splashStill = Duration(milliseconds: 800);
const _stillIn = 200.0;

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
/// [onDone] once it has faded out, or at once when the app is left while it
/// shows (coming back, the app is as it was, without the rest of it).
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

  /// Ends it when the app goes to the background: the rest of it is not
  /// played on the way back (its clock would only have paused).
  AppLifecycleListener? _life;

  bool _started = false;
  bool _still = false;
  bool _fading = false;
  bool _gone = false;

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
    _life = AppLifecycleListener(onHide: _leave);
  }

  void _tick(Duration elapsed) {
    final step = (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    _ms.value += math.min(step, _maxStep);
    if (_ms.value >= _length) _end();
  }

  /// Fades out: at the end, or at once after a touch.
  void _end() {
    if (_fading || !mounted) return;
    setState(() => _fading = true);
    _clock.stop();
    _fade.forward().then((_) => _finish());
  }

  /// The app was left: gone at once, unseen.
  void _leave() {
    _clock.stop();
    _fade.stop();
    _finish();
  }

  void _finish() {
    if (_gone) return;
    _gone = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _life?.dispose();
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
    // Where the baseline sits in each line, for the fill's water.
    final baseline = widget.style == SplashStyle.fill ? _baseline(type) : 0.0;
    final words = ValueListenableBuilder(
      valueListenable: _ms,
      builder: (context, now, _) {
        // At rest, standing still, with Reduce Motion.
        final ms = _still ? double.infinity : now;
        final words = switch (widget.style) {
          SplashStyle.rise => _Rise(ms: ms, style: type),
          SplashStyle.riseUp => _Rise(ms: ms, style: type, fromBottom: true),
          SplashStyle.sweep => _Sweep(ms: ms, style: type),
          SplashStyle.fill => _Fill(
            ms: ms,
            style: type,
            baseline: baseline,
            empty: dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
          ),
        };
        // Reduce Motion takes the movement away, not the gentle fade in.
        return _still
            ? Opacity(
                opacity: _phase(now, 0, _stillIn, Curves.easeOut),
                child: words,
              )
            : words;
      },
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: IgnorePointer(
        // While it fades, the app under it already takes taps.
        ignoring: _fading,
        // Any touch skips it, a scroll as well as a tap, so the feed under it
        // never seems stuck.
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _end(),
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
/// 1b ([fromBottom]): "news" first, then "official", then "only".
class _Rise extends StatelessWidget {
  const _Rise({required this.ms, required this.style, this.fromBottom = false});

  final double ms;
  final TextStyle style;
  final bool fromBottom;

  static const _stagger = 240.0;
  static const _length = 1100.0;

  @override
  Widget build(BuildContext context) {
    final size = style.fontSize!;
    return _Lines(
      style: style,
      line: (i, text) {
        final order = fromBottom ? splashLines.length - 1 - i : i;
        final start = _lead + order * _stagger;
        final t = _phase(ms, start, _length, Curves.easeOutCubic);
        // The fold does the reveal; this only softens the first points.
        final shown = _phase(ms, start, 150, Curves.easeOut);
        return ClipRect(
          // The fold sits just under the tail of the "y", so a line is out of
          // sight until it rises past it.
          clipper: _LineWindow(over: size * 0.14, under: size * 0.08),
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
    // The band's middle, 0 at the bottom of the words' box and 1 at its top.
    // The letters fill about 0.1 to 0.9 of it, so the band starts with its
    // edge on the bottom of the letters and leaves with its edge on their top:
    // all its travel is seen.
    const half = 0.24;
    final at =
        -0.6 * half +
        (1 + 1.2 * half) * _phase(ms, _lead + 200, 1450, Curves.easeInOutSine);
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
/// the bottom up behind a moving wave, like water rising inside them. Each
/// line has its own water, "news" first: the next line starts a third of the
/// way into the one under it, so an edge is always moving through ink (one
/// water line for all three would cross the empty room between the lines
/// with nothing to see, and look like it stops).
class _Fill extends StatelessWidget {
  const _Fill({
    required this.ms,
    required this.style,
    required this.baseline,
    required this.empty,
  });

  final double ms;
  final TextStyle style;

  /// Where the baseline sits in a line's box, in points from its top.
  final double baseline;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    final shown = _phase(ms, _lead, 300, Curves.easeOut);
    final size = style.fontSize!;
    final levels = splashFillLevels(ms);
    return Opacity(
      opacity: shown,
      child: Stack(
        children: [
          _Lines(style: style.copyWith(color: empty)),
          _Lines(
            style: style,
            line: (i, text) {
              final ink = _ink(splashLines[i]);
              return ClipPath(
                clipper: _Water(
                  level: levels[i],
                  // The waves keep moving while the level rises; still at rest.
                  seconds: ms.isFinite ? ms / 1000 : 0,
                  top: baseline - ink.over * size,
                  bottom: baseline + ink.under * size,
                  wave: size * _fillWave,
                  length: size * 2.1,
                ),
                child: text,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The waves' height, in ems.
const _fillWave = 0.075;

/// From the first line's water starting to the last one's being full, in ms.
const _fillMotion = 1500.0;

/// How far into a line's fill the next line starts. Early enough that the
/// next line's letters start filling while only the tall letters of the one
/// under it ("f", "l") are still filling, so the motion does not thin out.
const _fillNext = 0.35;

/// How far [word]'s letters reach over and under the baseline, in ems:
/// Georgia Bold's ink, measured (the "l" 0.756 over, the "y" 0.217 under, the
/// x-height 0.498, the round letters' overshoot 0.016 under). A letter not
/// measured here (a capital, a digit, another alphabet) counts as the font's
/// full height, so no letter is ever left unfilled.
({double over, double under}) _ink(String word) {
  var over = 0.498, under = 0.016;
  for (final letter in word.split('')) {
    if (!'abcdefghijklmnopqrstuvwxyz'.contains(letter)) {
      return (over: 0.92, under: 0.23);
    }
    if ('bdfhijklt'.contains(letter)) over = 0.756;
    if ('gjpqy'.contains(letter)) under = 0.217;
  }
  return (over: over, under: under);
}

/// When each line of the fill fills, (start, length) in ms, in the order of
/// [splashLines]. The bottom line goes first, and each next one starts
/// [_fillNext] of the way into the one under it; each takes as long as its
/// ink is tall, so the water rises at the same speed in every line.
final List<(double, double)> _fillTimes = () {
  // The water's travel per line, bottom first: its ink, and the waves under
  // it at the start and (calmer, see [_Water]) over it at the end.
  final travel = [
    for (final word in splashLines.reversed)
      _ink(word).over + _ink(word).under + _fillWave * 1.35 * (1 + 0.6),
  ];
  final whole =
      travel.take(travel.length - 1).fold(0.0, (a, b) => a + b * _fillNext) +
      travel.last;
  final perEm = _fillMotion / whole;
  final times = <(double, double)>[];
  var start = _lead;
  for (final t in travel) {
    times.add((start, t * perEm));
    start += t * perEm * _fillNext;
  }
  return times.reversed.toList();
}();

/// The fill's water level in each line at [ms] (0 empty, 1 full), in the
/// order of [splashLines].
@visibleForTesting
List<double> splashFillLevels(double ms) => [
  for (final (start, length) in _fillTimes)
    _phase(ms, start, length, Curves.easeInOutSine),
];

/// Where the baseline sits in a line of [style], in points from its top.
double _baseline(TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: splashLines.first, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final baseline = painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  painter.dispose();
  return baseline;
}

/// Everything in a line under a wavy water line: at [level] 0 the crests are
/// just under its ink ([top] to [bottom]), at 1 the troughs just over it.
class _Water extends CustomClipper<Path> {
  const _Water({
    required this.level,
    required this.seconds,
    required this.top,
    required this.bottom,
    required this.wave,
    required this.length,
  });

  final double level;
  final double seconds;

  /// The line's ink, in points from the top of its box.
  final double top;
  final double bottom;

  /// The waves' height and length, in points.
  final double wave;
  final double length;

  @override
  Path getClip(Size size) {
    // Past the line's box all round, for the letters that reach out of it
    // (the tail of the "y").
    final room = Rect.fromLTRB(
      -size.height * 0.2,
      -size.height,
      size.width + size.height * 0.2,
      size.height * 2,
    );
    if (level >= 1) return Path()..addRect(room);
    if (level <= 0) return Path();
    // The waves calm down as the line fills. Together the two waves reach
    // 1.35 times their height over and under the middle.
    final height = wave * (1 - 0.4 * level);
    final from = bottom + wave * 1.35;
    final to = top - wave * 0.6 * 1.35;
    final middle = from + (to - from) * level;
    final path = Path()..moveTo(room.left, room.bottom);
    for (var x = room.left; x <= room.right + 4; x += 4) {
      final a = 2 * math.pi * x / length;
      final y =
          middle +
          height * math.sin(a - seconds * 2 * math.pi * 0.9) +
          height * 0.35 * math.sin(a * 2.3 + seconds * 2 * math.pi * 0.6);
      path.lineTo(x, y);
    }
    return path
      ..lineTo(room.right + 4, room.bottom)
      ..close();
  }

  @override
  bool shouldReclip(_Water old) =>
      old.level != level ||
      old.seconds != seconds ||
      old.top != top ||
      old.bottom != bottom ||
      old.wave != wave ||
      old.length != length;
}
