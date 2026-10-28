import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/glass.dart';
import '../../core/motion.dart';
import '../../core/pictures.dart';

/// An article's picture full screen (#141): it flies there from the article,
/// two fingers zoom in, and a swipe down (or the close button) puts it back.
class PictureViewer extends StatefulWidget {
  const PictureViewer({super.key, required this.url, required this.articleId});

  final String url;
  final String articleId;

  /// Over the article, which shows through as the picture is swiped away.
  static Route<void> route({required String url, required String articleId}) =>
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Motion.slow,
        reverseTransitionDuration: Motion.base,
        pageBuilder: (_, _, _) => PictureViewer(url: url, articleId: articleId),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  @override
  State<PictureViewer> createState() => _PictureViewerState();
}

class _PictureViewerState extends State<PictureViewer>
    with SingleTickerProviderStateMixin {
  final _zoom = TransformationController();

  /// How far the picture has been swiped down (or up), in points.
  double _drag = 0;

  /// Where a swipe let go short of closing, springing back from.
  double _from = 0;
  late final AnimationController _settle;

  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  /// A swipe this far, or this fast, closes the picture.
  static const _closeAfter = 120.0;
  static const _closeFaster = 800.0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: Motion.slow)
      ..addListener(
        () => setState(
          () => _drag = _from * (1 - Motion.spring.transform(_settle.value)),
        ),
      );
  }

  @override
  void dispose() {
    _settle.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _close() {
    Haptics.light();
    Navigator.of(context).maybePop();
  }

  void _dragEnd(DragEndDetails details) {
    if (_drag.abs() > _closeAfter ||
        details.velocity.pixelsPerSecond.dy.abs() > _closeFaster) {
      _close();
      return;
    }
    _from = _drag;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final away = (_drag.abs() / 400).clamp(0.0, 1.0);
    final padding = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 1 - away * 0.8),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Zoomed in, a finger moves the picture instead.
              onVerticalDragUpdate: _zoomed
                  ? null
                  : (d) => setState(() => _drag += d.delta.dy),
              onVerticalDragEnd: _zoomed ? null : _dragEnd,
              child: Transform.translate(
                offset: Offset(0, _drag),
                child: InteractiveViewer(
                  transformationController: _zoom,
                  panEnabled: _zoomed,
                  maxScale: 4,
                  onInteractionEnd: (_) => setState(() {}),
                  child: Center(
                    child: PictureHero(
                      articleId: widget.articleId,
                      url: widget.url,
                      child: Image(
                        image: screenPicture(context, widget.url),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: padding.top + 6,
            right: 12,
            child: Opacity(
              opacity: 1 - away,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
                onPressed: _close,
                child: GlassCircle(
                  size: 48,
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 18,
                    color: CupertinoColors.white,
                    semanticLabel: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
