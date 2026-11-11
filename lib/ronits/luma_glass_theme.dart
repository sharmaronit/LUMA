import 'package:flutter/material.dart';
import 'glass_surface.dart';
import 'wallpaper_tone.dart';

/// Both finishes sample the prepared wallpaper; Real keeps its lighter tint.
class LumaGlassPanel extends StatelessWidget {
  const LumaGlassPanel({
    super.key,
    required this.child,
    this.enabled = true,
    this.cachedBlur = true,
    this.subtle = false,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.showRim = true,
    this.clipChild = true,
    this.lightweightTint = true,
  });
  final Widget child;
  final bool enabled, cachedBlur, subtle;
  final bool showRim;
  final bool clipChild;
  final bool lightweightTint;
  final double radius;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final palette = MinimalPalette.of(context);
    final canvas = palette.background;
    final ink = palette.text;
    final real =
        MenuAppearanceScope.of(context)?.minimalBackground == 'glass-real';
    final bright =
        (WallpaperAccentScope.of(context)?.computeLuminance() ?? .5) > .35;
    final baseOpacity = subtle ? .48 : (bright ? .78 : .68);
    // Measured wallpaper brightness: the light tint stays on dark photos and
    // deepens just enough on bright ones for white content to stay legible.
    final scrim = WallpaperToneScope.of(context).chromeScrim();
    final light0 = lightweightTint ? (scrim > .20 ? scrim : .20) : 0.0;
    final light1 = lightweightTint ? (scrim + .08 > .30 ? scrim + .08 : .30) : 0.0;
    final blurSigma = cachedBlur ? 20.0 : 4.0;
    final content = DecoratedBox(
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              ink.withValues(alpha: .06),
              canvas.withValues(
                alpha: lightweightTint
                    ? light0
                    : real
                    ? baseOpacity - .08
                    : baseOpacity,
              ),
            ),
            canvas.withValues(
              alpha: lightweightTint
                  ? light1.clamp(0.0, 1.0)
                  : (baseOpacity + .10).clamp(0, 1),
            ),
          ],
        ),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(radius),
          side: showRim
              ? BorderSide(color: ink.withValues(alpha: .34), width: .5)
              : BorderSide.none,
        ),
      ),
    );
    final cached = MenuAppearanceScope.of(context)?.blurBuilder;
    final shape = BorderRadius.circular(radius);
    final foreground = Padding(padding: padding, child: child);
    final surface = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: ClipRSuperellipse(
              borderRadius: shape,
              child: StaticPaintCache(
                child: cached?.call(content, blurSigma, 1.35) ?? content,
              ),
            ),
          ),
        ),
        foreground,
      ],
    );
    final key = ValueKey(cachedBlur ? 'luma-glass-panel' : 'luma-glass-button');
    if (!clipChild) return KeyedSubtree(key: key, child: surface);
    return ClipRSuperellipse(key: key, borderRadius: shape, child: surface);
  }
}

/// Cache shader/clip-heavy static pictures even when they use few draw calls.
/// The containing RepaintBoundary keeps animated siblings out of the cache.
class StaticPaintCache extends StatelessWidget {
  const StaticPaintCache({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomPaint(
    isComplex: true,
    foregroundPainter: const _GlassCacheHint(),
    child: child,
  );
}

class _GlassCacheHint extends CustomPainter {
  const _GlassCacheHint();
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_GlassCacheHint oldDelegate) => false;
}
