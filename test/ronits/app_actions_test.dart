import 'package:luma/ronits/app_actions.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'long press shows supplied app actions and dispatches the selected action',
    (tester) async {
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      const app = LauncherAppItem(id: 'test.app', name: 'Streaming app');
      String? launched;
      await tester.pumpWidget(
        MaterialApp(
          home: LauncherHome(
            apps: const [app],
            favorites: const [app],
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: LauncherMaterial.minimal,
            reducedMotion: true,
            onMaterialChanged: (_) {},
            onLaunch: (_) async {},
            onSettings: () {},
            onWifi: () {},
            onManage: () {},
            onFavorite: (_) async {},
            loadAppActions: (_) async => const [
              AppQuickAction('shortcut:search', 'Search'),
              AppQuickAction('info', 'App info'),
            ],
            onAppAction: (item, id, query) async {
              expect(item.id, 'test.app');
              launched = id;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quick actions'));
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('App info'), findsOneWidget);
      expect(find.text('Downloads'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(launched, 'shortcut:search');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('app search requires a query and submits trimmed text', (
    tester,
  ) async {
    String? query;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              query = await showDialog<String>(
                context: context,
                builder: (_) => const AppSearchDialog(appName: 'Streaming app'),
              );
            },
            child: const Text('Open search'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Search'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '  nature  ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(query, 'nature');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'native app actions filter malformed entries and send exact package and shortcut ID',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('app.luma.tvlauncher/method');
      MethodCall? launch;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getAppActions')
              return [
                {'id': 'info', 'label': 'App info'},
                {'label': 'Invalid'},
              ];
            launch = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = NativeAppActions();
      final actions = await service.load('test.app');
      expect(actions.map((action) => action.id), ['info']);
      await service.launch('test.app', 'shortcut:search');
      expect(launch?.method, 'launchAppAction');
      expect(launch?.arguments, {
        'package': 'test.app',
        'id': 'shortcut:search',
      });
      await service.launch('test.app', 'search', query: 'nature');
      expect(launch?.arguments, {
        'package': 'test.app',
        'id': 'search',
        'query': 'nature',
      });
    },
  );
}
