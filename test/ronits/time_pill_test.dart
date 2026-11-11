import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';

void main() {
  testWidgets(
    'glass action pills sample prepared wallpaper without live image filters',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      final app = LauncherAppItem(id: 'app', name: 'App');
      await tester.pumpWidget(
        MenuAppearanceScope(
          mode: LauncherMaterial.minimal,
          minimalBackground: 'glass',
          blurBuilder: (child, sigma, saturation) => KeyedSubtree(
            key: const ValueKey('test-blur-surface'),
            child: child,
          ),
          child: MaterialApp(
            home: LauncherHome(
              apps: [app],
              favorites: [app],
              wallpaper: const AssetImage('assets/mountain.jpg'),
              mode: LauncherMaterial.minimal,
              minimalBackground: 'glass',
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
      final header = find.byKey(const ValueKey('home-action-pills'));
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('liquid-glass-v2')),
        ),
        findsNWidgets(4),
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('test-blur-surface')),
        ),
        findsNWidgets(4),
      );
      expect(find.byKey(const ValueKey('test-blur-surface')), findsWidgets);
      expect(
        find.descendant(of: header, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      expect(
        find.descendant(of: header, matching: find.byType(ImageFiltered)),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final button = tester.widget<TextButton>(
        find.descendant(
          of: find.byTooltip('Search apps'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.focusNode!.hasFocus, true);
      expect(find.byKey(const ValueKey('test-blur-surface')), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Home has compact action pills and remote can open settings and search',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({
        'home_wallpaper_accent': false,
        'home_show_watch': false,
        'time_format': 'HH:mm',
      });
      await tester.pumpWidget(
        PreviewApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsNothing);
      expect(find.text('Apps'), findsNothing);
      final pill = find.byKey(const ValueKey('home-clock-pill'));
      expect(pill, findsOneWidget);
      expect(
        find.descendant(of: pill, matching: find.byType(Text)),
        findsOneWidget,
      );
      final label = tester
          .widget<Text>(find.descendant(of: pill, matching: find.byType(Text)))
          .data!;
      expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(label), true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final button = tester.widget<TextButton>(
        find.descendant(
          of: find.byTooltip('Search apps'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.focusNode!.hasFocus, true);
      final shape =
          button.style!.shape!.resolve({WidgetState.focused}) as CircleBorder;
      expect(shape.side.width, 2);
      expect(find.byTooltip('Voice search'), findsOneWidget);
      expect(find.byTooltip('All apps'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byTooltip('All apps')).dx,
        greaterThan(tester.getTopLeft(find.byTooltip('Voice search')).dx),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reference-control-center')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Luma settings'));
      await tester.pumpAndSettle();
      expect(find.text('Luma Settings'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
