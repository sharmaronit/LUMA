import 'package:luma/ronits/first_run_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('app.luma.tvlauncher/method');
  testWidgets(
    'five-step setup saves choices and checks default Home without requesting permissions',
    (tester) async {
      final calls = <MethodCall>[];
      var home = false;
      var completed = false;
      var favorites = 0;
      String? background;
      bool? sounds;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'requestSetupPermission') home = true;
        if (call.method == 'getSetupStatus') return {'home': home};
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FirstRunGuide(
            onComplete: () async {
              completed = true;
            },
            onChooseFavorites: () async {
              favorites++;
            },
            onBackgroundChanged: (value) async {
              background = value;
            },
            onSoundsChanged: (value) async {
              sounds = value;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 5'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose dock apps'));
      await tester.pumpAndSettle();
      expect(favorites, 1);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simple dark'));
      await tester.pumpAndSettle();
      expect(background, 'charcoal');
      await tester.tap(find.text('Navigation sounds: On'));
      await tester.pumpAndSettle();
      expect(sounds, false);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Preview sound'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Navigation sounds: Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview sound'));
      await tester.pumpAndSettle();
      expect(calls.any((call) => call.method == 'playNavigationSound'), true);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose default Home app'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Luma is your Home'), findsOneWidget);
      expect(
        calls
            .where((call) => call.method == 'requestSetupPermission')
            .map((call) => call.arguments),
        ['home'],
      );
      expect(calls.any((call) => call.method == 'startVoiceSearch'), false);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Luma'));
      await tester.pumpAndSettle();
      expect(completed, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unavailable Home selection explains failure and setup can still finish',
    (tester) async {
      var completed = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'requestSetupPermission')
          throw PlatformException(code: 'unavailable');
        return {'home': false};
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
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
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Choose default Home app'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not complete'), findsOneWidget);
      await tester.tap(find.text('Set up later'));
      await tester.pumpAndSettle();
      expect(completed, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
