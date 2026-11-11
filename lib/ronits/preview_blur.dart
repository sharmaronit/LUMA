// Static wallpaper blur for the browser preview; no live BackdropFilter passes.
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'glass_surface.dart';
import 'shared_blur_cache.dart';
import 'wallpaper_image.dart';

class PreviewBlurStore {
  final _cache = SharedBlurCache();
  String _asset = 'assets/mountain.jpg';
  String get asset => _asset;
  set asset(String value) {
    if (_asset == value) return;
    _asset = value;
    _cache.clear();
  }

  Future<ui.Image> acquire(double sigma, double saturation, Size screen) =>
      _cache.acquire(
        (asset, sigma <= 8 ? 8.0 : 24.0, saturation, screen),
        () async {
          const width = 640, height = 360;
          final source = await _resolve(
            ResizeImage(
              wallpaperImage(asset),
              width: width,
              height: height,
              policy: ResizeImagePolicy.fit,
            ),
          );
          ui.Picture? picture;
          try {
            const rect = Rect.fromLTWH(0, 0, 640, 360);
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            final blur = (sigma <= 8 ? 8.0 : 24.0) * width / screen.width;
            canvas.saveLayer(
              rect,
              Paint()
                ..imageFilter = ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.clamp,
                )
                ..colorFilter = glassSaturation(saturation),
            );
            paintImage(
              canvas: canvas,
              rect: rect,
              image: source,
              fit: BoxFit.cover,
            );
            canvas.restore();
            picture = recorder.endRecording();
            return await picture.toImage(width, height);
          } finally {
            source.dispose();
            picture?.dispose();
          }
        },
      );
  void dispose() => _cache.dispose();
  Future<ui.Image> _resolve(ImageProvider provider) {
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
}

class PreviewCachedBackdrop extends StatefulWidget {
  const PreviewCachedBackdrop({
    super.key,
    required this.store,
    required this.sigma,
    required this.saturation,
    required this.child,
  });
  final PreviewBlurStore store;
  final double sigma, saturation;
  final Widget child;
  @override
  State<PreviewCachedBackdrop> createState() => _PreviewCachedBackdropState();
}

class _PreviewCachedBackdropState extends State<PreviewCachedBackdrop> {
  ui.Image? _image;
  Object? _key;
  int _generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(PreviewCachedBackdrop old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final screen = MediaQuery.sizeOf(context);
    final key = (
      widget.store.asset,
      widget.sigma <= 8 ? 8.0 : 24.0,
      widget.saturation,
      screen,
    );
    if (key == _key) return;
    _key = key;
    final generation = ++_generation;
    widget.store.acquire(widget.sigma, widget.saturation, screen).then((image) {
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final scroll = Scrollable.maybeOf(context)?.position;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        if (_image != null)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                if (route?.animation != null) route!.animation!,
                if (scroll != null) scroll,
              ]),
              builder: (context, _) => _PreviewBlit(
                image: _image!,
                navigator:
                    Navigator.of(context).context.findRenderObject()
                        as RenderBox,
              ),
            ),
          ),
        widget.child,
      ],
    );
  }
}

class _PreviewBlit extends LeafRenderObjectWidget {
  const _PreviewBlit({required this.image, required this.navigator});
  final ui.Image image;
  final RenderBox navigator;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PreviewBlitRender(image, navigator);
  @override
  void updateRenderObject(
    BuildContext context,
    _PreviewBlitRender renderObject,
  ) {
    renderObject.image = image;
    renderObject.navigator = navigator;
    renderObject.markNeedsPaint();
  }
}

class _PreviewBlitRender extends RenderBox {
  _PreviewBlitRender(this.image, this.navigator);
  ui.Image image;
  RenderBox navigator;
  @override
  bool get sizedByParent => true;
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;
  @override
  void paint(PaintingContext context, Offset offset) {
    final bounds = MatrixUtils.transformRect(
      getTransformTo(navigator),
      Offset.zero & size,
    );
    final screen = navigator.size;
    final src = Rect.fromLTWH(
      bounds.left * image.width / screen.width,
      bounds.top * image.height / screen.height,
      bounds.width * image.width / screen.width,
      bounds.height * image.height / screen.height,
    );
    context.canvas.drawImageRect(
      image,
      src,
      offset & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }
}
