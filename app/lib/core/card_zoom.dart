import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'motion.dart';

/// A card an article opens from (#141): [CardZoomRoute] grows the article out
/// of it and puts it back there. Every feed look's rows are one
/// (`FeedList.tile`). While its article covers it, the card is hidden, so the
/// article shrinks back into an empty place, as in Apple's apps.
class ZoomSource extends StatefulWidget {
  const ZoomSource({super.key, required this.id, required this.child});

  /// The article's id.
  final String id;
  final Widget child;

  static final _built = <String, _ZoomSourceState>{};

  /// The article whose card is hidden now, if any.
  static final _hidden = ValueNotifier<String?>(null);

  /// Where the card of [id] is on screen now; null when it is not built.
  static Rect? rectOf(String id) {
    final box = _built[id]?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  State<ZoomSource> createState() => _ZoomSourceState();
}

class _ZoomSourceState extends State<ZoomSource> {
  @override
  void initState() {
    super.initState();
    ZoomSource._built[widget.id] = this;
  }

  @override
  void didUpdateWidget(ZoomSource old) {
    super.didUpdateWidget(old);
    if (old.id == widget.id) return;
    _forget(old.id);
    ZoomSource._built[widget.id] = this;
  }

  @override
  void dispose() {
    _forget(widget.id);
    super.dispose();
  }

  void _forget(String id) {
    if (ZoomSource._built[id] == this) ZoomSource._built.remove(id);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: ZoomSource._hidden,
    builder: (context, hidden, child) =>
        Opacity(opacity: hidden == widget.id ? 0 : 1, child: child),
    child: widget.child,
  );
}

/// An article that grows out of its card and goes back into it (#141), as
/// iOS's zoom transition does in Photos and the App Store. The card's box
/// grows to the whole screen while the article, laid out at full size and
/// scaled to the box's width, shows through it.
///
/// A pull down at the top of the article, or a swipe from the left edge,
/// shrinks it under the finger; let go far enough and it goes back into its
/// card, otherwise it springs open again. With Reduce Motion on, the screens
/// fade.
class CardZoomRoute<T> extends PageRoute<T> {
  CardZoomRoute({
    required this.builder,
    required this.from,
    required this.sourceId,
    super.settings,
  });

  final WidgetBuilder builder;

  /// The card's box on screen when it was tapped.
  final Rect from;

  /// The article's id: its card ([ZoomSource]) is hidden while it is open.
  final String sourceId;

  /// True while an article grows out of its card, goes back into it, or is
  /// shrunk by hand: the screen under it shows then, and its native glass is
  /// drawn plainly meanwhile (`GlassCircle`).
  static final moving = ValueNotifier<bool>(false);

  /// The reader is shrinking the article by hand.
  bool _dragging = false;

  void _updateMoving() =>
      moving.value = _dragging || (animation?.isAnimating ?? false);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 440);

  @override
  void install() {
    super.install();
    animation!
      ..addListener(_hideCard)
      ..addStatusListener(_statusChanged);
  }

  void _statusChanged(AnimationStatus _) => _updateMoving();

  /// The card hides once the article covers it, and shows again as the
  /// article fades back into it.
  void _hideCard() {
    if (animation!.value > _fadeEnd) {
      ZoomSource._hidden.value = sourceId;
    } else if (ZoomSource._hidden.value == sourceId) {
      ZoomSource._hidden.value = null;
    }
  }

  /// While the reader shrinks the article by hand, the feed shows under it.
  /// Once open, the page is opaque, so the feed is not drawn under it.
  void _showBelow(bool show) {
    _dragging = show;
    _updateMoving();
    if (overlayEntries.isEmpty) return;
    overlayEntries.first.opaque =
        !show && animation!.status == AnimationStatus.completed;
  }

  @override
  void dispose() {
    animation
      ?..removeListener(_hideCard)
      ..removeStatusListener(_statusChanged);
    // Not while the navigator builds: the feed rebuilds on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ZoomSource._hidden.value == sourceId) {
        ZoomSource._hidden.value = null;
      }
      moving.value = false;
    });
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return _CardZoom(route: this, animation: animation, child: child);
  }
}

/// The part of the opening in which the article shows through its card, and
/// of the closing in which it fades back into it.
const _fadeEnd = 0.3;

class _CardZoom extends StatefulWidget {
  const _CardZoom({
    required this.route,
    required this.animation,
    required this.child,
  });

  final CardZoomRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_CardZoom> createState() => _CardZoomState();
}

