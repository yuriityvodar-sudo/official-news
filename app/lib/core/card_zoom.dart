import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/rendering.dart';
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

/// The pieces a card and its article both show, which fly from one to the
/// other while the article opens or closes (#141).
enum ZoomPiece { headline, picture, publisher, time }

/// A [ZoomPiece] of a card, or the same piece in its article: while the
/// article grows out of its card or goes back into it, [CardZoomRoute] draws
/// the piece flying from one place to the other, and hides both meanwhile,
/// so nothing is swapped in place. One inside a [ZoomSource] is the card's;
/// any other is the article's.
///
/// A picture's part goes inside its clip and says what the clip is
/// ([radius]): in flight the corners change from the card's to the
/// article's.
class ZoomPart extends StatefulWidget {
  const ZoomPart({
    super.key,
    required this.id,
    required this.piece,
    this.radius = BorderRadius.zero,
    required this.child,
  });

  /// The article's id.
  final String id;
  final ZoomPiece piece;

  /// The corners a picture is clipped to here.
  final BorderRadius radius;
  final Widget child;

  static final _cards = <String, List<_ZoomPartState>>{};
  static final _articles = <String, List<_ZoomPartState>>{};

  static String _tag(String id, ZoomPiece piece) => '$id/${piece.name}';

  /// The card's piece of [tag] ([inCard]) or the article's, as laid out
  /// now. A piece built twice (a picture flying full screen is, for a
  /// moment) is the one built last.
  static _ZoomPartState? _find(String tag, {required bool inCard}) {
    final parts = (inCard ? _cards : _articles)[tag];
    if (parts == null) return null;
    for (final part in parts.reversed) {
      if (part._box != null) return part;
    }
    return null;
  }

  @override
  State<ZoomPart> createState() => _ZoomPartState();
}

class _ZoomPartState extends State<ZoomPart> {
  String? _tag;
  bool _inCard = false;

  Map<String, List<_ZoomPartState>> get _parts =>
      _inCard ? ZoomPart._cards : ZoomPart._articles;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  @override
  void didUpdateWidget(ZoomPart old) {
    super.didUpdateWidget(old);
    _register();
  }

  @override
  void dispose() {
    _forget();
    super.dispose();
  }

  void _register() {
    _forget();
    _inCard = context.findAncestorWidgetOfExactType<ZoomSource>() != null;
    final tag = _tag = ZoomPart._tag(widget.id, widget.piece);
    (_parts[tag] ??= []).add(this);
  }

  void _forget() {
    final tag = _tag;
    if (tag == null) return;
    final parts = _parts[tag];
    if (parts == null) return;
    parts.remove(this);
    if (parts.isEmpty) _parts.remove(tag);
  }

  RenderBox? get _box {
    if (!mounted) return null;
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// Its size as laid out, before any scale above it.
  Size get _size => _box!.size;

  /// Where it is now, in [ancestor]'s coordinates (on screen without one).
  Rect? _rectIn([RenderObject? ancestor]) {
    final box = _box;
    if (box == null) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(ancestor),
      Offset.zero & box.size,
    );
  }

  /// The size of its first letters as laid out, so a headline grows from the
  /// card's size to the article's; null for a picture.
  double? get _fontSize {
    double? size;
    void visit(RenderObject object) {
      if (size != null) return;
      if (object is RenderParagraph) {
        final font = _firstFont(object.text, null);
        if (font != null) size = object.textScaler.scale(font);
        return;
      }
      object.visitChildren(visit);
    }

    final box = _box;
    if (box != null) visit(box);
    return size;
  }

  /// The font size of the first words of [span], which may come from a span
  /// around them ([inherited]): "BRAZIL  Chamber of Deputies" is several.
  static double? _firstFont(InlineSpan span, double? inherited) {
    final size = span.style?.fontSize ?? inherited;
    if (span is! TextSpan) return null;
    if (span.text?.isNotEmpty ?? false) return size;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = _firstFont(child, size);
      if (found != null) return found;
    }
    return null;
  }

  /// Its child to draw somewhere else, with this place's themes and text
  /// styles.
  Widget get _drawn => InheritedTheme.captureAll(context, widget.child);

  @override
  Widget build(BuildContext context) => _HiddenInFlight(
    tag: ZoomPart._tag(widget.id, widget.piece),
    child: widget.child,
  );
}

/// The pieces in flight now ([ZoomPart._tag]); in their places they are not
/// drawn meanwhile.
class _InFlight extends ChangeNotifier {
  Set<String> _tags = const {};

  bool contains(String tag) => _tags.contains(tag);

  void set(Set<String> tags) {
    if (setEquals(tags, _tags)) return;
    _tags = tags;
    notifyListeners();
  }
}

final _inFlight = _InFlight();

