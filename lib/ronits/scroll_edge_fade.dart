import 'package:flutter/material.dart';
import 'motion.dart';
import 'prepared_backdrop_scope.dart';

/// Fade only edges that have more content beyond them. The child remains stable
/// as scrolling changes the mask, preserving focus and scroll positions.
class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.axis = Axis.vertical,
    this.extent = 28,
    this.backdropFade = true,
    this.edgePadding = 0,
  });
  final Widget child;
  final Axis axis;
  final double extent;
  final bool backdropFade;

  /// Leading/trailing scroll padding contains no artwork to fade away.
  final double edgePadding;
  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  final _viewport = GlobalKey();
  final _content = GlobalKey();
  Offset _edges = Offset.zero;
  void _update(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != widget.axis) return;
    final edges = Offset(
      metrics.extentBefore > widget.edgePadding + 1 ? 1 : 0,
      metrics.extentAfter > widget.edgePadding + 1 ? 1 : 0,
    );
    if (edges != _edges) setState(() => _edges = edges);
  }

  @override
  Widget build(BuildContext context) {
    final backdrop = PreparedBackdropScope.of(context);
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (event) {
        _update(event.metrics, event.depth);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          _update(event.metrics, event.depth);
          return false;
        },
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(end: _edges),
          duration: motionReduced(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          child: RepaintBoundary(key: _content, child: widget.child),
          builder: (_, edges, child) {
            // An all-white mask still allocates an offscreen layer. Keep the
            // content identity when introducing/removing the mask as overflow changes.
            if (edges == Offset.zero) return child!;
            return backdrop != null && widget.backdropFade
                ? CustomPaint(
                    key: _viewport,
                    foregroundPainter: _BackdropEdgePainter(
                      backdrop,
                      _viewport,
                      widget.axis,
                      widget.extent,
                      edges,
                    ),
                    child: child,
                  )
                : ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) {
                      final length = widget.axis == Axis.horizontal
                          ? bounds.width
                          : bounds.height;
                      final stop = length <= 0
                          ? 0.0
                          : (widget.extent / length).clamp(0.0, .49);
                      return LinearGradient(
                        begin: widget.axis == Axis.horizontal
                            ? Alignment.centerLeft
                            : Alignment.topCenter,
                        end: widget.axis == Axis.horizontal
                            ? Alignment.centerRight
                            : Alignment.bottomCenter,
                        stops: [0, stop, 1 - stop, 1],
                        colors: [
                          Colors.white.withValues(alpha: 1 - edges.dx),
                          Colors.white,
                          Colors.white,
                          Colors.white.withValues(alpha: 1 - edges.dy),
                        ],
                      ).createShader(bounds);
                    },
                    child: child,
                  );
          },
        ),
      ),
    );
  }
}

class _BackdropEdgePainter extends CustomPainter {
  _BackdropEdgePainter(
    this.backdrop,
    this.viewport,
    this.axis,
    this.extent,
    this.edges,
  );
  final PreparedBackdropScope backdrop;
  final GlobalKey viewport;
  final Axis axis;
  final double extent;
  final Offset edges;
  @override
  void paint(Canvas canvas, Size size) {
    final root = backdrop.origin.currentContext?.findRenderObject();
    final view = viewport.currentContext?.findRenderObject();
    if (root is! RenderBox || view is! RenderBox) return;
    final offset = root.globalToLocal(view.localToGlobal(Offset.zero));
    final target = (-offset) & root.size;
    final horizontal = axis == Axis.horizontal;
    final amount = extent.clamp(
      0.0,
      (horizontal ? size.width : size.height) / 2,
    );
    void edge(bool leading, double strength) {
      if (strength <= .001 || amount <= 0) return;
      final rect = horizontal
          ? Rect.fromLTWH(
              leading ? 0 : size.width - amount,
              0,
              amount,
              size.height,
            )
          : Rect.fromLTWH(
              0,
              leading ? 0 : size.height - amount,
              size.width,
              amount,
            );
      canvas.save();
      canvas.clipRect(rect);
      // Only this narrow strip gets an alpha layer, rather than the app grid.
      canvas.saveLayer(rect, Paint());
      if (backdrop.image case final image?) {
        paintImage(
          canvas: canvas,
          rect: target,
          image: image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
        );
      } else {
        canvas.drawRect(rect, Paint()..color = backdrop.fallback);
      }
      final gradient = LinearGradient(
        begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: leading
            ? [Colors.white.withValues(alpha: strength), Colors.transparent]
            : [Colors.transparent, Colors.white.withValues(alpha: strength)],
      );
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = gradient.createShader(rect),
      );
      canvas.restore();
      canvas.restore();
    }

    edge(true, edges.dx);
    edge(false, edges.dy);
  }

  @override
  bool shouldRepaint(_BackdropEdgePainter old) =>
      old.backdrop.image != backdrop.image ||
      old.backdrop.fallback != backdrop.fallback ||
      old.edges != edges ||
      old.axis != axis ||
      old.extent != extent;
}
