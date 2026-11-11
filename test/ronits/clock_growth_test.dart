import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/liquid_glass_v2.dart';

void main() {
  for (final style in ['digital', 'analog']) {
    testWidgets(
      '$style Home clock visibly grows across the size range without clipping',
      (tester) async {
        tester.view.physicalSize = const Size(960, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        SharedPreferences.setMockInitialValues({
          'home_clock_style': style,
          'home_clock_size': '0',
          'minimal_background': 'glass',
          'home_wallpaper_accent': false,
        });
        final preferences = await SharedPreferences.getInstance();
        await tester.pumpWidget(PreviewApp(preferences: preferences));
        await tester.pumpAndSettle();
        final face = find.byKey(ValueKey('luma-$style-clock'));
        final small = tester.getRect(face);
        await tester.tap(find.byTooltip('Clock'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Luma settings'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('settings-category-Appearance')),
        );
        await tester.pumpAndSettle();
        final section = find.byKey(const ValueKey('setting-clock-section'));
        await tester.ensureVisible(section);
        await tester.tap(section);
        await tester.pumpAndSettle();
        final slider = find.byKey(const ValueKey('setting-clock-size-slider'));
        await tester.ensureVisible(slider);
        final rect = tester.getRect(slider);
        await tester.tapAt(Offset(rect.right - 25, rect.center.dy));
        await tester.pumpAndSettle();
        expect(
          int.parse(preferences.getString('home_clock_size')!),
          greaterThanOrEqualTo(95),
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        final large = tester.getRect(face);
        expect(
          large.height,
          greaterThan(small.height * (style == 'digital' ? 1.6 : 2.5)),
        );
        final pill = tester.getRect(
          find.byKey(const ValueKey('home-clock-pill')),
        );
        final clock = tester.getRect(face);
        final panel = tester.widget<LiquidGlassV2>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('home-clock-pill')),
                matching: find.byType(LiquidGlassV2),
              )
              .first,
        );
        expect(panel.enabled, style == 'digital');
        expect(clock.top, greaterThan(pill.top));
        expect(clock.bottom, lessThan(pill.bottom));
        expect(pill.bottom, lessThan(220));
        expect(
          tester
              .getRect(find.byKey(const ValueKey('home-favourites-dock')))
              .bottom,
          lessThan(540),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
