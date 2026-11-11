import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/launcher_backup.dart';
import 'package:luma/ronits/motion.dart';
import 'package:luma/providers/settings_service.dart';

void screen(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(960, 540);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets(
    'minimal has no wallpaper, glass or entrance layer; remote navigation and hold work',
    (tester) async {
      screen(tester);
      var blurCalls = 0, launches = 0;
      final remote = LauncherRemoteController();
      final apps = [
        for (var i = 0; i < 36; i++)
          LauncherAppItem(
            id: 'a$i',
            name: 'App $i',
            artwork: Future.value(null),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MenuAppearanceScope(
            mode: LauncherMaterial.minimal,
            blurBuilder: (child, sigma, saturation) {
              blurCalls++;
              return child;
            },
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
          ),
          home: LauncherHome(
            mode: LauncherMaterial.minimal,
            apps: apps,
            favorites: apps.take(6).toList(),
            wallpaper: const AssetImage('deliberately-not-loaded.jpg'),
            remoteController: remote,
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
      expect(find.text('Favourite apps'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(GlassSurface), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(LumaEntrance), findsNothing);
      expect(find.byKey(const ValueKey('a35')), findsNothing);
      expect(
        tester
            .widget<Scaffold>(find.byKey(const ValueKey('minimal-home')))
            .backgroundColor,
        const Color(0xff1b1c1e),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('minimal-sliding-focus-frame')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('All apps'));
      await tester.pumpAndSettle();
      final firstGrid = find.byKey(const ValueKey('a0'));
      expect(
        find.descendant(
          of: firstGrid,
          matching: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.hasPrimaryFocus == true,
          ),
        ),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final firstFav = find.byKey(const ValueKey('favorite-a0'));
      expect(
        find.descendant(
          of: firstFav,
          matching: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.hasPrimaryFocus == true,
          ),
        ),
        findsOneWidget,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Remove from favourites'), findsOneWidget);
      expect(launches, 0);
      expect(blurCalls, 0);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const ValueKey('minimal-scroll')),
          )
          .controller!;
      await tester.tap(find.byTooltip('All apps'));
      await tester.pumpAndSettle();
      final gridScroll = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('all-apps-grid')),
          )
          .controller!
          .position;
      gridScroll.jumpTo(gridScroll.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('a35')), findsOneWidget);
      remote.send(LauncherRemoteCommand.home);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );

  testWidgets(
    'minimal background persists, stays open and wallpaper is optional',
    (tester) async {
      screen(tester);
      SharedPreferences.setMockInitialValues({'performance_mode': false});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('minimal-home')), findsOneWidget);
      await tester.tap(find.byTooltip('Clock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Luma settings'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-category-Appearance')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Theme'));
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      for (final choice in {
        'Minimal': 'charcoal',
        'Liquid Performative': 'glass',
        'Liquid Glass Real': 'glass-real',
      }.entries) {
        await tester.ensureVisible(
          find.byKey(ValueKey('minimal-background-${choice.value}')),
        );
        await tester.tap(
          find.byKey(ValueKey('minimal-background-${choice.value}')),
        );
        await tester.pumpAndSettle();
        expect(prefs.getString('minimal_background'), choice.value);
        expect(find.text('Theme'), findsWidgets);
        expect(find.byType(BackdropFilter), findsNothing);
        final restored = LauncherBackup.parse(
          LauncherBackup(LauncherBackup.preferencesFrom(prefs), {
            'categories': [],
            'hidden': [],
          }).encode(),
        );
        expect(restored.preferences['minimal_background'], choice.value);
      }
      expect(find.text('OnePlus · White & red'), findsNothing);
      expect(find.text('OnePlus · Black & red'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'minimal preferences survive settings recreation and backup validation',
    () async {
      SharedPreferences.setMockInitialValues({'performance_mode': false});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      await settings.setLauncherMaterial('minimal');
      await settings.setMinimalBackground('glass-real');
      await settings.setMinimalBackground('invalid');
      expect(SettingsService(prefs).minimalBackground, 'glass-real');
      final backup = LauncherBackup(LauncherBackup.preferencesFrom(prefs), {
        'categories': [],
        'hidden': [],
      });
      final restored = LauncherBackup.parse(backup.encode());
      expect(restored.preferences['minimal_background'], 'glass-real');
      expect(restored.preferences['launcher_material'], 'minimal');
    },
  );
}
