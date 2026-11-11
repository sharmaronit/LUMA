import 'font_styles.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'artwork_storage.dart';
import 'tv_icon_pack.dart';

const remoteShortcutKeys = <String, LogicalKeyboardKey>{
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  'Red': LogicalKeyboardKey.colorF0Red,
  'Green': LogicalKeyboardKey.colorF1Green,
  'Yellow': LogicalKeyboardKey.colorF2Yellow,
  'Blue': LogicalKeyboardKey.colorF3Blue,
  'Play/Pause': LogicalKeyboardKey.mediaPlayPause,
};

class AppCustomization extends ChangeNotifier {
  AppCustomization(this.preferences);
  final SharedPreferences preferences;
  final Map<String, String> shortcuts = {}, artwork = {};
  final Map<String, Future<ImageProvider?>> _images = {};
  bool ready = false;
  static const shortcutsKey = 'luma_remote_shortcuts';
  static const artworkKey = 'luma_app_artwork';
  static const fontKey = 'launcher_font_style';
  void refreshPreferences() => notifyListeners();
  String get fontStyle => launcherFont(preferences.getString(fontKey)).id;
  Future<void> setFontStyle(String id) async {
    if (!launcherFonts.any((font) => font.id == id))
      throw ArgumentError('Invalid font');
    if (!await preferences.setString(fontKey, id))
      throw StateError('Could not save font');
    notifyListeners();
  }

  Future<void> load() async {
    Map<String, String> read(String key) {
      try {
        final value = jsonDecode(preferences.getString(key) ?? '{}');
        return value is Map
            ? {
                for (final e in value.entries)
                  if (e.key is String && e.value is String)
                    e.key as String: e.value as String,
              }
            : {};
      } catch (_) {
        return {};
      }
    }

    shortcuts.addAll(
      read(shortcutsKey)..removeWhere(
        (k, v) => !remoteShortcutKeys.containsKey(k) || !_validAction(v),
      ),
    );
    artwork.addAll(read(artworkKey)..removeWhere((k, v) => !validArtwork(v)));
    ready = true;
    notifyListeners();
  }

