import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Share the existing prepared backdrop with narrow edge painters. Ownership
/// stays with the wallpaper widget; edge fades never decode or blur another image.
class PreparedBackdropScope extends InheritedWidget {
  const PreparedBackdropScope({
    super.key,
    required this.image,
    required this.origin,
    required this.fallback,
    required super.child,
  });
  final ui.Image? image;
  final GlobalKey origin;
  final Color fallback;
  static PreparedBackdropScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreparedBackdropScope>();
  @override
  bool updateShouldNotify(PreparedBackdropScope old) =>
      image != old.image || fallback != old.fallback;
}
