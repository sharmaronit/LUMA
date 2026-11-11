/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:math' as math;
import '../providers/settings_service.dart';
import '../ronits/glass_surface.dart' show glassSaturation;
import '../ronits/motion.dart' show MenuSlideTransition;
import 'dart:ui' as ui;

import 'package:luma/providers/wallpaper_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Replaces a live [BackdropFilter] over the (static) wallpaper with a
/// pre-blurred snapshot of the wallpaper that is blitted behind [child].
///
/// A live [BackdropFilter] re-samples and re-blurs the scene on *every*
/// composited frame, which is expensive on low-end GPUs (e.g. Android TV
/// sticks). Because the wallpaper is static, we blur it once into a [ui.Image]
/// and simply copy the region located under this widget each frame — a cheap
/// blit that naturally follows scrolling through the paint offset.
///
/// Uses a wallpaper-scoped shared cache. Performance mode uses two blur strengths
/// at up to 640x360 and never falls back to live blur.
///
/// Full-screen blurred wallpaper layer (no foreground content).
class CachedBlurLayer extends StatefulWidget {
  final double sigma;

  const CachedBlurLayer({super.key, required this.sigma});

  @override
  State<CachedBlurLayer> createState() => _CachedBlurLayerState();
}

class _CachedBlurLayerState
    extends _CachedBlurBackgroundState<CachedBlurLayer> {
  @override
  double get sigma => widget.sigma;

  @override
  Widget buildBlurContent(Widget blurBackground) => blurBackground;

  @override
  Widget buildWithoutBlur() => const SizedBox.expand();

  @override
  Widget buildLiveBlur() => BackdropFilter(
    filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: const SizedBox.expand(),
  );
}

class CachedBlurBackdrop extends StatefulWidget {
  final double sigma;
  final Widget child;
  final double saturation;

  const CachedBlurBackdrop({
    super.key,
    required this.sigma,
    required this.child,
    this.saturation = 1,
  });

  @override
  State<CachedBlurBackdrop> createState() => _CachedBlurBackdropState();
}

class _CachedBlurBackdropState
    extends _CachedBlurBackgroundState<CachedBlurBackdrop> {
  @override
  double get sigma => widget.sigma;

  @override
  Widget buildWithoutBlur() => buildBlurContent(const SizedBox.expand());

  @override
  double get saturation => widget.saturation;

  @override
  Widget buildBlurContent(Widget blurBackground) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: blurBackground),
        widget.child,
      ],
    );
  }

  @override
  Widget buildLiveBlur() => BackdropFilter(
    filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: widget.child,
  );
}

