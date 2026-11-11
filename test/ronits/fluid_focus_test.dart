import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:provider/provider.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/widgets/settings/wallpaper_panel_page.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/launcher_backup.dart';
import 'package:luma/ronits/launcher_home.dart';

void main() {
  testWidgets(
    'hovering a partially visible favourite does not scroll the row',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({
        'minimal_background': 'glass',
        'home_card_size': 'large',
        'home_wallpaper_accent': false,
        'home_remember_selection': false,
      });
      await tester.pumpWidget(
        PreviewApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pumpAndSettle();
      final rail = find.byKey(const PageStorageKey('minimal-favourites-rail'));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: rail, matching: find.byType(Scrollable)),
      );
      final viewport = tester.getRect(rail);
      final card = tester.getRect(
        find.byKey(const ValueKey('favorite-sonyliv')),
      );
      expect(card.right, greaterThan(viewport.right));
      final before = scroll.position.pixels;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(Offset(viewport.right - 8, card.center.dy - 20));
      await tester.pumpAndSettle();
      expect(
        scroll.position.pixels,
        before,
        reason: 'Mouse hover must not slide or crop the row under the pointer',
      );
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mouse hover keeps rounded cards within their own motion slots', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({
      'minimal_background': 'glass',
      'home_wallpaper_accent': false,
      'home_remember_selection': false,
    });
    await tester.pumpWidget(
      PreviewApp(preferences: await SharedPreferences.getInstance()),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    void expectContained(String id) {
      final slot = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey('favorite-$id')),
          matching: find.byKey(ValueKey('minimal-card-motion-slot-$id')),
        ),
      );
      final card = tester.getRect(
        find
            .descendant(
              of: find.byKey(ValueKey('favorite-$id')),
              matching: find.byType(ClipRSuperellipse),
            )
            .first,
      );
      expect(
        card.top,
        greaterThanOrEqualTo(slot.top),
        reason: 'Hover must paint the entire rounded top inside the tile',
      );
      expect(card.bottom, lessThanOrEqualTo(slot.bottom));
    }

    for (final id in ['netflix', 'jiohotstar', 'netflix', 'jiohotstar']) {
      await mouse.moveTo(
        tester.getCenter(find.byKey(ValueKey('favorite-$id'))),
      );
      await tester.pump();
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        for (final visible in ['youtube', 'netflix', 'jiohotstar']) {
          expectContained(visible);
        }
      }
    }
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'favourite top corners stay inside the rail throughout focus movement',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final background in ['charcoal', 'glass']) {
        SharedPreferences.setMockInitialValues({
          'minimal_background': background,
          'home_remember_selection': false,
          'home_wallpaper_accent': false,
        });
        await tester.pumpWidget(
          PreviewApp(preferences: await SharedPreferences.getInstance()),
        );
        await tester.pumpAndSettle();
        void expectCompleteCorners(String id) {
          final rail = tester.getRect(
            find.byKey(const PageStorageKey('minimal-favourites-rail')),
          );
          final card = tester.getRect(
            find
                .descendant(
                  of: find.byKey(ValueKey('favorite-$id')),
                  matching: find.byType(ClipRSuperellipse),
                )
                .first,
          );
          expect(
            card.top,
            greaterThanOrEqualTo(rail.top + 2),
            reason:
                'The lifted rounded edge needs clearance from the rail clip',
          );
          expect(card.bottom, lessThanOrEqualTo(rail.bottom));
        }

        expectCompleteCorners('youtube');
        for (final id in ['netflix', 'jiohotstar']) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));
          expectCompleteCorners(id);
          await tester.pumpAndSettle();
          expectCompleteCorners(id);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('landscape focus tracks TV cards and respects reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(PreviewApp(preferences: prefs));
    await tester.pumpAndSettle();
    Rect logo(String id) =>
        tester.getRect(find.byKey(ValueKey('minimal-focus-$id')).first);
    expect(
      find.byKey(const ValueKey('minimal-sliding-focus-frame')),
      findsNothing,
    );
    final raised = logo('youtube');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final resting = logo('youtube');
    expect(resting.top - raised.top, closeTo(resting.height * .0175, .5));
    expect(raised.width, closeTo(resting.width * 1.035, .5));
    expect(raised.height, closeTo(resting.height * 1.035, .5));
    double labelOpacity(String id) => tester
        .widget<AnimatedOpacity>(
          find
              .descendant(
                of: find.byKey(ValueKey('favorite-$id')),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;
    expect(labelOpacity('youtube'), 0);
    expect(labelOpacity('netflix'), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(logo('youtube').top, closeTo(raised.top, .5));
    await tester.pumpWidget(const SizedBox());
    await prefs.setBool('reduce_motion', true);
    await tester.pumpWidget(PreviewApp(preferences: prefs));
    await tester.pumpAndSettle();
    final still = logo('youtube');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(logo('youtube').top, still.top);
    expect(
      find.byKey(const ValueKey('minimal-sliding-focus-frame')),
      findsNothing,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late artwork keeps landscape card geometry stable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final bytes = await tester.runAsync(
      () => rootBundle.load('assets/preview/banner-youtube.png'),
    );
    final pending = Completer<ImageProvider?>();
    final app = LauncherAppItem(
      id: 'late',
      name: 'Delayed icon',
      icon: pending.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LauncherHome(
          mode: LauncherMaterial.minimal,
          apps: [app],
          favorites: [app],
          wallpaper: const AssetImage('unused.jpg'),
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
    await tester.pump(const Duration(milliseconds: 500));
    Rect art() =>
        tester.getRect(find.byKey(const ValueKey('minimal-focus-late')).first);
    final before = art();
    expect(before.width, greaterThan(before.height * 1.4));
    pending.complete(
      MemoryImage(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    await tester.pumpAndSettle();
    expect(art().size, before.size);
    expect(
      find.byKey(const ValueKey("minimal-sliding-focus-frame")),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'clean wallpaper settings expose static photos rather than legacy video effects',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: WallpaperPanelPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
      expect(find.byIcon(Icons.gradient), findsNothing);
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
      await settings.setTimeBasedWallpaperEnabled(true);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.wb_sunny), findsOneWidget);
      expect(find.byIcon(Icons.nights_stay), findsOneWidget);
      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  test(
    'retired appearances migrate without losing theme or app layout',
    () async {
      for (final retired in ['ronits', 'frosted', 'lite', 'solid']) {
        SharedPreferences.setMockInitialValues({
          'launcher_material': retired,
          'minimal_background': 'oxygen-black',
        });
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsService(prefs);
        expect(settings.launcherMaterial, 'minimal');
        expect(settings.minimalBackground, 'charcoal');
        expect(prefs.getString('launcher_material'), 'minimal');
        expect(LauncherMaterial.fromName(retired), LauncherMaterial.minimal);
        final backup = LauncherBackup.parse(
          LauncherBackup(
            {
              'launcher_material': retired,
              'minimal_background': 'oxygen-black',
            },
            {'categories': [], 'hidden': []},
          ).encode(),
        );
        expect(backup.preferences['launcher_material'], 'minimal');
        expect(backup.preferences['minimal_background'], 'oxygen-black');
        settings.dispose();
      }
    },
  );
}
