import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import 'theme.dart';

/// How the feed shows the articles already read. Yurii compared the styles
/// in the prototype (16 Oct) and chose none at all (20 Oct): a read article
/// looks like any other. The others stay for a build to try
/// (`--dart-define=READ_STYLE=blue`).
enum ReadStyle {
  /// Nothing: a read article stays as it is, in its full colours, with the
  /// official-source tick.
  none,

  /// Today's: a read article fades, its text and its picture.
  dim,

  /// A small blue dot (iOS's systemBlue) on an article not opened yet, in
  /// place of the official-source tick; it goes once the article is opened.
  blue,

  /// The same dot in the app's red.
  red,
}

/// What a row shows of an article having been read, in [style].
@immutable
class ReadMark {
  const ReadMark(this.style, {required this.read});

  final ReadStyle style;
  final bool read;

  /// Faded, as today: a read article in [ReadStyle.dim].
  bool get dimmed => read && style == ReadStyle.dim;

  /// The dot styles: the row keeps the dot's place, read or not, so nothing
  /// on its line moves when the dot goes. The official-source tick is not
  /// shown then: every source is official, and the dot takes its place.
  bool get dots => style == ReadStyle.blue || style == ReadStyle.red;

  /// Not opened yet, in a dot style: the dot shows, VoiceOver says "Unread".
  bool get unread => dots && !read;

  /// A read article's red marks (C's importance rule) turn grey: in Dim, as
  /// today, and in Red, where red on a row must mean "not opened yet". In
  /// Blue they keep their red: it is not the dot's colour there.
  bool get greyAccent =>
      read && (style == ReadStyle.dim || style == ReadStyle.red);

  /// The dot's colour. [red] is the look's own red for Red, where it has one
  /// (B's deeper red in light mode), so a screen has one red, not two.
  Color color(BuildContext context, {Color? red}) => style == ReadStyle.red
      ? red ?? AppColors.accent
      : CupertinoColors.systemBlue.resolveFrom(context);
}

/// The dot's size, and the room on each side of it on a line of text.
const unreadDotSize = 8.0;
const _gap = 4.0;

/// The dot grows with the reader's text size up to 1.4x, as the official-source
/// tick does: it is a mark, not text.
const _maxGrow = 1.4;

/// The dot in a row of widgets ([PublisherLine]), after [gap] points: a
/// filled circle for an unread article, the same room left empty for a read
/// one. The row centres it on the line. It grows with the reader's text size
/// as the text of [fontSize] it follows does, up to 1.4x, and so does the
/// gap. VoiceOver does not read it: the row's own value says "Unread".
class UnreadDot extends StatelessWidget {
  const UnreadDot(this.mark, {super.key, required this.fontSize, this.gap = 5});

  final ReadMark mark;
  final double fontSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final grow = math.min(
      MediaQuery.textScalerOf(context).scale(fontSize) / fontSize,
      _maxGrow,
    );
    final size = unreadDotSize * grow;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: gap * grow),
      child: mark.unread
          ? _circle(size, mark.color(context))
          : SizedBox.square(dimension: size),
    );
  }
}

/// A filled circle; a DecoratedBox, no layer of its own.
Widget _circle(double size, Color color) => SizedBox.square(
  dimension: size,
  child: DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  ),
);

/// The dot inside a line of text, between two words ("GERMANY ● Federal
/// Government") or after the last one ([trailing]). It is always the same
/// width, so the words after it stay where they are when it goes.
///
/// [fontSize] is the size of the text it follows and [scaler] the line's:
/// Flutter scales an inline widget with its text, so the dot is drawn smaller
/// to grow only to 1.4x. Its middle sits about at the middle of a capital
/// letter (half a point lower, measured on the iPhone 16e).
/// A read article shows nothing in its place, or [separator], a small round
/// dot in that colour, for a line whose words are otherwise separated by " · ".
/// [red] is the look's own red for Red ([ReadMark.color]).
/// VoiceOver does not read it: the card's own label says "Unread".
InlineSpan unreadDotSpan(
  BuildContext context,
  ReadMark mark, {
  required double fontSize,
  required TextScaler scaler,
  Color? separator,
  Color? red,
  bool trailing = false,
}) {
  final grow = scaler.scale(fontSize) / fontSize;
  final keep = math.min(grow, _maxGrow) / grow;
  final dot = unreadDotSize * keep;
  final gap = _gap * keep;
  // Measured from the baseline, in the text's own (unscaled) points.
  final middle = 0.35 * fontSize;
  final Widget? shown;
  final double top;
  if (mark.unread) {
    shown = _circle(dot, mark.color(context, red: red));
    top = middle + dot / 2;
  } else if (separator != null) {
    // About the size and height of the " · " it stands for.
    final size = 0.2 * fontSize;
    shown = _circle(size, separator);
    top = 0.3 * fontSize + size / 2;
  } else {
    shown = null;
    top = middle + dot / 2;
  }
  final slot = SizedBox(
    width: (trailing ? gap : 2 * gap) + dot,
    height: top,
    child: shown == null
        ? null
        : Align(
            alignment: trailing ? Alignment.topRight : Alignment.topCenter,
            child: shown,
          ),
  );
  return WidgetSpan(
    // Its bottom on the line's baseline, whatever the line's height.
    alignment: PlaceholderAlignment.aboveBaseline,
    baseline: TextBaseline.alphabetic,
    style: TextStyle(fontSize: fontSize),
    child: slot,
  );
}
