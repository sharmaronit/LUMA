import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/cached_wallpaper.dart';

void main() {
  Future<void> setup(
    WidgetTester tester, {
    bool favorites = true,
    int favoriteCount = 6,
    int appCount = 24,
    Size viewport = const Size(960, 540),
  }) async {
    tester.view.physicalSize = viewport;
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
      for (var i = 0; i < appCount; i++)
        LauncherAppItem(id: 'a$i', name: 'App $i', installedAt: i * 1000),
    ];
    await tester.pumpWidget(
      MenuAppearanceScope(
        mode: LauncherMaterial.minimal,
        minimalBackground: 'glass',
        blurBuilder: (child, sigma, saturation) => child,
        child: MaterialApp(
          home: LauncherHome(
            apps: apps,
            favorites: favorites ? apps.take(favoriteCount).toList() : [],
            sections: [
              LauncherAppSection(
                id: 'video',
                name: 'Video',
                apps: [apps[0], apps[6], apps[7]],
              ),
            ],
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: LauncherMaterial.minimal,
            minimalBackground: 'glass',
            reducedMotion: true,
            onMaterialChanged: (_) {},
            onLaunch: (_) async {},
            onSettings: () {},
            onWifi: () {},
            onManage: () {},
            onFavorite: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('All apps'));
    await tester.pumpAndSettle();
  }

  bool focused(String key) {
    var found = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
      element,
    ) {
      if (element.widget.key == ValueKey(key)) found = true;
      return !found;
    });
    return found;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'All apps sorting uses installation dates and persists the chosen order',
    (tester) async {
      await setup(tester, favorites: false);
      Future<void> sort(String label) async {
        await tester.tap(find.byTooltip('Sort apps'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await sort('Recently installed');
      final newest = tester.getRect(
        find.byKey(const ValueKey('minimal-focus-a23')),
      );
      final previous = tester.getRect(
        find.byKey(const ValueKey('minimal-focus-a22')),
      );
      expect(newest.left, lessThan(previous.left));
      expect(newest.top, closeTo(previous.top, 1));
      expect(
        (await SharedPreferences.getInstance()).getString('all_apps_sort'),
        'newest',
      );
      await sort('Name A-Z');
      expect(
        tester.getRect(find.byKey(const ValueKey('minimal-focus-a0'))).left,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('minimal-focus-a1'))).left,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('remote Down reaches the end of a long app library', (
    tester,
  ) async {
    await setup(tester, favorites: false, appCount: 100);
    for (var i = 0; i < 40; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    for (var i = 0; i < 8; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(
      focused('a99'),
      true,
      reason: FocusManager.instance.primaryFocus?.debugLabel,
    );
    final tile = tester.getRect(find.byKey(const ValueKey('a99')));
    expect(tile.bottom, lessThanOrEqualTo(540));
    expect(tile.top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'wide screens use the full width and sparse libraries use the height',
    (tester) async {
      await setup(tester, appCount: 12, viewport: const Size(3840, 1914));
      final dock = tester.getRect(
        find.byKey(const ValueKey('all-apps-favourites-dock')),
      );
      expect(dock.left, 48);
      expect(dock.right, 3840 - 48);
      final favorite = tester.getSize(
        find.byKey(const ValueKey('minimal-focus-a0')),
      );
      expect(favorite.width, greaterThan(500));
      expect(favorite.width / favorite.height, closeTo(16 / 9, .01));
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        6,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('minimal-focus-a11'))).bottom,
        lessThanOrEqualTo(1914),
      );
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('all-apps-grid')),
          )
          .controller!;
      // Favourites now wrap instead of hiding beyond a horizontal rail.
      expect(scroll.position.maxScrollExtent, lessThan(1914 * .3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Down reaches overflow favourites and the remaining apps', (
    tester,
  ) async {
    await setup(tester, appCount: 24, favoriteCount: 18);
    final dock = find.byKey(const ValueKey('all-apps-favourites-dock'));
    expect(
      find.descendant(of: dock, matching: find.byKey(const ValueKey('a5'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dock, matching: find.byKey(const ValueKey('a6'))),
      findsNothing,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('a0'))).top,
      tester.getRect(find.byKey(const ValueKey('a5'))).top,
    );
    for (var i = 0; i < 16; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    for (var i = 0; i < 8; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focused('a23'), true);
    expect(
      tester.getRect(find.byKey(const ValueKey('a23'))).bottom,
      lessThanOrEqualTo(540),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'All apps separates favourites, uses static cached wallpaper and remembers selection',
    (tester) async {
      await setup(tester);
      final dock = find.byKey(const ValueKey('all-apps-favourites-dock'));
      expect(dock, findsOneWidget);
      for (var i = 0; i < 6; i++) {
        expect(
          find.descendant(of: dock, matching: find.byKey(ValueKey('a$i'))),
          findsOneWidget,
        );
        expect(find.byKey(ValueKey('a$i')), findsOneWidget);
      }
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(grid.delegate.estimatedChildCount, 18);
      final background = tester.widget<CachedWallpaperBackground>(
        find.byType(CachedWallpaperBackground),
      );
      expect(background.wallpaper, const AssetImage('assets/mountain.jpg'));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ImageFiltered && widget.enabled,
        ),
        findsNothing,
      );
      expect(focused('a0'), true);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused('a1'), true);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused('a7'), true);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused('a1'), true);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('All apps'));
      await tester.pumpAndSettle();
      expect(
        identical(
          tester
              .widget<CachedWallpaperBackground>(
                find.byType(CachedWallpaperBackground),
              )
              .cache,
          background.cache,
        ),
        true,
      );
      expect(focused('a1'), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'each category tab opens with its own bar: favourites first, then its apps',
    (tester) async {
      await setup(tester);
      await tester.tap(find.byKey(const ValueKey('app-filter-entertainment')));
      await tester.pumpAndSettle();
      expect(find.text('3 apps'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('all-apps-favourites-dock')),
        findsOneWidget,
      );
      // a0 is a favourite; a6 and a7 top the bar up. Other favourites stay
      // on the All tab.
      for (final id in ['a0', 'a6', 'a7']) {
        expect(find.byKey(ValueKey(id)), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('a1')), findsNothing);
      expect(find.text('All your apps are in Favourites'), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'All apps filter Entertainment',
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused('a0'), true);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused('a6'), true);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused('a7'), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('without favourites all installed apps remain in the grid', (
    tester,
  ) async {
    await setup(tester, favorites: false);
    expect(
      find.byKey(const ValueKey('all-apps-favourites-dock')),
      findsNothing,
    );
    expect(
      tester
          .widget<SliverGrid>(find.byType(SliverGrid))
          .delegate
          .estimatedChildCount,
      24,
    );
    expect(focused('a0'), true);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'All apps filter All',
    );
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused('a0'), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
