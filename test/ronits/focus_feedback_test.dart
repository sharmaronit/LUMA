import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/focus_feedback.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';

void main() {
  testWidgets('hover, remote focus and held Select show visible feedback', (
    tester,
  ) async {
    var launches = 0, options = 0;
    final first = LauncherAppItem(
      id: 'one',
      name: 'One',
      artwork: Future.value(null),
    );
    final second = LauncherAppItem(
      id: 'two',
      name: 'Two',
      artwork: Future.value(null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 220,
              child: FocusHighlightLayer(
                child: Row(
                  children: [
                    Expanded(
                      child: LauncherTile(
                        app: first,
                        autofocus: true,
                        onPressed: () => launches++,
                        onLongPress: () => options++,
                      ),
                    ),
                    const SizedBox(width: 30),
                    Expanded(
                      child: LauncherTile(
                        app: second,
                        onPressed: () => launches++,
                        onLongPress: () => options++,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final underline = find.byKey(const ValueKey('app-focus-underline'));
    expect(underline, findsOneWidget);
    final original = tester.getTopLeft(underline);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('tile-scale-two'))),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(underline).dx, greaterThan(original.dx));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(underline).dx, closeTo(original.dx, 1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('tile-scale-one')))
          .scale,
      .98,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(options, 1);
    expect(launches, 0);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'underline stays under its tile after entrance and viewport resize',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final apps = [
        for (var i = 0; i < 6; i++)
          LauncherAppItem(
            id: '$i',
            name: 'App $i',
            artwork: Future.value(null),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: LauncherHome(
            apps: apps,
            favorites: apps,
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: LauncherMaterial.ronits,
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
      void aligned() {
        final tile = tester.getRect(
          find
              .ancestor(
                of: find.byKey(const ValueKey('tile-scale-0')),
                matching: find.byType(AspectRatio),
              )
              .first,
        );
        final bar = tester.getRect(
          find.byKey(const ValueKey('app-focus-underline')),
        );
        expect(bar.top, closeTo(tile.bottom + 8, 1));
        expect(bar.center.dx, closeTo(tile.center.dx, 1));
      }

      aligned();
      tester.view.physicalSize = const Size(960, 540);
      await tester.pumpAndSettle();
      aligned();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('menu highlight moves while a saved checkmark remains selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              child: FocusHighlightLayer(
                menu: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TvMenuRow(
                      title: 'Network',
                      autofocus: true,
                      onPressed: () {},
                    ),
                    TvMenuRow(title: 'Solid', selected: true, onPressed: () {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
