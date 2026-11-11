import 'ronits/app_customization.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'ronits/wallpaper_image.dart';
import 'ronits/clock_preferences.dart';
import 'ronits/menu_dialog.dart';
import 'ronits/preview_shows.dart';
import 'ronits/preview_icon_bounds.dart';
import 'ronits/motion.dart';
import 'ronits/typography.dart';
import 'ronits/scenery_wallpapers.dart';
import 'ronits/solid_theme_scope.dart';
import 'ronits/launcher_backup.dart';
import 'ronits/backup_dialog.dart';
import 'ronits/preview_management.dart';
// Browser entry point: the same home widgets as Android, with mock services.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:shared_preferences/shared_preferences.dart';
import 'ronits/launcher_home.dart';
import 'ronits/preview_remote.dart';
import 'ronits/voice_session.dart';
import 'ronits/preview_blur.dart';
import 'ronits/glass_surface.dart';
import 'ronits/preview_setup.dart';
import 'ronits/tv_icon_pack.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerLumaFontLicense();
  final preferences = await SharedPreferences.getInstance();
  await prepareRestoredPreview(preferences);
  runApp(PreviewApp(preferences: preferences));
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key, required this.preferences});
  final SharedPreferences preferences;
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _remote = LauncherRemoteController();
  final _blur = PreviewBlurStore();
  int _previewGeneration = 0;
  late String wallpaperAsset;
  String minimalBackground = 'charcoal';
  String? solidColorHex;
  late LauncherMaterial mode;
  late bool reducedMotion;
  bool performanceMode = true;
  String clockFormat = 'h:mm a';
  String clockStyle = 'digital', clockSize = 'medium';
  late List<String> favoriteIds;
  Set<String> hiddenIds = {};
  int gridColumns = 6;
  List<String> recentIds = [];
  final apps = [
    for (final item in [
      ('youtube', 'YouTube'),
      ('netflix', 'Netflix'),
      ('jiohotstar', 'JioHotstar'),
      ('primevideo', 'Prime Video'),
      ('sonyliv', 'Sony LIV'),
      ('zee5', 'ZEE5'),
      ('jiotv', 'JioTV+'),
      ('spotify', 'Spotify'),
      ('plex', 'Plex'),
      ('vlc', 'VLC'),
      ('crunchyroll', 'Crunchyroll'),
      ('apple-tv', 'Apple TV'),
    ])
      LauncherAppItem(
        id: item.$1,
        name: item.$2,
        category: classifyTvApp(item.$1, item.$2),
        iconBounds: previewIconBounds[item.$1],
        icon: Future.value(AssetImage('assets/preview/${item.$1}.png')),
        artwork: Future.value(
          AssetImage('assets/preview/banner-${item.$1}.png'),
        ),
      ),
  ];
  @override
  void initState() {
    super.initState();
    PreviewArtworkShelf.register();
    final retired = widget.preferences.getString('launcher_material');
    if (retired != null && retired != 'minimal')
      unawaited(widget.preferences.setString('launcher_material', 'minimal'));
    final saved = widget.preferences.getString('preview_wallpaper');
    wallpaperAsset =
        (isCustomWallpaper(saved) ||
            sceneryWallpapers.any((photo) => photo.asset == saved))
        ? saved!
        : sceneryWallpapers.first.asset;
    _blur.asset = wallpaperAsset;
    recentIds = widget.preferences.getStringList('preview_recent') ?? [];
    clockFormat = widget.preferences.getString('time_format') ?? 'h:mm a';
    clockStyle = widget.preferences.getString('home_clock_style') == 'analog'
        ? 'analog'
        : 'digital';
    clockSize = normaliseClockSize(
      widget.preferences.getString('home_clock_size'),
    );
    mode = LauncherMaterial.fromName(
      widget.preferences.getString('launcher_material'),
    );
    solidColorHex = widget.preferences.getString('solid_theme_color');
    performanceMode = widget.preferences.getBool('performance_mode') ?? true;
    minimalBackground =
        [
          'wallpaper',
          'glass',
          'glass-real',
        ].contains(widget.preferences.getString('minimal_background'))
        ? widget.preferences.getString('minimal_background')!
        : 'charcoal';
    reducedMotion = widget.preferences.getBool('reduce_motion') ?? false;
    hiddenIds = (widget.preferences.getStringList('preview_hidden') ?? [])
        .toSet();
    gridColumns = (widget.preferences.getInt('preview_grid_columns') ?? 6)
        .clamp(3, 8);
    favoriteIds =
        widget.preferences.getStringList('preview_favorites') ??
        apps.take(6).map((app) => app.id).toList();
  }

  @override
  void dispose() {
    _blur.dispose();
    _remote.dispose();
    super.dispose();
  }

  void _reloadPreferences() {
    if (!mounted) return;
    setState(() {
      mode = LauncherMaterial.fromName(
        widget.preferences.getString('launcher_material'),
      );
      reducedMotion = widget.preferences.getBool('reduce_motion') ?? false;
      clockFormat = widget.preferences.getString('time_format') ?? 'h:mm a';
      clockStyle = widget.preferences.getString('home_clock_style') == 'analog'
          ? 'analog'
          : 'digital';
      clockSize = normaliseClockSize(
        widget.preferences.getString('home_clock_size'),
      );
      solidColorHex = widget.preferences.getString('solid_theme_color');
      performanceMode = widget.preferences.getBool('performance_mode') ?? true;
      minimalBackground =
          [
            'wallpaper',
            'glass',
            'glass-real',
          ].contains(widget.preferences.getString('minimal_background'))
          ? widget.preferences.getString('minimal_background')!
          : 'charcoal';
      favoriteIds =
          (widget.preferences.getStringList('preview_favorites') ??
                  apps.take(6).map((app) => app.id).toList())
              .where((id) => apps.any((app) => app.id == id))
              .toList();
      hiddenIds = (widget.preferences.getStringList('preview_hidden') ?? [])
          .toSet();
      gridColumns = (widget.preferences.getInt('preview_grid_columns') ?? 6)
          .clamp(3, 8);
      final saved = widget.preferences.getString('preview_wallpaper');
      wallpaperAsset =
          (isCustomWallpaper(saved) ||
              sceneryWallpapers.any((photo) => photo.asset == saved))
          ? saved!
          : sceneryWallpapers.first.asset;
      _blur.asset = wallpaperAsset;
    });
  }

  Future<void> _backup(BuildContext context) => showBackupDialog(
    context,
    mode: mode,
    blurBuilder: (child, sigma, saturation) => PreviewCachedBackdrop(
      store: _blur,
      sigma: sigma,
      saturation: saturation,
      child: child,
    ),
    export: () async =>
        LauncherBackup(LauncherBackup.preferencesFrom(widget.preferences), {
          'categories': [
            {
              'name': 'Favorites',
              'sort': 'manual',
              'type': 'row',
              'columns': 6,
              'rowHeight': 110,
              'apps': favoriteIds,
            },
          ],
          'hidden': hiddenIds.toList(),
        }).encode(),
    restore: (backup) async {
      final old = LauncherBackup.preferencesFrom(widget.preferences);
      try {
        await LauncherBackup.applyPreferences(
          widget.preferences,
          backup.preferences,
        );
        final categories = backup.layout['categories'] as List;
        final favorites = categories
            .where((c) => c['name'] == 'Favorites')
            .firstOrNull;
        if (favorites != null)
          await widget.preferences.setStringList(
            'preview_favorites',
            (favorites['apps'] as List)
                .cast<String>()
                .where((id) => apps.any((app) => app.id == id))
                .toList(),
          );
        await widget.preferences.setStringList(
          'preview_hidden',
          (backup.layout['hidden'] as List).cast<String>(),
        );
      } catch (_) {
        await LauncherBackup.applyPreferences(widget.preferences, old);
        rethrow;
      }
      _reloadPreferences();
      if (context.mounted)
        AppCustomizationScope.of(context)?.refreshPreferences();
    },
  );

  Future<void> _saveFavorites() async {
    await widget.preferences.setStringList('preview_favorites', favoriteIds);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    shortcuts: {...WidgetsApp.defaultShortcuts, ...previewRemoteShortcuts},
    navigatorKey: _navigatorKey,
    debugShowCheckedModeBanner: false,
    title: 'Luma · Flutter preview',
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations:
            reducedMotion || MediaQuery.disableAnimationsOf(context),
      ),
      child: SolidThemeScope(
        color: solidThemeColor(solidColorHex),
        child: MotionPreview(
          onReplay: () => setState(() => _previewGeneration++),
          child: PreviewRemote(
            navigatorKey: _navigatorKey,
            controller: _remote,
            child: MenuAppearanceScope(
              economyGlass: performanceMode,
              minimalBackground: minimalBackground,
              mode: mode,
              blurBuilder: (child, sigma, saturation) => PreviewCachedBackdrop(
                store: _blur,
                sigma: sigma,
                saturation: saturation,
                child: child,
              ),
              child: LauncherCustomization(child: child!),
            ),
          ),
        ),
      ),
    ),
    theme: ThemeData(
      fontFamily: 'Inter',
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            letterSpacing: 0,
          ),
        ),
      ),
      focusColor: Colors.white.withValues(alpha: .18),
      hoverColor: Colors.white.withValues(alpha: .10),
      brightness: Brightness.dark,
      useMaterial3: true,
      colorSchemeSeed: const Color(0xffb9cfe7),
    ),
    home: Builder(
      builder: (context) => LauncherHome(
        onPickAppArtwork: () async {
          final image = await ImagePicker().pickImage(
            source: ImageSource.gallery,
            maxWidth: 1280,
            maxHeight: 720,
            imageQuality: 90,
          );
          return image == null ? null : image.readAsBytes();
        },
        key: ValueKey(_previewGeneration),
        blurBuilder: (child, sigma, saturation) => PreviewCachedBackdrop(
          store: _blur,
          sigma: sigma,
          saturation: saturation,
          child: child,
        ),
        createVoiceSession: DemoVoiceSession.new,
        remoteController: _remote,
        onBackup: () => _backup(context),
        onLayout: () =>
            showPreviewLayout(context, widget.preferences, _reloadPreferences),
        gridColumns: gridColumns,
        recentApps: recentIds
            .where(
              (id) =>
                  !hiddenIds.contains(id) && apps.any((app) => app.id == id),
            )
            .map((id) => apps.firstWhere((app) => app.id == id))
            .toList(),
        sections: [
          LauncherAppSection(
            id: 'entertainment',
            name: 'Entertainment',
            apps: apps
                .where(
                  (app) =>
                      !hiddenIds.contains(app.id) &&
                      [
                        'youtube',
                        'netflix',
                        'jiohotstar',
                        'primevideo',
                        'sonyliv',
                        'zee5',
                        'jiotv',
                        'crunchyroll',
                        'apple-tv',
                      ].contains(app.id),
                )
                .toList(),
          ),
          LauncherAppSection(
            id: 'music',
            name: 'Music',
            apps: apps
                .where(
                  (app) => !hiddenIds.contains(app.id) && app.id == 'spotify',
                )
                .toList(),
          ),
          LauncherAppSection(
            id: 'tools',
            name: 'Tools',
            apps: apps
                .where(
                  (app) =>
                      !hiddenIds.contains(app.id) &&
                      ['plex', 'vlc'].contains(app.id),
                )
                .toList(),
          ),
        ],
        apps: apps.where((app) => !hiddenIds.contains(app.id)).toList(),
        favorites: favoriteIds
            .where(
              (id) =>
                  !hiddenIds.contains(id) && apps.any((app) => app.id == id),
            )
            .map((id) => apps.firstWhere((app) => app.id == id))
            .toList(),
        minimalBackground: minimalBackground,
        performanceMode: performanceMode,
        onPerformanceChanged: (value) async {
          await widget.preferences.setBool('performance_mode', value);
          if (mounted) setState(() => performanceMode = value);
        },
        onMinimalBackgroundChanged: (value) async {
          await widget.preferences.setString('minimal_background', value);
          if (value == 'wallpaper' || value == 'charcoal')
            await widget.preferences.setString(
              'minimal_last_background',
              value,
            );
          if (mounted) setState(() => minimalBackground = value);
        },
        wallpaper: wallpaperImage(wallpaperAsset),
        onWallpaper: () async {
          final asset = await showSceneryPicker(
            context,
            initialAsset: wallpaperAsset,
            onCustomWallpaper: () async {
              try {
                final photo = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1920,
                  maxHeight: 1080,
                  imageQuality: 85,
                );
                if (photo == null || !mounted) return null;
                final bytes = await photo.readAsBytes();
                if (bytes.length > 4 * 1024 * 1024)
                  throw const FormatException(
                    'Choose a photo smaller than 4 MB',
                  );
                final codec = await ui.instantiateImageCodec(
                  bytes,
                  targetWidth: 64,
                );
                codec.dispose();
                final source = 'data:image/jpeg;base64,${base64Encode(bytes)}';
                return (source: source, image: MemoryImage(bytes));
              } catch (_) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Choose a valid photo smaller than 4 MB.'),
                    ),
                  );
              }
              return null;
            },
            mode: mode,
            blurBuilder: (child, sigma, saturation) => PreviewCachedBackdrop(
              store: _blur,
              sigma: sigma,
              saturation: saturation,
              child: child,
            ),
          );
          if (asset == null || !mounted) return;
          try {
            final saved = await widget.preferences.setString(
              'preview_wallpaper',
              asset,
            );
            if (!saved) throw StateError('Could not save photo');
            await widget.preferences.setString(
              'minimal_last_background',
              'wallpaper',
            );
            if (!['glass', 'glass-real'].contains(minimalBackground)) {
              await widget.preferences.setString(
                'minimal_background',
                'wallpaper',
              );
              if (mounted) setState(() => minimalBackground = 'wallpaper');
            }
            if (mounted)
              setState(() {
                wallpaperAsset = asset;
                _blur.asset = asset;
              });
          } catch (_) {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Could not save this wallpaper. Try a smaller photo.',
                  ),
                ),
              );
          }
        },
        timeFormat: clockFormat,
        clockStyle: clockStyle,
        clockSize: clockSize,
        onClockStyleChanged: (value) async {
          await widget.preferences.setString('home_clock_style', value);
          if (mounted) setState(() => clockStyle = value);
        },
        onClockSizeChanged: (value) async {
          await widget.preferences.setString('home_clock_size', value);
          if (mounted) setState(() => clockSize = value);
        },
        onTimeFormatChanged: (value) async {
          await widget.preferences.setString('time_format', value);
          if (mounted) setState(() => clockFormat = value);
        },
        networkStatus: 'Browser preview · TV connection not available',
        bluetoothStatus: 'Browser preview · accessories not available',
        mode: mode,
        reducedMotion: reducedMotion,
        preview: true,
        homeContinueWatching: const PreviewArtworkShelf(),
        continueWatching: const PreviewShows(),
        onMaterialChanged: (value) async {
          await widget.preferences.setString('launcher_material', value.name);
          setState(() => mode = value);
        },
        onReducedMotionChanged: (value) async {
          await widget.preferences.setBool('reduce_motion', value);
          setState(() => reducedMotion = value);
        },
        onFavorite: (item) async {
          if (favoriteIds.contains(item.id)) {
            favoriteIds.remove(item.id);
          } else {
            favoriteIds.add(item.id);
          }
          await _saveFavorites();
        },
        onMoveFavorite: (item, offset) async {
          final index = favoriteIds.indexOf(item.id);
          final target = index + offset;
          if (index >= 0 && target >= 0 && target < favoriteIds.length) {
            favoriteIds.removeAt(index);
            favoriteIds.insert(target, item.id);
            await _saveFavorites();
          }
        },
        onLaunch: (item) async {
          final next = [
            item.id,
            ...recentIds.where((id) => id != item.id),
          ].take(6).toList();
          await widget.preferences.setStringList('preview_recent', next);
          if (!mounted) return;
          setState(() => recentIds = next);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${item.name} · Android launch simulated in browser',
              ),
            ),
          );
        },
        onDeviceSettings: (section) =>
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Android TV $section settings open on the TV.'),
              ),
            ),
        onWifi: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Network settings are available on the Android TV build.',
            ),
          ),
        ),
        onSolidColorChanged: (hex) async {
          await widget.preferences.setString('solid_theme_color', hex);
          if (mounted) setState(() => solidColorHex = hex);
        },
        onSettings: () => showLumaDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => LumaMenuDialog(
            title: const Text('Luma preview'),
            content: const Text(
              'Development preview with sample apps. On Android, installed apps, wallpapers and settings use native services. Luma is free software under GPL-3.0-or-later; see Licences & credits.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
        onManage: () => showPreviewAppManager(
          context,
          widget.preferences,
          apps,
          _reloadPreferences,
        ),
      ),
    ),
  );
}

