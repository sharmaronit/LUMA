import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/ronits/reference_control_center.dart';
import 'package:luma/ronits/liquid_glass_v2.dart';
import 'package:luma/preview_main.dart';

void main() {
  testWidgets(
    'reference controls navigate by remote and invoke real shortcut callbacks',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 260,
                child: ReferenceControlCenter(
                  onWifi: () => actions.add('wifi'),
                  onDeviceSettings: actions.add,
                  onSettings: () => actions.add('luma'),
                  onApps: () => actions.add('apps'),
                  onSearch: () => actions.add('search'),
                  onWallpaper: () => actions.add('wallpaper'),
                  loadStatus: () async => {
                    'network': 'Wi-Fi · Internet available',
                    'bluetooth': 'On · 1 paired accessories',
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('1 paired'), findsOneWidget);
      // Compact layout: one row of round toggles, Wi-Fi first; the
      // shortcut icons, starting with Luma settings, sit below.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(actions, ['wifi']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(actions.last, 'sound');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(actions.last, 'display');
      await tester.tap(find.byTooltip('TV settings'));
      await tester.pumpAndSettle();
      expect(actions.last, 'all');
      for (final name in ['Wi-Fi', 'Bluetooth']) {
        await tester.tap(find.byKey(ValueKey('quick-control-$name')));
        await tester.pumpAndSettle();
      }
      expect(actions.sublist(actions.length - 2), ['wifi', 'bluetooth']);
      for (final label in [
        'Luma settings',
        'Wallpapers',
        'All apps',
        'Search apps',
      ]) {
        await tester.tap(find.byTooltip(label));
        await tester.pumpAndSettle();
      }
      expect(actions.sublist(actions.length - 4), [
        'luma',
        'wallpaper',
        'apps',
        'search',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'add button shares the app artwork centre at different TV sizes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [const Size(960, 540), const Size(1600, 900)]) {
        tester.view.physicalSize = size;
        SharedPreferences.setMockInitialValues({
          'home_remember_selection': false,
          'home_wallpaper_accent': false,
          'minimal_background': 'glass',
        });
        await tester.pumpWidget(
          PreviewApp(preferences: await SharedPreferences.getInstance()),
        );
        await tester.pumpAndSettle();
        final plus = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Add dock apps',
        );
        tester.widget<IconButton>(plus).focusNode!.requestFocus();
        await tester.pumpAndSettle();
        final last = find.byKey(const ValueKey('minimal-focus-zee5')).first;
        final dock = find.byKey(const ValueKey('home-favourites-dock'));
        final shell = tester.widget<LiquidGlassV2>(dock);
        final glass = shell.glassInset.deflateRect(tester.getRect(dock));
        final artwork = tester.getRect(last);
        expect(
          artwork.top - glass.top,
          closeTo(glass.bottom - artwork.bottom, .1),
        );
        expect(
          tester.getCenter(plus).dy,
          closeTo(tester.getCenter(last).dy, 1),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
