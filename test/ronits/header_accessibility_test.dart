import 'package:luma/preview_main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('each Home utility button has its own accessible label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handle = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
    await tester.pumpWidget(
      PreviewApp(preferences: await SharedPreferences.getInstance()),
    );
    await tester.pumpAndSettle();
    for (final label in ['Search apps', 'Voice search', 'All apps', 'Clock']) {
      final button = find.descendant(
        of: find.byTooltip(label),
        matching: find.byType(TextButton),
      );
      expect(
        tester.getSemantics(button).label,
        contains(label),
        reason: '$label must label the button itself',
      );
    }
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });
}
