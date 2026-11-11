import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/ronits/launcher_backup.dart';

void main() {
  test('clock style and size persist, validate, and survive backup', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsService(preferences);
    expect(settings.clockStyle, 'digital');
    expect(settings.clockSize, 'medium');
    await settings.setClockStyle('analog');
    await settings.setClockSize('large');
    await settings.setClockStyle('invalid');
    await settings.setClockSize('invalid');
    final restored = SettingsService(preferences);
    expect(restored.clockStyle, 'analog');
    expect(restored.clockSize, 'large');
    final backup = LauncherBackup.parse(
      LauncherBackup(LauncherBackup.preferencesFrom(preferences), {
        'categories': [],
        'hidden': [],
      }).encode(),
    );
    expect(backup.preferences['home_clock_style'], 'analog');
    expect(backup.preferences['home_clock_size'], 'large');
    await settings.setClockSize('35');
    await settings.setClockSize('101');
    await settings.setClockSize('-1');
    expect(SettingsService(preferences).clockSize, '35');
    final sliderBackup = LauncherBackup.parse(
      LauncherBackup(LauncherBackup.preferencesFrom(preferences), {
        'categories': [],
        'hidden': [],
      }).encode(),
    );
    expect(sliderBackup.preferences['home_clock_size'], '35');
    settings.dispose();
    restored.dispose();
  });
  testWidgets(
    'clock controls stay open, resize the analog clock, and restore after restart',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(PreviewApp(preferences: preferences));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('luma-digital-clock')), findsOneWidget);
      await tester.tap(find.byTooltip('Clock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Luma settings'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-category-Appearance')),
      );
      await tester.pumpAndSettle();
      final section = find.byKey(const ValueKey('setting-clock-section'));
      await tester.ensureVisible(section);
      await tester.tap(section);
      await tester.pumpAndSettle();
      final style = find.byKey(const ValueKey('setting-clock-style'));
      await tester.tap(style);
      await tester.pumpAndSettle();
      expect(preferences.getString('home_clock_style'), 'analog');
      final slider = find.byKey(const ValueKey('setting-clock-size-slider'));
      await tester.ensureVisible(slider);
      tester
          .widget<Focus>(find.byKey(const ValueKey('clock-size-control')))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(preferences.getString('home_clock_size'), '55');
      expect(tester.widget<Slider>(slider).value, closeTo(55, .001));
      final homeFace = find.descendant(
        of: find.byKey(const ValueKey('home-clock-pill')),
        matching: find.byKey(const ValueKey('luma-analog-clock')),
      );
      expect(tester.getSize(homeFace).width, closeTo(98.8, .01));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(preferences.getString('home_clock_size'), '50');
      await tester.drag(slider, const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(
        int.parse(preferences.getString('home_clock_size')!),
        greaterThan(50),
      );
      expect(find.byKey(const ValueKey('setting-clock-style')), findsOneWidget);
      expect(tester.getSize(homeFace).width, greaterThan(40));
      final saved = preferences.getString('home_clock_size');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsWidgets);
      await tester.tap(section);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value.toInt().toString(), saved);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(PreviewApp(preferences: preferences));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('luma-analog-clock')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
