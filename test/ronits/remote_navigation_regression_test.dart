import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';

void main() {
  testWidgets(
    'remote moves between header and dock, clamps edges and selects once',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      var launches = 0;
      final apps = [
        for (var i = 0; i < 10; i++) LauncherAppItem(id: 'a$i', name: 'App $i'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: LauncherHome(
            apps: apps,
            favorites: apps.take(2).toList(),
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: LauncherMaterial.minimal,
            onMaterialChanged: (_) {},
            onLaunch: (_) async {
              launches++;
            },
            onSettings: () {},
            onWifi: () {},
            onManage: () {},
            onFavorite: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      bool focused(String key) {
        var found = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
          if (e.widget.key == ValueKey(key)) found = true;
          return !found;
        });
        return found;
      }

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      expect(focused('favorite-a0'), true);
      await press(LogicalKeyboardKey.arrowLeft);
      expect(focused('favorite-a0'), true);
      await press(LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Home search');
      await press(LogicalKeyboardKey.arrowRight);
      await press(LogicalKeyboardKey.arrowDown);
      expect(focused('favorite-a0'), true);
      await press(LogicalKeyboardKey.numpadEnter);
      expect(launches, 1);
      await press(LogicalKeyboardKey.arrowRight);
      expect(focused('favorite-a1'), true);
      await press(LogicalKeyboardKey.arrowRight);
      await press(LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Home search');
      await tester.tap(find.byTooltip('All apps'));
      await tester.pumpAndSettle();
      expect(focused('a0'), true);
      await press(LogicalKeyboardKey.arrowDown);
      expect(focused('a2'), true);
      for (var i = 0; i < 3; i++) {
        await press(LogicalKeyboardKey.arrowRight);
      }
      expect(focused('a5'), true);
      await press(LogicalKeyboardKey.arrowDown);
      expect(
        focused('a9'),
        true,
        reason: 'An incomplete final row must remain reachable',
      );
      await press(LogicalKeyboardKey.arrowDown);
      expect(focused('a9'), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
