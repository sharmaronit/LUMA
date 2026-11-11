import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/wallpaper_image.dart';

void main() {
  test(
    'custom photos reuse their provider across rebuilds and replace on change',
    () {
      const first = 'data:image/jpeg;base64,AQID';
      final image = wallpaperImage(first);
      expect(image, isA<MemoryImage>());
      expect(identical(image, wallpaperImage(first)), true);
      expect(
        identical(image, wallpaperImage('data:image/jpeg;base64,BAUG')),
        false,
      );
      expect(wallpaperImage('assets/mountain.jpg'), isA<AssetImage>());
    },
  );
}
