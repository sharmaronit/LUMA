import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/home_preferences.dart';
import 'package:luma/ronits/launcher_backup.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';

void tv(WidgetTester tester) {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('wallpaper accent samples once and changes with wallpaper', (
    tester,
  ) async {
    tv(tester);
    SharedPreferences.setMockInitialValues({});
    Future<MemoryImage> wallpaper(Color color) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(color, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      image.dispose();
      return MemoryImage(data!.buffer.asUint8List());
    }

    final red = await tester.runAsync(() => wallpaper(Colors.red));
    final blue = await tester.runAsync(() => wallpaper(Colors.blue));
    final app = LauncherAppItem(id: 'a', name: 'A');
    Widget home(ImageProvider image) => MaterialApp(
      home: LauncherHome(
        apps: [app],
        favorites: [app],
        wallpaper: image,
        mode: LauncherMaterial.minimal,
        onMaterialChanged: (_) {},
        onLaunch: (_) async {},
        onSettings: () {},
        onWifi: () {},
        onManage: () {},
        onFavorite: (_) async {},
      ),
    );
    await tester.pumpWidget(home(red!));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    Color? accent() => tester
        .widget<WallpaperAccentScope>(find.byType(WallpaperAccentScope).first)
        .color;
    expect(accent(), isNotNull);
    expect(accent()!.r, greaterThan(accent()!.b));
    final first = accent();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(accent(), first);
    await tester.pumpWidget(home(blue!));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    expect(accent()!.b, greaterThan(accent()!.r));
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('card sizes update Home live and settings remain open', (
    tester,
  ) async {
    tv(tester);
    SharedPreferences.setMockInitialValues({
      'home_wallpaper_accent': false,
      'home_show_watch': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(PreviewApp(preferences: prefs));
    await tester.pumpAndSettle();
    double cardWidth() => tester
        .getSize(find.byKey(const ValueKey('minimal-focus-youtube')).first)
        .width;
    final initial = cardWidth();
    await tester.tap(find.byTooltip('Clock'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Luma settings'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-category-Home & Apps')),
    );
    await tester.pumpAndSettle();
    final layout = find
        .byKey(const ValueKey('setting-categories-and-layout'))
        .last;
    await tester.ensureVisible(layout);
    await tester.tap(layout);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-size-large')));
    await tester.pumpAndSettle();
    expect(prefs.getString('home_card_size'), 'large');
    expect(cardWidth(), greaterThan(initial));
    expect(find.byKey(const ValueKey('home-card-preview')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-From your apps')));
    await tester.pumpAndSettle();
    expect(prefs.getBool('home_show_watch'), true);
    expect(find.text('Home & Apps'), findsWidgets);
    expect(find.byKey(const ValueKey('home-row-order')), findsNothing);
    expect(find.byKey(const ValueKey('home-show-recent')), findsNothing);
    expect(find.byKey(const ValueKey('home-content-shortcut')), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-watch-row')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'favourite selection restores after restart and removed app falls back',
    (tester) async {
      tv(tester);
      SharedPreferences.setMockInitialValues({
        'home_wallpaper_accent': false,
        'home_selected_app': 'netflix',
        'home_selected_library': false,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Semantics>()
            ?.properties
            .label,
        'Netflix',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      final saved = prefs.getString('home_selected_app');
      expect(saved, isNot('netflix'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(prefs.getString('home_selected_app'), saved);
      await tester.pumpWidget(const SizedBox());
      await prefs.setString('home_selected_app', 'removed.app');
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Semantics>()
            ?.properties
            .label,
        'YouTube',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('deep library app restores into lazy grid after restart', (
    tester,
  ) async {
    tv(tester);
    SharedPreferences.setMockInitialValues({
      'home_wallpaper_accent': false,
      'home_selected_app': 'a42',
      'home_selected_library': true,
    });
    final apps = [
      for (var i = 0; i < 60; i++) LauncherAppItem(id: 'a$i', name: 'App $i'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: LauncherHome(
          apps: apps,
          favorites: apps.take(4).toList(),
          wallpaper: const AssetImage('unused'),
          mode: LauncherMaterial.minimal,
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
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<Semantics>()
          ?.properties
          .label,
      'App 42',
    );
    expect(find.byKey(const ValueKey('a42')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'Home preferences validate defaults and round-trip through backup',
    () async {
      SharedPreferences.setMockInitialValues({
        'home_card_size': 'large',
        'home_show_watch': true,
        'home_row_order': ['recent', 'watch'],
        'home_remember_selection': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final home = HomePreferences(prefs);
      await home.saveSelection('private.app', true, 100);
      expect(home.selected, isNull);
      final backup = LauncherBackup(LauncherBackup.preferencesFrom(prefs), {
        'categories': [],
        'hidden': [],
      });
      final restored = LauncherBackup.parse(backup.encode());
      expect(restored.preferences['home_card_size'], 'large');
      expect(restored.preferences['home_row_order'], ['recent', 'watch']);
      expect(restored.preferences.containsKey('home_selected_app'), false);
    },
  );
}
