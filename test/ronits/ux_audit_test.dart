import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/ronits/focus_feedback.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/quick_settings.dart';
import 'package:luma/ronits/programme_library.dart';
import 'package:luma/ronits/programme_browser.dart';
import 'package:luma/widgets/settings/luma_settings_page.dart';
import 'package:luma/ronits/scenery_wallpapers.dart';
import 'package:luma/ronits/first_run_guide.dart';

void main() {
  testWidgets('remote Back returns to the previous setup step', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FirstRunGuide(
          onComplete: () async {
            completed = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    // The remote's Back arrives as a system back (route pop) on Android TV.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Luma'), findsOneWidget);
    expect(completed, false);
    // On the first step, Back finishes the guide - exactly once.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(completed, true);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'failed photo import stays in the picker with recovery feedback',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSceneryPicker(
                  context,
                  onCustomWallpaper: () async =>
                      throw StateError('unreadable photo'),
                ),
                child: const Text('Wallpapers'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Wallpapers'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-wallpaper')));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open that photo. Try another image.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('apply-wallpaper')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('wallpaper Minimal theme opens with its selected row focused', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: QuickSettingsContent(
              mode: LauncherMaterial.minimal,
              reducedMotion: true,
              initialCategory: 'Appearance',
              minimalBackground: 'wallpaper',
              onMinimalBackgroundChanged: (_) {},
              onMaterialChanged: (_) {},
              onWifi: () {},
              onSettings: () {},
              onDeviceSettings: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TvMenuRow>()
          ?.title,
      'Minimal',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sound preview uses saved volume and is disabled when muted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(await SharedPreferences.getInstance());
    const channel = MethodChannel('app.luma.tvlauncher/method');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(home: Scaffold(body: LumaSoundSettings())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preview-navigation-sound')));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'playNavigationSound');
    expect(calls.single.arguments, {
      'sound': 'select',
      'volume': settings.navigationSoundVolume,
    });
    await settings.setAppKeyClickEnabled(false);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('preview-navigation-sound')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('source picker explains missing access and refresh failures', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final library = ProgrammeLibrary.shared;
    await tester.runAsync(library.ready);
    library.replace([]);
    library.registerSources({}, allowed: false);
    library.refreshSources = () async => throw StateError('offline');
    addTearDown(() {
      library.refreshSources = null;
      library.registerSources({}, allowed: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProgrammeSources(context),
              child: const Text('Sources'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sources'));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(
      find.text('Allow content access to find programme cards from your apps.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not refresh programme sources. Please try again.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
