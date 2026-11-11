import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/programme_rail.dart';

void main() {
  testWidgets(
    'cinematic cards keep long metadata readable at TV text sizes and omit unknown progress',
    (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: Center(
                  child: SizedBox(
                    width: 292,
                    height: 210,
                    child: ProgrammeCard(
                      title: 'A programme with a very long title that must fit',
                      provider: 'A streaming service with a long name',
                      subtitle: 'Episode details supplied by the provider',
                      footer: 'Continue watching',
                      onPressed: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('A programme with a very long title that must fit'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('programme-artwork-gradient')),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'empty content collapses and All apps follows a compact favourites section',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      final apps = [
        for (var i = 0; i < 12; i++) LauncherAppItem(id: 'a$i', name: 'App $i'),
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
      expect(find.byKey(const ValueKey('home-watch-row')), findsNothing);
      final appsHeading = tester.getTopLeft(
        find.byKey(const ValueKey('open-all-apps')),
      );
      final favouriteBottom = tester.getBottomLeft(
        find.byKey(const ValueKey('favorite-a0')),
      );
      expect(appsHeading.dy, lessThan(540));
      expect(appsHeading.dy - favouriteBottom.dy, lessThan(130));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Home artwork shows real title samples with brands and no invented progress',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      await tester.pumpWidget(
        PreviewApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('From your apps'), findsOneWidget);
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('Fallout'), findsOneWidget);
      expect(find.text('Prime Video'), findsWidgets);
      expect(find.textContaining('Artwork preview'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
