// Luma
// Copyright (C) 2026 Ronit Sharma
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'glass_wallpaper.dart';

/// Wallpapers that have a foreground cut-out, with the baseline of the clock
/// digits as a fraction of the screen height. Keep in step with
/// scripts/generate-depth-layers.cjs, which makes the cut-outs.
/// Measured from each photo's skyline. [x] is the centre of the time: it
/// moves left or right to where the scenery is lowest, so the clock can stay
/// large. The highest peak under the digits covers at most about a fifth of
/// their height, so the scenery overlaps the bottom of the time without
/// cutting it off.
const depthWallpapers = <String, ({double x, double bottom, double height})>{
  'assets/wallpapers/aoraki-sunrise.jpg': (
    x: 0.50,
    bottom: 0.630,
    height: 0.30,
  ),
  'assets/wallpapers/dolomites.jpg': (x: 0.30, bottom: 0.385, height: 0.24),
  'assets/wallpapers/summit-glow.jpg': (x: 0.61, bottom: 0.460, height: 0.26),
  'assets/wallpapers/green-summit.jpg': (x: 0.50, bottom: 0.453, height: 0.26),
  'assets/wallpapers/rose-peak.jpg': (x: 0.40, bottom: 0.449, height: 0.26),
  'assets/wallpapers/blue-summit.jpg': (x: 0.34, bottom: 0.442, height: 0.26),
  'assets/wallpapers/misty-peak.jpg': (x: 0.28, bottom: 0.444, height: 0.26),
  'assets/wallpapers/volcano-view.jpg': (x: 0.50, bottom: 0.565, height: 0.26),
  'assets/wallpapers/steppe-range.jpg': (x: 0.50, bottom: 0.474, height: 0.26),
  'assets/wallpapers/golden-shore.jpg': (x: 0.50, bottom: 0.640, height: 0.26),
  'assets/wallpapers/star-dunes.jpg': (x: 0.55, bottom: 0.593, height: 0.26),
  'assets/wallpapers/twilight-lake.jpg': (x: 0.30, bottom: 0.422, height: 0.24),
  'assets/wallpapers/aurora-camp.jpg': (x: 0.50, bottom: 0.600, height: 0.26),
  'assets/wallpapers/lighthouse.jpg': (x: 0.32, bottom: 0.450, height: 0.26),
};

bool hasDepthLayer(String? asset) => depthWallpapers.containsKey(asset);

String depthLayerAsset(String wallpaper) {
  final name = wallpaper.split('/').last.replaceAll('.jpg', '');
  return 'assets/wallpapers/depth/$name.webp';
}

// Geometry of the cut-out strip, as fractions of a 1920x1080 screen. The
// strip was cut for digits up to _stripClock tall; the digits drawn are
// smaller and sit on the same baseline.
const _stripClock = 0.37, _stripWidth = 0.60;

/// Left edge of the cut-out strip for a clock centred at [x], kept on screen.
/// Rounded to whole pixels of a 1920 wide screen, as the generator does.
double depthStripLeft(double x) =>
    (1920 * (x - _stripWidth / 2).clamp(0.0, 1 - _stripWidth)).round() / 1920;
const _stripAbove = 0.012, _stripBelow = 0.026;

/// How much taller than their natural shape the digits are drawn.
const depthDigitStretch = 1.22;

/// The clock always uses this tall, narrow face, whatever font the rest of
/// the app uses. Antonio is openly licensed (SIL OFL).
const depthClockFont = 'Antonio';

/// The line above the time, for example "Tuesday 27 October".
String depthClockDate(DateTime time) => DateFormat('EEEE d MMMM').format(time);

/// The strip's rectangle on a screen of [size], rounded the same way the
/// generator rounds it so the cut-out lands exactly on the wallpaper.
Rect depthStripRect(Size size, double bottom, [double x = .5]) {
  // Never above the screen: on a high skyline the strip starts at the top.
  final top =
      math.max(0, (1080 * (bottom - _stripClock - _stripAbove)).round()) / 1080;
  final height =
      (1080 * (_stripClock + _stripAbove + _stripBelow)).round() / 1080;
  return Rect.fromLTWH(
    size.width * depthStripLeft(x),
    size.height * top,
    size.width * _stripWidth,
    size.height * height,
  );
}