/// Not drawn while its piece flies ([_InFlight]); laid out as always, so
/// nothing around it moves.
class _HiddenInFlight extends SingleChildRenderObjectWidget {
  const _HiddenInFlight({required this.tag, super.child});

  final String tag;

  @override
  _RenderHiddenInFlight createRenderObject(BuildContext context) =>
      _RenderHiddenInFlight(tag);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHiddenInFlight renderObject,
  ) => renderObject.tag = tag;
}

class _RenderHiddenInFlight extends RenderProxyBox {
  _RenderHiddenInFlight(this._tag);

  String _tag;

  set tag(String value) {
    if (value == _tag) return;
    _tag = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _inFlight.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _inFlight.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_inFlight.contains(_tag)) super.paint(context, offset);
  }
}

/// An article that grows out of its card and goes back into it (#141), as
/// iOS's zoom transition does in Photos and the App Store. The card's box
/// grows to the whole screen, and what the card and its article both show,
/// the headline, the picture, the publisher and the time ([ZoomPart]), flies
/// from its place in the card to its place in the article, growing and
/// changing shape on the way: nothing is swapped in place. The rest of the
/// card goes under the box, and the rest of the article, laid out at full
/// size and scaled to the box's width (no line breaks moving), fades in
/// around the pieces. On the way back, the other way round.
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
    super.settings,
  });

  final WidgetBuilder builder;

  /// The card's box on screen when it was tapped.
  final Rect from;

  /// The colour behind the card (the feed's): the growing box's own, under
  /// the article.
  final Color background;

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

  /// How far the box has grown, as [_CardZoom] draws it: 0 the card, 1 the
  /// whole screen.
  CurvedAnimation? _grown;

  @override
  void install() {
    super.install();
    _grown = CurvedAnimation(
      parent: animation!,
      curve: _curve,
      reverseCurve: _curve.flipped,
    );
    animation!
      ..addListener(_hideCard)
      ..addStatusListener(_statusChanged);
  }

  void _statusChanged(AnimationStatus status) {
    _updateMoving();
    // Open, or back in the card: every piece is in its place again.
    if (!status.isAnimating) _inFlight.set(const {});
  }

  /// The card hides once the growing box covers it, and shows again under the
  /// box on the way back.
  void _hideCard() {
    // The article's first frame is built offstage, for heroes to measure,
    // and its animation stands at the end meanwhile: the card stays, or its
    // place would be empty for that frame.
    if (offstage) return;
    if (_grown!.value > _cardCovered) {
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
    _grown?.dispose();
    _inFlight.set(const {});
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

/// iOS's own curve for a screen moving into place.
const _curve = Cubic(0.32, 0.72, 0, 1);

// The parts of the way from the card (0) to the open article (1), by how far
// the box has grown: the same places, opening or closing.

/// Up to here the card shows through the box, less and less; from here it
/// is covered, and hidden in the feed.
const _cardCovered = 0.4;

/// The article fades in (out, on the way back) from [_cardCovered] to here.
const _pageShown = 0.9;

/// The card's words turn into the article's from here to [_wordsTo].
const _wordsFrom = 0.25;
const _wordsTo = 0.75;

/// 0 before [from], 1 after [to], and in between, how far [t] is.
double _between(double t, double from, double to) =>
    ((t - from) / (to - from)).clamp(0.0, 1.0);

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

  /// The article at full size, where its pieces are measured.
  final _page = GlobalKey();

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
          final flights = widget.animation.isAnimating
              ? _flights(context, t, box, size)
              : const <Widget>[];
          if (flights.isEmpty) _inFlight.set(const {});
          return Stack(
            children: [
              Positioned.fromRect(
                rect: box,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    lerpDouble(_cardRadius, 0, t)! + _shrunkRadius * shrunk,
                  ),
                  clipBehavior: open ? Clip.none : Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _Behind(
                          color: route.background,
                          card: card.shift(-box.topLeft),
                          covered: _between(t, 0, _cardCovered),
                        ),
                      ),
                      Opacity(
                        opacity: _between(t, _cardCovered, _pageShown),
                        // The article keeps its full-size layout: no text
                        // moves to a new line while it grows.
                        child: FittedBox(
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.topCenter,
                          clipBehavior: open ? Clip.none : Clip.hardEdge,
                          child: page,
                        ),
                      ),
                      if (flights.isNotEmpty)
                        IgnorePointer(
                          child: ExcludeSemantics(
                            child: Stack(children: flights),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  /// The pieces the card and its article both show ([ZoomPart]), each where
  /// it is now on its way from the one to the other, in the box; in their
  /// places they are not drawn meanwhile ([_inFlight]). A piece scrolled out
  /// of the article does not fly: it fades with the article.
  List<Widget> _flights(BuildContext context, double t, Rect box, Size size) {
    final page = _page.currentContext?.findRenderObject();
    if (page == null) return const [];
    // The article as it is drawn now: as wide as the box, from its top.
    final scale = box.width / size.width;
    final flying = <String>{};
    final pieces = <Widget>[];
    for (final piece in ZoomPiece.values) {
      final tag = ZoomPart._tag(widget.route.sourceId, piece);
      final card = ZoomPart._find(tag, inCard: true);
      final article = ZoomPart._find(tag, inCard: false);
      if (card == null || article == null) continue;
      if (card._size.isEmpty || article._size.isEmpty) continue;
      final from = card._rectIn();
      final there = article._rectIn(page);
      if (from == null || there == null) continue;
      if (!there.overlaps(Offset.zero & size)) continue;
      final to = Rect.fromLTWH(
        box.left + there.left * scale,
        box.top + there.top * scale,
        there.width * scale,
        there.height * scale,
      );
      final flight = _Flight(
        tag: tag,
        card: card,
        article: article,
        from: from,
        to: to,
        rect: Rect.lerp(from, to, t)!.shift(-box.topLeft),
        t: t,
      );
      flying.add(tag);
      pieces.addAll(
        piece == ZoomPiece.picture
            ? flight.picture(context)
            : flight.words(context),
      );
    }
    _inFlight.set(flying);
    return pieces;
  }
}

/// One piece on its way from the card ([from], on screen) to the article
/// ([to]), now at [rect] in the box, [t] of the way there.
class _Flight {
  _Flight({
    required this.tag,
    required this.card,
    required this.article,
    required this.from,
    required this.to,
    required this.rect,
    required this.t,
  });

  final String tag;
  final _ZoomPartState card;
  final _ZoomPartState article;
  final Rect from;
  final Rect to;
  final Rect rect;
  final double t;

  /// How much the card's piece is scaled where it is (a card held down is a
  /// little smaller), and the article's (as wide as the box).
  double get _cardScale => from.width / card._size.width;
  double get _articleScale => to.width / article._size.width;

  /// A text: the card's words and the article's, each laid out as in its
  /// place, grow together from the card's letter size to the article's, the
  /// one fading into the other half way. "3d ago" becomes the date this way,
  /// and "Ministry · Italy" the ministry.
  List<Widget> words(BuildContext context) {
    var cardFont = card._fontSize;
    var articleFont = article._fontSize;
    if (cardFont == null || articleFont == null) cardFont = articleFont = 1;
    // The letters' size on screen now.
    final font = lerpDouble(
      cardFont * _cardScale,
      articleFont * _articleScale,
      t,
    )!;
    final shown = _between(t, _wordsFrom, _wordsTo);
    Widget drawn(_ZoomPartState part, double scale, double opacity) =>
        Positioned(
          key: ValueKey('$tag/${identical(part, card) ? 'card' : 'article'}'),
          left: rect.left,
          top: rect.top,
          width: part._size.width,
          height: part._size.height,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: part._drawn,
            ),
          ),
        );
    return [
      if (shown < 1) drawn(card, font / cardFont, 1 - shown),
      if (shown > 0) drawn(article, font / articleFont, shown),
    ];
  }

  /// The picture: its box and corners change from the card's to the
  /// article's, so the card's square crop opens into the article's wide one;
  /// the article's picture, decoded sharper, comes in over it.
  List<Widget> picture(BuildContext context) {
    final shown = _between(t, _wordsFrom, _wordsTo);
    return [
      Positioned.fromRect(
        key: ValueKey(tag),
        rect: rect,
        child: ClipRRect(
          borderRadius: BorderRadius.lerp(
            card.widget.radius * _cardScale,
            article.widget.radius * _articleScale,
            t,
          )!,
          child: Stack(
            fit: StackFit.expand,
            children: [
              card._drawn,
              if (shown > 0)
                Opacity(opacity: shown, child: article._drawn),
            ],
          ),
        ),
      ),
    ];
  }
}

/// The growing box's background: the card shows through it at first
/// ([covered] 0), then less and less, while everywhere else the box covers
/// the feed.
class _Behind extends CustomPainter {
  _Behind({required this.color, required this.card, required this.covered});

  final Color color;

  /// The card's place in the box.
  final Rect card;

  /// How much of the card it covers: 0 none, 1 all.
  final double covered;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final fill = Paint()..color = color;
    if (covered == 1 || !card.overlaps(box)) {
      canvas.drawRect(box, fill);
      return;
    }
    // One layer with a hole, so no seam shows around the card.
    canvas
      ..saveLayer(box, Paint())
      ..drawRect(box, fill)
      ..drawRect(
        card,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 1 - covered)
          ..blendMode = BlendMode.dstOut,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_Behind old) =>
      old.color != color || old.card != card || old.covered != covered;
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
