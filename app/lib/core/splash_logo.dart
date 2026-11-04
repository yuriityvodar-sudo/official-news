import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The N's way from the splash into the masthead (#141, Roman's pick 1 of
/// `handoff/intro-logo.html`, 4 Nov): where the masthead's N stands, for
/// the splash's N to fly to, and whether it has landed there. Until it has,
/// the masthead's own N stays unseen ([SplashLogoTarget]), so the two never
/// show at once.
class SplashLogo extends InheritedWidget {
  const SplashLogo({
    super.key,
    required this.target,
    required this.landed,
    required super.child,
  });

  /// The masthead's N on the screen, as it last stood; null while there is
  /// none.
  final ValueNotifier<Rect?> target;

  /// Whether the masthead's own N shows: always, but while the splash's N
  /// flies to it.
  final ValueListenable<bool> landed;

  static SplashLogo? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SplashLogo>();

  @override
  bool updateShouldNotify(SplashLogo old) =>
      old.target != target || old.landed != landed;
}

/// The masthead's N ([child]): tells [SplashLogo] where it stands on the
/// screen after each frame it is built in, and shows only once the splash's
/// N has landed there. Outside a [SplashLogo], [child] as it is.
class SplashLogoTarget extends StatefulWidget {
  const SplashLogoTarget({super.key, required this.child});

  final Widget child;

  @override
  State<SplashLogoTarget> createState() => _SplashLogoTargetState();
}

class _SplashLogoTargetState extends State<SplashLogoTarget> {
  void _report() {
    if (!mounted) return;
    final target = context.getInheritedWidgetOfExactType<SplashLogo>()?.target;
    final box = context.findRenderObject();
    if (target == null || box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    // As drawn: through the masthead's own scaling.
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    if (target.value != rect) target.value = rect;
  }

  @override
  Widget build(BuildContext context) {
    final logo = SplashLogo.of(context);
    if (logo == null) return widget.child;
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return ValueListenableBuilder<bool>(
      valueListenable: logo.landed,
      child: widget.child,
      builder: (context, landed, child) =>
          Opacity(opacity: landed ? 1 : 0, child: child),
    );
  }
}