class _CardZoomState extends State<_CardZoom>
    with SingleTickerProviderStateMixin {
  /// iOS's own curve for a screen moving into place.
  static const _curve = Cubic(0.32, 0.72, 0, 1);

  /// The card's corners, and the article's while it is shrunk by hand.
  static const _cardRadius = 12.0;
  static const _shrunkRadius = 28.0;

  /// How small the article gets at the end of a drag.
  static const _smallest = 0.8;

  /// A pull down this long at the top of the article closes it.
  static const _pullToClose = 90.0;

  /// Pulled this far down, the article is at its smallest.
  static const _pullRange = 300.0;

  late final _grow = CurvedAnimation(
    parent: widget.animation,
    curve: _curve,
    reverseCurve: _curve.flipped,
  );

  /// How far the reader has shrunk the article by hand: 0 open, 1 as small
  /// as it gets.
  late final _drag = AnimationController(vsync: this);

  /// Where the article's centre moves at the end of a drag: down for a pull,
  /// right for the edge swipe.
  Offset _travel = Offset.zero;

  /// The pull down at the top of the article, in points, while the finger
  /// is on it.
  double _pulled = 0;
  bool _pulling = false;

  /// The left-edge swipe, in points.
  double _swiped = 0;

  /// Let go far enough: on its way back into its card.
  bool _leaving = false;

  @override
  void dispose() {
    _grow.dispose();
    _drag.dispose();
    super.dispose();
  }

  void _shrink(double amount, Offset travel) {
    if (_leaving || widget.animation.status != AnimationStatus.completed) {
      return;
    }
    final value = amount.clamp(0.0, 1.0);
    if (_drag.value == 0 && value > 0) widget.route._showBelow(true);
    if (_drag.value > 0 && value == 0) widget.route._showBelow(false);
    _travel = travel;
    _drag.value = value;
  }

  void _letGo({required bool close}) {
    if (_leaving || _drag.value == 0) return;
    final route = widget.route;
    if (close && route.isCurrent) {
      _leaving = true;
      // The drag stays where it is: the way back starts from there.
      _drag.stop();
      route.navigator!.pop();
      return;
    }
    _drag.animateTo(0, duration: Motion.slow, curve: Motion.ease).whenComplete(
      () {
        if (mounted && !_leaving) route._showBelow(false);
      },
    );
  }

  /// A pull down at the top: the list scrolls past its top (iOS) or reports
  /// the overscroll (Android).
  bool _scrolled(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    double? pulled;
    if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll < 0) {
      pulled = _pulled - n.overscroll;
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final above = n.metrics.minScrollExtent - n.metrics.pixels;
      if (above > 0) {
        // A list that still bounces at its top.
        pulled = above;
      } else if (_pulled > 0) {
        // Back up again: the article grows back.
        pulled = _pulled - (n.scrollDelta ?? 0);
      }
    }
    if (pulled != null) {
      _pulled = math.max(0, pulled);
      _pulling = _pulled > 0;
      // Its centre follows the finger.
      _shrink(_pulled / _pullRange, const Offset(0, _pullRange));
    }
    return false;
  }

  void _fingerUp() {
    if (!_pulling) return;
    final close = _pulled >= _pullToClose;
    _pulling = false;
    _pulled = 0;
    _letGo(close: close);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      // Swiped this far from the left edge, the article is at its smallest,
      // and its centre has followed the finger.
      final swipe = size.width * 0.6;
      final page = SizedBox.fromSize(
        size: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: _scrolled,
                child: Listener(
                  onPointerUp: (_) => _fingerUp(),
                  onPointerCancel: (_) => _fingerUp(),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      physics: _HoldsAtTop(
                        parent: ScrollConfiguration.of(
                          context,
                        ).getScrollPhysics(context),
                      ),
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
            // The left edge, as iOS's back swipe.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 20,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) => _swiped = 0,
                onHorizontalDragUpdate: (details) {
                  _swiped = math.max(0, _swiped + details.delta.dx);
                  _shrink(_swiped / swipe, Offset(swipe, 0));
                },
                onHorizontalDragEnd: (details) => _letGo(
                  close:
                      _drag.value > 0.3 || (details.primaryVelocity ?? 0) > 500,
                ),
                onHorizontalDragCancel: () => _letGo(close: false),
              ),
            ),
          ],
        ),
      );
      return AnimatedBuilder(
        animation: Listenable.merge([_grow, _drag]),
        child: page,
        builder: (context, page) {
          final t = _grow.value;
          // Shrunk by hand, then carried back into the card from there.
          final shrunk = _drag.value * t;
          // Back to where the card is now: the feed may have moved meanwhile.
          final route = widget.route;
          final card = widget.animation.status == AnimationStatus.reverse
              ? ZoomSource.rectOf(route.sourceId) ?? route.from
              : route.from;
          var box = Rect.lerp(card, Offset.zero & size, t)!;
          if (shrunk > 0) {
            final scale = 1 - (1 - _smallest) * shrunk;
            box = Rect.fromCenter(
              center: box.center + _travel * shrunk,
              width: box.width * scale,
              height: box.height * scale,
            );
          }
          final open = t == 1 && shrunk == 0;
          return Stack(
            children: [
              Positioned.fromRect(
                rect: box,
                child: Opacity(
                  opacity: (widget.animation.value / _fadeEnd).clamp(0.0, 1.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      lerpDouble(_cardRadius, 0, t)! + _shrunkRadius * shrunk,
                    ),
                    clipBehavior: open ? Clip.none : Clip.antiAlias,
                    // The article keeps its full-size layout: no text moves
                    // to a new line while it grows.
                    child: FittedBox(
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                      clipBehavior: open ? Clip.none : Clip.hardEdge,
                      child: page,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// How the article scrolls while it can be pulled back into its card: at its
/// top the text does not bounce down, the whole article follows the finger
/// instead ([_CardZoomState._scrolled]). Everywhere else it scrolls as the
/// platform does.
class _HoldsAtTop extends ScrollPhysics {
  const _HoldsAtTop({super.parent});

  @override
  _HoldsAtTop applyTo(ScrollPhysics? ancestor) =>
      _HoldsAtTop(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final top = position.minScrollExtent;
    if (value < position.pixels && position.pixels <= top) {
      return value - position.pixels;
    }
    if (value < top && top < position.pixels) return value - top;
    return super.applyBoundaryConditions(position, value);
  }
}
