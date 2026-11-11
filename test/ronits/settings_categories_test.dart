import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/motion.dart';
import 'package:luma/ronits/quick_settings.dart';
import 'package:luma/widgets/settings/luma_settings_page.dart';

void main() {
  testWidgets(
    'one settings panel groups controls and Back restores the category',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final service = SettingsService(preferences);
      final opened = <String>[];
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: service,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                autofocus: true,
                child: const Text('Open'),
                onPressed: () => showLumaDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: SizedBox(
                      width: 380,
                      height: 460,
                      child: QuickSettingsContent(
                        mode: LauncherMaterial.minimal,
                        reducedMotion: false,
                        onMaterialChanged: (_) {},
                        onWifi: () => opened.add('wifi'),
                        onDeviceSettings: opened.add,
                        onSettings: () {},
                        onMinimalBackgroundChanged: (_) {},
                        onWallpaper: () {},
                        onClockStyleChanged: (_) {},
                        onManage: () {},
                        onLayout: () {},
                        onFromAppsChanged: (_) {},
                        onReducedMotionChanged: (_) {},
                        onBackup: () {},
                        onFontStyle: () {},
                        onRemoteShortcuts: () {},
                        soundSettings: const LumaSoundSettings(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      Finder group(String name) =>
          find.byKey(ValueKey('settings-category-$name'));
      for (final name in [
        'Appearance',
        'Home & Apps',
        'Sound & Motion',
        'Device',
        'About',
      ]) {
        expect(group(name), findsOneWidget);
      }
      expect(find.text('Theme'), findsNothing);
      expect(find.text('More launcher settings'), findsNothing);
      await tester.tap(group('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Wallpapers'), findsOneWidget);
      expect(find.text('Clock'), findsOneWidget);
      expect(find.text('Font style'), findsOneWidget);
      expect(find.text('Remote shortcuts'), findsNothing);
      expect(find.text('Navigation sounds'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(group('Appearance'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Settings Appearance',
      );
      await tester.tap(group('Home & Apps'));
      await tester.pumpAndSettle();
      expect(find.text('From your apps'), findsOneWidget);
      expect(find.text('Programme sources'), findsOneWidget);
      expect(find.text('Apps & Favourites'), findsOneWidget);
      expect(find.text('Remote shortcuts'), findsOneWidget);
      expect(find.text('Font style'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(group('Sound & Motion'));
      await tester.pumpAndSettle();
      expect(find.text('Navigation sounds'), findsOneWidget);
      expect(find.text('Reduce motion'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setting-navigation-sounds')));
      await tester.pumpAndSettle();
      expect(service.appKeyClickEnabled, false);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.tap(find.byTooltip('Back to settings'));
      await tester.pumpAndSettle();
      await tester.tap(group('Device'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('setting-network')));
      await tester.tap(
        find.byKey(const ValueKey('setting-bluetooth-and-remotes')),
      );
      expect(opened, ['wifi', 'bluetooth']);
      await tester.tap(find.byTooltip('Back to settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(group('About'));
      await tester.tap(group('About'));
      await tester.pumpAndSettle();
      expect(find.text('Backup & restore'), findsOneWidget);
      expect(find.text('Advanced'), findsNothing);
      await tester.tap(find.byTooltip('Close Luma Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickSettingsContent), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );
}
