import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

/// Opens the screen [scrollableBuilder] builds as Flutter's sheet, on the
/// app's root navigator, as `showCupertinoSheet` does: every sheet in the app
/// opens here, through [SheetRoute].
Future<T?> showSheet<T>({
  required BuildContext context,
  required ScrollableWidgetBuilder scrollableBuilder,
}) => Navigator.of(
  context,
  rootNavigator: true,
).push<T>(SheetRoute<T>(scrollableBuilder: scrollableBuilder));

/// Flutter's sheet, with one change: the screen under it shrinks through a
/// transform, not an image filter ([_underSheet]), and so does a sheet under
/// a new sheet ([_CoveredSheet]). iOS's own views there (the glass,
/// `GlassCircle`) follow a transform but not a filter
/// (flutter/flutter#169495). With the filter, the AI chat opened over an
/// article showed only the top of its header and its composer, the glass
/// staying iOS's under it (TestFlight 55, Roman, 30 Oct).
class SheetRoute<T> extends CupertinoSheetRoute<T> {
  SheetRoute({required super.scrollableBuilder, super.settings});

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _underSheet;

  /// Flutter's own transitions with a dismissed secondary animation, as if
  /// no sheet ever came over this one: [_CoveredSheet] moves it instead.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _CoveredSheet(
    covered: secondaryAnimation,
    child: super.buildTransitions(
      context,
      animation,
      kAlwaysDismissedAnimation,
      child,
    ),
  );
}

/// A sheet as a new sheet comes over it: up by 0.5% of its height and
/// shrunk as the screen under a sheet ([_scale]), around its own top, 8% down
/// the screen, as Flutter's `CupertinoSheetTransition` moves it inside the
/// sheet's top gap, through a transform rather than its image filter.
class _CoveredSheet extends StatefulWidget {
  const _CoveredSheet({required this.covered, required this.child});

  final Animation<double> covered;
  final Widget child;

  @override
  State<_CoveredSheet> createState() => _CoveredSheetState();
}

class _CoveredSheetState extends State<_CoveredSheet> {
  late CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _curve = _curveOf(widget.covered);
  }

  @override
  void didUpdateWidget(_CoveredSheet old) {
    super.didUpdateWidget(old);
    if (old.covered == widget.covered) return;
    _curve.dispose();
    _curve = _curveOf(widget.covered);
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  static CurvedAnimation _curveOf(Animation<double> covered) => CurvedAnimation(
    curve: Curves.linearToEaseOut,
    reverseCurve: Curves.easeInToLinear,
    parent: covered,
  );

  @override
  Widget build(BuildContext context) => SlideTransition(
    // Flutter's 0.5% is of the sheet below its 8% top gap.
    position: _curve.drive(
      Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.005 * 0.92)),
    ),
    transformHitTests: false,
    child: ScaleTransition(
      scale: _curve.drive(_scale),
      alignment: const Alignment(0, -1 + 2 * 0.08),
      child: widget.child,
    ),
  );
}

/// How much the screen under a sheet shrinks, as in Flutter.
final Animatable<double> _scale = Tween<double>(begin: 1, end: 1 - 0.0835);

/// The screen under a sheet: Flutter's own
/// `CupertinoSheetTransition.delegateTransition` (SDK 3.44.6), without its
/// `filterQuality: FilterQuality.medium`, so [ScaleTransition] shrinks the
/// screen through a transform. This is Flutter's own fix (`hasPlatformView`
/// in the cupertino_ui package, flutter/packages#12565), not in our SDK. The
/// rest is as in Flutter: the screen slides down by 7% and shrinks by 8.35%,
/// its corners go from the phone's own to 12 points and it darkens a little;
/// a sheet under the new one moves up and shrinks instead.
Widget _underSheet(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  bool allowSnapshotting,
  Widget? child,
) {
  if (CupertinoSheetRoute.hasParentSheet(context)) {
    return _sheetUnderSheet(secondaryAnimation, child);
  }
  final linear = Navigator.of(context).userGestureInProgress;
  final curvedAnimation = CurvedAnimation(
    curve: linear ? Curves.linear : Curves.linearToEaseOut,
    reverseCurve: linear ? Curves.linear : Curves.easeInToLinear,
    parent: secondaryAnimation,
  );

  final deviceCornerRadius =
      (MediaQuery.maybeViewPaddingOf(context)?.top ?? 0) * 0.9;
  final roundedDeviceCorners = deviceCornerRadius > 20;
  final radiusAnimation = curvedAnimation.drive(
    Tween<BorderRadiusGeometry>(
      begin: BorderRadius.vertical(
        top: Radius.circular(roundedDeviceCorners ? deviceCornerRadius : 0),
      ),
      end: const BorderRadius.all(Radius.circular(12)),
    ),
  );
  final opacityAnimation = curvedAnimation.drive(
    Tween<double>(begin: 0, end: 0.10),
  );
  final slideAnimation = curvedAnimation.drive(
    Tween<Offset>(begin: Offset.zero, end: const Offset(0, 0.07)),
  );
  final scaleAnimation = curvedAnimation.drive(_scale);
  curvedAnimation.dispose();

  final isDarkMode = CupertinoTheme.brightnessOf(context) == Brightness.dark;
  final overlayColor = isDarkMode
      ? const Color(0xFFc8c8c8)
      : const Color(0xFF000000);
  final contrastedChild = child != null && !secondaryAnimation.isDismissed
      ? Stack(
          children: [
            child,
            FadeTransition(
              opacity: opacityAnimation,
              child: ColoredBox(
                color: overlayColor,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        )
      : child;

  final topGapHeight = MediaQuery.sizeOf(context).height * 0.08;
  return Stack(
    children: [
      AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
        child: SizedBox(height: topGapHeight, width: double.infinity),
      ),
      SlideTransition(
        position: slideAnimation,
        child: ScaleTransition(
          scale: scaleAnimation,
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: radiusAnimation,
            child: child,
            builder: (context, child) => ClipRSuperellipse(
              borderRadius: !secondaryAnimation.isDismissed
                  ? radiusAnimation.value
                  : BorderRadius.zero,
              child: contrastedChild,
            ),
          ),
        ),
      ),
    ],
  );
}

/// A sheet under a new sheet, as Flutter moves it (its
/// `_delegatedCoverSheetSecondaryTransition`), through a transform too.
Widget _sheetUnderSheet(Animation<double> secondaryAnimation, Widget? child) {
  final curvedAnimation = CurvedAnimation(
    curve: Curves.linearToEaseOut,
    reverseCurve: Curves.easeInToLinear,
    parent: secondaryAnimation,
  );
  final slideAnimation = curvedAnimation.drive(
    Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.005)),
  );
  final scaleAnimation = curvedAnimation.drive(_scale);
  curvedAnimation.dispose();

  return SlideTransition(
    position: slideAnimation,
    transformHitTests: false,
    child: ScaleTransition(
      scale: scaleAnimation,
      alignment: Alignment.topCenter,
      child: ClipRSuperellipse(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: child,
      ),
    ),
  );
}
