import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:luma/luma_channel.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/providers/watch_next_service.dart';
import 'package:luma/ronits/programme_rail.dart';
import 'package:luma/widgets/watch_next_row.dart';

void main() {
  testWidgets(
    'native Watch Next uses the shared cards and reports failed playback',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      const channel = MethodChannel('app.luma.tvlauncher/method');
      var launches = 0;
      var canRead = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        switch (call.method) {
          case 'checkWatchNextPermission':
            return canRead;
          case 'getWatchNextItems':
            return [
              {
                'id': 7,
                'title': 'Provider programme',
                'description': 'Episode from the provider',
                'packageName': 'test.tv',
                'contentId': 'episode-7',
                'progressPercent': 42,
              },
            ];
          case 'launchWatchNextItem':
            launches++;
            expect((call.arguments as Map)['contentId'], 'episode-7');
            return false;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({'show_watch_next_section': true});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      final service = WatchNextService(LumaChannel());
      await tester.pump();
      await service.refreshPermissionAndItems();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<WatchNextService>.value(value: service),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  size: Size(960, 540),
                  textScaler: TextScaler.linear(1.3),
                ),
                child: const WatchNextRow(showEmptyState: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammeCard), findsOneWidget);
      expect(find.text('Provider programme'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .42,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(ProgrammeCard).first,
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(find.text('This programme could not be opened.'), findsOneWidget);
      canRead = false;
      await service.refreshPermissionAndItems();
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammeCard), findsNothing);
      expect(find.textContaining('Allow access'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      settings.dispose();
    },
  );
  testWidgets(
    'Home shelf uses provider cards and keeps source controls without permission',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      const channel = MethodChannel('app.luma.tvlauncher/method');
      var launches = 0;
      var canRead = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        switch (call.method) {
          case 'checkWatchNextPermission':
            return canRead;
          case 'getWatchNextItems':
            return [
              {
                'id': 7,
                'title': 'Provider programme',
                'description': 'Episode from the provider',
                'packageName': 'test.tv',
                'contentId': 'episode-7',
                'progressPercent': 42,
              },
            ];
          case 'launchWatchNextItem':
            launches++;
            expect((call.arguments as Map)['contentId'], 'episode-7');
            return false;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({'show_watch_next_section': true});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      final service = WatchNextService(LumaChannel());
      await tester.pump();
      await service.refreshPermissionAndItems();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<WatchNextService>.value(value: service),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  size: Size(960, 540),
                  textScaler: TextScaler.linear(1.3),
                ),
                child: const WatchNextRow(homeShelf: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammeCard), findsOneWidget);
      expect(find.text('Provider programme'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .42,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(ProgrammeCard).first,
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(find.text('This programme could not be opened.'), findsOneWidget);
      canRead = false;
      await service.refreshPermissionAndItems();
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammeCard), findsNothing);
      expect(find.textContaining('Allow access'), findsNothing);
      expect(find.text('From your apps'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('programme-filter-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      settings.dispose();
    },
  );
}
