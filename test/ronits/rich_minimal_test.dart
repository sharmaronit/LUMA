import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/actions.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/launcher_home.dart';

void tv(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(960, 540);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets(
    'quiet home has compact controls, landscape tiles and a remote accessible lazy library',
    (tester) async {
      tv(tester);
      var banners = 0, icons = 0;
      final apps = [
        for (var i = 0; i < 36; i++)
          LauncherAppItem(
            id: 'a$i',
            name: 'App $i',
            loadIcon: () async {
              icons++;
              return null;
            },
            loadArtwork: () async {
              banners++;
              return null;
            },
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: LauncherHome(
            mode: LauncherMaterial.minimal,
            apps: apps,
            favorites: apps.take(6).toList(),
            wallpaper: const AssetImage('not-mounted.jpg'),
            onMaterialChanged: (_) {},
            onLaunch: (_) async {},
            onSettings: () {},
            onWifi: () {},
            onManage: () {},
            onFavorite: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Luma'), findsNothing);
      expect(find.text('YOUR TV HOME'), findsNothing);
      expect(find.text('Recently opened'), findsNothing);
      expect(find.byTooltip('Search apps'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-clock-pill')), findsOneWidget);
      expect(find.byTooltip('All apps'), findsOneWidget);
      expect(find.byTooltip('Play next'), findsNothing);
      expect(find.byTooltip('Clock'), findsOneWidget);
      expect(banners, greaterThanOrEqualTo(6));
      expect(icons, greaterThanOrEqualTo(6));
      expect(find.byKey(const ValueKey('a35')), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      final loadedBeforeFocus = icons;
      final targetFinder = find.byKey(const ValueKey('minimal-focus-a1')).first;
      final before = tester.getRect(targetFinder);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final moving = tester.getRect(targetFinder);
      expect(moving.top, lessThan(before.top));
      expect(moving.top, greaterThan(before.top - 10));
      expect(moving.width, inExclusiveRange(before.width, before.width * 1.06));
      expect(moving.height, inExclusiveRange(before.height, before.height * 1.06));
      expect(
        find.byKey(const ValueKey('minimal-sliding-focus-frame')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        icons,
        loadedBeforeFocus,
        reason: 'Focus animation must not reload app artwork',
      );
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      final add = find.byTooltip('Add dock apps');
      expect(tester.getRect(add).right, lessThanOrEqualTo(960 - 16));
      await tester.tap(find.byTooltip('All apps'));
      await tester.pumpAndSettle();
      final grid = find.byKey(const ValueKey('a0'));
      expect(
        find.descendant(
          of: grid,
          matching: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.hasPrimaryFocus == true,
          ),
        ),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const ValueKey('minimal-scroll')),
          )
          .controller!;
      expect(scroll.offset, 0);
      await tester.tap(find.byTooltip('All apps'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-apps-page')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pinned navigation and collection filtering preserve remote focus',
    (tester) async {
      tv(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('All apps'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-apps-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-clock-pill')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('app-filter-games')));
      await tester.pumpAndSettle();
      expect(find.text('No games installed'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'All apps filter Games',
      );
      await tester.tap(find.byKey(const ValueKey('app-filter-music')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spotify')), findsOneWidget);
      // The Music bar holds music apps only.
      expect(find.byKey(const ValueKey('youtube')), findsNothing);
      expect(find.text('Music'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to Home'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('favorite-youtube'))).top,
        lessThan(540),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'root Back action uses its navigator even when constructed above MaterialApp',
    (tester) async {
      tv(tester);
      final navigator = GlobalKey<NavigatorState>();
      late BackAction action;
      final apps = [
        LauncherAppItem(
          id: 'back-app',
          name: 'App',
          artwork: Future.value(null),
        ),
      ];
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            action = BackAction(context, navigatorKey: navigator);
            return MaterialApp(
              navigatorKey: navigator,
              home: LauncherHome(
                mode: LauncherMaterial.minimal,
                apps: apps,
                favorites: apps,
                wallpaper: const AssetImage('unused.jpg'),
                onMaterialChanged: (_) {},
                onLaunch: (_) async {},
                onSettings: () {},
                onWifi: () {},
                onManage: () {},
                onFavorite: (_) async {},
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('All apps'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-apps-page')), findsOneWidget);
      await action.invoke(const BackIntent());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-apps-page')), findsNothing);
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const ValueKey('minimal-scroll')),
          )
          .controller!;
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('asynchronously loaded favourites receive initial focus', (
    tester,
  ) async {
    tv(tester);
    final apps = [
      LauncherAppItem(
        id: 'loaded',
        name: 'Loaded app',
        artwork: Future.value(null),
      ),
    ];
    Widget home(bool loaded) => MaterialApp(
      home: LauncherHome(
        mode: LauncherMaterial.minimal,
        apps: loaded ? apps : const [],
        favorites: loaded ? apps : const [],
        wallpaper: const AssetImage('not-mounted.jpg'),
        onMaterialChanged: (_) {},
        onLaunch: (_) async {},
        onSettings: () {},
        onWifi: () {},
        onManage: () {},
        onFavorite: (_) async {},
      ),
    );
    await tester.pumpWidget(home(false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(home(true));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('favorite-loaded')),
        matching: find.byWidgetPredicate(
          (w) => w is Focus && w.focusNode?.hasPrimaryFocus == true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<CustomScrollView>(
            find.byKey(const ValueKey('minimal-scroll')),
          )
          .controller!
          .offset,
      0,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('programme shelf uses supplied content without inventing viewing history', (tester) async {
    tv(tester);
    SharedPreferences.setMockInitialValues({'home_show_watch': true});
    await tester.pumpWidget(MaterialApp(home: LauncherHome(
      mode: LauncherMaterial.minimal,
      apps: const [], favorites: const [], wallpaper: const AssetImage('not-mounted.jpg'),
      homeContinueWatching: TextButton(onPressed: () {}, child: const Text('Real provider content')),
      onMaterialChanged: (_) {}, onLaunch: (_) async {}, onSettings: () {},
      onWifi: () {}, onManage: () {}, onFavorite: (_) async {},
    )));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Real provider content').hitTestable(), findsOneWidget);
    expect(find.text('Recently opened'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(PreviewApp(preferences: await SharedPreferences.getInstance()));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('From your apps'), findsOneWidget);
    expect(find.text('Wednesday'), findsOneWidget);
    expect(find.textContaining('Artwork preview'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Recently opened'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
