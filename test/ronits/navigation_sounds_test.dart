import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/ronits/navigation_sounds.dart';

void main() {
  testWidgets(
    'remote tones require movement, respect mute and use saved volume',
    (tester) async {
      SharedPreferences.setMockInitialValues({'navigation_sound_volume': .2});
      final settings = SettingsService(await SharedPreferences.getInstance());
      final first = FocusNode(), second = FocusNode();
      final calls = <MethodCall>[];
      const channel = MethodChannel('app.luma.tvlauncher/method');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'playNavigationSound') calls.add(call);
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        first.dispose();
        second.dispose();
        settings.dispose();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: NavigationSounds(
            child: MaterialApp(
              home: Scaffold(
                body: Focus(
                  onKeyEvent: (_, event) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      if (event is KeyDownEvent || event is KeyRepeatEvent)
                        second.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Row(
                    children: [
                      TextButton(
                        focusNode: first,
                        onPressed: () {},
                        child: const Text('First'),
                      ),
                      TextButton(
                        focusNode: second,
                        onPressed: () {},
                        child: const Text('Second'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      first.requestFocus();
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'Initial/programmatic focus is silent');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(second.hasFocus, isTrue);
      expect(calls.single.method, 'playNavigationSound');
      expect(calls.single.arguments, {'sound': 'move', 'volume': .2});
      calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'No sound at a navigation boundary');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls.single.arguments['sound'], 'select');
      calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(calls.single.arguments['sound'], 'back');
      calls.clear();
      await settings.setAppKeyClickEnabled(false);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await settings.setAppKeyClickEnabled(true);
      await settings.setNavigationSoundVolume(0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getDouble(
          'navigation_sound_volume',
        ),
        0,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, isEmpty, reason: 'Keyboard observer removed on dispose');
    },
  );
}
