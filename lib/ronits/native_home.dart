import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'standby.dart';
import 'profiles.dart';
import 'depth_clock.dart';
import 'app_actions.dart';
import 'app_customization.dart';
import 'programme_library.dart';
// Native bindings for the shared launcher UI. GPL-3.0-or-later.
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app.dart';
import '../models/category.dart';
import '../widgets/settings/launcher_sections_panel_page.dart';
import '../providers/apps_service.dart';
import '../providers/settings_service.dart';
import '../providers/wallpaper_service.dart';
import '../providers/watch_next_service.dart';
import '../providers/launcher_state.dart';
import '../providers/network_service.dart';
import '../providers/brightness_service.dart';
import '../luma_channel.dart';
import '../widgets/cached_blur_backdrop.dart';
import '../widgets/settings/settings_panel.dart';
import '../widgets/settings/luma_settings_page.dart';
import '../widgets/settings/applications_panel_page.dart';
import '../widgets/wallpaper_video_background.dart';
import '../widgets/watch_next_row.dart';
import '../widgets/tv_media_picker.dart';
import 'glass_surface.dart';
import 'launcher_home.dart';
import 'motion.dart';
import 'scenery_wallpapers.dart';
import 'native_voice_session.dart';
import 'launcher_backup.dart';
import 'backup_dialog.dart';
import 'tv_icon_pack.dart';
import 'configured_first_run.dart';
import 'notification_center.dart';
import 'tv_controls.dart';
import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';

class NativeLauncherHome extends StatefulWidget {
  const NativeLauncherHome({super.key});
  @override
  State<NativeLauncherHome> createState() => _NativeLauncherHomeState();
}

