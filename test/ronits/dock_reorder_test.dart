import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/launcher_home.dart';

void main() {
  testWidgets(
    'anchored Move follows the app, repeats arrows and saves before exit',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({
        'home_wallpaper_accent': false,
        'home_remember_selection': false,
      });
      final apps = [
        for (final id in ['a', 'b', 'c', 'd'])
          LauncherAppItem(id: id, name: 'App $id'),
      ];
      final favorites = apps.toList();
      var savedMoves = 0, launches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => LauncherHome(
              apps: apps,
              favorites: favorites.toList(),
              wallpaper: const AssetImage('assets/mountain.jpg'),
              mode: LauncherMaterial.minimal,
              minimalBackground: 'charcoal',
              reducedMotion: true,
              onMaterialChanged: (_) {},
              onLaunch: (_) async {
                launches++;
              },
              onSettings: () {},
              onWifi: () {},
              onManage: () {},
              onFavorite: (_) async {},
              onMoveFavorite: (app, offset) async {
                final from = favorites.indexWhere((item) => item.id == app.id);
                final to = from + offset;
                if (to < 0 || to >= favorites.length) return;
                update(() {
                  favorites.insert(to, favorites.removeAt(from));
                });
                await Future<void>.value();
                savedMoves++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('anchored-app-menu'));
      expect(menu, findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      final menuRect = tester.getRect(menu);
      expect(menuRect.left, greaterThanOrEqualTo(16));
      expect(menuRect.right, lessThanOrEqualTo(944));
      expect(
        menuRect.bottom,
        lessThan(tester.getRect(find.byKey(const ValueKey('favorite-a'))).top),
      );
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-move-hint')), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(favorites.map((app) => app.id), ['b', 'a', 'c', 'd']);
      expect(
        savedMoves,
        1,
        reason: 'Saved without confirming or leaving Move mode',
      );
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(favorites.map((app) => app.id), ['b', 'c', 'd', 'a']);
      expect(savedMoves, 3);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Moving favourite',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-move-hint')), findsNothing);
      expect(launches, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(tester.getRect(menu).right, lessThanOrEqualTo(944));
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(savedMoves, 4);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-move-hint')), findsNothing);
      expect(
        favorites.map((app) => app.id),
        ['b', 'c', 'a', 'd'],
        reason: 'Back finishes; it does not undo saved moves',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
