import 'package:luma/providers/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _gb = 1024 * 1024 * 1024;

Future<SettingsService> _settings(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsService(await SharedPreferences.getInstance());
}

void main() {
  test('low-end detection: low-RAM flag or 2.5 GB or less', () {
    expect(SettingsService.isLowEndProfile({'isLowRamDevice': true}), isTrue);
    expect(
      SettingsService.isLowEndProfile({'totalMemBytes': (1.9 * _gb).round()}),
      isTrue,
    );
    expect(
      SettingsService.isLowEndProfile({'totalMemBytes': 4 * _gb}),
      isFalse,
    );
    expect(SettingsService.isLowEndProfile({}), isFalse);
  });

  test('Lite mode is off by default, even on low-end TVs', () async {
    final settings = await _settings({
      'minimal_background': 'glass',
      'device_low_end': true,
    });
    expect(settings.liteMode, 'off');
    expect(settings.liteModeActive, isFalse);
    expect(settings.minimalBackground, 'glass');
  });

  test('auto Lite mode follows the detected device and is cached', () async {
    final settings = await _settings({
      'minimal_background': 'glass',
      'lite_mode': 'auto',
    });
    expect(settings.liteMode, 'auto');
    expect(settings.liteModeActive, isFalse);
    expect(settings.minimalBackground, 'glass');

    await settings.detectDeviceProfile(
      () async => {'totalMemBytes': 2 * _gb, 'isLowRamDevice': false},
    );
    expect(settings.deviceLowEnd, isTrue);
    expect(settings.liteModeActive, isTrue);
    // Rendered as plain wallpaper, but the user's choice is kept.
    expect(settings.minimalBackground, 'wallpaper');
    expect(settings.selectedMinimalBackground, 'glass');

    final reloaded = SettingsService(await SharedPreferences.getInstance());
    expect(reloaded.liteModeActive, isTrue);
  });

  test('manual override wins over detection; off restores glass', () async {
    final settings = await _settings({
      'minimal_background': 'glass-real',
      'device_low_end': true,
      'lite_mode': 'auto',
    });
    expect(settings.minimalBackground, 'wallpaper');
    await settings.setLiteMode('off');
    expect(settings.liteModeActive, isFalse);
    expect(settings.minimalBackground, 'glass-real');
    await settings.setLiteMode('on');
    expect(settings.minimalBackground, 'wallpaper');
    await settings.setLiteMode('bogus');
    expect(settings.liteMode, 'on');
  });

  test('matte themes are unaffected by Lite mode', () async {
    final settings = await _settings({
      'minimal_background': 'wallpaper',
      'lite_mode': 'on',
    });
    expect(settings.minimalBackground, 'wallpaper');
    await settings.setMinimalBackground('charcoal');
    expect(settings.minimalBackground, 'charcoal');
  });

  test('detection failure leaves Lite mode off', () async {
    final settings = await _settings({'lite_mode': 'auto'});
    await settings.detectDeviceProfile(() async => throw Exception('no'));
    expect(settings.liteModeActive, isFalse);
  });
}
