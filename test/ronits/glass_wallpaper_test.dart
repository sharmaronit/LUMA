import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/glass_wallpaper.dart';

void main() {
  testWidgets('prepared glass wallpaper retains scroll-dependent contrast', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final scroll = ScrollController();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  key: boundary,
                  child: GlassWallpaper(
                    image: const AssetImage('assets/mountain.jpg'),
                    scroll: scroll,
                  ),
                ),
              ),
              ListView(
                controller: scroll,
                children: const [SizedBox(height: 1000)],
              ),
            ],
          ),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 10 &&
          find
              .byKey(const ValueKey('prepared-glass-wallpaper'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(
      find.byKey(const ValueKey('prepared-glass-wallpaper')),
      findsOneWidget,
    );
    Future<int?> brightness() => tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final pixel = (135 * image.width + 160) * 4;
        return bytes.getUint8(pixel) +
            bytes.getUint8(pixel + 1) +
            bytes.getUint8(pixel + 2);
      } finally {
        image.dispose();
      }
    });
    final normal = (await brightness())!;
    scroll.jumpTo(240);
    await tester.pump();
    expect((await brightness())!, lessThan(normal - 5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
