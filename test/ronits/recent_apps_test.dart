import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/recent_apps.dart';

class FakeSystem implements RecentAppsSystem {
  FakeSystem({this.result = CloseResult.stopped});
  CloseResult result;
  final closed = <String>[];
  int available = 500 * 1024 * 1024;
  @override
  Future<TvMemory?> memory() async =>
      TvMemory(2300 * 1024 * 1024, available);
  @override
  Future<CloseResult> close(String package) async {
    closed.add(package);
    if (result != CloseResult.refused) available += 200 * 1024 * 1024;
    return result;
  }
}

const apps = [
  RecentApp(id: 'com.example.settings', name: 'Settings'),
  RecentApp(id: 'com.example.tv', name: 'TV'),
  RecentApp(id: 'com.example.files', name: 'File Manager'),
];

Future<String?> Function() open(
  WidgetTester tester,
  FakeSystem system, [
  List<RecentApp> list = apps,
]) {
  String? chosen;
  var done = false;
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final ready = tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              chosen = await showRecentApps(
                context,
                apps: list,
                system: system,
              );
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  return () async {
    await ready;
    if (!done && find.text('Recent apps').evaluate().isEmpty) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }
    return chosen;
  };
}

void main() {
  test('memory label', () {
    const memory = TvMemory(2469606195, 536870912);
    expect(memory.label, 'RAM 1.8 GB used of 2.3 GB');
    expect(memory.fraction, closeTo(.78, .01));
    expect(const TvMemory(0, 0).fraction, 0);
  });

  testWidgets('shows recent apps and memory; OK opens the focused app', (
    tester,
  ) async {
    final result = open(tester, FakeSystem());
    await result();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-memory')), findsOneWidget);
    expect(find.text('Press ▲ on an app to close it'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(await result(), 'com.example.tv');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Up closes the focused app and focus moves on', (tester) async {
    final system = FakeSystem();
    final result = open(tester, system);
    await result();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(system.closed, ['com.example.settings']);
    expect(find.byKey(const ValueKey('recent-com.example.settings')), findsNothing);
    expect(find.text('Settings closed.'), findsOneWidget);
    // Focus is on the next app, so OK opens it.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(await result(), 'com.example.tv');
  });

  testWidgets('without the debugging permission it says memory was freed', (
    tester,
  ) async {
    final result = open(tester, FakeSystem(result: CloseResult.freed));
    await result();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.textContaining('memory freed'), findsOneWidget);
  });

  testWidgets('a refused close keeps the app in the list', (tester) async {
    final result = open(tester, FakeSystem(result: CloseResult.refused));
    await result();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-com.example.settings')), findsOneWidget);
    expect(find.textContaining('would not let Luma close'), findsOneWidget);
  });

  testWidgets('closing the last app leaves a clear empty state; Back returns', (
    tester,
  ) async {
    final result = open(tester, FakeSystem(), const [
      RecentApp(id: 'com.example.tv', name: 'TV'),
    ]);
    await result();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-empty')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Recent apps'), findsNothing);
    expect(await result(), isNull);
  });

  testWidgets('no recent apps at all', (tester) async {
    final result = open(tester, FakeSystem(), const []);
    await result();
    expect(find.textContaining('No recent apps yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
