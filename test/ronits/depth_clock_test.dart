import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/depth_clock.dart';
import 'package:luma/ronits/scenery_wallpapers.dart';

void main() {
  test('every depth wallpaper is in the gallery and has its cut-out', () {
    for (final asset in depthWallpapers.keys) {
      expect(sceneryWallpapers.any((photo) => photo.asset == asset), isTrue);
      expect(File(depthLayerAsset(asset)).existsSync(), isTrue, reason: asset);
    }
    expect(hasDepthLayer('assets/wallpapers/coast.jpg'), isFalse);
    expect(hasDepthLayer(null), isFalse);
  });

  test('the clock and its date sit below the top bar and above the dock', () {
    for (final (:x, :bottom, :height) in depthWallpapers.values) {
      expect(height, inInclusiveRange(.15, .33));
      // Date line above the digits still clears the top bar.
      expect(bottom - height - .05, greaterThan(.05));
      expect(bottom, lessThan(.67));
      // The cut-out strip stays on screen and covers the digits.
      final strip = depthStripRect(const Size(1920, 1080), bottom, x);
      expect(strip.left, greaterThanOrEqualTo(0));
      expect(strip.right, lessThanOrEqualTo(1920));
      expect(strip.top, greaterThanOrEqualTo(0));
      expect(strip.bottom, lessThanOrEqualTo(1080));
      expect(strip.top, lessThanOrEqualTo(1080 * (bottom - height)));
      expect(strip.bottom, greaterThan(1080 * bottom));
    }
  });

  test('cut-out strip lands on the generator\'s pixels', () {
    final rect = depthStripRect(const Size(1920, 1080), .42);
    expect(rect, const Rect.fromLTWH(384, 41, 1152, 441));
  });

  test('date line reads like a lock screen', () {
    expect(depthClockDate(DateTime(2026, 10, 27)), 'Tuesday 27 October');
  });

  test('digits never include AM or PM', () {
    final time = DateTime(2026, 11, 12, 21, 5);
    expect(depthClockText(time, 'h:mm a'), '9:05');
    expect(depthClockText(time, 'HH:mm'), '21:05');
    expect(depthClockText(time, 'H:mm'), '21:05');
  });

  testWidgets('draws one finished picture once the cut-out has loaded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: DepthClock(
            wallpaper: 'assets/wallpapers/dolomites.jpg',
            image: const AssetImage('assets/wallpapers/dolomites.jpg'),
            pattern: 'HH:mm',
            now: () => DateTime(2026, 11, 12, 10, 42),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find
            .byKey(const ValueKey('depth-clock-layer'))
            .evaluate()
            .isNotEmpty)
          break;
      }
    });
    expect(find.byKey(const ValueKey('depth-clock-layer')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows nothing on a screen that is not 16:9', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: DepthClock(
          wallpaper: 'assets/wallpapers/dolomites.jpg',
          image: AssetImage('assets/wallpapers/dolomites.jpg'),
          pattern: 'HH:mm',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('depth-clock-layer')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
