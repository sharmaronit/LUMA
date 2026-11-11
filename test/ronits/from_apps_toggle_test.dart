import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/quick_settings.dart';

void main() {
  testWidgets('From your apps toggles live, stays in settings and persists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({
      'home_wallpaper_accent': false,
      'home_show_watch': true,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(PreviewApp(preferences: preferences));
    await tester.pumpAndSettle();
    Future<void> settings() async {
      await tester.tap(find.byTooltip('Clock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Luma settings'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-category-Home & Apps')),
      );
      await tester.pumpAndSettle();
    }

    await settings();
    final toggle = find.byKey(const ValueKey('toggle-From your apps'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(preferences.getBool('home_show_watch'), false);
    expect(
      tester
          .widget<QuickSettingsContent>(find.byType(QuickSettingsContent).last)
          .fullSettings,
      true,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-watch-row')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(PreviewApp(preferences: preferences));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-watch-row')), findsNothing);
    await settings();
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(preferences.getBool('home_show_watch'), true);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('minimal-scroll')),
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-watch-row')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
