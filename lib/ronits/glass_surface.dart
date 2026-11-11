// RONITS Liquid Glass adaptation. See docs/ronits-liquid-glass-reference.md.
// Distributed under GPL-3.0-or-later, alongside the launcher.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'motion.dart';
import 'solid_theme_scope.dart';
import 'luma_glass_theme.dart';

final _menuColorSchemes = <(Color, Brightness), ColorScheme>{};
ColorScheme _menuColorScheme(Color accent, Brightness brightness) {
  final key = (accent, brightness);
  final cached = _menuColorSchemes[key];
  if (cached != null) return cached;
  if (_menuColorSchemes.length >= 24) {
    _menuColorSchemes.remove(_menuColorSchemes.keys.first);
  }
  return _menuColorSchemes[key] = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  );
}

enum LauncherMaterial {
  minimal('Minimal'),
  lite('Glass lite'),
  frosted('Frosted glass'),
  ronits('RONITS Liquid Glass'),
  solid('Solid');

  const LauncherMaterial(this.label);
  final String label;
  // Retired renderer names remain readable in old backups; all now use Clean.
  static LauncherMaterial fromName(String? name) => minimal;
}

typedef GlassBlurBuilder =
    Widget Function(Widget child, double sigma, double saturation);

/// Shared above the Navigator, so nested routes follow appearance changes live.
class MenuAppearanceScope extends InheritedWidget {
  const MenuAppearanceScope({
    super.key,
    required this.mode,
    this.minimalBackground = 'charcoal',
    this.economyGlass = false,
    required this.blurBuilder,
    required super.child,
  });
  final LauncherMaterial mode;
  final String minimalBackground;
  final bool economyGlass;
  final GlassBlurBuilder? blurBuilder;
  static MenuAppearanceScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MenuAppearanceScope>();
  @override
  bool updateShouldNotify(MenuAppearanceScope oldWidget) =>
      mode != oldWidget.mode ||
      minimalBackground != oldWidget.minimalBackground ||
      economyGlass != oldWidget.economyGlass ||
      blurBuilder != oldWidget.blurBuilder;
}

/// Flat classic OxygenOS-inspired palettes; no backdrop filtering.
class WallpaperAccentScope extends InheritedWidget {
  const WallpaperAccentScope({
    super.key,
    required this.color,
    required super.child,
  });
  final Color? color;
  static Color? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WallpaperAccentScope>()?.color;
  @override
  bool updateShouldNotify(WallpaperAccentScope oldWidget) =>
      color != oldWidget.color;
}

class MinimalPalette {
  const MinimalPalette(this.name, [this.wallpaperAccent]);
  final Color? wallpaperAccent;
  final String name;
  static MinimalPalette of(BuildContext context) => MinimalPalette(
    MenuAppearanceScope.of(context)?.minimalBackground ?? 'charcoal',
    WallpaperAccentScope.of(context),
  );
  bool get glass => name == 'glass' || name == 'glass-real';
  bool get light => false;
  Color get background => const Color(0xff1b1c1e);
  Color get text => const Color(0xffeeeff1);
  Color get muted => glass ? const Color(0xffe0e6ed) : const Color(0xffa0a2a6);
  Color get accent => wallpaperAccent ?? const Color(0xffeeeff1);
  Color get surface => const Color(0xff242629);
}