abstract class _CachedBlurBackgroundState<T extends StatefulWidget>
    extends State<T> {
  ui.Image? _blurred;
  Object? _builtKey, _failedKey;
  bool _building = false;
  int _alignmentRevision = 0;
  Animation<double>? _settleAnimation;
  void _settled(AnimationStatus status) {
    if (mounted &&
        (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed)) {
      setState(() => _alignmentRevision++);
    }
  }

  void _watchSettle(Animation<double>? animation) {
    if (identical(animation, _settleAnimation)) return;
    _settleAnimation?.removeStatusListener(_settled);
    _settleAnimation = animation;
    _settleAnimation?.addStatusListener(_settled);
  }

  double get sigma;
  double get saturation => 1;
  Widget buildBlurContent(Widget blurBackground);
  Widget buildLiveBlur();
  Widget buildWithoutBlur();

  @override
  void dispose() {
    _settleAnimation?.removeStatusListener(_settled);
    _blurred?.dispose();
    super.dispose();
  }

  Future<void> _build(
    WallpaperService service,
    Size screen,
    double dpr,
    double blur,
    double colorSaturation,
    Object key,
  ) async {
    if (_building) return;
    _building = true;
    final glassTheme = [
      'glass',
      'glass-real',
    ].contains(context.read<SettingsService>().minimalBackground);
    final provider =
        service.wallpaper ??
        (glassTheme ? const AssetImage('assets/mountain.jpg') : null);
    final gradient = service.gradient.gradient;
    final width = (screen.width * dpr).round(),
        height = (screen.height * dpr).round();
    try {
      final image = await service.sharedBlurCache.acquire(key, () async {
        ui.Image? source;
        ui.Picture? picture;
        try {
          if (provider != null)
            source = await _resolveImage(
              ResizeImage(
                provider,
                width: width,
                height: height,
                policy: ResizeImagePolicy.fit,
              ),
            );
          final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          final paint = Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: blur * dpr,
              sigmaY: blur * dpr,
              tileMode: TileMode.clamp,
            )
            ..colorFilter = glassSaturation(colorSaturation);
          canvas.saveLayer(rect, paint);
          if (source != null) {
            paintImage(
              canvas: canvas,
              rect: rect,
              image: source,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            );
          } else {
            canvas.drawRect(
              rect,
              Paint()..shader = gradient.createShader(rect),
            );
          }
          canvas.restore();
          picture = recorder.endRecording();
          return await picture.toImage(width, height);
        } finally {
          source?.dispose();
          picture?.dispose();
        }
      });
      if (!mounted) {
        image.dispose();
        return;
      }
      _blurred?.dispose();
      _blurred = image;
      _builtKey = key;
    } catch (_) {
      _failedKey = key;
    } finally {
      _building = false;
      if (mounted) setState(() {});
    }
  }

  Future<ui.Image> _resolveImage(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete(info.image.clone());
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        completer.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<WallpaperService>();
    final performance = context.select<SettingsService, bool>(
      (settings) =>
          settings.performanceMode ||
          ['glass', 'glass-real'].contains(settings.minimalBackground),
    );
    if (service.wallpaperVideoFile != null)
      return performance ? buildWithoutBlur() : buildLiveBlur();
    final screen = MediaQuery.sizeOf(context);
    if (screen.isEmpty) return buildWithoutBlur();
    final maxWidth = performance ? 640.0 : 1280.0;
    final maxHeight = performance ? 360.0 : 720.0;
    final dpr = math.min(
      MediaQuery.devicePixelRatioOf(context),
      math.min(maxWidth / screen.width, maxHeight / screen.height),
    );
    // Texture resolution may change; the visible blur radius stays consistent.
    final blur = sigma;
    final revision = service.wallpaperRevision;
    final key = (
      revision,
      [
        'glass',
        'glass-real',
      ].contains(context.read<SettingsService>().minimalBackground),
      service.wallpaper,
      service.wallpaper == null ? service.gradient.uuid : null,
      (screen.width * dpr).round(),
      (screen.height * dpr).round(),
      blur * dpr,
      saturation,
    );
    if (_builtKey != key && _failedKey != key && !_building) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && service.wallpaperRevision == revision)
          _build(service, screen, dpr, blur, saturation, key);
      });
    }
    final image = _blurred;
    if (image == null)
      return performance ? buildWithoutBlur() : buildLiveBlur();
    // Retain a prepared texture during a quality/wallpaper refresh, avoiding a flash.
    final route = ModalRoute.of(context);
    final scroll = Scrollable.maybeOf(context)?.position;
    final slideOnly =
        context.findAncestorWidgetOfExactType<MenuSlideTransition>() != null;
    // Repainting this texture on every route tick invalidates the glass cache.
    // Carry it with the short slide, then align it once at the endpoint.
    _watchSettle(slideOnly ? route?.animation : null);
    return buildBlurContent(
      AnimatedBuilder(
        animation: Listenable.merge([
          if (!slideOnly && route?.animation != null) route!.animation!,
          if (scroll != null) scroll,
        ]),
        builder: (_, _) => _BlurBlit(
          image: image,
          screenSize: screen,
          // Focus-only rebuilds retain the texture. Scrolling and route
          // movement must refresh its crop at the new screen position.
          alignment: (
            scroll?.pixels ?? 0.0,
            slideOnly ? 1.0 : route?.animation?.value ?? 1.0,
            _alignmentRevision,
          ),
        ),
      ),
    );
  }
}

/// Blits the region of the pre-blurred wallpaper [image] located under this
/// render box (in screen space) using the paint offset, so it stays aligned
/// with the wallpaper while scrolling.
class _BlurBlit extends LeafRenderObjectWidget {
  final ui.Image image;
  final Size screenSize;
  final (double, double, int) alignment;

  const _BlurBlit({
    required this.image,
    required this.screenSize,
    required this.alignment,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BlurBlitRender(image, screenSize, alignment);

  @override
  void updateRenderObject(BuildContext context, _BlurBlitRender renderObject) {
    renderObject
      ..image = image
      ..screenSize = screenSize
      ..alignment = alignment;
  }
}

class _BlurBlitRender extends RenderBox {
  ui.Image _image;
  Size _screenSize;
  (double, double, int) _alignment;

  _BlurBlitRender(this._image, this._screenSize, this._alignment);

  set alignment((double, double, int) value) {
    if (value != _alignment) {
      _alignment = value;
      markNeedsPaint();
    }
  }

  set image(ui.Image value) {
    if (value != _image) {
      _image = value;
      markNeedsPaint();
    }
  }

  set screenSize(Size value) {
    if (value != _screenSize) {
      _screenSize = value;
      markNeedsPaint();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final scaleX = _image.width / _screenSize.width;
    final scaleY = _image.height / _screenSize.height;
    // Sample the blurred wallpaper at this box's true on-screen position so the
    // crop stays aligned with the real wallpaper (offset alone is layer-local).
    final bounds = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    final src = Rect.fromLTWH(
      bounds.left * scaleX,
      bounds.top * scaleY,
      bounds.width * scaleX,
      bounds.height * scaleY,
    );
    final dst = offset & size;
    context.canvas.drawImageRect(
      _image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
  }
}
