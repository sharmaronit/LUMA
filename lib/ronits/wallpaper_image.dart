import 'dart:convert';
import 'package:flutter/painting.dart';

/// Stock assets and locally persisted browser photos share the same blur path.
String? _customSource;
ImageProvider? _customImage;

ImageProvider wallpaperImage(String source) {
  if (!source.startsWith('data:image/')) return AssetImage(source);
  // Preserve provider identity across settings rebuilds. Re-decoding the photo
  // would invalidate both the image cache and wallpaper accent on each change.
  if (_customSource == source && _customImage != null) return _customImage!;
  final image = MemoryImage(
    base64Decode(source.substring(source.indexOf(',') + 1)),
  );
  _customSource = source;
  return _customImage = image;
}

bool isCustomWallpaper(String? source) =>
    source != null && source.startsWith('data:image/') && source.contains(',');
