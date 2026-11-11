import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/shared_blur_cache.dart';

Future<ui.Image> image() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff446688), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(4, 4);
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'multiple surfaces share one blur build and keep safe image handles',
    () async {
      final cache = SharedBlurCache();
      var builds = 0;
      final pending = Completer<ui.Image>();
      Future<ui.Image> build() {
        builds++;
        return pending.future;
      }

      final first = cache.acquire('wallpaper', build);
      final second = cache.acquire('wallpaper', build);
      pending.complete(await image());
      final handles = await Future.wait([first, second]);
      expect(builds, 1);
      expect(cache.entryCount, 1);
      cache.clear();
      await Future<void>.delayed(Duration.zero);
      expect(await handles[0].toByteData(), isNotNull);
      handles[0].dispose();
      expect(await handles[1].toByteData(), isNotNull);
      handles[1].dispose();
      cache.dispose();
    },
  );
  test('cache is bounded and retries a failed image build', () async {
    final cache = SharedBlurCache(capacity: 2);
    for (final key in ['one', 'two', 'three']) {
      (await cache.acquire(key, image)).dispose();
    }
    expect(cache.entryCount, 2);
    await expectLater(
      cache.acquire('failed', () async => throw StateError('decode')),
      throwsStateError,
    );
    final retried = await cache.acquire('failed', image);
    expect(retried.width, 4);
    retried.dispose();
    cache.dispose();
  });
  test('wallpaper invalidation rejects in-flight stale images', () async {
    final cache = SharedBlurCache();
    final pending = Completer<ui.Image>();
    final request = cache.acquire('old wallpaper', () => pending.future);
    final assertion = expectLater(request, throwsStateError);
    cache.clear();
    pending.complete(await image());
    await assertion;
    expect(cache.entryCount, 0);
    (await cache.acquire('new wallpaper', image)).dispose();
    cache.dispose();
  });
}
