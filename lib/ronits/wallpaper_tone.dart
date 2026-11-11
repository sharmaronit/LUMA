import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'glass_surface.dart';

/// How bright the wallpaper is behind Luma's chrome, so glass can keep white
/// icons and text legible on light photos (white skies, snow, beaches).
///
/// Values are perceived lightness (gamma-encoded luma, 0 = black, 1 = white),
/// taken as a high percentile of each band so a bright patch is not averaged
/// away by a dark one.
@immutable
class WallpaperTone {
  const WallpaperTone({this.top = 0, this.bottom = 0});

  /// Band behind the top bar and quick settings (top quarter of the screen).
  final double top;

  /// Band behind the favourites dock (lower third of the screen).
  final double bottom;

  static const dark = WallpaperTone();

  /// Updated by the home screen whenever the wallpaper changes; read above the
  /// Navigator so dialogs (quick settings, menus) get the same answer.
  static final notifier = ValueNotifier<WallpaperTone>(dark);

  double get chrome => math.max(top, bottom);

  /// Default lightness the glass may show through before white content loses
  /// contrast. 0.40 gamma-encoded is ~0.13 relative luminance, ~5.7:1 against
  /// white (WCAG AA for body text is 4.5:1).
  static const defaultTarget = .40;

  /// Gamma-encoded lightness of the charcoal scrim colour (0xff16181c).
  static const _ink = .09;

  /// Opacity of a dark scrim needed over a backdrop of [lightness] for white
  /// content to reach [target] lightness or darker. Zero for dark wallpapers.
  static double scrimFor(
    double lightness, {
    double target = defaultTarget,
    double max = .85,
  }) {
    if (lightness <= target) return 0;
    return ((lightness - target) / (lightness - _ink)).clamp(0.0, max);
  }

  double topScrim([double target = defaultTarget]) =>
      scrimFor(top, target: target);
  double bottomScrim([double target = defaultTarget]) =>
      scrimFor(bottom, target: target);
  double chromeScrim([double target = defaultTarget]) =>
      scrimFor(chrome, target: target);

  @override
  bool operator ==(Object other) =>
      other is WallpaperTone &&
      (other.top - top).abs() < .01 &&
      (other.bottom - bottom).abs() < .01;

  @override
  int get hashCode => Object.hash((top * 100).round(), (bottom * 100).round());

  @override
  String toString() =>
      'WallpaperTone(top: ${top.toStringAsFixed(2)}, '
      'bottom: ${bottom.toStringAsFixed(2)})';
}

const scrimColor = Color(0xff16181c);

class WallpaperToneScope extends InheritedWidget {
  const WallpaperToneScope({
    super.key,
    required this.tone,
    required super.child,
  });
  final WallpaperTone tone;

  /// The tone for surfaces drawn over the wallpaper. Matte (charcoal) themes
  /// show no wallpaper, so they always report [WallpaperTone.dark].
  static WallpaperTone of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<WallpaperToneScope>();
    final background = MenuAppearanceScope.of(context)?.minimalBackground;
    if (scope == null || background == 'charcoal') return WallpaperTone.dark;
    return scope.tone;
  }

  @override
  bool updateShouldNotify(WallpaperToneScope oldWidget) =>
      tone != oldWidget.tone;
}

/// Lightness percentile of an RGBA thumbnail's rows [fromRow, toRow).
double bandLightness(
  ByteDataReader pixel,
  int width,
  int fromRow,
  int toRow, {
  double percentile = .8,
}) {
  final values = <double>[];
  for (var y = fromRow; y < toRow; y++) {
    for (var x = 0; x < width; x++) {
      final (r, g, b, a) = pixel(x, y);
      if (a < 128) continue;
      values.add((.2126 * r + .7152 * g + .0722 * b) / 255);
    }
  }
  if (values.isEmpty) return 0;
  values.sort();
  return values[((values.length - 1) * percentile).round()];
}

typedef ByteDataReader = (int, int, int, int) Function(int x, int y);
