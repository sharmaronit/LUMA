import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/providers/apps_service.dart';
import 'package:luma/widgets/settings/applications_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import '../../mocks.dart';
import '../../mocks.mocks.dart';

/// Apps & Favourites (opened from Luma's home): All, Favorites and Hidden.
void main() {
  late MockAppsService appsService;
  final visible = fakeApp(packageName: 'pkg.netflix', name: 'Netflix');
  final other = fakeApp(packageName: 'pkg.youtube', name: 'YouTube');
  final hidden = fakeApp(packageName: 'pkg.old', name: 'Old App', hidden: true);

  setUp(() {
    appsService = MockAppsService();
    final favourites = fakeCategory(name: 'Favorites')..applications.add(visible);
    when(appsService.applications).thenReturn([visible, other, hidden]);
    when(appsService.categories).thenReturn([favourites]);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppsService>.value(
        value: appsService,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ApplicationsPanelPage()),
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => Container()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('All Apps lists visible apps and leaves hidden ones out', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('All Apps'), findsWidgets);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Old App'), findsNothing);
  });

  testWidgets('tabs show favourites and hidden apps', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.star));
    await tester.pumpAndSettle();
    expect(find.text('Favorite Apps'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('YouTube'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Hidden Apps'), findsOneWidget);
    expect(find.text('Old App'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
  });

  testWidgets('Right and Left on the remote switch tabs and stop at the ends', (
    tester,
  ) async {
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      // The page ignores focus-driven tab changes for 150 ms after a key.
      await tester.pump(const Duration(milliseconds: 200));
    }

    await pump(tester);
    await press(LogicalKeyboardKey.arrowRight);
    expect(find.text('Favorite Apps'), findsOneWidget);
    await press(LogicalKeyboardKey.arrowRight);
    expect(find.text('Hidden Apps'), findsOneWidget);
    await press(LogicalKeyboardKey.arrowRight);
    expect(find.text('Hidden Apps'), findsOneWidget, reason: 'last tab');
    await press(LogicalKeyboardKey.arrowLeft);
    await press(LogicalKeyboardKey.arrowLeft);
    expect(find.text('All Apps'), findsOneWidget);
    await press(LogicalKeyboardKey.arrowLeft);
    expect(find.text('All Apps'), findsOneWidget, reason: 'first tab');
    expect(tester.takeException(), isNull);
  });
}
