import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';

void main() {
  for (final order in [
    ['recent'],
    ['watch', 'recent'],
    ['recent', 'watch'],
  ]) {
    testWidgets(
      'remote follows visible Home rows in order $order, then All apps',
      (tester) async {
        tester.view.physicalSize = const Size(960, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        SharedPreferences.setMockInitialValues({
          'home_wallpaper_accent': false,
          'home_show_recent': true,
          'home_show_watch': order.contains('watch'),
          'home_row_order': [...order, if (!order.contains('watch')) 'watch'],
        });
        final apps = [
          for (var i = 0; i < 30; i++)
            LauncherAppItem(id: 'a$i', name: 'App $i'),
        ];
        final remote = LauncherRemoteController();
        addTearDown(remote.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: LauncherHome(
              remoteController: remote,
              apps: apps,
              favorites: apps.take(4).toList(),
              recentApps: apps.skip(5).take(3).toList(),
              wallpaper: const AssetImage('unused'),
              mode: LauncherMaterial.minimal,
              onMaterialChanged: (_) {},
              onLaunch: (_) async {},
              onSettings: () {},
              onWifi: () {},
              onManage: () {},
              onFavorite: (_) async {},
              homeContinueWatching: SizedBox(
                height: 130,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 12,
                  itemBuilder: (_, i) => SizedBox(
                    width: 220,
                    child: TextButton(
                      key: ValueKey('watch-$i'),
                      onPressed: () {},
                      child: Text('Programme $i'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
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

        Future<void> press(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        for (final row in order.where((row) => row == 'watch')) {
          await press(LogicalKeyboardKey.arrowDown);
          expect(
            focused(row == 'watch' ? 'watch-0' : 'recent-a5'),
            true,
            reason:
                'Down must enter $row; primary=${FocusManager.instance.primaryFocus}; watchFocus=${[for (var i = 0; i < 12; i++)
                  if (focused("watch-$i")) i]}',
          );
        }
        // Home ends after its last row: Down keeps focus where it is.
        final last = FocusManager.instance.primaryFocus;
        await press(LogicalKeyboardKey.arrowDown);
        expect(FocusManager.instance.primaryFocus, same(last));
        expect(find.byKey(const ValueKey('all-apps-page')), findsNothing);
        remote.send(LauncherRemoteCommand.home);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('All apps'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('all-apps-page')), findsOneWidget);
        expect(find.text('Recently opened'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(focused('favorite-a0'), true);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
