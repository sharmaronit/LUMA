import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'depth_clock.dart';
import 'glass_surface.dart';
import 'motion.dart';

/// Every bundled wallpaper has a foreground cut-out for the depth clock.
const sceneryWallpapers = <({String name, String asset})>[
  (name: 'Aoraki sunrise', asset: 'assets/wallpapers/aoraki-sunrise.jpg'),
  (name: 'Dolomites', asset: 'assets/wallpapers/dolomites.jpg'),
  (name: 'Summit glow', asset: 'assets/wallpapers/summit-glow.jpg'),
  (name: 'Green summit', asset: 'assets/wallpapers/green-summit.jpg'),
  (name: 'Rose peak', asset: 'assets/wallpapers/rose-peak.jpg'),
  (name: 'Blue summit', asset: 'assets/wallpapers/blue-summit.jpg'),
  (name: 'Misty peak', asset: 'assets/wallpapers/misty-peak.jpg'),
  (name: 'Volcano view', asset: 'assets/wallpapers/volcano-view.jpg'),
  (name: 'Steppe range', asset: 'assets/wallpapers/steppe-range.jpg'),
  (name: 'Golden shore', asset: 'assets/wallpapers/golden-shore.jpg'),
  (name: 'Star dunes', asset: 'assets/wallpapers/star-dunes.jpg'),
  (name: 'Twilight lake', asset: 'assets/wallpapers/twilight-lake.jpg'),
  (name: 'Aurora camp', asset: 'assets/wallpapers/aurora-camp.jpg'),
  (name: 'Lighthouse', asset: 'assets/wallpapers/lighthouse.jpg'),
];

/// Returns only an explicitly applied choice; browsing is preview-only.
typedef WallpaperPhoto = ({String source, ImageProvider image});

/// Full-screen wallpaper browser. Each wallpaper fills the screen with its
/// depth clock, exactly as Home will look. Left and Right flip through them
/// ("Your photo" is last), OK applies, Back cancels. Resolves to the applied
/// asset, or a custom photo's source.
///
/// [mode] and [blurBuilder] are kept for callers of the earlier list picker.
Future<String?> showSceneryPicker(
  BuildContext context, {
  LauncherMaterial mode = LauncherMaterial.ronits,
  GlassBlurBuilder? blurBuilder,
  Future<WallpaperPhoto?> Function()? onCustomWallpaper,
  String? initialAsset,
  String timeFormat = 'HH:mm',
}) => Navigator.of(context, rootNavigator: true).push<String>(
  PageRouteBuilder<String>(
    opaque: true,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => WallpaperBrowser(
      onCustomWallpaper: onCustomWallpaper,
      initialAsset: initialAsset,
      timeFormat: timeFormat,
    ),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class WallpaperBrowser extends StatefulWidget {
  const WallpaperBrowser({
    super.key,
    this.onCustomWallpaper,
    this.initialAsset,
    this.timeFormat = 'HH:mm',
  });
  final Future<WallpaperPhoto?> Function()? onCustomWallpaper;
  final String? initialAsset;
  final String timeFormat;
  @override
  State<WallpaperBrowser> createState() => _WallpaperBrowserState();
}

class _WallpaperBrowserState extends State<WallpaperBrowser> {
  late int index = sceneryWallpapers
      .indexWhere((photo) => photo.asset == widget.initialAsset)
      .clamp(0, sceneryWallpapers.length - 1);
  late final pages = PageController(initialPage: index);
  final focus = FocusNode(debugLabel: 'Wallpaper browser');
  WallpaperPhoto? custom;
  bool importing = false;
  String? message;

  /// The last page holds "Your photo" when photos can be chosen.
  int get count =>
      sceneryWallpapers.length + (widget.onCustomWallpaper == null ? 0 : 1);
  bool get onCustomPage => index >= sceneryWallpapers.length;

  @override
  void dispose() {
    pages.dispose();
    focus.dispose();
    super.dispose();
  }

  void go(int step) {
    final next = (index + step).clamp(0, count - 1);
    if (next == index) return;
    setState(() {
      index = next;
      message = null;
    });
    if (motionReduced(context)) {
      pages.jumpToPage(next);
    } else {
      pages.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> choose() async {
    final navigator = Navigator.of(context);
    if (!onCustomPage) {
      navigator.pop(sceneryWallpapers[index].asset);
      return;
    }
    if (custom != null) {
      navigator.pop(custom!.source);
      return;
    }
    if (importing) return;
    setState(() {
      importing = true;
      message = null;
    });
    try {
      final photo = await widget.onCustomWallpaper!();
      if (mounted && photo != null) setState(() => custom = photo);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not open that photo. Try another image.',
        );
      }
    } finally {
      if (mounted) setState(() => importing = false);
      focus.requestFocus();
    }
  }

  KeyEventResult key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      go(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      go(-1);
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent) unawaited(choose());
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      // Nothing above or below; keep focus here.
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget page(int i) {
    if (i >= sceneryWallpapers.length) {
      final photo = custom;
      if (photo != null) {
        return Image(
          image: photo.image,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
        );
      }
      return ColoredBox(
        color: const Color(0xff111316),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_photo_alternate_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                importing ? 'Opening your photos…' : 'Choose your photo',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message ?? 'Press OK to pick a picture from this TV',
                style: TextStyle(color: Colors.white.withValues(alpha: .7)),
              ),
            ],
          ),
        ),
      );
    }
    final photo = sceneryWallpapers[i];
    final screen = MediaQuery.sizeOf(context);
    final image = ResizeImage.resizeIfNeeded(
      (screen.width * MediaQuery.devicePixelRatioOf(context)).round(),
      null,
      AssetImage(photo.asset),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          key: ValueKey('wallpaper-page-${photo.asset}'),
          image: image,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          semanticLabel: photo.name,
        ),
        // Only the page in view draws its clock, so flipping stays smooth.
        if (i == index && hasDepthLayer(photo.asset))
          DepthClock(
            key: ValueKey('wallpaper-clock-${photo.asset}'),
            wallpaper: photo.asset,
            image: image,
            pattern: widget.timeFormat,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final applied =
        !onCustomPage && sceneryWallpapers[index].asset == widget.initialAsset;
    final name = onCustomPage ? 'Your photo' : sceneryWallpapers[index].name;
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: key,
      child: Material(
        key: const ValueKey('wallpaper-browser'),
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: pages,
              itemCount: count,
              onPageChanged: (value) => setState(() => index = value),
              itemBuilder: (_, i) => page(i),
            ),
            // A soft shade so the labels read on any photo.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x8c000000)],
                    stops: [.68, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        key: const ValueKey('wallpaper-preview-name'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (applied) ...[
                        const SizedBox(width: 12),
                        Container(
                          key: const ValueKey('wallpaper-applied'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .5),
                              width: .8,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, size: 15),
                              SizedBox(width: 4),
                              Text('On Home', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < count; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == index ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: i == index ? .95 : .4,
                            ),
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    onCustomPage && custom == null
                        ? '◀ ▶  Browse      OK  Choose a photo      Back  Cancel'
                        : '◀ ▶  Browse      OK  Apply      Back  Cancel',
                    key: const ValueKey('wallpaper-hint'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: .75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
