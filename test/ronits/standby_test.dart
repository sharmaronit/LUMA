import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/standby.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<StandbySettings> settings([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return StandbySettings(await SharedPreferences.getInstance());
}

Future<void> pumpHost(WidgetTester tester, StandbySettings value) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: StandbyHost(
        settings: value,
        idle: const Duration(seconds: 120),
        child: Scaffold(
          body: TextButton(
            autofocus: true,
            onPressed: () {},
            child: const Text('Home'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const screen = ValueKey('standby-screen');

void main() {
  test('defaults: on, analogue, two minutes', () async {
    final value = await settings();
    expect(value.enabled, isTrue);
    expect(value.style, 'analog');
    expect(StandbySettings.idle, const Duration(minutes: 2));
    await value.setStyle('nonsense');
    expect(value.style, 'analog');
    await value.setStyle('colour');
    expect(value.style, 'colour');
  });

  testWidgets('appears after two idle minutes and any button closes it', (
    tester,
  ) async {
    await pumpHost(tester, await settings());
    await tester.pump(const Duration(seconds: 119));
    expect(find.byKey(screen), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(screen), findsOneWidget);
    expect(find.byKey(const ValueKey('standby-analog')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(screen), findsNothing);
    expect(find.text('Home'), findsOneWidget);

    // And it comes back after another idle spell.
    await tester.pump(const Duration(seconds: 121));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(screen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a button press restarts the two minutes', (tester) async {
    await pumpHost(tester, await settings());
    await tester.pump(const Duration(seconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(seconds: 100));
    expect(find.byKey(screen), findsNothing);
  });

  testWidgets('never appears when switched off or in the background', (
    tester,
  ) async {
    final value = await settings({'standby_enabled': false});
    await pumpHost(tester, value);
    await tester.pump(const Duration(seconds: 300));
    expect(find.byKey(screen), findsNothing);

    await value.setEnabled(true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 300));
    expect(find.byKey(screen), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 121));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(screen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('both faces paint at any time of day', (tester) async {
    for (final style in StandbySettings.styles) {
      for (final time in [
        DateTime(2026, 11, 12, 0, 0, 0),
        DateTime(2026, 11, 12, 10, 9, 36),
        DateTime(2026, 11, 12, 23, 59, 59),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: StandbyScreen(style: style, now: () => time),
          ),
        );
        await tester.pump();
        expect(find.byKey(ValueKey('standby-$style')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
