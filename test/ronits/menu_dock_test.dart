import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/menu_dialog.dart';
import 'package:luma/ronits/glass_select_field.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/preview_management.dart';

void main() {
  testWidgets(
    'nested layout follows live menu mode and the shared blur recipe',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 540);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var mode = LauncherMaterial.ronits;
      late StateSetter change;
      final strengths = <double>[];
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, update) {
            change = update;
            return MaterialApp(
              builder: (_, child) => MenuAppearanceScope(
                mode: mode,
                blurBuilder: (child, sigma, saturation) {
                  strengths.add(sigma);
                  return child;
                },
                child: child!,
              ),
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showPreviewLayout(context, prefs, () {}),
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(strengths, isNotEmpty);
      expect(strengths.every((sigma) => sigma == 30), isTrue);
      await tester.ensureVisible(find.text('4 columns'));
      await tester.tap(find.text('4 columns'));
      await tester.pumpAndSettle();
      expect(prefs.getInt('preview_grid_columns'), 4);
      expect(find.byType(LumaMenuDialog), findsOneWidget);
      strengths.clear();
      change(() => mode = LauncherMaterial.solid);
      await tester.pumpAndSettle();
      expect(strengths, isEmpty);
      expect(find.text('App grid layout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('category picker uses shared glass and keeps the parent open', (
    tester,
  ) async {
    var value = 4;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MenuAppearanceScope(
          mode: LauncherMaterial.solid,
          blurBuilder: null,
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, update) => GlassSelectField<int>(
                  initialValue: value,
                  items: const [
                    DropdownMenuItem(value: 4, child: Text('4 columns')),
                    DropdownMenuItem(value: 6, child: Text('6 columns')),
                  ],
                  onChanged: (selected) => update(() => value = selected!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('4 columns'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value, 6);
    expect(find.byType(LumaMenuDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LumaMenuDialog), findsNothing);
    expect(find.text('6 columns'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dock picker persists edits, stays open, supports more than six apps and remote',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 540);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'preview_favorites': <String>[]});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add dock apps'), findsOneWidget);
      await tester.tap(find.byTooltip('Add dock apps'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(prefs.getStringList('preview_favorites')!.length, 1);
      expect(find.text('Dock apps · 1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(prefs.getStringList('preview_favorites'), isEmpty);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add dock apps'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      var calls = 0;
      final apps = [
        for (var i = 0; i < 7; i++) LauncherAppItem(id: '$i', name: 'App $i'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DockAppPicker(
              apps: apps,
              favorites: apps.take(6).map((app) => app.id).toSet(),
              onToggle: (_) async {
                calls++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('App 6'),
        120,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('App 6')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('App 6'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Replace a dock app'), findsNothing);
      expect(find.text('Dock apps · 7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
