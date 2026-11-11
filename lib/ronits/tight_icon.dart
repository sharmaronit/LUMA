import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Android supplies trimmed PNGs; preview assets supply their alpha bounds.
/// Reading the PNG header avoids another decode just to find its aspect ratio.
double visibleIconAspect(ImageProvider? image, Rect bounds) {
  var aspect = 1.0;
  if (image is MemoryImage) {
    final bytes = image.bytes;
    if (bytes.length >= 24 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      final data = ByteData.sublistView(bytes);
      final width = data.getUint32(16), height = data.getUint32(20);
      if (width > 0 && height > 0) aspect = width / height;
    }
  }
  return aspect * bounds.width / bounds.height;
}

class TightIconImage extends StatelessWidget {
  const TightIconImage({
    super.key,
    required this.image,
    required this.bounds,
    required this.placeholder,
  });
  final ImageProvider? image;
  final Rect bounds;
  final Widget placeholder;
  @override
  Widget build(BuildContext context) {
    if (image == null) return placeholder;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / bounds.width;
        final height = constraints.maxHeight / bounds.height;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: Transform.translate(
              offset: Offset(-bounds.left * width, -bounds.top * height),
              child: Image(
                image: ResizeImage(
                  image!,
                  width: 192,
                  height: 192,
                  policy: ResizeImagePolicy.fit,
                ),
                width: width,
                height: height,
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => placeholder,
              ),
            ),
          ),
        );
      },
    );
  }
}