/// The digits only: a depth clock never shows AM/PM.
String depthClockText(DateTime time, String pattern) =>
    DateFormat(pattern.contains('H') ? 'HH:mm' : 'h:mm').format(time);

/// Glass clock digits that sit behind the wallpaper's scenery.
///
/// The digits and a cut-out of the wallpaper's foreground are drawn once into
/// a single picture, and again only when the minute changes. Every frame in
/// between, the TV draws that one finished picture and nothing else, so the
/// clock costs the same as a small photo however slow the device is. Nothing
/// here animates.
class DepthClock extends StatefulWidget {
  const DepthClock({
    super.key,
    required this.wallpaper,
    required this.image,
    required this.pattern,
    this.scroll,
    this.now,
  });

  /// Asset name of the wallpaper, which selects the cut-out.
  final String wallpaper;

  /// The wallpaper picture itself; the glass digits show it blurred.
  final ImageProvider image;
  final String pattern;

  /// The home screen's scroll position; the clock fades as content scrolls up.
  final ScrollController? scroll;
  final DateTime Function()? now;
  @override
  State<DepthClock> createState() => _DepthClockState();
}

class _DepthClockState extends State<DepthClock> {
  Timer? _tick;
  late String _text = _format();
  late String _date = _formatDate();
  ui.Image? _strip, _glass, _picture;
  Object? _request;
  int _generation = 0;
  bool _baking = false, _stale = false;
  Size _screen = Size.zero;
  double _ratio = 1;

