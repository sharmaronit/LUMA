import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/clock_settings.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/luma_glass_theme.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/scenery_wallpapers.dart';

void main() {
  testWidgets(
    'TV search starts without the IME and Done returns to app selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      var launches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LauncherHome(
            apps: [LauncherAppItem(id: 'netflix', name: 'Netflix')],
            favorites: const [],
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: LauncherMaterial.minimal,
            reducedMotion: true,
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
      await tester.tap(find.byTooltip('Search apps'));
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Search result netflix',
      );
      expect(tester.testTextInput.isVisible, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Netflix');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, false);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Search result netflix',
      );
      expect(launches, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Apply uses remote selection and preserves wallpaper across theme changes',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final theme in ['wallpaper', 'glass', 'glass-real']) {
        SharedPreferences.setMockInitialValues({
          'minimal_background': theme,
          'reduce_motion': true,
          'home_show_watch': false,
        });
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(PreviewApp(preferences: prefs));
        await tester.pumpAndSettle();
        // Wallpapers now opens from quick settings (no settings row on Home).
        await tester.tap(find.byTooltip('Clock'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Wallpapers'));
        await tester.pumpAndSettle();
        final asset = sceneryWallpapers[1].asset;
        final choice = find.byKey(ValueKey('wallpaper-choice-$asset'));
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Apply wallpaper',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(prefs.getString('preview_wallpaper'), asset);
        expect(
          find.byKey(const ValueKey('wallpaper-large-preview')),
          findsNothing,
        );
        final home = tester.widget<LauncherHome>(find.byType(LauncherHome));
        expect(home.wallpaper, AssetImage(asset));
        expect(prefs.getString('minimal_last_background'), 'wallpaper');
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Clock'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Luma settings'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('settings-category-Appearance')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('minimal-background')),
        );
        await tester.tap(find.byKey(const ValueKey('minimal-background')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('minimal-background-charcoal')),
        );
        await tester.pumpAndSettle();
        expect(prefs.getString('minimal_background'), 'wallpaper');
        expect(find.byKey(const ValueKey('home-wallpaper')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'same-path wallpaper replacement rebinds the image in every theme',
    (tester) async {
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      for (final theme in ['wallpaper', 'glass', 'glass-real']) {
        final revision = ValueNotifier<int>(0);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<int>(
              valueListenable: revision,
              builder: (_, value, __) => LauncherHome(
                apps: const [],
                favorites: const [],
                wallpaper: const AssetImage('assets/mountain.jpg'),
                wallpaperRevision: value,
                minimalBackground: theme,
                mode: LauncherMaterial.minimal,
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
        final image = find.byKey(const ValueKey('home-wallpaper-0'));
        final before = tester.element(image);
        revision.value++;
        await tester.pumpAndSettle();
        expect(
          identical(
            before,
            tester.element(find.byKey(const ValueKey('home-wallpaper-1'))),
          ),
          false,
          reason: 'A replaced file must get a fresh image stream in $theme',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        revision.dispose();
      }
    },
  );
  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({
      'reduce_motion': true,
      'home_show_watch': false,
      'home_remember_selection': false,
    });
    await tester.pumpWidget(
      PreviewApp(preferences: await SharedPreferences.getInstance()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('search Down enters results and Up returns to query', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byTooltip('Search apps'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search query');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('Search result '),
    );
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search query');
    await tester.enterText(find.byType(TextField), 'Netflix');
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Search result netflix',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('All apps filters follow remote focus without pressing Select', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byTooltip('All apps'));
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'All apps filter Entertainment',
    );
    expect(find.byKey(const ValueKey('spotify')), findsNothing);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'All apps filter Music',
    );
    expect(find.byKey(const ValueKey('spotify')), findsOneWidget);
    expect(find.byKey(const ValueKey('youtube')), findsNothing);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'clock navigation does not resize; style, format and size are remote accessible',
    (tester) async {
      final sizes = <String>[], styles = <String>[], formats = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ClockSettings(
                  style: 'digital',
                  size: '50',
                  pattern: 'h:mm a',
                  onStyleChanged: styles.add,
                  onSizeChanged: sizes.add,
                  onFormatChanged: formats.add,
                ),
                TextButton(onPressed: () {}, child: const Text('Back')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sizes, isEmpty);
      await key(tester, LogicalKeyboardKey.select);
      expect(styles, ['analog']);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.select);
      expect(formats, ['HH:mm']);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(sizes, isEmpty);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(sizes, ['55']);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Clock format');
      expect(sizes, ['55']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Real glass reuses cached blur in both performance modes', (
    tester,
  ) async {
    for (final economy in [false, true]) {
      await tester.pumpWidget(
        MenuAppearanceScope(
          mode: LauncherMaterial.minimal,
          minimalBackground: 'glass-real',
          economyGlass: economy,
          blurBuilder: (child, _, __) => KeyedSubtree(
            key: const ValueKey('economy-cached-glass'),
            child: child,
          ),
          child: const MaterialApp(
            home: Scaffold(body: LumaGlassPanel(child: Text('Glass'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.byKey(const ValueKey('economy-cached-glass')),
        findsOneWidget,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
}
