import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/wallpaper_tone.dart';

void main() {
  test('dark wallpapers keep clear glass', () {
    expect(WallpaperTone.scrimFor(0), 0);
    expect(WallpaperTone.scrimFor(.3), 0);
    expect(WallpaperTone.scrimFor(WallpaperTone.defaultTarget), 0);
  });

  test('bright wallpapers get enough scrim for white content', () {
    for (final lightness in [.6, .75, .85, .95, 1.0]) {
      final a = WallpaperTone.scrimFor(lightness);
      // Blend in the same (gamma-encoded) space Flutter composites in.
      final result = a * .09 + (1 - a) * lightness;
      expect(
        result,
        lessThanOrEqualTo(WallpaperTone.defaultTarget + 1e-9),
        reason: 'L=$lightness',
      );
      expect(a, lessThanOrEqualTo(.85));
      // A deeper material for quick settings.
      final deep = WallpaperTone.scrimFor(lightness, target: .30);
      expect(deep * .09 + (1 - deep) * lightness, lessThanOrEqualTo(.30 + 1e-9));
    }
  });

  test('band lightness uses a high percentile, not the mean', () {
    // 16x4 thumbnail: three quarters black, one quarter white sky.
    (int, int, int, int) pixel(int x, int y) =>
        x < 12 ? (0, 0, 0, 255) : (255, 255, 255, 255);
    expect(bandLightness(pixel, 16, 0, 4), closeTo(1, .001));
    expect(bandLightness(pixel, 16, 0, 4, percentile: .5), closeTo(0, .001));
  });

  test('tones compare by value so unchanged wallpapers do not rebuild', () {
    expect(
      const WallpaperTone(top: .5, bottom: .2),
      const WallpaperTone(top: .505, bottom: .2),
    );
    expect(
      const WallpaperTone(top: .5, bottom: .2) ==
          const WallpaperTone(top: .7, bottom: .2),
      isFalse,
    );
  });
}