ColorFilter glassSaturation(double saturation) {
  final r = (1 - saturation) * .2126,
      g = (1 - saturation) * .7152,
      b = (1 - saturation) * .0722;
  return ColorFilter.matrix([
    r + saturation,
    g,
    b,
    0,
    0,
    r,
    g + saturation,
    b,
    0,
    0,
    r,
    g,
    b + saturation,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.mode,
    required this.child,
    this.sheet = false,
    this.frostedSheet = false,
    this.radius = 28,
    this.blurBuilder,
    this.light = false,
  });
  final LauncherMaterial mode;
  final Widget child;
  final bool sheet, light, frostedSheet;
  final double radius;
  final GlassBlurBuilder? blurBuilder;

  @override
  Widget build(BuildContext context) {
    final appearance = sheet ? MenuAppearanceScope.of(context) : null;
    final mode = appearance?.mode ?? this.mode;
    final blurBuilder = appearance?.blurBuilder ?? this.blurBuilder;
    // All menu sheets use the same recipe; dock and header keep their own.
    final frostedSheet = sheet || this.frostedSheet;
    if (mode == LauncherMaterial.minimal) {
      final glass = [
        'glass',
        'glass-real',
      ].contains(appearance?.minimalBackground);
      final surface = Material(
        key: const ValueKey('minimal-menu-surface'),
        color: glass ? Colors.transparent : MinimalPalette.of(context).surface,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(lumaPanelRadius),
        ),
        clipBehavior: Clip.hardEdge,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: MinimalPalette.of(context).text),
          child: Theme(
            data: Theme.of(context).copyWith(
              brightness: MinimalPalette.of(context).light
                  ? Brightness.light
                  : Brightness.dark,
              colorScheme: _menuColorScheme(
                MinimalPalette.of(context).accent,
                MinimalPalette.of(context).light
                    ? Brightness.light
                    : Brightness.dark,
              ),
              textButtonTheme: TextButtonThemeData(
                style:
                    (Theme.of(context).textButtonTheme.style ??
                            const ButtonStyle())
                        .copyWith(
                          foregroundColor: WidgetStatePropertyAll(
                            MinimalPalette.of(context).accent,
                          ),
                        ),
              ),
              iconTheme: IconThemeData(color: MinimalPalette.of(context).text),
            ),
            child: child,
          ),
        ),
      );
      return RepaintBoundary(
        child: LumaGlassPanel(
          enabled: glass,
          radius: lumaPanelRadius,
          child: surface,
        ),
      );
    }
    final ronits = mode == LauncherMaterial.ronits;
    final canvas = mode == LauncherMaterial.solid
        ? SolidThemeScope.of(context)
        : light
        ? const Color(0xfff2f4f8)
        : const Color(0xff172638);
    final ink = light ? const Color(0xff172333) : const Color(0xfff4f7fb);
    final solid = mode == LauncherMaterial.solid;
    final sigma = frostedSheet
        ? 30.0
        : ronits
        ? (sheet
              ? 12.0
              : radius >= 100
              ? 4.0
              : 20.0)
        : (sheet ? 16.0 : 32.0);
    final saturation = ronits ? 1.35 : 1.45;
    final shape = BorderRadius.circular(radius);
    Widget content = AnimatedContainer(
      duration: motionReduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: lumaEase,
      decoration: BoxDecoration(
        color: canvas.withValues(
          alpha: solid
              ? 1
              : frostedSheet
              ? .46
              : sheet
              ? .82
              : ronits
              ? (radius >= 100 ? .40 : .28)
              : .40,
        ),
        borderRadius: shape,
        border: Border.all(
          color: ink.withValues(alpha: ronits ? .34 : .30),
          width: ronits ? .5 : 1,
        ),
        boxShadow: sheet
            ? const []
            : [
                BoxShadow(
                  color: ink.withValues(alpha: .08),
                  offset: const Offset(0, 1),
                  blurRadius: 1,
                  blurStyle: BlurStyle.inner,
                ),
              ],
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: ink),
        child: child,
      ),
    );
    if (!solid && mode != LauncherMaterial.lite) {
      content =
          blurBuilder?.call(content, sigma, saturation) ??
          BackdropFilter(
            filter: ui.ImageFilter.compose(
              outer: glassSaturation(saturation),
              inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            ),
            child: content,
          );
    }
    return RepaintBoundary(
      child: ClipRSuperellipse(borderRadius: shape, child: content),
    );
  }
}
