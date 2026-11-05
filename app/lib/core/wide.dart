import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The iPad and other wide windows (#137; Roman's pick A of
/// `handoff/ipad-layout.html`, 5 Nov: like Apple News): the feed in columns,
/// an article, the AI chat and the lists in a column in the middle. On
/// iPadOS 26 a window can take any width, so the layout follows the
/// window's width, never the device: a narrow window is laid out as a phone.

/// How many columns of cards the feed has in a window [width] points wide:
/// one up to 700 (a phone, a narrow iPad window), two up to 1100, three wider.
int feedColumns(double width) => width < 700
    ? 1
    : width < 1100
    ? 2
    : 3;

/// Whether a window [width] points wide is laid out wide: the feed in
/// columns, the rest in a column in the middle.
bool isWide(double width) => feedColumns(width) > 1;

/// How wide a column of reading is at most in a wide window: an article,
/// Settings, the Conversations.
const readableWidth = 680.0;

/// The AI chat's column, a little wider: its questions stand at the right.
const chatWidth = 720.0;

/// A sheet's column: the paywall, the top-up sheet.
const sheetWidth = 640.0;

/// The margin on each side that keeps a column at most [maxWidth] wide in
/// the middle of a window [width] wide; none in a window not laid out wide.
double sideMargin(double width, {double maxWidth = readableWidth}) =>
    isWide(width) ? math.max(0, (width - maxWidth) / 2) : 0;

/// [child] in a column at most [maxWidth] wide in the middle of a wide
/// window; as it is anywhere else. The column is measured in the space
/// [child] is given, so one inside another (a sheet's, the chat's) adds
/// nothing.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    this.maxWidth = readableWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(MediaQuery.sizeOf(context).width);
    // Always the same widgets, so a window that turns wide keeps the page's state.
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: wide
              ? math.max(0, (constraints.maxWidth - maxWidth) / 2)
              : 0,
        ),
        child: child,
      ),
    );
  }
}

/// A whole page, [child], in a column in the middle of a wide window, the
/// page's [color] on each side ([ReadableWidth]): Settings, the
/// Conversations, an info page, the AI chat, a sheet.
class ReadablePage extends StatelessWidget {
  const ReadablePage({
    super.key,
    required this.color,
    this.maxWidth = readableWidth,
    required this.child,
  });

  final Color color;
  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: ReadableWidth(maxWidth: maxWidth, child: child),
  );
}

/// Cards side by side, all as tall as the tallest, as Apple News lines up
/// its stories (#137): `spans[i]` of the row's [columns] columns for
/// `children[i]`, [gap] apart. A last row may leave columns empty at its end.
class CardRow extends MultiChildRenderObjectWidget {
  const CardRow({
    super.key,
    required this.columns,
    required this.spans,
    this.gap = 12,
    required super.children,
  }) : assert(spans.length == children.length);

  final int columns;
  final List<int> spans;
  final double gap;

  @override
  RenderCardRow createRenderObject(BuildContext context) =>
      RenderCardRow(columns: columns, spans: spans, gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderCardRow renderObject) =>
      renderObject
        ..columns = columns
        ..spans = spans
        ..gap = gap;
}

class _CardRowData extends ContainerBoxParentData<RenderBox> {}

/// [CardRow]'s render object.
class RenderCardRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CardRowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardRowData> {
  RenderCardRow({
    required this._columns,
    required this._spans,
    required this._gap,
  });

  int _columns;
  set columns(int value) {
    if (value == _columns) return;
    _columns = value;
    markNeedsLayout();
  }

  List<int> _spans;
  set spans(List<int> value) {
    if (listEquals(value, _spans)) return;
    _spans = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardRowData) child.parentData = _CardRowData();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final column = (width - _gap * (_columns - 1)) / _columns;
    double widthOf(int span) => column * span + _gap * (span - 1);
    // Each card at its own height first, then every one at the tallest's.
    var tallest = 0.0;
    var child = firstChild;
    var i = 0;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: widthOf(_spans[i])),
        parentUsesSize: true,
      );
      tallest = math.max(tallest, child.size.height);
      child = childAfter(child);
      i++;
    }
    var x = 0.0;
    child = firstChild;
    i = 0;
    while (child != null) {
      final w = widthOf(_spans[i]);
      child.layout(
        BoxConstraints.tightFor(width: w, height: tallest),
        parentUsesSize: true,
      );
      (child.parentData! as _CardRowData).offset = Offset(x, 0);
      x += w + _gap;
      child = childAfter(child);
      i++;
    }
    size = constraints.constrain(Size(width, tallest));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
