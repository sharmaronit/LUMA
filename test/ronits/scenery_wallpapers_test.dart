import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/scenery_wallpapers.dart';

void main() {
  testWidgets('a custom photo is previewed before Apply returns it', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showSceneryPicker(
                  context,
                  onCustomWallpaper: () async => (
                    source: 'custom-photo',
                    image: const AssetImage('assets/mountain.jpg'),
                  ),
                );
              },
              child: const Text('Choose'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-wallpaper')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Image>(find.byKey(const ValueKey('wallpaper-large-preview')))
          .semanticLabel,
      'Your photo',
    );
    expect(selected, isNull);
    await tester.tap(find.byKey(const ValueKey('apply-wallpaper')));
    await tester.pumpAndSettle();
    expect(selected, 'custom-photo');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'custom wallpaper action keeps the picker open and stock choices usable',
    (tester) async {
      var imports = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSceneryPicker(
                  context,
                  onCustomWallpaper: () async {
                    imports++;
                    return (
                      source: 'custom-photo',
                      image: const AssetImage('assets/mountain.jpg'),
                    );
                  },
                ),
                child: const Text('Choose'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      // Focus starts on the current wallpaper; the photo button is above it.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(imports, 1);
      expect(find.text('Wallpapers'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Wallpapers'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Wallpapers'), findsNothing);
    },
  );
  test('all fourteen wallpapers are bundled, each with a depth cut-out', () {
    expect(sceneryWallpapers.length, 14);
    expect(
      sceneryWallpapers.any((photo) => photo.asset.contains('ios27')),
      false,
    );
    expect(File('assets/wallpapers/ios27-blue.jpg').existsSync(), false);
    expect(File('assets/wallpapers/ios27-dark.jpg').existsSync(), false);
    for (final photo in sceneryWallpapers) {
      expect(File(photo.asset).lengthSync(), greaterThan(10000));
    }
  });
  testWidgets('picker returns the chosen wallpaper without applying another', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showSceneryPicker(context);
              },
              child: const Text('Choose'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dolomites'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(
      tester
          .widget<Image>(find.byKey(const ValueKey('wallpaper-large-preview')))
          .semanticLabel,
      'Dolomites',
    );
    await tester.tap(find.byKey(const ValueKey('apply-wallpaper')));
    await tester.pumpAndSettle();
    expect(selected, 'assets/wallpapers/dolomites.jpg');
  });
  testWidgets('TV preview is large, 16:9 and Back cancels without applying', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showSceneryPicker(
                  context,
                  initialAsset: 'assets/wallpapers/rose-peak.jpg',
                );
              },
              child: const Text('Choose'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    final image = find.byKey(const ValueKey('wallpaper-large-preview'));
    final size = tester.getSize(image);
    expect(size.width, greaterThan(480));
    expect(size.width / size.height, closeTo(16 / 9, .01));
    expect(tester.widget<Image>(image).semanticLabel, 'Rose peak');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(image).semanticLabel, 'Blue summit');
    expect(selected, isNull);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });
}
