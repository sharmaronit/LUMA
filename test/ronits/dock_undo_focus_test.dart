import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/launcher_home.dart';

void main() {
  testWidgets(
    'removing a dock app puts focus on Undo and OK restores its position',
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
        for (final id in ['a', 'b', 'c'])
          LauncherAppItem(id: id, name: 'App $id'),
      ];
      final favorites = apps.toList();
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
              onLaunch: (_) async {},
              onSettings: () {},
              onWifi: () {},
              onManage: () {},
              onFavorite: (app) async {
                update(() {
                  final index = favorites.indexWhere(
                    (item) => item.id == app.id,
                  );
                  if (index < 0) {
                    favorites.add(app);
                  } else {
                    favorites.removeAt(index);
                  }
                });
              },
              onMoveFavorite: (app, offset) async {
                update(() {
                  final index = favorites.indexWhere(
                    (item) => item.id == app.id,
                  );
                  favorites.insert(index + offset, favorites.removeAt(index));
                });
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from favourites'));
      await tester.pumpAndSettle();
      expect(favorites.map((app) => app.id), ['b', 'c']);
      final undo = find.byKey(const ValueKey('dock-undo'));
      expect(undo, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: undo,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Focus && widget.focusNode?.hasPrimaryFocus == true,
          ),
        ),
        findsOneWidget,
      );
      final rect = tester.getRect(undo);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(540));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(favorites.map((app) => app.id), ['a', 'b', 'c']);
      expect(undo, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