/// Preview-only controls. Never compiled into the Android entry point.
class MotionPreview extends StatefulWidget {
  const MotionPreview({super.key, required this.child, required this.onReplay});
  final Widget child;
  final VoidCallback onReplay;
  @override
  State<MotionPreview> createState() => _MotionPreviewState();
}

class _MotionPreviewState extends State<MotionPreview> {
  double speed = 1;
  @override
  void dispose() {
    timeDilation = 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Uri.base.queryParameters['motion'] != '1') return widget.child;
    return ColoredBox(
      color: const Color(0xff0b1119),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(
                  builder: (context, constraints) => FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 960,
                      height: 540,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: const Size(960, 540),
                          devicePixelRatio:
                              MediaQuery.devicePixelRatioOf(context) *
                              constraints.maxWidth /
                              960,
                        ),
                        child: ClipRect(child: widget.child),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: ExcludeFocus(
              child: Material(
                color: const Color(0xee172333),
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Motion lab  '),
                      DropdownButton<double>(
                        value: speed,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1× speed')),
                          DropdownMenuItem(
                            value: .5,
                            child: Text('0.5× speed'),
                          ),
                          DropdownMenuItem(
                            value: .25,
                            child: Text('0.25× speed'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null)
                            setState(() {
                              speed = value;
                              timeDilation = 1 / value;
                            });
                        },
                      ),
                      TextButton.icon(
                        onPressed: widget.onReplay,
                        icon: const Icon(Icons.replay),
                        label: const Text('Reset Home'),
                      ),
                      const Text(
                        '↑ ↓ ← → Navigate · Enter / Space Select · Hold Select: options\nEsc / Backspace Back · H Home · S Search · Q Settings · M Menu · V Voice',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
