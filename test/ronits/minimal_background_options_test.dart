import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/solid_theme_scope.dart';
import 'package:luma/providers/settings_service.dart';

void main() {
  testWidgets(
    'Minimal wallpaper and colour controls update Home without closing settings',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({
        'minimal_background': 'charcoal',
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-wallpaper')), findsNothing);
      await tester.tap(find.byTooltip('Clock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Luma settings'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-category-Appearance')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('minimal-backdrop')),
      );
      await tester.tap(find.byKey(const ValueKey('minimal-backdrop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('minimal-use-wallpaper')));
      await tester.pumpAndSettle();
      expect(prefs.getString('minimal_background'), 'wallpaper');
      expect(find.byKey(const ValueKey('home-wallpaper')), findsOneWidget);
      expect(find.text('Minimal background'), findsWidgets);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.byKey(const ValueKey('minimal-use-colour')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deep black'));
      await tester.pumpAndSettle();
      expect(prefs.getString('solid_theme_color'), '000000');
      expect(prefs.getString('minimal_background'), 'charcoal');
      expect(find.byKey(const ValueKey('home-wallpaper')), findsNothing);
      expect(
        tester
            .widget<Scaffold>(find.byKey(const ValueKey('minimal-home')))
            .backgroundColor,
        Colors.black,
      );
      expect(find.text('Minimal background colour'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Scaffold>(find.byKey(const ValueKey('minimal-home')))
            .backgroundColor,
        solidThemeColor('000000'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'native settings preserve Minimal wallpaper and colour across recreation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      await settings.setMinimalBackground('wallpaper');
      await settings.setSolidThemeColor('3B3028');
      final restored = SettingsService(prefs);
      expect(restored.minimalBackground, 'wallpaper');
      expect(restored.solidThemeColorHex, '3B3028');
      settings.dispose();
      restored.dispose();
    },
  );
}