  String _format() =>
      depthClockText((widget.now ?? DateTime.now)(), widget.pattern);
  String _formatDate() => depthClockDate((widget.now ?? DateTime.now)());

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    _tick = Timer(Duration(seconds: 60 - now.second, milliseconds: 20), () {
      if (!mounted) return;
      final next = _format();
      if (next != _text) {
        _text = next;
        _date = _formatDate();
        _bake();
      }
      _schedule();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(DepthClock old) {
    super.didUpdateWidget(old);
    final text = _format();
    final changed = text != _text;
    _text = text;
    _date = _formatDate();
    _load();
    if (changed) _bake();
  }

  Future<ui.Image> _resolve(ImageProvider provider) {
    final result = Completer<ui.Image>();
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!result.isCompleted) result.complete(info.image.clone());
        info.dispose();
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return result.future;
  }

  /// Loads the cut-out and prepares the blurred wallpaper for the digits.
  /// Runs once per wallpaper and screen size.
  void _load() {
    final place = depthWallpapers[widget.wallpaper];
    final bottom = place?.bottom;
    final screen = MediaQuery.sizeOf(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final key = (widget.wallpaper, widget.image, screen, ratio);
    if (key == _request) return;
    _request = key;
    final ticket = ++_generation;
    _screen = screen;
    _ratio = ratio;
    if (bottom == null || screen.isEmpty) return;
    final rect = depthStripRect(screen, bottom, place!.x);
    final width = (rect.width * ratio).round();
    if (width <= 0) return;
    () async {
      ui.Image? strip, glass;
      try {
        strip = await _resolve(
          ResizeImage.resizeIfNeeded(
            width,
            null,
            AssetImage(depthLayerAsset(widget.wallpaper)),
          ),
        );
        // Half resolution is plenty for a picture that is blurred anyway.
        final source = await _resolve(
          ResizeImage.resizeIfNeeded(
            (screen.width * ratio / 2).round(),
            null,
            widget.image,
          ),
        );
        try {
          glass = await _blurBehind(source, rect, screen, ratio / 2);
        } finally {
          source.dispose();
        }
      } catch (_) {
        // Without both pictures the plain wallpaper is shown.
        strip?.dispose();
        glass?.dispose();
        return;
      }
      if (!mounted || ticket != _generation) {
        strip.dispose();
        glass.dispose();
        return;
      }
      _strip?.dispose();
      _glass?.dispose();
      _strip = strip;
      _glass = glass;
      _bake();
    }();
  }

  /// The part of the wallpaper under the strip, blurred, at [scale] pixels
  /// per logical pixel.
  Future<ui.Image> _blurBehind(
    ui.Image wallpaper,
    Rect rect,
    Size screen,
    double scale,
  ) async {
    final width = (rect.width * scale).ceil(),
        height = (rect.height * scale).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    canvas.saveLayer(
      null,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 22 * scale,
          sigmaY: 22 * scale,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.translate(-rect.left * scale, -rect.top * scale);
    paintImage(
      canvas: canvas,
      rect: Offset.zero & (screen * scale),
      image: wallpaper,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
    );
    canvas.restore();
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// Draws digits and foreground into one picture. Called when the minute or
  /// the wallpaper changes, never per frame.
  Future<void> _bake() async {
    if (_baking) {
      _stale = true;
      return;
    }
    final strip = _strip, glass = _glass;
    final place = depthWallpapers[widget.wallpaper];
    final bottom = place?.bottom;
    if (strip == null || glass == null || bottom == null) return;
    _baking = true;
    final ticket = _generation;
    final rect = depthStripRect(_screen, bottom, place!.x);
    final width = (rect.width * _ratio).round();
    final height = (rect.height * _ratio).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final area = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.clipRect(area);
    _paintDigits(canvas, area, rect, bottom, glass);
    _paintForeground(canvas, area, rect, strip);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width, height);
    } catch (_) {
      image = null;
    } finally {
      picture.dispose();
    }
    _baking = false;
    if (!mounted || ticket != _generation || image == null) {
      image?.dispose();
    } else {
      setState(() {
        _picture?.dispose();
        _picture = image;
      });
    }
    if (_stale && mounted) {
      _stale = false;
      unawaited(_bake());
    }
  }

  void _paintDigits(
    Canvas canvas,
    Rect area,
    Rect rect,
    double bottom,
    ui.Image glass,
  ) {
    TextPainter layout(
      double fontSize, {
      Paint? paint,
      List<Shadow>? shadows,
    }) => TextPainter(
      text: TextSpan(
        text: _text,
        style: TextStyle(
          fontFamily: depthClockFont,
          fontSize: fontSize,
          fontVariations: const [ui.FontVariation('wght', 200)],
          height: 1,
          letterSpacing: fontSize * .045,
          foreground: paint,
          color: paint == null ? const Color(0x00000000) : null,
          shadows: shadows,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    // The digits are laid out at their natural shape and then stretched
    // upwards a little more. Antonio's digits are about 0.84 of the font
    // size tall.
    const digitRatio = .84;
    final tall =
        _screen.height * _ratio * depthWallpapers[widget.wallpaper]!.height;
    var fontSize = tall / depthDigitStretch / digitRatio;
    var probe = layout(fontSize);
    final maxWidth = area.width * .86;
    if (probe.width > maxWidth) {
      fontSize *= maxWidth / probe.width;
      probe.dispose();
      probe = layout(fontSize);
    }
    final baseline = probe.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final textWidth = probe.width;
    probe.dispose();
    // Centre of the time within the strip.
    final centre =
        (_screen.width * depthWallpapers[widget.wallpaper]!.x - rect.left) *
        _ratio;
    final left = centre - textWidth / 2;
    final baselineY = (_screen.height * bottom - rect.top) * _ratio;
    final digitTop = baselineY - fontSize * digitRatio * depthDigitStretch;

    // The date sits just above the digits.
    final date = TextPainter(
      text: TextSpan(
        text: _date,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: _screen.height * _ratio * .027,
          fontWeight: FontWeight.w600,
          height: 1,
          color: const Color(0xf0ffffff),
          shadows: [
            Shadow(color: const Color(0x40000000), blurRadius: 6 * _ratio),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    date.paint(
      canvas,
      Offset(
        centre - date.width / 2,
        digitTop - date.height - _screen.height * _ratio * .016,
      ),
    );
    date.dispose();

    canvas.save();
    canvas.translate(left, baselineY);
    canvas.scale(1, depthDigitStretch);
    void draw({Paint? paint, List<Shadow>? shadows}) {
      final painter = layout(fontSize, paint: paint, shadows: shadows);
      painter.paint(canvas, Offset(0, -baseline));
      painter.dispose();
    }

    // A soft shadow lifts the glass off the sky.
    draw(
      shadows: [
        Shadow(
          color: const Color(0x2e000000),
          blurRadius: 9 * _ratio,
          offset: Offset(0, 2 * _ratio),
        ),
      ],
    );
    // The glass: the wallpaper behind, blurred, slightly magnified as a lens
    // would, and brightened to a pale white. Shaders are given in the
    // stretched text's own coordinates, so the picture is mapped back to
    // where it is on screen.
    final scale = area.width / glass.width;
    final onScreen = Matrix4.identity()
      ..translateByDouble(area.width / 2, area.height / 2, 0, 1)
      ..scaleByDouble(scale * 1.06, scale * 1.06, 1, 1)
      ..translateByDouble(-glass.width / 2, -glass.height / 2, 0, 1);
    final toText = Matrix4.identity()
      ..scaleByDouble(1, 1 / depthDigitStretch, 1, 1)
      ..translateByDouble(-left, -baselineY, 0, 1);
    draw(
      paint: Paint()
        ..shader = ui.ImageShader(
          glass,
          TileMode.clamp,
          TileMode.clamp,
          toText.multiplied(onScreen).storage,
          filterQuality: FilterQuality.low,
        )
        ..colorFilter = const ColorFilter.mode(
          Color(0x4dffffff),
          BlendMode.srcOver,
        ),
    );
    // Frosted sheen: light pooling at the top of each digit and a faint
    // glow returning at the bottom, as on a curved pane of glass.
    draw(
      paint: Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, -fontSize * digitRatio),
          Offset.zero,
          const [Color(0x70ffffff), Color(0x08ffffff), Color(0x26ffffff)],
          const [0, .6, 1],
        ),
    );
    // The rim: a bright hairline edge that defines the glass against the
    // sky, brighter on top where the light hits.
    draw(
      paint: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * _ratio / depthDigitStretch
        ..strokeJoin = StrokeJoin.round
        ..shader = ui.Gradient.linear(
          Offset(0, -fontSize * digitRatio),
          Offset.zero,
          const [Color(0xe6ffffff), Color(0x59ffffff), Color(0x99ffffff)],
          const [0, .55, 1],
        ),
    );
    canvas.restore();
  }

  /// The cut-out, with the same tint the wallpaper underneath gets so no seam
  /// shows where the strip ends.
  void _paintForeground(Canvas canvas, Rect area, Rect rect, ui.Image strip) {
    canvas.saveLayer(area, Paint());
    canvas.drawImageRect(
      strip,
      Rect.fromLTWH(0, 0, strip.width.toDouble(), strip.height.toDouble()),
      area,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.drawRect(
      area,
      Paint()
        ..color = const Color(0x10000000)
        ..blendMode = BlendMode.srcATop,
    );
    canvas.drawRect(
      area,
      Paint()
        ..shader = glassWallpaperContrast(0).createShader(
          Rect.fromLTWH(
            -rect.left * _ratio,
            -rect.top * _ratio,
            _screen.width * _ratio,
            _screen.height * _ratio,
          ),
        )
        ..blendMode = BlendMode.srcATop,
    );
    canvas.restore();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _generation++;
    _request = null;
    _strip?.dispose();
    _glass?.dispose();
    _picture?.dispose();
    super.dispose();
  }

  double _fade() {
    final scroll = widget.scroll;
    if (scroll == null || !scroll.hasClients) return 1;
    return (1 - scroll.offset / 140).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final place = depthWallpapers[widget.wallpaper];
    final bottom = place?.bottom;
    final picture = _picture;
    final size = MediaQuery.sizeOf(context);
    // The cut-outs are made for 16:9; on any other shape they would not line
    // up with the wallpaper, so the plain wallpaper is shown instead.
    final wide = (size.aspectRatio - 16 / 9).abs() < .03;
    if (bottom == null || picture == null || !wide) {
      return const SizedBox.shrink();
    }
    final rect = depthStripRect(size, bottom, place!.x);
    Widget layer(double fade) => RawImage(
      key: const ValueKey('depth-clock-layer'),
      image: picture,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.low,
      opacity: fade >= 1 ? null : AlwaysStoppedAnimation(fade),
    );
    final scroll = widget.scroll;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: scroll == null
                  ? layer(1)
                  : AnimatedBuilder(
                      animation: scroll,
                      builder: (_, _) {
                        final fade = _fade();
                        return fade <= 0
                            ? const SizedBox.shrink()
                            : layer(fade);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
