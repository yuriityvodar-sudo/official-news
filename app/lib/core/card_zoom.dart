import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'motion.dart';

/// A card an article opens from (#141): [CardZoomRoute] grows the article out
/// of it and puts it back there. Every feed look's rows are one
/// (`FeedList.tile`). The article's top is the same [card], drawn the same
/// ([cardOf], [ZoomTop]), so nothing in it changes while it opens: the card
/// itself grows into the article, as in the App Store. While the article is
/// open, the card in the feed is hidden, so the article goes back into an
/// empty place.
class ZoomSource extends StatefulWidget {
  const ZoomSource({
    super.key,
    required this.id,
    required this.card,
    required this.child,
  });

  /// The article's id.
  final String id;

  /// The card as the article's top shows it: the row without what only the
  /// feed does with it (its arrival, the press).
  final Widget card;
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

  /// The card of [id], to draw at the top of its article: with the feed's
  /// themes, not tappable there; null when it is not built.
  static Widget? cardOf(String id) {
    final source = _built[id];
    if (source == null || !source.mounted) return null;
    return InheritedTheme.captureAll(
      source.context,
      _ArticleTop(child: IgnorePointer(child: source.widget.card)),
    );
  }

  /// Whether [context] is in a card drawn as its article's top ([cardOf]): a
  /// card with a shadow or a frame of its own leaves it out there, where the
  /// card has become the page.
  static bool isArticleTop(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ArticleTop>() != null;

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

class _ArticleTop extends InheritedWidget {
  const _ArticleTop({required super.child});

  @override
  bool updateShouldNotify(_ArticleTop old) => false;
}

/// The card at the top of an article that opened out of it ([ZoomSource.cardOf]):
/// [CardZoomRoute] keeps it where the card was and carries it to its place
/// here, so the card and the article's top are one. Elsewhere (an article
/// opened from a notification) just [child].
class ZoomTop extends StatelessWidget {
  const ZoomTop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is! CardZoomRoute) return child;
    return KeyedSubtree(key: route._top, child: child);
  }
}

/// The rest of an article that opened out of its card: it comes in around
/// the card as the card grows, and goes before the card is back in its
/// place. Elsewhere just [child].
class ZoomRest extends StatelessWidget {
  const ZoomRest({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final rest = route is CardZoomRoute ? route._rest : null;
    if (rest == null || Motion.reduced(context)) return child;
    return FadeTransition(opacity: rest, child: child);
  }
}

/// An article that grows out of its card and goes back into it (#141), as
/// iOS's zoom transition does in the App Store: the card itself grows to the
/// whole screen. The article's top is the same card ([ZoomTop]), laid out
/// the same, so nothing is swapped and no line breaks move: it travels from
/// its place in the feed to the top of the article while its frame grows
/// around it, and the rest of the article comes in below ([ZoomRest]). On
/// the way back, the other way round. The motion is a spring, as iOS's.
///
/// A pull down at the top of the article, or a swipe from the left edge,
/// shrinks it under the finger; let go far enough and it goes back into its
/// card, otherwise it springs open again. With Reduce Motion on, the screens
/// fade.
class CardZoomRoute<T> extends PageRoute<T> {
  CardZoomRoute({
    required this.builder,
    required this.from,
    required this.background,
    required this.sourceId,
    this.radius = 12,
    super.settings,
  });

  final WidgetBuilder builder;

  /// The card's box on screen when it was tapped.
  final Rect from;

  /// The card's own colour, which becomes the article's page.
  final Color background;

  /// The card's corners.
  final double radius;

  /// The card at the article's top ([ZoomTop]).
  final _top = GlobalKey();

  /// How much of the rest of the article shows ([ZoomRest]).
  Animation<double>? _rest;

