import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'shared_blur_cache.dart';
import 'prepared_backdrop_scope.dart';

const _wallpaperContrast = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x99000000), Color(0x66000000), Color(0x88000000)],
  stops: [0, .32, 1],
);

/// One small blurred texture, retained by Home and reused when All apps reopens.
class CachedWallpaperBackground extends StatefulWidget {
  const CachedWallpaperBackground({
    super.key,
    required this.wallpaper,
    required this.cache,
    this.revision = 0,
    this.child,
    this.enabled = true,
    this.fallback = const Color(0xff20262b),
  });
  final ImageProvider wallpaper;
  final SharedBlurCache cache;
  final int revision;
  final Widget? child;
  final bool enabled;
  final Color fallback;
  @override
  State<CachedWallpaperBackground> createState() =>
      _CachedWallpaperBackgroundState();
}

class _CachedWallpaperBackgroundState extends State<CachedWallpaperBackground> {
  ui.Image? image;
  Object? request;
  int generation = 0;
  final _origin = GlobalKey();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  @override
  void didUpdateWidget(CachedWallpaperBackground old) {
    super.didUpdateWidget(old);
    load();
  }

  void load() {
    if (!widget.enabled) return;
    final screen = MediaQuery.sizeOf(context);
    final height = (640 / screen.aspectRatio).round().clamp(1, 640);
    final key = (widget.wallpaper, widget.revision, screen, 640, height);
    if (request == key) return;
    request = key;
    final ticket = ++generation;
    final provider = widget.wallpaper;
    widget.cache
        .acquire(key, () async {
          final source = await resolve(
            ResizeImage(
              provider,
              width: 640,
              height: height,
              policy: ResizeImagePolicy.fit,
            ),
          );
          ui.Picture? picture;
          try {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            final rect = Rect.fromLTWH(0, 0, 640, height.toDouble());
            final blur = 24 * 640 / screen.width;
            canvas.saveLayer(
              rect,
              Paint()
                ..imageFilter = ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.clamp,
                ),
            );
            paintImage(
              canvas: canvas,
              rect: rect,
              image: source,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            );
            canvas.restore();
            // Bake the fixed contrast into the blur texture, avoiding another
            // full-screen gradient shader during app-grid navigation.
            canvas.drawRect(
              rect,
              Paint()..shader = _wallpaperContrast.createShader(rect),
            );
            picture = recorder.endRecording();
            return await picture.toImage(640, height);
          } finally {
            source.dispose();
            picture?.dispose();
          }
        })
        .then(
          (value) {
            if (!mounted || ticket != generation) {
              value.dispose();
              return;
            }
            setState(() {
              image?.dispose();
              image = value;
            });
          },
          onError: (Object _, StackTrace __) {
            // Keep the quiet fallback surface if a custom image is unavailable.
          },
        );
  }

  Future<ui.Image> resolve(ImageProvider provider) {
    final result = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        result.complete(info.image.clone());
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        result.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return result.future;
  }

  @override
  void dispose() {
    generation++;
    image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PreparedBackdropScope(
    image: widget.enabled ? image : null,
    origin: _origin,
    fallback: widget.fallback,
    child: RepaintBoundary(
      child: ColoredBox(
        color: widget.fallback,
        child: Stack(
          key: _origin,
          fit: StackFit.expand,
          children: [
            if (widget.enabled && image != null)
              RawImage(
                image: image,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              ),
            if (widget.enabled && image == null)
              const DecoratedBox(
                decoration: BoxDecoration(gradient: _wallpaperContrast),
              ),
            if (widget.child != null) widget.child!,
          ],
        ),
      ),
    ),
  );
}