  static bool _validAction(String value) =>
      ['search', 'voice', 'apps'].contains(value) ||
      (value.startsWith('app:') && value.length > 4);
  static bool validArtwork(String value) =>
      value == 'original' ||
      value == 'custom' ||
      (value.startsWith('pack:') &&
          tvIconPackNames.values.contains(value.substring(5)));
  Future<void> setShortcut(String key, String? action) async {
    if (!remoteShortcutKeys.containsKey(key) ||
        (action != null && !_validAction(action)))
      throw ArgumentError('Invalid shortcut');
    final next = {...shortcuts};
    action == null ? next.remove(key) : next[key] = action;
    if (!await preferences.setString(shortcutsKey, jsonEncode(next)))
      throw StateError('Could not save shortcut');
    shortcuts
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  String? actionFor(LogicalKeyboardKey key) {
    for (final entry in remoteShortcutKeys.entries) {
      if (entry.value == key) return shortcuts[entry.key];
    }
    return null;
  }

  Future<ImageProvider?> _image(String id, String source) async {
    if (source.startsWith('pack:'))
      return AssetImage('assets/tv-icons/${source.substring(5)}.png');
    if (source == 'custom') {
      try {
        final bytes = await readAppArtwork(id);
        return bytes == null ? null : MemoryImage(bytes);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<ImageProvider?>? image(String id) {
    final source = artwork[id];
    return source == null
        ? null
        : _images.putIfAbsent(id, () => _image(id, source));
  }

  Future<void> setArtwork(String id, String? source, {Uint8List? bytes}) async {
    final wasCustom = artwork[id] == 'custom';
    if (source != null && !validArtwork(source))
      throw ArgumentError('Invalid artwork');
    if (source == 'custom') {
      if (bytes == null || bytes.isEmpty || bytes.length > 8 * 1024 * 1024)
        throw const FormatException('Choose an image smaller than 8 MB.');
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final scale = math.min(1.0, math.min(640 / width, 360 / height));
          return ui.TargetImageSize(
            width: math.max(1, (width * scale).round()),
            height: math.max(1, (height * scale).round()),
          );
        },
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final encoded = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (encoded == null) throw const FormatException('Invalid image');
          await saveAppArtwork(id, encoded.buffer.asUint8List());
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    final next = {...artwork};
    source == null ? next.remove(id) : next[id] = source;
    if (!await preferences.setString(artworkKey, jsonEncode(next)))
      throw StateError('Could not save artwork');
    artwork
      ..clear()
      ..addAll(next);
    if (source == null) {
      _images.remove(id);
    } else {
      _images[id] = _image(id, source);
    }
    notifyListeners();
    if (wasCustom && source != 'custom') {
      try {
        await deleteAppArtwork(id);
      } catch (_) {}
    }
  }
}

class AppCustomizationScope extends InheritedNotifier<AppCustomization> {
  const AppCustomizationScope({
    super.key,
    required AppCustomization? controller,
    required super.child,
  }) : super(notifier: controller);
  static AppCustomization? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppCustomizationScope>()
      ?.notifier;
}

class LauncherCustomization extends StatefulWidget {
  const LauncherCustomization({super.key, required this.child});
  final Widget child;
  @override
  State<LauncherCustomization> createState() => _LauncherCustomizationState();
}

class _LauncherCustomizationState extends State<LauncherCustomization> {
  AppCustomization? controller;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final next = AppCustomization(await SharedPreferences.getInstance());
      await next.load();
      if (!mounted) {
        next.dispose();
        return;
      }
      setState(() => controller = next);
    } catch (_) {
      /* Launch remains available when storage fails. */
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppCustomizationScope(
    controller: controller,
    child: Builder(
      builder: (context) {
        final style = AppCustomizationScope.of(context)?.fontStyle;
        return Theme(
          data: launcherFontTheme(Theme.of(context), style),
          child: widget.child,
        );
      },
    ),
  );
}

/// Overrides only the image; focus and launch callbacks retain the app identity.
class AppArtworkBuilder extends StatelessWidget {
  const AppArtworkBuilder({
    super.key,
    required this.id,
    required this.future,
    required this.original,
    required this.builder,
  });
  final String id;
  final Future<ImageProvider?> future;
  final Future<ImageProvider?> Function() original;
  final AsyncWidgetBuilder<ImageProvider?> builder;
  @override
  Widget build(BuildContext context) {
    final store = AppCustomizationScope.of(context);
    final source = store?.artwork[id];
    if (source == null)
      return FutureBuilder<ImageProvider?>(future: future, builder: builder);
    return _OverrideImage(
      key: ValueKey((id, source, store!.image(id))),
      store: store,
      id: id,
      fallback: future,
      original: original,
      builder: builder,
    );
  }
}

class _OverrideImage extends StatefulWidget {
  const _OverrideImage({
    super.key,
    required this.store,
    required this.id,
    required this.fallback,
    required this.original,
    required this.builder,
  });
  final AppCustomization store;
  final String id;
  final Future<ImageProvider?> fallback;
  final Future<ImageProvider?> Function() original;
  final AsyncWidgetBuilder<ImageProvider?> builder;
  @override
  State<_OverrideImage> createState() => _OverrideImageState();
}

class _OverrideImageState extends State<_OverrideImage> {
  late Future<ImageProvider?> image = load();
  Future<ImageProvider?> load() async {
    try {
      final result = await (widget.store.artwork[widget.id] == 'original'
          ? widget.original()
          : widget.store.image(widget.id)!);
      return result ?? await widget.fallback;
    } catch (_) {
      return widget.fallback;
    }
  }

  @override
  void didUpdateWidget(_OverrideImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store.image(widget.id) != widget.store.image(widget.id) ||
        oldWidget.fallback != widget.fallback)
      image = load();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<ImageProvider?>(future: image, builder: widget.builder);
}
