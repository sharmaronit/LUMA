import 'dart:async';
import 'package:luma/widgets/tv_media_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transparent_image/transparent_image.dart';

const channel = MethodChannel('app.luma.tvlauncher/method');
const photo = {
  'id': 1,
  'name': 'Selected photo',
  'uri': 'content://media/images/1',
};

Future<void> openPicker(
  WidgetTester tester, {
  ValueChanged<TvMediaSelection?>? selected,
}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              selected?.call(
                await TvMediaPicker.show(
                  context,
                  mode: TvMediaPickerMode.image,
                ),
              );
              if (selected == null)
                await TvMediaPicker.show(
                  context,
                  mode: TvMediaPickerMode.image,
                );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
}

void main() {
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'content URI photos remain selectable without a filesystem path',
    (tester) async {
      final permissionTypes = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'checkMediaPermissions') {
          permissionTypes.add(call.arguments);
          return true;
        }
        if (call.method == 'getMediaStoreImages') return [photo];
        if (call.method == 'getMediaStoreImageThumbnail')
          return kTransparentImage;
        return null;
      });
      TvMediaSelection? selection;
      await openPicker(tester, selected: (value) => selection = value);
      await tester.pumpAndSettle();
      expect(find.text('Selected photo'), findsOneWidget);
      expect(permissionTypes, ['image']);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selection?.uri, photo['uri']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late permission completion does not update a dismissed picker', (
    tester,
  ) async {
    final permission = Completer<bool>();
    var queries = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'checkMediaPermissions') return permission.future;
      if (call.method == 'getMediaStoreImages') {
        queries++;
        return [];
      }
      return null;
    });
    await openPicker(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    permission.complete(true);
    await tester.pumpAndSettle();
    expect(queries, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('provider failures show Retry and recover without reopening', (
    tester,
  ) async {
    var failed = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'checkMediaPermissions') return true;
      if (call.method == 'getMediaStoreImages') {
        if (failed) throw PlatformException(code: 'offline');
        return [photo];
      }
      if (call.method == 'getMediaStoreImageThumbnail')
        return kTransparentImage;
      return null;
    });
    await openPicker(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load your media. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('No images found on device'), findsNothing);
    failed = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Selected photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('media loading waits for the actual permission result', (
    tester,
  ) async {
    var allowed = false, queries = 0;
    final request = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'checkMediaPermissions') return allowed;
      if (call.method == 'requestMediaPermissions') {
        await request.future;
        return null;
      }
      if (call.method == 'getMediaStoreImages') {
        queries++;
        return [];
      }
      return null;
    });
    await openPicker(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(queries, 0);
    allowed = true;
    request.complete();
    await tester.pumpAndSettle();
    expect(queries, 1);
    expect(find.text('No images found on device'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
