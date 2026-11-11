import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Bake the stationary wallpaper tint and contrast ramp once. Scrolling blends
/// two prepared endpoints instead of shading the full TV screen every frame.
class GlassWallpaper extends StatefulWidget {
  const GlassWallpaper({
    super.key,
    required this.image,
    required this.scroll,
    this.onDimPrepared,
  });
  final ImageProvider image;
  final ScrollController scroll;
  final ValueChanged<ui.Image>? onDimPrepared;
  @override
  State<GlassWallpaper> createState() => _GlassWallpaperState();
}

class _GlassWallpaperState extends State<GlassWallpaper> {
  ui.Image? _normal, _dim;
  Object? _request;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(GlassWallpaper old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = (size.width * dpr).round();
    final height = (size.height * dpr).round();
    final key = (widget.image, width, height);
    if (key == _request || width <= 0 || height <= 0) return;
    _request = key;
    final ticket = ++_generation;
    _prepare(widget.image, width, height).then(
      (images) {
        if (!mounted || ticket != _generation) {
          for (final image in images) {
            image.dispose();
          }
          return;
        }
        setState(() {
          _normal?.dispose();
          _dim?.dispose();
          _normal = images[0];
          _dim = images[1];
        });
        if (widget.onDimPrepared != null) widget.onDimPrepared!(_dim!.clone());
      },
      onError: (Object _, StackTrace __) {
        // Retain the original wallpaper recipe if preparation is unavailable.
      },
    );
  }

  Future<List<ui.Image>> _prepare(
    ImageProvider provider,
    int width,
    int height,
  ) async {
    final source = Completer<ui.Image>();
    final stream = ResizeImage(
      provider,
      width: width,
      height: height,
      policy: ResizeImagePolicy.fit,
    ).resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        source.complete(info.image.clone());
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        source.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    final image = await source.future;
    final images = <ui.Image>[];
    try {
      final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      for (final amount in [0.0, 1.0]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        paintImage(
          canvas: canvas,
          rect: rect,
          image: image,
          fit: BoxFit.cover,
          colorFilter: const ColorFilter.mode(
            Color(0x10000000),
            BlendMode.darken,
          ),
          filterQuality: FilterQuality.low,
        );
        canvas.drawRect(
          rect,
          Paint()..shader = glassWallpaperContrast(amount).createShader(rect),
        );
        final picture = recorder.endRecording();
        try {
          images.add(await picture.toImage(width, height));
        } finally {
          picture.dispose();
        }
      }
      return images;
    } catch (_) {
      for (final image in images) {
        image.dispose();
      }
      rethrow;
    } finally {
      image.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    _normal?.dispose();
    _dim?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_normal == null || _dim == null) {
      return AnimatedBuilder(
        animation: widget.scroll,
        builder: (_, _) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            gradient: glassWallpaperContrast(_contrast(widget.scroll)),
          ),
          child: Image(
            image: widget.image,
            fit: BoxFit.cover,
            color: const Color(0x10000000),
            colorBlendMode: BlendMode.darken,
          ),
        ),
      );
    }
    return CustomPaint(
      key: const ValueKey('prepared-glass-wallpaper'),
      painter: _GlassWallpaperPainter(_normal!, _dim!, widget.scroll),
      child: const SizedBox.expand(),
    );
  }
}

double _contrast(ScrollController scroll) =>
    scroll.hasClients ? (scroll.offset / 240).clamp(0.0, 1.0) : 0;

LinearGradient glassWallpaperContrast(double amount) => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    const Color(0x1407111e),
    Color.lerp(const Color(0x0007111e), const Color(0x6607111e), amount)!,
    Color.lerp(const Color(0x7009101b), const Color(0xb009101b), amount)!,
  ],
  stops: const [0, .35, 1],
);

class _GlassWallpaperPainter extends CustomPainter {
  _GlassWallpaperPainter(this.normal, this.dim, this.scroll)
    : super(repaint: scroll);
  final ui.Image normal, dim;
  final ScrollController scroll;
  @override
  void paint(Canvas canvas, Size size) {
    final amount = _contrast(scroll);
    final source = Rect.fromLTWH(
      0,
      0,
      normal.width.toDouble(),
      normal.height.toDouble(),
    );
    final target = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.low;
    if (amount < 1) canvas.drawImageRect(normal, source, target, paint);
    if (amount > 0) {
      paint.color = Color.fromRGBO(255, 255, 255, amount);
      canvas.drawImageRect(dim, source, target, paint);
    }
  }

  @override
  bool shouldRepaint(_GlassWallpaperPainter old) =>
      old.normal != normal || old.dim != dim || old.scroll != scroll;
}