class _NativeLauncherHomeState extends State<NativeLauncherHome>
    with WidgetsBindingObserver {
  int _homeReset = 0, _recentsToken = 0;
  bool? _keepScreenOn;

  /// When each app was closed from the Recent apps panel (ms since epoch).
  /// An app stays out of the panel until it is opened again after that.
  Map<String, int> _closedAt = {};
  static const _closedKey = 'luma_recent_closed';

  Future<void> _loadClosed() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final stored = jsonDecode(prefs.getString(_closedKey) ?? '{}') as Map;
      if (mounted) {
        setState(
          () => _closedAt = {
            for (final entry in stored.entries)
              if (entry.value is int) '${entry.key}': entry.value as int,
          },
        );
      }
    } catch (_) {
      /* A damaged record only means closed apps show again. */
    }
  }

  Future<void> _markClosed(String id) async {
    setState(
      () =>
          _closedAt = {..._closedAt, id: DateTime.now().millisecondsSinceEpoch},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_closedKey, jsonEncode(_closedAt));
  }

  bool _setupDialogOpen = false;
  final _items = <String, LauncherAppItem>{};
  final _notifications = ChannelNotificationSource();
  final _tvControls = ChannelTvControls();
  StreamSubscription<void>? _notificationChanges;
  int _notificationCount = 0;
  String _packageName = 'app.luma.tvlauncher';

  Future<void> _refreshNotificationCount() async {
    try {
      final count = await _notifications.hasAccess()
          ? (await _notifications.load()).length
          : 0;
      if (mounted && count != _notificationCount) {
        setState(() => _notificationCount = count);
      }
    } catch (_) {
      // Older builds or TVs without the service simply show no badge.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationChanges = _notifications.changes.listen(
      (_) => _refreshNotificationCount(),
    );
    unawaited(_refreshNotificationCount());
    PackageInfo.fromPlatform()
        .then((info) => _packageName = info.packageName)
        .catchError((Object _) => _packageName);
    _loadClosed();
    LumaChannel().setHomePressedHandler(_onHomePressed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onboarding();
    });
  }

  void _onHomePressed(bool alreadyHome) {
    if (!mounted) return;
    if (_setupDialogOpen) return;
    final navigator = Navigator.of(context);
    // Home on the bare home screen opens Recent apps. Anywhere else it
    // goes home, as it always has.
    final onHome = alreadyHome && !navigator.canPop();
    navigator.popUntil((route) => route.isFirst);
    setState(() => onHome ? _recentsToken++ : _homeReset++);
  }

  @override
  void dispose() {
    LumaChannel().clearHomePressedHandler(_onHomePressed);
    _notificationChanges?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Access may have just been granted in Android settings.
      unawaited(_refreshNotificationCount());
      context.read<LauncherState>().refresh(context.read<AppsService>());
      context.read<WatchNextService>().refreshPermissionAndItems().catchError((
        Object error,
      ) {
        debugPrint('Programme refresh unavailable: $error');
      });
      context.read<NetworkService>().refreshPermissionAndUsage();
      context.read<BrightnessService>().checkPermission();
    }
  }

  void _settings({bool apps = false}) => showLumaDialog<void>(
    context: context,
    fromSide: true,
    reducedMotion: context.read<SettingsService>().reduceMotion,
    builder: (_) => SettingsPanel(
      initialRoute: apps
          ? ApplicationsPanelPage.routeName
          : LumaSettingsPage.routeName,
    ),
  );
  Future<void> _backup() async {
    final settings = context.read<SettingsService>();
    final apps = context.read<AppsService>();
    await showBackupDialog(
      context,
      mode: LauncherMaterial.fromName(settings.launcherMaterial),
      blurBuilder: (child, sigma, saturation) => CachedBlurBackdrop(
        sigma: sigma,
        saturation: saturation,
        child: child,
      ),
      export: () async => LauncherBackup(
        settings.exportBackupPreferences(),
        apps.exportLayout(),
      ).encode(),
      readLocal: () => LumaChannel().readLocalBackup(),
      saveLocal: (value) => LumaChannel().saveLocalBackup(value),
      readFile: () => LumaChannel().importBackup(),
      writeFile: (value) => LumaChannel().exportBackup(value),
      restore: (backup) async {
        final oldPrefs = settings.exportBackupPreferences();
        final oldLayout = apps.exportLayout();
        try {
          await apps.restoreLayout(backup.layout);
          await settings.restoreBackupPreferences(backup.preferences);
          if (mounted) AppCustomizationScope.of(context)?.refreshPreferences();
        } catch (_) {
          await apps.restoreLayout(oldLayout);
          await settings.restoreBackupPreferences(oldPrefs);
          rethrow;
        }
      },
    );
  }

  Future<void> _onboarding() async {
    final settings = context.read<SettingsService>();
    if (const bool.fromEnvironment('LUMA_FRAME_PROBE')) {
      debugPrint(
        'LUMA_RENDER_MODE ${settings.minimalBackground} cachedGlass=true',
      );
    }
    if (settings.launcherSetupSeen) return;
    setState(() => _setupDialogOpen = true);
    await showLumaDialog<void>(
      context: context,
      reducedMotion: settings.reduceMotion,
      builder: (dialogContext) => ConfiguredFirstRunGuide(
        onComplete: () async {
          await settings.setLauncherSetupSeen(true);
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        },
      ),
      barrierDismissible: false,
    );
    await settings.setLauncherSetupSeen(true);
    if (mounted)
      setState(() {
        _setupDialogOpen = false;
        _homeReset++;
      });
  }

  LauncherAppItem _item(App app, AppsService service) {
    final key = '${app.packageName}:${app.version}:${app.installedAt}';
    if (service.consumeDirtyImage(app.packageName))
      _items.removeWhere((key, _) => key.startsWith('${app.packageName}:'));
    return _items.putIfAbsent(
      key,
      () => LauncherAppItem(
        id: app.packageName,
        name: app.name,
        installedAt: app.installedAt,
        category: classifyTvApp(
          app.packageName,
          app.name,
          platformCategory: app.appCategory,
          isGame: app.isGame,
        ),
        loadIcon: () async {
          try {
            final bytes = await service.getAppIcon(app.packageName);
            return bytes.isEmpty ? null : MemoryImage(bytes);
          } catch (_) {
            return null;
          }
        },
        loadArtwork: () async {
          try {
            final banner = await service.getAppBanner(app.packageName);
            if (banner.isNotEmpty) return MemoryImage(banner);
            final icon = await service.getAppIcon(app.packageName);
            return icon.isEmpty ? null : MemoryImage(icon);
          } catch (_) {
            return null;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AppsService>();
    if (service.initializationError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load your apps. Please try again.'),
              const SizedBox(height: 16),
              FilledButton(
                autofocus: true,
                onPressed: service.initialize,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    ProgrammeLibrary.shared.loadAppIcon = (package) async {
      try {
        final bytes = await service.getAppIcon(package);
        return bytes.isEmpty ? null : MemoryImage(bytes);
      } catch (_) {
        return null;
      }
    };
    ProgrammeLibrary.shared.providerNames = {
      for (final app in service.applications) app.packageName: app.name,
    };
    final settings = context.watch<SettingsService>();
    final profiles = context.watch<ProfileService?>();
    if (_keepScreenOn != settings.keepScreenOn) {
      _keepScreenOn = settings.keepScreenOn;
      LumaChannel().setKeepScreenOn(_keepScreenOn!);
    }
    final wallpaper = context.watch<WallpaperService>();
    final watch = context.watch<WatchNextService>();
    ProgrammeLibrary.shared.refreshSources = watch.refreshPermissionAndItems;
    ProgrammeLibrary.shared.requestSourceAccess = watch.requestPermission;
    ProgrammeLibrary.shared.sourceAccessAllowed = watch.hasPermission;
    final installed = {
      for (final app in service.applications) app.packageName: app,
    };
    _items.removeWhere((_, value) => !installed.containsKey(value.id));
    final apps = service.applications
        .where((app) => !app.hidden)
        .map((app) => _item(app, service))
        .toList();
    final favorites = service.categories
        .where((category) => category.name == 'Favorites')
        .expand((category) => category.applications)
        .where((app) => !app.hidden)
        .map((app) => _item(app, service))
        .toList();
    App resolve(LauncherAppItem item) =>
        installed[item.id] ?? (throw StateError('App removed'));
    // StandBy appears when the home screen is left idle.
    return StandbyHost(
      child: LauncherHome(
        loadAppActions: (app) => NativeAppActions().load(app.id),
        onAppAction: (app, action, query) =>
            NativeAppActions().launch(app.id, action, query: query),
        onPickAppArtwork: () async {
          final media = await TvMediaPicker.show(
            context,
            mode: TvMediaPickerMode.image,
          );
          if (media == null) return null;
          final bytes = await LumaChannel().loadContentUriImage(media.uri);
          if (bytes.isEmpty) throw const FormatException('Image unavailable');
          return bytes;
        },
        createVoiceSession: NativeVoiceSession.new,
        resetToken: _homeReset,
        recentsToken: _recentsToken,
        onRecentClosed: _markClosed,
        openApps:
            ([
                  ...service.applications.where(
                    (app) =>
                        !app.hidden &&
                        app.lastLaunchedAt != null &&
                        // Luma itself is always running.
                        !app.packageName.startsWith('app.luma.tvlauncher') &&
                        app.lastLaunchedAt!.millisecondsSinceEpoch >
                            (_closedAt[app.packageName] ?? 0),
                  ),
                ]..sort(
                  (a, b) => b.lastLaunchedAt!.compareTo(a.lastLaunchedAt!),
                ))
                .take(12)
                .map((app) => _item(app, service))
                .toList(),
        autofocusApps: !_setupDialogOpen,
        onBackup: _backup,
        loadConnectionStatus: () => LumaChannel().getConnectionStatus(),
        onBluetoothStatusPermission: () =>
            LumaChannel().requestBluetoothStatus(),
        timeFormat: settings.timeFormat,
        clockStyle: settings.clockStyle,
        clockSize: settings.clockSize,
        onClockStyleChanged: settings.setClockStyle,
        onClockSizeChanged: settings.setClockSize,
        onTimeFormatChanged: settings.setClockFormat,
        onLayout: () => showLumaDialog<void>(
          context: context,
          fromSide: true,
          builder: (_) => const SettingsPanel(
            initialRoute: LauncherSectionsPanelPage.routeName,
          ),
        ),
        sections: [
          for (final category in service.launcherSections)
            if (category is Category &&
                category.name.toLowerCase() != 'favorites')
              LauncherAppSection(
                id: '${category.id}',
                name: category.name.toLowerCase() == 'all apps'
                    ? 'App collection'
                    : category.name,
                apps: category.applications
                    .where((app) => !app.hidden)
                    .map((app) => _item(app, service))
                    .toList(),
                columns: category.columnsCount,
                horizontal: category.type == CategoryType.row,
                rowHeight: category.rowHeight,
              )
            else if (category is LauncherSpacer)
              LauncherAppSection(
                id: 'spacer-${category.id}',
                name: '',
                apps: const [],
                spacerHeight: category.height,
              ),
        ],
        recentApps:
            ([
                  ...service.applications.where(
                    (app) => !app.hidden && app.lastLaunchedAt != null,
                  ),
                ]..sort(
                  (a, b) => b.lastLaunchedAt!.compareTo(a.lastLaunchedAt!),
                ))
                .take(6)
                .map((app) => _item(app, service))
                .toList(),
        apps: apps,
        favorites: favorites,
        loading: !service.initialized,
        wallpaper:
            wallpaper.wallpaper ?? const AssetImage('assets/mountain.jpg'),
        wallpaperRevision: wallpaper.wallpaperRevision,
        background: wallpaper.wallpaperVideoFile == null
            ? (wallpaper.wallpaper == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: wallpaper.gradient.gradient,
                      ),
                    )
                  : null)
            : WallpaperVideoBackground(file: wallpaper.wallpaperVideoFile!),
        mode: LauncherMaterial.fromName(settings.launcherMaterial),
        minimalBackground: settings.minimalBackground,
        onMinimalBackgroundChanged: settings.setMinimalBackground,
        reducedMotion: settings.reduceMotion,
        onReducedMotionChanged: settings.setReduceMotion,
        onMaterialChanged: (mode) => settings.setLauncherMaterial(mode.name),
        onLaunch: (item) => service.launchApp(resolve(item)),
        onFavorite: (item) => service.toggleFavorite(resolve(item)),
        onMoveFavorite: (item, offset) async {
          final category = await service.getOrCreateFavoritesCategory();
          final old = category.applications.indexWhere(
            (app) => app.packageName == item.id,
          );
          final next = old + offset;
          if (old >= 0 && next >= 0 && next < category.applications.length)
            await service.reorderApplication(category, old, next);
        },
        onWallpaper: () async {
          final asset = await showSceneryPicker(
            context,
            initialAsset: settings.selectedWallpaperAsset,
            timeFormat: settings.timeFormat,
            onCustomWallpaper: () async {
              final photo = await TvMediaPicker.show(
                context,
                mode: TvMediaPickerMode.image,
              );
              if (photo == null || !context.mounted) return null;
              try {
                final bytes = await LumaChannel().loadContentUriImage(
                  photo.uri,
                );
                if (bytes.isEmpty) throw StateError('Empty photo');
                return (source: photo.uri, image: MemoryImage(bytes));
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not open this photo. Try a different image.',
                      ),
                    ),
                  );
                }
              }
              return null;
            },
            mode: LauncherMaterial.fromName(settings.launcherMaterial),
            blurBuilder: (child, sigma, saturation) => CachedBlurBackdrop(
              sigma: sigma,
              saturation: saturation,
              child: child,
            ),
          );
          if (asset == null || !context.mounted) return;
          try {
            if (sceneryWallpapers.any((photo) => photo.asset == asset)) {
              await wallpaper.setSceneryWallpaper(asset);
            } else {
              await settings.setTimeBasedWallpaperEnabled(false);
              await wallpaper.pickWallpaperFromUri(asset);
            }
            if (![
              'glass',
              'glass-real',
            ].contains(settings.selectedMinimalBackground)) {
              await settings.setMinimalBackground('wallpaper');
            }
          } catch (_) {
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Unable to set wallpaper. Please try again.'),
                ),
              );
          }
        },
        onSolidColorChanged: settings.setSolidThemeColor,
        performanceMode: settings.performanceMode,
        onPerformanceChanged: settings.setPerformanceMode,
        tvControls: _tvControls,
        notificationCount: _notificationCount,
        profile: profiles != null && profiles.profiles.length > 1
            ? profiles.active
            : null,
        profiles: profiles?.profiles ?? const [],
        onProfileSelected: profiles == null
            ? null
            : (profile) => profiles.switchTo(profile.id),
        onProfiles: profiles == null
            ? null
            : () => showProfilesSettings(context, profiles),
        onNotifications: () async {
          await showNotificationCenter(
            context,
            source: _notifications,
            packageName: _packageName,
            blurBuilder: (child, sigma, saturation) => CachedBlurBackdrop(
              sigma: sigma,
              saturation: saturation,
              child: child,
            ),
          );
          unawaited(_refreshNotificationCount());
        },
        liteMode: settings.liteMode,
        liteModeActive: settings.liteModeActive,
        onLiteModeChanged: settings.setLiteMode,
        depthClock: settings.depthClock,
        depthAsset:
            settings.depthClock &&
                !settings.liteModeActive &&
                wallpaper.wallpaperVideoFile == null &&
                !settings.timeBasedWallpaperEnabled &&
                hasDepthLayer(settings.selectedWallpaperAsset)
            ? settings.selectedWallpaperAsset
            : null,
        onDepthClockChanged: settings.setDepthClock,
        keepScreenOn: settings.keepScreenOn,
        onKeepScreenOnChanged: settings.setKeepScreenOn,
        selectedMinimalBackground: settings.selectedMinimalBackground,
        showWatchNext: settings.showWatchNextSection,
        onWatchNextChanged: settings.setShowWatchNextSection,
        onHomeSettings: () => LumaChannel().openHomeSettings(),
        soundSettings: const LumaSoundSettings(),
        aboutSettings: const LumaAboutSettings(),
        onSettings: () => _settings(),
        onManage: () => _settings(apps: true),
        onWifi: () => LumaChannel().openWifiSettings(),
        onDeviceSettings: (section) async {
          final opened = await LumaChannel().openQuickSettings(section);
          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Device settings could not be opened.'),
              ),
            );
          }
        },
        homeHasWatchContent: true,
        homeContinueWatching: const WatchNextRow(homeShelf: true),
        continueWatching: WatchNextRow(
          showEmptyState: settings.launcherMaterial == 'minimal',
        ),
        blurBuilder: (child, sigma, saturation) =>
            (settings.performanceMode ||
                ['glass', 'glass-real'].contains(settings.minimalBackground))
            ? CachedBlurBackdrop(
                sigma: sigma,
                saturation: saturation,
                child: child,
              )
            : BackdropFilter(
                filter: ImageFilter.compose(
                  outer: glassSaturation(saturation),
                  inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                ),
                child: child,
              ),
      ),
    );
  }
}
