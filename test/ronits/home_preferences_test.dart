import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';

void main() {
  test('saved clock pattern produces 12/24-hour display', () {
    final now = DateTime(2026, 10, 18, 17, 6);
    expect(launcherClockLabel(now, 'HH:mm'), '17:06');
    expect(launcherClockLabel(now, 'h:mm a'), '5:06 PM');
  });
  testWidgets(
    'All apps contains favourites; category columns and rows are rendered',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 540);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final apps = [
        for (var i = 0; i < 12; i++)
          LauncherAppItem(
            id: 'item$i',
            name: 'App $i',
            artwork: Future.value(null),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: LauncherHome(
            apps: apps,
            favorites: apps.take(6).toList(),
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: LauncherMaterial.solid,
            onMaterialChanged: (_) {},
            onLaunch: (_) async {},
            onSettings: () {},
            onWifi: () {},
            onManage: () {},
            onFavorite: (_) async {},
            sections: [
              LauncherAppSection(
                id: 'cinema',
                name: 'Cinema',
                apps: apps.take(4).toList(),
                columns: 4,
              ),
              LauncherAppSection(
                id: 'row',
                name: 'Music',
                apps: apps,
                horizontal: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('item0')), findsOneWidget);
      // The pinned header becomes invisible instead of covering the app shelves.
      final header = find
          .ancestor(
            of: find.byTooltip('Control Centre'),
            matching: find.byType(Opacity),
          )
          .first;
      expect(tester.widget<Opacity>(header).opacity, 0);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Cinema'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      final grid = find.byWidgetPredicate(
        (w) =>
            w is SliverGrid &&
            (w.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
                    .crossAxisCount ==
                4,
      );
      expect(grid, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
