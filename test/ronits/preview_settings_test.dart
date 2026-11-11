import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/quick_settings.dart';

void main() {
  testWidgets(
    'retired appearance migrates; flat themes persist without closing settings',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'launcher_material': 'ronits'});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(prefs.getString('launcher_material'), 'minimal');
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.byTooltip('Clock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Luma settings'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-category-Appearance')),
      );
      await tester.pumpAndSettle();
      final panel = tester.widget<QuickSettingsContent>(
        find.byType(QuickSettingsContent).last,
      );
      expect(panel.fullSettings, isTrue);
      expect(panel.mode, LauncherMaterial.minimal);
      expect(find.text('Theme'), findsOneWidget);
      for (final label in [
        'Solid',
        'Solid theme color',
        'Glass lite',
        'Frosted glass',
        'RONITS Liquid Glass',
        'Performance mode',
      ]) {
        expect(find.text(label), findsNothing);
      }
      await tester.ensureVisible(find.text('Theme').last);
      await tester.tap(find.text('Theme').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('minimal-background-charcoal')),
      );
      await tester.pumpAndSettle();
      expect(prefs.getString('minimal_background'), 'charcoal');
      expect(find.text('Liquid Performative'), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuickSettingsContent>(
              find.byType(QuickSettingsContent).last,
            )
            .fullSettings,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuickSettingsContent>(find.byType(QuickSettingsContent))
            .fullSettings,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('settings-category-Appearance')),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Scaffold>(find.byKey(const ValueKey('minimal-home')))
            .backgroundColor,
        const Color(0xff1b1c1e),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
