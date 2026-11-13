import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/launcher_home.dart';

void main() {
  testWidgets(
    'search launches a matching installed app and handles empty results',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final apps = [
        for (final name in ['YouTube', 'Netflix', 'JioHotstar'])
          LauncherAppItem(id: name, name: name, artwork: Future.value(null)),
      ];
      String? launched;
      await tester.pumpWidget(
        MaterialApp(
          home: LauncherHome(
            apps: apps,
            favorites: apps,
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: LauncherMaterial.solid,
            onMaterialChanged: (_) {},
            onLaunch: (app) async {
              launched = app.id;
            },
            onSettings: () {},
            onWifi: () {},
            onManage: () {},
            onFavorite: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search apps'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'does-not-exist');
      await tester.pump();
      expect(
        find.textContaining('No results. Only programmes'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'net');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('search-result-Netflix')),
        findsOneWidget,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(launched, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(launched, 'Netflix');
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('remote long press opens options without also launching', (
    tester,
  ) async {
    var launches = 0, options = 0;
    final app = LauncherAppItem(
      id: 'test',
      name: 'Test app',
      artwork: Future.value(null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 175,
              child: LauncherTile(
                app: app,
                autofocus: true,
                onPressed: () => launches++,
                onLongPress: () => options++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 650));
    expect(options, 0);
    expect(launches, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(options, 1);
    expect(launches, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(launches, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('releasing held Select leaves the options menu awaiting input', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final app = LauncherAppItem(
      id: 'youtube',
      name: 'YouTube',
      artwork: Future.value(null),
    );
    var changes = 0, launches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LauncherHome(
          apps: [app],
          favorites: [app],
          wallpaper: const AssetImage('assets/mountain.jpg'),
          mode: LauncherMaterial.solid,
          onMaterialChanged: (_) {},
          onLaunch: (_) async {
            launches++;
          },
          onSettings: () {},
          onWifi: () {},
          onManage: () {},
          onFavorite: (_) async {
            changes++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Remove from favourites'), findsOneWidget);
    expect(changes, 0);
    expect(launches, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('control centre fits a 960 by 540 TV viewport', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 540);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final app = LauncherAppItem(
      id: 'test',
      name: 'Test app',
      artwork: Future.value(null),
    );
    LauncherMaterial? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) => LauncherHome(
            apps: [app],
            favorites: [app],
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: selected ?? LauncherMaterial.ronits,
            onMaterialChanged: (value) => update(() => selected = value),
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
    await tester.tap(find.byTooltip('Control Centre'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Two columns: the section name is in the list and heads its options.
    expect(
      find.byKey(const ValueKey('settings-category-Appearance')),
      findsOneWidget,
    );
    expect(find.text('Appearance'), findsNWidgets(2));
    for (final name in [
      'Frosted glass',
      'Glass lite',
      'RONITS Liquid Glass',
      'Solid',
    ]) {
      expect(find.text(name), findsNothing);
    }
    expect(selected, isNull);
    expect(find.text('Luma Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Luma Settings'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('quick settings stays open when routing device sections', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 540);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    String? section;
    var network = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LauncherHome(
          apps: const [],
          favorites: const [],
          wallpaper: const AssetImage('assets/mountain.jpg'),
          mode: LauncherMaterial.solid,
          onMaterialChanged: (_) {},
          onLaunch: (_) async {},
          onSettings: () {},
          onWifi: () {
            network++;
          },
          onManage: () {},
          onFavorite: (_) async {},
          onDeviceSettings: (value) => section = value,
        ),
      ),
    );
    for (final entry in {'Android TV settings': 'all'}.entries) {
      await tester.tap(find.byTooltip('Control Centre'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-category-Device')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(entry.key));
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(section, entry.value);
      expect(find.text('Device'), findsNWidgets(2));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(network, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Home reset returns a scrolled launcher to its first app', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 540);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final apps = [
      for (var i = 0; i < 24; i++)
        LauncherAppItem(
          id: 'app$i',
          name: 'App $i',
          artwork: Future.value(null),
        ),
    ];
    Widget build(int token) => MaterialApp(
      home: LauncherHome(
        resetToken: token,
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
      ),
    );
    await tester.pumpWidget(build(0));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    await tester.pumpWidget(build(1));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    final focus = tester.widget<Focus>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Focus && widget.focusNode?.debugLabel == 'First home app',
      ),
    );
    expect(focus.focusNode!.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'dock rests at bottom and Down reveals apps; header focus is visible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 540);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final apps = [
        for (var i = 0; i < 18; i++)
          LauncherAppItem(
            id: 'a$i',
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
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dock = find.byKey(const ValueKey('favorite-a0'));
      expect(tester.getRect(dock).bottom, greaterThan(450));
      expect(tester.getRect(dock).bottom, lessThan(540));
      final heading = find.text('All apps');
      if (heading.evaluate().isNotEmpty)
        expect(tester.getTopLeft(heading).dy, greaterThanOrEqualTo(540));
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      expect(scroll.offset, 0);
      final add = find.byTooltip('Add dock apps');
      final lastApp = find.byKey(const ValueKey('favorite-a5'));
      expect(
        tester.getCenter(add).dx,
        greaterThan(tester.getRect(lastApp).right),
      );
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      final addIcon = tester.widget<IconButton>(
        find.ancestor(of: add, matching: find.byType(IconButton)),
      );
      expect(addIcon.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(tester.widget<LauncherTile>(lastApp).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(addIcon.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(200));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final search = find.ancestor(
        of: find.byTooltip('Search apps'),
        matching: find.byType(HomeControlButton),
      );
      final icon = tester.widget<IconButton>(
        find.descendant(of: search, matching: find.byType(IconButton)),
      );
      icon.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedScale>(
              find.descendant(of: search, matching: find.byType(AnimatedScale)),
            )
            .scale,
        1.12,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final settings = find.ancestor(
        of: find.byTooltip('Control Centre'),
        matching: find.byType(HomeControlButton),
      );
      expect(
        tester
            .widget<AnimatedScale>(
              find.descendant(
                of: settings,
                matching: find.byType(AnimatedScale),
              ),
            )
            .scale,
        1.12,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'scaled preview does not scroll the bottom dock on initial focus',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 810);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final apps = [
        for (var i = 0; i < 18; i++)
          LauncherAppItem(
            id: 'scaled$i',
            name: 'App $i',
            artwork: Future.value(null),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FittedBox(
            child: SizedBox(
              width: 960,
              height: 540,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(size: const Size(960, 540)),
                child: ClipRect(child: child!),
              ),
            ),
          ),
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
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      expect(scroll.offset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(200));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
