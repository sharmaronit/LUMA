import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'glass_surface.dart';
import 'luma_glass_theme.dart';
import 'wallpaper_tone.dart';

enum WallpaperBand { top, bottom, chrome }

/// Lightweight reference-style glass. The existing cache supplies the blur;
/// focus changes repaint the content independently of the glass and its rim.
class LiquidGlassV2 extends StatelessWidget {
  const LiquidGlassV2({
    super.key,
    required this.child,
    this.enabled = true,
    this.compact = false,
    this.radius = 30,
    this.padding = EdgeInsets.zero,
    this.blurBuilder,
    this.glassInset = EdgeInsets.zero,
    this.band = WallpaperBand.chrome,
    this.minScrim = 0,
    this.contrastTarget = WallpaperTone.defaultTarget,
  });

  final Widget child;
  final bool enabled, compact;
  final double radius;
  final EdgeInsets padding, glassInset;
  final GlassBlurBuilder? blurBuilder;

  /// Which part of the wallpaper this surface sits over.
  final WallpaperBand band;

  /// Floor for the dark scrim, for surfaces that should always read as a
  /// dark material (e.g. quick settings) whatever the wallpaper.
  final double minScrim;

  /// Lightness the backdrop is darkened to on bright wallpapers. Lower values
  /// give a deeper material (quick settings uses a darker one).
  final double contrastTarget;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return Padding(padding: padding, child: child);
    final highContrast = MediaQuery.highContrastOf(context);
    final blur = blurBuilder ?? MenuAppearanceScope.of(context)?.blurBuilder;
    final tone = WallpaperToneScope.of(context);
    // Dark wallpapers keep the clear glass look (scrim 0). On bright ones the
    // glass gains just enough dark tint for white icons/text to stay legible,
    // and the white sheen fades out so it can't wash the content out.
    final scrim = math.max(minScrim, switch (band) {
      WallpaperBand.top => tone.topScrim(contrastTarget),
      WallpaperBand.bottom => tone.bottomScrim(contrastTarget),
      WallpaperBand.chrome => tone.chromeScrim(contrastTarget),
    });
    final sheen = 1 - (scrim / .8).clamp(0.0, 1.0);
    final base = highContrast
        ? const Color(0xe6141a22)
        : Color.alphaBlend(
            Colors.white.withValues(alpha: (compact ? .10 : .07) * sheen),
            scrimColor.withValues(alpha: scrim),
          );
    final tint = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: .07 * sheen),
              base,
            ),
            Color.alphaBlend(const Color(0x04000000), base),
          ],
        ),
      ),
    );
    return Stack(
      key: const ValueKey('liquid-glass-v2'),
      fit: StackFit.passthrough,
      children: [
        Positioned(
          top: glassInset.top,
          bottom: glassInset.bottom,
          left: glassInset.left,
          right: glassInset.right,
          child: RepaintBoundary(
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(radius),
              child: StaticPaintCache(
                child: CustomPaint(
                  foregroundPainter: _GlassRim(radius, highContrast),
                  child: blur?.call(tint, 8, 1.05) ?? tint,
                ),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );
  }
}

/// Two fine, opposing edges give the shell thickness without a live refraction
/// shader or a filtered layer around the app tiles.
class _GlassRim extends CustomPainter {
  const _GlassRim(this.radius, this.highContrast);
  final double radius;
  final bool highContrast;

  Path contour(Rect rect, double inset) => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(
      (radius - inset).clamp(0, double.infinity),
    ),
  ).getOuterPath(rect.deflate(inset));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawPath(
      contour(rect, .6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highContrast ? 1.5 : .9
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, .32, .56, .8, 1],
          colors: [
            Color(0x99ffffff),
            Color(0x70ffffff),
            Color(0x20ffffff),
            Color(0x40ffffff),
            Color(0x70ffffff),
          ],
        ).createShader(rect),
    );
    if (size.shortestSide > 6) {
      canvas.drawPath(
        contour(rect, 1.9),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .65
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x10000000), Color(0x05ffffff), Color(0x20ffffff)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassRim old) =>
      radius != old.radius || highContrast != old.highContrast;
}
