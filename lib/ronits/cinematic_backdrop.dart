import 'dart:async';
import 'dart:ui' as ui;
import 'prepared_backdrop_scope.dart';
import 'package:flutter/material.dart';
import 'motion.dart';

/// Artwork is reported by focused cards, never by scrolling or pointer position.
class ProgrammeArtworkFocus extends Notification {
  const ProgrammeArtworkFocus(this.image);
  final ImageProvider? image;
}

class CinematicBackdropHost extends StatefulWidget {
  const CinematicBackdropHost({super.key, required this.child});
  final Widget child;
  @override
  State<CinematicBackdropHost> createState() => _CinematicBackdropHostState();
}

class _CinematicBackdropHostState extends State<CinematicBackdropHost> {
  final image = ValueNotifier<ui.Image?>(null);
  Timer? pause;
  ImageProvider? currentSource;
  final retained = <ui.Image>[];
  int revision = 0;
  bool select(ProgrammeArtworkFocus event) {
    pause?.cancel();
    final ticket = ++revision;
    pause = Timer(const Duration(milliseconds: 450), () async {
      final source = event.image;
      if (source == null) {
        currentSource = null;
        image.value = null;
        return;
      }
      if (source == currentSource) return;
      try {
        final output = await _prepare(source);
        if (!mounted || ticket != revision) {
          output.dispose();
          return;
        }
        currentSource = source;
        retained.add(output);
        // Keep outgoing textures alive until their crossfade has completed.
        // Focus settling is 450 ms, so two retained transitions exceed 320 ms.
        while (retained.length > 3) {
          retained.removeAt(0).dispose();
        }
        image.value = output;
      } catch (_) {
        if (mounted && ticket == revision) {
          currentSource = null;
          image.value = null;
        }
      }
    });
    return false;
  }

  Future<ui.Image> _prepare(ImageProvider provider) async {
    final size = MediaQuery.sizeOf(context);
    const width = 960;
    final height = (width * size.height / size.width).round().clamp(1, 960);
    final decoded = Completer<ui.Image>();
    final stream = ResizeImage(
      provider,
      width: width,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    ).resolve(createLocalImageConfiguration(context));
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        decoded.complete(info.image.clone());
        info.dispose();
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        decoded.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    final source = await decoded.future;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      paintImage(
        canvas: canvas,
        rect: rect,
        image: source,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xb80b1018), Color(0x990b1018), Color(0xf00b1018)],
          ).createShader(rect),
      );
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  @override
  void dispose() {
    pause?.cancel();
    revision++;
    image.dispose();
    for (final texture in retained) {
      texture.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = PreparedBackdropScope.of(context);
    return NotificationListener<ProgrammeArtworkFocus>(
      onNotification: select,
      child: _BackdropScope(
        image: image,
        child: ValueListenableBuilder<ui.Image?>(
          valueListenable: image,
          child: widget.child,
          builder: (_, prepared, child) => base == null
              ? child!
              : PreparedBackdropScope(
                  image: prepared ?? base.image,
                  origin: base.origin,
                  fallback: base.fallback,
                  child: child!,
                ),
        ),
      ),
    );
  }
}

class _BackdropScope extends InheritedWidget {
  const _BackdropScope({required this.image, required super.child});
  final ValueNotifier<ui.Image?> image;
  @override
  bool updateShouldNotify(_BackdropScope oldWidget) => image != oldWidget.image;
}

/// Once artwork covers Home, stop painting the wallpaper underneath it.
/// Keep its state and prepared edge textures alive for the return transition.
class CinematicWallpaper extends StatefulWidget {
  const CinematicWallpaper({super.key, required this.child});
  final Widget child;
  @override
  State<CinematicWallpaper> createState() => _CinematicWallpaperState();
}

class _CinematicWallpaperState extends State<CinematicWallpaper> {
  ValueNotifier<ui.Image?>? source;
  Timer? settle;
  bool covered = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context
        .dependOnInheritedWidgetOfExactType<_BackdropScope>()
        ?.image;
    if (source == next) return;
    source?.removeListener(changed);
    source = next;
    source?.addListener(changed);
  }

  void changed() {
    settle?.cancel();
    if (source?.value == null) {
      if (covered) setState(() => covered = false);
    } else if (!covered) {
      settle = Timer(
        motionReduced(context)
            ? Duration.zero
            : const Duration(milliseconds: 350),
        () {
          if (mounted && source?.value != null) setState(() => covered = true);
        },
      );
    }
  }

  @override
  void dispose() {
    settle?.cancel();
    source?.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Offstage(offstage: covered, child: widget.child);
}

class CinematicBackdropLayer extends StatelessWidget {
  const CinematicBackdropLayer({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_BackdropScope>();
    if (scope == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: ValueListenableBuilder<ui.Image?>(
          valueListenable: scope.image,
          builder: (context, image, _) => AnimatedSwitcher(
            duration: motionReduced(context)
                ? Duration.zero
                : const Duration(milliseconds: 320),
            child: image == null
                ? const SizedBox.expand(key: ValueKey('wallpaper-backdrop'))
                : RawImage(
                    key: ValueKey(image),
                    image: image,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  ),
          ),
        ),
      ),
    );
  }
}