  /// The article's id: its card ([ZoomSource]) is hidden while it is open.
  final String sourceId;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 600);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 520);

  @override
  void install() {
    super.install();
    _rest = CurvedAnimation(
      parent: animation!,
      curve: const Interval(0.25, 0.75, curve: Curves.easeOut),
    );
    animation!.addListener(_hideCard);
  }

  /// The card in the feed hides as soon as its copy at the article's top is
  /// drawn over it, and shows again once that copy is back in its place.
  void _hideCard() {
    // The article's first frame is built offstage, for heroes to measure,
    // and its animation stands at the end meanwhile: the card stays, or its
    // place would be empty for that frame.
    if (offstage) return;
    if (animation!.value > 0) {
      ZoomSource._hidden.value = sourceId;
    } else if (ZoomSource._hidden.value == sourceId) {
      ZoomSource._hidden.value = null;
    }
  }

  /// While the reader shrinks the article by hand, the feed shows under it.
  /// Once open, the page is opaque, so the feed is not drawn under it.
  void _showBelow(bool show) {
    if (overlayEntries.isEmpty) return;
    overlayEntries.first.opaque =
        !show && animation!.status == AnimationStatus.completed;
  }

  @override
  void dispose() {
    animation?.removeListener(_hideCard);
    // Not while the navigator builds: the feed rebuilds on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ZoomSource._hidden.value == sourceId) {
        ZoomSource._hidden.value = null;
      }
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

/// iOS's spring for a view moving into place: critically damped, settling
/// in about half a second, as a curve over the transition's time. It starts
/// softly and lands without a long tail.
class _Spring extends Curve {
  const _Spring();

  /// How many of the spring's own periods the transition lasts.
  static const _periods = 1.15;

  static double _at(double t) {
    final w = 2 * math.pi * _periods * t;
    return 1 - (1 + w) * math.exp(-w);
  }

  @override
  double transformInternal(double t) => _at(t) / _at(1);
}

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
  static const _curve = _Spring();

  /// The article's corners while it is shrunk by hand.
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

  /// The article at full size, where its top card is measured.
  final _page = GlobalKey();

  /// Where the card at the article's top is in the article now (it scrolls
  /// with it); null before the article is laid out.
  Offset? _topInPage() {
    final top = widget.route._top.currentContext?.findRenderObject();
    final page = _page.currentContext?.findRenderObject();
    if (top is! RenderBox || page is! RenderBox) return null;
    if (!top.attached || !top.hasSize || !page.attached) return null;
    return top.localToGlobal(Offset.zero, ancestor: page);
  }

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
        key: _page,
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
          final grown = Rect.lerp(card, Offset.zero & size, t)!;
          // The article moves so that its top card stands where the card is
          // in the feed, then slides with it to its own place. Measured only
          // while it moves: open, a sheet coming or going over the article
          // (the paywall) moves the page in the tree, and its card cannot be
          // measured while it is between places.
          final top = t < 1 ? _topInPage() : null;
          final moved = top == null
              ? Offset.zero
              : (card.topLeft - top) * (1 - t);
          final scale = 1 - (1 - _smallest) * shrunk;
          final centre = grown.center + _travel * shrunk;
          final box = Rect.fromCenter(
            center: centre,
            width: grown.width * scale,
            height: grown.height * scale,
          );
          final open = t == 1 && shrunk == 0;
          // Page points to the box's: moved, then shrunk about the middle.
          final transform =
              Matrix4.translationValues(
                  centre.dx - box.left,
                  centre.dy - box.top,
                  0,
                )
                ..scaleByDouble(scale, scale, 1, 1)
                ..translateByDouble(
                  moved.dx - grown.center.dx,
                  moved.dy - grown.center.dy,
                  0,
                  1,
                );
          return Stack(
            children: [
              Positioned.fromRect(
                rect: box,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    lerpDouble(route.radius, 0, t)! + _shrunkRadius * shrunk,
                  ),
                  clipBehavior: open ? Clip.none : Clip.antiAlias,
                  child: ColoredBox(
                    color: route.background,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: size.width,
                      maxWidth: size.width,
                      minHeight: size.height,
                      maxHeight: size.height,
                      child: Transform(transform: transform, child: page),
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
