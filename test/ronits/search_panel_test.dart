import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/search_panel.dart';
import 'package:luma/ronits/glass_surface.dart';

void main() {
  testWidgets('search remains usable with the TV keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    SharedPreferences.setMockInitialValues({
      'reduce_motion': true,
      'home_wallpaper_accent': false,
    });
    await tester.pumpWidget(
      PreviewApp(preferences: await SharedPreferences.getInstance()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search apps'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'typed search keeps stable geometry while voice uses a compact top island',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({
        'reduce_motion': true,
        'home_wallpaper_accent': false,
      });
      await tester.pumpWidget(
        PreviewApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search apps'));
      await tester.pumpAndSettle();
      final panel = find.byType(FloatingSearchPanel);
      Size surfaceSize() => tester.getSize(
        find.descendant(of: panel, matching: find.byType(GlassSurface)).first,
      );
      final original = surfaceSize();
      final list = tester.widget<ListView>(
        find.descendant(of: panel, matching: find.byType(ListView)).first,
      );
      final children =
          (list.childrenDelegate as SliverChildListDelegate).children;
      expect(
        children.indexWhere((w) => w is Text && w.data == 'Apps'),
        lessThan(
          children.indexWhere((w) => w is Text && w.data == 'Movies & shows'),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Netflix');
      await tester.pumpAndSettle();
      expect(surfaceSize(), original);
      await tester.enterText(find.byType(TextField), 'no matching app');
      await tester.pumpAndSettle();
      expect(surfaceSize(), original);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Voice search'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingSearchPanel), findsNothing);
      final island = find.byKey(const ValueKey('voice-island'));
      expect(tester.getSize(island).height, lessThan(original.height));
      expect(tester.getRect(island).top, 16);
      expect(find.text('Type instead'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
