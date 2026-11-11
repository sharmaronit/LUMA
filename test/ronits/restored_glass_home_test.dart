import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';

void main() {
  testWidgets(
    'glass Home preserves the scenery, fits six favourites and reveals content on Down',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final size in [const Size(960, 540), const Size(1600, 900)]) {
        tester.view.physicalSize = size;
        SharedPreferences.setMockInitialValues({
          'minimal_background': 'glass',
          'home_wallpaper_accent': false,
          'home_remember_selection': false,
          'home_show_watch': true,
        });
        await tester.pumpWidget(
          PreviewApp(preferences: await SharedPreferences.getInstance()),
        );
        await tester.pumpAndSettle();
        final dock = tester.getRect(
          find.byKey(const ValueKey('home-favourites-dock')),
        );
        expect(dock.top, greaterThan(size.height * .58));
        expect(dock.bottom, lessThan(size.height));
        final rail = tester.getRect(
          find.byKey(const PageStorageKey('minimal-favourites-rail')),
        );
        for (final id in [
          'youtube',
          'netflix',
          'jiohotstar',
          'primevideo',
          'sonyliv',
          'zee5',
        ]) {
          final card = tester.getRect(
            find.byKey(ValueKey('minimal-focus-$id')).first,
          );
          expect(card.left, greaterThanOrEqualTo(rail.left));
          expect(card.right, lessThanOrEqualTo(rail.right));
          expect(card.top, greaterThan(dock.top));
          expect(card.bottom, lessThan(dock.bottom));
        }
        expect(find.text('From your apps').hitTestable(), findsNothing);
        final search = tester.getRect(find.byTooltip('Search apps'));
        final clock = tester.getRect(
          find.byKey(const ValueKey('home-clock-pill')),
        );
        expect(search.left, lessThan(64));
        expect(search.width, closeTo(search.height, .01));
        expect(clock.right, greaterThan(size.width - 64));
        expect(
          clock.left,
          greaterThan(tester.getRect(find.byTooltip('All apps')).right + 32),
        );
        final active = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('glass-favourite-highlight-youtube')).first,
        );
        expect((active.decoration as BoxDecoration).color!.a, 0);
        expect(find.byType(BackdropFilter), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final content = tester.getRect(find.text('From your apps'));
        expect(content.top, greaterThanOrEqualTo(16));
        expect(content.top, lessThan(size.height * .5));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
