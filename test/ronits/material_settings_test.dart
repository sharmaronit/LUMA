import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/solid_theme_scope.dart';

void main() {
  test(
    'material and accessibility choices survive service recreation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      expect(settings.launcherMaterial, 'minimal');
      expect(settings.performanceMode, isTrue);
      await settings.setLauncherMaterial('solid');
      await settings.setReduceMotion(true);
      final restored = SettingsService(prefs);
      expect(restored.launcherMaterial, 'minimal');
      expect(restored.reduceMotion, isTrue);
      await restored.setLauncherMaterial('unknown');
      expect(restored.launcherMaterial, 'minimal');
      expect(LauncherMaterial.fromName('unknown'), LauncherMaterial.minimal);
    },
  );
  test(
    'solid theme colors persist, reject invalid values and keep readable contrast',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      await settings.setSolidThemeColor('183C32');
      expect(SettingsService(prefs).solidThemeColorHex, '183C32');
      await settings.setSolidThemeColor('not-a-color');
      expect(settings.solidThemeColorHex, '183C32');
      expect(solidThemeColor('corrupt'), solidThemeColor(null));
      for (final color in solidThemeColors) {
        expect(
          1.05 / (solidThemeColor(color.hex).computeLuminance() + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );
}
