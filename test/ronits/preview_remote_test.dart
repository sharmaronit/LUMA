import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/preview_remote.dart';

void main() {
  testWidgets('remote OK and Back work on standard dialog controls', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final remote = LauncherRemoteController();
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        shortcuts: previewRemoteShortcuts,
        builder: (_, child) => PreviewRemote(
          navigatorKey: navigator,
          controller: remote,
          child: child!,
        ),
        home: const Scaffold(),
      ),
    );
    for (final back in [
      LogicalKeyboardKey.goBack,
      LogicalKeyboardKey.gameButtonB,
    ]) {
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: TextButton(
              autofocus: true,
              onPressed: () => activations++,
              child: const Text('Apply'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final ok in [
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.numpadEnter,
        LogicalKeyboardKey.gameButtonA,
      ]) {
        final before = activations;
        await tester.sendKeyEvent(ok);
        await tester.pumpAndSettle();
        expect(activations, before + 1);
      }
      await tester.sendKeyEvent(
        back,
        physicalKey: back == LogicalKeyboardKey.goBack
            ? PhysicalKeyboardKey.escape
            : PhysicalKeyboardKey.gameButtonB,
      );
      await tester.pumpAndSettle();
      expect(find.text('Apply'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    remote.dispose();
  });

  testWidgets(
    'desktop remote navigates, selects, opens panels and preserves typing',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final navigator = GlobalKey<NavigatorState>();
      final remote = LauncherRemoteController();
      final apps = [
        for (final name in ['YouTube', 'Netflix'])
          LauncherAppItem(id: name, name: name, artwork: Future.value(null)),
      ];
      String? launched;
      await tester.pumpWidget(
        MaterialApp(
          shortcuts: {
            // Emulate web defaults before applying the TV remote override.
            const SingleActivator(LogicalKeyboardKey.arrowRight):
                const ScrollIntent(direction: AxisDirection.right),
            ...previewRemoteShortcuts,
          },
          navigatorKey: navigator,
          builder: (_, child) => PreviewRemote(
            navigatorKey: navigator,
            controller: remote,
            child: child!,
          ),
          home: LauncherHome(
            apps: apps,
            favorites: apps,
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: LauncherMaterial.solid,
            remoteController: remote,
            onMaterialChanged: (_) {},
            onLaunch: (app) async {
              launched = app.id;
            },
            onSettings: () {},
            onWifi: () {},
            onManage: () {},
            onFavorite: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(launched, 'Netflix');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(find.text('Remove from favourites'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('anchored-app-menu')),
          matching: find.text('Netflix'),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Remove from favourites'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'shqm');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(find.text('Luma Settings'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(find.text('Luma Settings'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      expect(find.text('Luma Settings'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(launched, 'YouTube');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );
}
