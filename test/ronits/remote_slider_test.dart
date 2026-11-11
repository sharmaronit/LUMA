import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/widgets/settings/luma_settings_page.dart';
import 'package:luma/ronits/tv_remote_slider.dart';

void main() {
  testWidgets(
    'remote sliders clamp, repeat, skip disabled controls and retain touch input',
    (tester) async {
      var value = 5.0;
      var committed = 5.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, update) => FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: Column(
                  children: [
                    TextButton(
                      autofocus: true,
                      onPressed: () {},
                      child: const Text('Above'),
                    ),
                    TvRemoteSlider(
                      value: value,
                      min: 5,
                      max: 100,
                      divisions: 19,
                      onChanged: (next) => update(() => value = next),
                      onChangeEnd: (next) => committed = next,
                    ),
                    const TvRemoteSlider(
                      value: 0,
                      divisions: 20,
                      onChanged: null,
                    ),
                    TextButton(onPressed: () {}, child: const Text('Below')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(value, 5);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(value, 20);
      expect(committed, 20);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextButton>()
            ?.child,
        isA<Text>(),
      );
      expect(
        (FocusManager.instance.primaryFocus!.context!
                    .findAncestorWidgetOfExactType<TextButton>()!
                    .child
                as Text)
            .data,
        'Below',
      );
      await tester.drag(find.byType(Slider).first, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(value, greaterThan(20));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'volume Up and Down leave the slider without changing its value',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            home: Scaffold(
              body: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: Column(
                  children: [
                    const LumaSoundSettings(),
                    TextButton(onPressed: () {}, child: const Text('Below')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final before = settings.navigationSoundVolume;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(settings.navigationSoundVolume, before);
      final preview = find.byKey(const ValueKey('preview-navigation-sound'));
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextButton>()
            ?.key,
        const ValueKey('preview-navigation-sound'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(settings.navigationSoundVolume, closeTo(before + .05, .001));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(settings.navigationSoundVolume, closeTo(before + .05, .001));
      expect(preview, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
