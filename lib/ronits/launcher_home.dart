import 'remote_navigation.dart';
import 'cinematic_backdrop.dart';
import 'app_actions.dart';
import 'font_styles.dart';
import 'app_customization.dart';
import 'programme_library.dart';
import 'clock_widget.dart';
import 'clock_preferences.dart';
import 'search_panel.dart';
import 'programme_browser.dart';
import 'programme_rail.dart';
import 'solid_theme_scope.dart';
// Shared production/browser presentation. No Android APIs or dart:io imports.
import 'dart:async';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import 'home_preferences.dart';
import 'luma_glass_theme.dart';
import 'liquid_glass_v2.dart';
import 'reference_control_center.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'glass_surface.dart';
import 'motion.dart';
import 'voice_session.dart';
import 'voice_search.dart';
import 'focus_feedback.dart';
import 'quick_settings.dart';
import 'menu_dialog.dart';
import 'menu_undo.dart';
import 'menu_focus.dart';
import 'cached_wallpaper.dart';
import 'glass_wallpaper.dart';
import 'scroll_edge_fade.dart';
import 'prepared_backdrop_scope.dart';
import 'shared_blur_cache.dart';
import 'app_grid_layout.dart';
import 'tv_icon_pack.dart';
import 'wallpaper_tone.dart';
import 'tv_controls.dart';
import 'depth_clock.dart';
import 'profiles.dart';
import 'recent_apps.dart';
import 'standby.dart';

part 'minimal_home.dart';
part 'home_personalization.dart';
part 'app_customization_menu.dart';
part 'dock_reorder.dart';

class LauncherAppItem {
  const LauncherAppItem({
    required this.id,
    required this.name,
    this.artwork,
    this.loadArtwork,
    this.icon,
    this.loadIcon,
    this.iconBounds,
    this.category,
    this.installedAt = 0,
  });
  final Rect? iconBounds;
  final String? category;
  final int installedAt;
  final String id, name;
  final Future<ImageProvider?>? artwork, icon;
  final Future<ImageProvider?> Function()? loadArtwork, loadIcon;
}

Future<ImageProvider?> installedAppArtwork(LauncherAppItem app) async {
  try {
    final banner =
        await (app.loadArtwork?.call() ?? app.artwork ?? Future.value(null));
    if (banner != null) return banner;
  } catch (_) {
    /* Fall back to the installed icon. */
  }
  try {
    return await (app.loadIcon?.call() ?? app.icon ?? Future.value(null));
  } catch (_) {
    return null;
  }
}

class LauncherAppSection {
  const LauncherAppSection({
    required this.id,
    required this.name,
    required this.apps,
    this.columns = 6,
    this.horizontal = false,
    this.rowHeight = 110,
    this.spacerHeight = 0,
  });
  final String id, name;
  final List<LauncherAppItem> apps;
  final int columns, rowHeight, spacerHeight;
  final bool horizontal;
}

String launcherClockLabel(DateTime now, String pattern) {
  try {
    return DateFormat(pattern).format(now);
  } catch (_) {
    return DateFormat('h:mm a').format(now);
  }
}

double _tileLabelExtent(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(14) * 1.3).ceilToDouble() + 23;

enum LauncherRemoteCommand { home, search, settings, options, voice }

class LauncherRemoteController extends ChangeNotifier {
  LauncherRemoteCommand? command;
  void send(LauncherRemoteCommand value) {
    command = value;
    notifyListeners();
  }
}

class LauncherHome extends StatefulWidget {
  const LauncherHome({
    super.key,
    required this.apps,
    required this.favorites,
    required this.wallpaper,
    this.wallpaperRevision = 0,
    required this.mode,
    required this.onMaterialChanged,
    required this.onLaunch,
    required this.onSettings,
    required this.onWifi,
    required this.onManage,
    required this.onFavorite,
    this.loadConnectionStatus,
    this.onBluetoothStatusPermission,
    this.timeFormat = 'h:mm a',
    this.clockStyle = 'digital',
    this.clockSize = 'medium',
    this.onClockStyleChanged,
    this.onClockSizeChanged,
    this.onTimeFormatChanged,
    this.sections = const [],
    this.recentApps = const [],
    this.gridColumns = 6,
    this.onLayout,
    this.onBackup,
    this.networkStatus = 'Checking connection…',
    this.bluetoothStatus = 'Open accessory settings',
    this.defaultHomeStatus,
    this.onSolidColorChanged,
    this.minimalBackground = 'charcoal',
    this.onMinimalBackgroundChanged,
    this.performanceMode = true,
    this.onPerformanceChanged,
    this.tvControls,
    this.notificationCount = 0,
    this.onNotifications,
    this.recentsToken = 0,
    this.openApps = const [],
    this.onRecentClosed,
    this.recentAppsSystem = const ChannelRecentAppsSystem(),
    this.profile,
    this.profiles = const [],
    this.onProfileSelected,
    this.onProfiles,
    this.liteMode = 'auto',
    this.liteModeActive = false,
    this.onLiteModeChanged,
    this.depthClock = true,
    this.depthAsset,
    this.onDepthClockChanged,
    this.keepScreenOn = true,
    this.onKeepScreenOnChanged,
    this.selectedMinimalBackground,
    this.showWatchNext = false,
    this.onWatchNextChanged,
    this.onHomeSettings,
    this.onWallpaper,
    this.createVoiceSession,
    this.remoteController,
    this.onDeviceSettings,
    this.onPickAppArtwork,
    this.loadAppActions,
    this.onAppAction,
    this.onMoveFavorite,
    this.blurBuilder,
    this.continueWatching,
    this.homeContinueWatching,
    this.homeHasWatchContent = true,
    this.background,
    this.resetToken = 0,
    this.autofocusApps = true,
    this.reducedMotion = false,
    this.onReducedMotionChanged,
    this.loading = false,
    this.preview = false,
    this.soundSettings,
    this.aboutSettings,
  });
  final Future<Map<String, dynamic>> Function()? loadConnectionStatus;
  final Future<void> Function()? onBluetoothStatusPermission;
  final String timeFormat, networkStatus, bluetoothStatus;
  final String clockStyle, clockSize;
  final ValueChanged<String>? onClockStyleChanged, onClockSizeChanged;
  final String? defaultHomeStatus;
  final ValueChanged<String>? onTimeFormatChanged;
  final List<LauncherAppSection> sections;
  final int gridColumns;
  final VoidCallback? onLayout, onBackup;
  final VoidCallback? onWallpaper, onHomeSettings;
  final String minimalBackground;
  final ValueChanged<String>? onMinimalBackgroundChanged;
  final ValueChanged<String>? onSolidColorChanged;
  final bool performanceMode, showWatchNext;
  final ValueChanged<bool>? onPerformanceChanged, onWatchNextChanged;

  /// Sleep timer and input switching in quick settings.
  final TvControls? tvControls;

  /// Bell on the home top bar; hidden when [onNotifications] is null.
  final int notificationCount;
  final VoidCallback? onNotifications;

  /// Goes up when Home is pressed while Luma is already on screen, which
  /// opens the Recent apps panel.
  final int recentsToken;

  /// Apps for the Recent apps panel: opened from Luma and not closed since.
  final List<LauncherAppItem> openApps;
  final ValueChanged<String>? onRecentClosed;
  final RecentAppsSystem recentAppsSystem;

  /// Who is watching; the badge shows only when there is more than one person.
  final Profile? profile;
  final List<Profile> profiles;
  final ValueChanged<Profile>? onProfileSelected;
  final VoidCallback? onProfiles;
  final String liteMode;
  final bool liteModeActive;
  final ValueChanged<String>? onLiteModeChanged;
  final bool depthClock;

  /// The selected wallpaper when the depth clock should be drawn over it.
  final String? depthAsset;
  final ValueChanged<bool>? onDepthClockChanged;
  final bool keepScreenOn;
  final ValueChanged<bool>? onKeepScreenOnChanged;

  /// The theme the user chose; [minimalBackground] is what is rendered.
  final String? selectedMinimalBackground;
  final VoiceSession Function()? createVoiceSession;
  final LauncherRemoteController? remoteController;
  final Widget? soundSettings, aboutSettings;
  final bool autofocusApps;
  final int resetToken;
  final List<LauncherAppItem> apps, favorites, recentApps;
  final ImageProvider wallpaper;
  final int wallpaperRevision;
  final LauncherMaterial mode;
  final ValueChanged<LauncherMaterial> onMaterialChanged;
  final Future<void> Function(LauncherAppItem app) onLaunch;
  final VoidCallback onSettings, onWifi, onManage;
  final ValueChanged<String>? onDeviceSettings;
  final Future<Uint8List?> Function()? onPickAppArtwork;
  final Future<List<AppQuickAction>> Function(LauncherAppItem app)?
  loadAppActions;
  final Future<void> Function(
    LauncherAppItem app,
    String action,
    String? query,
  )?
  onAppAction;
  final Future<void> Function(LauncherAppItem app) onFavorite;
  final Future<void> Function(LauncherAppItem app, int offset)? onMoveFavorite;
  final GlassBlurBuilder? blurBuilder;
  final Widget? continueWatching, homeContinueWatching, background;
  final bool homeHasWatchContent;
  final bool reducedMotion, loading, preview;
  final ValueChanged<bool>? onReducedMotionChanged;
  @override
  State<LauncherHome> createState() => _LauncherHomeState();
}

class _LauncherHomeState extends State<LauncherHome>
    with WidgetsBindingObserver {
  void _updateHome(VoidCallback change) => setState(change);
  HomePreferences? _homePreferences;
  bool _selectionRestored = false, _restoreScheduled = false;
  bool _selectionLibrary = false;
  Timer? _selectionSave;
  final _rememberedFocus = <String, FocusNode>{};
  Color? _wallpaperAccent;
  int _accentTicket = 0;
  VoidCallback? _cancelAccent;
  LauncherAppItem? _focusedApp;
  String? _launching;
  DateTime? _lastLaunch;
  String? _lastLaunchId;
  int _homeTicket = 0;
  double _minimalLibraryOffset = 500;
  bool _minimalInLibrary = false;
  String? _lastAppsSelection;
  void _minimalScrolled() {
    if (!mounted || !_minimalScroll.hasClients) return;
    final inLibrary = _minimalScroll.offset >= _minimalLibraryOffset - 100;
    if (inLibrary != _minimalInLibrary)
      setState(() => _minimalInLibrary = inLibrary);
  }

  final _homeRowAnchors = <String, GlobalKey>{};
  final _homeRowScopes = <String, FocusScopeNode>{};
  final _homeContentAnchor = GlobalKey();
  final _homeBackdropOrigin = GlobalKey();
  ui.Image? _homeEdgeImage;
  void _preparedHomeEdges(ui.Image image) {
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _homeEdgeImage?.dispose();
      _homeEdgeImage = image;
    });
  }

  final _homeContentFocus = FocusScopeNode(debugLabel: 'Home content');
  final _minimalAddAnchor = GlobalKey();
  final _settingsRevision = ValueNotifier(0);
  final _searchFocus = FocusNode(debugLabel: 'Home search');
  final _appsWallpaperCache = SharedBlurCache(capacity: 1);
  final _firstAppFocus = FocusNode(debugLabel: 'First home app');
  final _dockMoveFocus = FocusNode(debugLabel: 'Moving favourite');
  String? _dockMoveId;
  bool _dockMoveBusy = false, _dockMoveExitRequested = false;
  final _dockMoveQueue = <int>[];
  final _addDockFocus = FocusNode(debugLabel: 'Add dock apps');
  final _lastDockFocus = FocusNode(debugLabel: 'Last dock app');
  final _gridFocus = FocusNode(debugLabel: 'First grid app');
  final _scroll = LumaScrollController();
  final _minimalScroll = LumaScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.remoteController?.addListener(_remote);
    HardwareKeyboard.instance.addHandler(_customRemoteKey);
    _minimalScroll.addListener(_minimalScrolled);
    unawaited(_loadHomePreferences());
    _registerProgrammeSources();
  }

  void _registerProgrammeSources() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final library = ProgrammeLibrary.shared;
      library.registerSources({
        for (final app in widget.apps)
          if ([
            'entertainment',
            'music',
          ].contains(app.category ?? classifyTvApp(app.id, app.name)))
            library.source
                        .where((entry) => entry.provider == app.name)
                        .firstOrNull
                        ?.item
                        .packageName ??
                    app.id:
                app.name,
      }, allowed: library.sourceAccessAllowed);
    });
  }

  AppCustomization? _customization;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _customization = AppCustomizationScope.of(context);
  }

  bool _customRemoteKey(KeyEvent event) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus?.widget is EditableText ||
        focus?.findAncestorStateOfType<EditableTextState>() != null)
      return false;
    final action = _customization?.actionFor(event.logicalKey);
    if (action == null) return false;
    if (event is! KeyDownEvent) return true;
    switch (action) {
      case 'search':
        unawaited(_search());
      case 'voice':
        unawaited(_voice());
      case 'apps':
        unawaited(_minimalLibrary());
      default:
        final app = widget.apps
            .where((a) => a.id == action.substring(4))
            .firstOrNull;
        if (app == null) {
          _message(
            'This app is no longer available. Change the shortcut in Settings.',
          );
        } else {
          unawaited(_launch(app));
        }
    }
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused)
      unawaited(_saveSelection());
  }

  @override
  void dispose() {
    _homeEdgeImage?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.remoteController?.removeListener(_remote);
    HardwareKeyboard.instance.removeHandler(_customRemoteKey);
    _selectionSave?.cancel();
    unawaited(_saveSelection());
    _accentTicket++;
    _cancelAccent?.call();
    for (final node in _rememberedFocus.values) {
      node.dispose();
    }
    for (final scope in _homeRowScopes.values) {
      scope.dispose();
    }
    _homeContentFocus.dispose();
    _settingsRevision.dispose();
    _searchFocus.dispose();
    _appsWallpaperCache.dispose();
    _firstAppFocus.dispose();
    _dockMoveFocus.dispose();
    _addDockFocus.dispose();
    _lastDockFocus.dispose();
    _gridFocus.dispose();
    _scroll.dispose();
    _minimalScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LauncherHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dockMoveId != null &&
        !widget.favorites.any((app) => app.id == _dockMoveId)) {
      _dockMoveId = null;
      _dockMoveQueue.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          (widget.favorites.isEmpty ? _addDockFocus : _firstAppFocus)
              .requestFocus();
      });
    }
    if (oldWidget.apps != widget.apps) _registerProgrammeSources();
    if (widget.mode == LauncherMaterial.minimal &&
        oldWidget.favorites.isEmpty &&
        widget.favorites.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _addDockFocus.hasFocus &&
            (ModalRoute.of(context)?.isCurrent ?? true))
          _firstAppFocus.requestFocus();
      });
    }
    if (oldWidget.wallpaper != widget.wallpaper ||
        oldWidget.wallpaperRevision != widget.wallpaperRevision) {
      _appsWallpaperCache.clear();
      unawaited(_extractAccent());
    }
    if (oldWidget.mode != widget.mode ||
        oldWidget.minimalBackground != widget.minimalBackground ||
        oldWidget.reducedMotion != widget.reducedMotion ||
        oldWidget.performanceMode != widget.performanceMode ||
        oldWidget.liteMode != widget.liteMode ||
        oldWidget.liteModeActive != widget.liteModeActive ||
        oldWidget.depthClock != widget.depthClock ||
        oldWidget.keepScreenOn != widget.keepScreenOn ||
        oldWidget.depthAsset != widget.depthAsset ||
        oldWidget.showWatchNext != widget.showWatchNext ||
        oldWidget.wallpaper != widget.wallpaper ||
        oldWidget.wallpaperRevision != widget.wallpaperRevision ||
        oldWidget.timeFormat != widget.timeFormat ||
        oldWidget.clockStyle != widget.clockStyle ||
        oldWidget.clockSize != widget.clockSize ||
        oldWidget.networkStatus != widget.networkStatus ||
        oldWidget.bluetoothStatus != widget.bluetoothStatus ||
        oldWidget.apps != widget.apps ||
        oldWidget.sections != widget.sections ||
        oldWidget.defaultHomeStatus != widget.defaultHomeStatus)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _settingsRevision.value++;
      });
    if (oldWidget.remoteController != widget.remoteController) {
      oldWidget.remoteController?.removeListener(_remote);
      widget.remoteController?.addListener(_remote);
    }
    if (oldWidget.recentsToken != widget.recentsToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scroll = widget.mode == LauncherMaterial.minimal
            ? _minimalScroll
            : _scroll;
        // Home from further down the page goes to the top first, as before.
        if (scroll.hasClients && scroll.offset > 1) {
          _goHome();
        } else {
          _openRecents();
        }
      });
    }
    if (oldWidget.resetToken != widget.resetToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goHome();
      });
    }
  }

  bool _recentsOpen = false;

  /// Recent apps: the apps opened from Luma, newest first.
  Future<void> _openRecents() async {
    if (_recentsOpen || !mounted) return;
    _recentsOpen = true;
    final recent = widget.openApps;
    final chosen = await showRecentApps(
      context,
      system: widget.recentAppsSystem,
      onClosed: widget.onRecentClosed,
      apps: [
        for (final app in recent)
          RecentApp(
            id: app.id,
            name: app.name,
            artwork: () async {
              try {
                final banner =
                    await (app.loadArtwork?.call() ??
                        app.artwork ??
                        Future<ImageProvider?>.value(null));
                if (banner != null) return banner;
              } catch (_) {
                // Apps without TV artwork fall back to their icon.
              }
              return await (app.loadIcon?.call() ??
                  app.icon ??
                  Future<ImageProvider?>.value(null));
            },
          ),
      ],
    );
    _recentsOpen = false;
    if (!mounted || chosen == null) return;
    final app = recent.where((item) => item.id == chosen).firstOrNull;
    if (app != null) await widget.onLaunch(app);
  }

  void _trackApp(LauncherAppItem app) {
    _focusedApp = app;
  }

  Future<void> _goHome() async {
    if (_dockMoveId != null) {
      _finishDockMove();
      return;
    }
    cancelPendingMenuFocusRestores();
    final scroll = widget.mode == LauncherMaterial.minimal
        ? _minimalScroll
        : _scroll;
    final ticket = ++_homeTicket;
    if (scroll.hasClients) {
      if (motionReduced(context, widget.reducedMotion))
        scroll.jumpTo(0);
      else
        await scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: lumaEase,
        );
    }
    if (mounted && ticket == _homeTicket) {
      (widget.favorites.isEmpty ? _addDockFocus : _firstAppFocus)
          .requestFocus();
    }
  }

  Future<void> _showApps() async {
    final ticket = ++_homeTicket;
    if (!_scroll.hasClients) return;
    final target = (MediaQuery.sizeOf(context).height - 80).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (motionReduced(context, widget.reducedMotion)) {
      _scroll.jumpTo(target);
    } else {
      await _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: lumaEase,
      );
    }
    if (mounted && ticket == _homeTicket) _gridFocus.requestFocus();
  }

  void _remote() {
    switch (widget.remoteController?.command) {
      case LauncherRemoteCommand.home:
        Navigator.of(context).popUntil((route) => route.isFirst);
        _goHome();
        break;
      case LauncherRemoteCommand.search:
        _search();
        break;
      case LauncherRemoteCommand.voice:
        _voice();
        break;
      case LauncherRemoteCommand.settings:
        _controls();
        break;
      case LauncherRemoteCommand.options:
        final app =
            _focusedApp ??
            (widget.favorites.isNotEmpty
                ? widget.favorites.first
                : widget.apps.firstOrNull);
        if (app != null) _options(app);
        break;
      case null:
        break;
    }
  }

  Future<void> _chooseDockApps() => showLumaDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DockAppPicker(
      apps: widget.apps,
      favorites: widget.favorites.map((app) => app.id).toSet(),
      onToggle: widget.onFavorite,
      onRestore: _restoreDockApp,
      onMove: widget.onMoveFavorite,
    ),
  );

  Future<void> _restoreDockApp(LauncherAppItem app, int index) async {
    if (widget.favorites.any((entry) => entry.id == app.id)) return;
    final lastIndex = widget.favorites.length;
    await widget.onFavorite(app);
    final offset = index - lastIndex;
    if (offset != 0) await widget.onMoveFavorite?.call(app, offset);
  }

  GlassSurface _glass(
    Widget child, {
    bool sheet = false,
    bool frostedSheet = false,
    double radius = 28,
  }) => GlassSurface(
    mode: widget.mode,
    sheet: sheet,
    frostedSheet: frostedSheet,
    radius: radius,
    blurBuilder: widget.blurBuilder,
    child: child,
  );
  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _launch(LauncherAppItem item) async {
    final now = DateTime.now();
    if (_launching != null ||
        (_lastLaunchId == item.id &&
            _lastLaunch != null &&
            now.difference(_lastLaunch!).inMilliseconds < 500))
      return;
    _lastLaunch = now;
    _lastLaunchId = item.id;
    setState(() => _launching = item.id);
    try {
      await _saveSelection();
      await widget.onLaunch(item);
    } catch (_) {
      _message('Unable to open ${item.name}. The app may have been removed.');
    } finally {
      if (mounted) setState(() => _launching = null);
    }
  }

  Future<void> _options(LauncherAppItem item) async {
    final favorite = widget.favorites.any((app) => app.id == item.id);
    final canMove =
        favorite &&
        widget.onMoveFavorite != null &&
        widget.mode == LauncherMaterial.minimal;
    final source = FocusManager.instance.primaryFocus?.context
        ?.findRenderObject();
    final overlay = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    final anchor = source is RenderBox && overlay is RenderBox
        ? overlay.globalToLocal(source.localToGlobal(Offset.zero)) & source.size
        : Rect.fromLTWH(32, 80, 160, 90);
    var quickActions = <AppQuickAction>[];
    try {
      quickActions =
          await widget.loadAppActions
              ?.call(item)
              .timeout(const Duration(seconds: 2)) ??
          [];
    } catch (_) {
      /* Dock actions remain available when app shortcuts fail. */
    }
    if (!mounted) return;
    final action = await showAppMenu<String>(
      context: context,
      anchor: anchor,
      title: item.name,
      reducedMotion: widget.reducedMotion,
      builder: (menuContext) => FocusHighlightLayer(
        menu: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canMove)
              TvMenuRow(
                autofocus: true,
                icon: Icons.open_with_rounded,
                title: 'Move',
                onPressed: () => Navigator.pop(menuContext, 'move'),
              ),
            if (quickActions.isNotEmpty && widget.onAppAction != null)
              TvMenuRow(
                key: const ValueKey('app-quick-actions'),
                icon: Icons.bolt_rounded,
                title: 'Quick actions',
                onPressed: () => Navigator.pop(menuContext, 'quick'),
              ),
            TvMenuRow(
              autofocus: !canMove,
              icon: favorite ? Icons.star_outline_rounded : Icons.star_rounded,
              title: favorite ? 'Remove from favourites' : 'Add to favourites',
              onPressed: () => Navigator.pop(menuContext, 'favorite'),
            ),
            if (_customization != null)
              TvMenuRow(
                key: const ValueKey('app-artwork-settings'),
                icon: Icons.image_outlined,
                title: 'App artwork',
                onPressed: () => Navigator.pop(menuContext, 'artwork'),
              ),
            TvMenuRow(
              icon: Icons.more_horiz_rounded,
              title: 'More options',
              onPressed: () => Navigator.pop(menuContext, 'manage'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'quick':
        final chosen = await showAppMenu<String>(
          context: context,
          anchor: anchor,
          title: item.name,
          reducedMotion: widget.reducedMotion,
          builder: (quickContext) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, shortcut) in quickActions.indexed)
                TvMenuRow(
                  autofocus: index == 0,
                  title: shortcut.label,
                  icon: shortcut.id == 'info'
                      ? Icons.info_outline
                      : Icons.bolt_rounded,
                  onPressed: () => Navigator.pop(quickContext, shortcut.id),
                ),
            ],
          ),
        );
        if (chosen != null && mounted) {
          String? query;
          if (chosen == 'search') {
            query = await showLumaDialog<String>(
              context: context,
              builder: (_) => AppSearchDialog(appName: item.name),
            );
            if (query == null || !mounted) return;
          }
          try {
            await widget.onAppAction?.call(item, chosen, query);
          } catch (_) {
            if (mounted) _message('This app action is no longer available.');
          }
        }
      case 'move':
        await _beginDockMove(item);
      case 'favorite':
        final index = widget.favorites.toList().indexWhere(
          (app) => app.id == item.id,
        );
        try {
          await widget.onFavorite(item);
          if (mounted && favorite) {
            await showAppMenu<void>(
              context: context,
              anchor: anchor,
              title: 'Removed from dock',
              reducedMotion: widget.reducedMotion,
              builder: (undoContext) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MenuUndoNotice(
                    key: const ValueKey('dock-undo'),
                    autofocus: true,
                    undo: MenuUndo(
                      'Restore ${item.name}',
                      () => _restoreDockApp(item, index),
                    ),
                    onRestored: () => Navigator.pop(undoContext),
                  ),
                  TvMenuRow(
                    title: 'Done',
                    onPressed: () => Navigator.pop(undoContext),
                  ),
                ],
              ),
            );
          }
        } catch (_) {
          if (mounted) _message('Could not save favourites.');
        }
      case 'artwork':
        await _artworkSettings(item);
      case 'manage':
        widget.onManage();
    }
  }

  Future<void> _search({String initialQuery = ''}) async {
    final previous = FocusManager.instance.primaryFocus;
    await showLumaDialog<void>(
      context: context,
      floating: true,
      reducedMotion: widget.reducedMotion,
      builder: (context) => _SearchDialog(
        autofocusInput: widget.preview,
        apps: widget.apps,
        initialQuery: initialQuery,
        mode: widget.mode,
        blurBuilder: widget.blurBuilder,
        reducedMotion: widget.reducedMotion,
        onLaunch: _launch,
      ),
    );
    if (mounted && previous?.context != null && previous!.canRequestFocus)
      previous.requestFocus();
  }

  Future<void> _voice() async {
    final previous = FocusManager.instance.primaryFocus;
    final create = widget.createVoiceSession;
    if (create == null) return;
    String? query;
    final session = create();
    await showLumaDialog<void>(
      context: context,
      fromTop: true,
      reducedMotion: widget.reducedMotion,
      builder: (_) => VoiceSearchDialog(
        session: session,
        mode: widget.mode,
        blurBuilder: widget.blurBuilder,
        reducedMotion: widget.reducedMotion,
        preview: widget.preview,
        onSearch: (value) => query = value,
      ),
    );
    if (!mounted) return;
    if (query != null) {
      await _search(initialQuery: query!);
    }
    if (mounted && previous?.context != null && previous!.canRequestFocus)
      previous.requestFocus();
  }

  void _controls({bool fullSettings = false, String? initialCategory}) {
    if (widget.mode == LauncherMaterial.minimal &&
        !fullSettings &&
        initialCategory == null) {
      showLumaDialog<void>(
        context: context,
        fromTop: true,
        reducedMotion: widget.reducedMotion,
        builder: (quickContext) => Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 72, 24, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 272,
                maxHeight: MediaQuery.sizeOf(context).height - 100,
              ),
              child: SingleChildScrollView(
                child: Material(
                  type: MaterialType.transparency,
                  child: ReferenceControlCenter(
                    blurBuilder: widget.blurBuilder,
                    timeFormat: widget.timeFormat,
                    tvControls: widget.tvControls,
                    onStandby: () => _openFromControls(
                      quickContext,
                      () => startStandbyNow(context),
                    ),
                    notificationCount: widget.notificationCount,
                    onNotifications: widget.onNotifications == null
                        ? null
                        : () => _openFromControls(
                            quickContext,
                            widget.onNotifications!,
                          ),
                    onRecents: () =>
                        _openFromControls(quickContext, _openRecents),
                    profiles: widget.profiles,
                    activeProfile: widget.profile,
                    onProfileSelected: widget.onProfileSelected == null
                        ? null
                        : (profile) => _openFromControls(
                            quickContext,
                            () => widget.onProfileSelected!(profile),
                          ),
                    loadStatus: widget.loadConnectionStatus,
                    onWifi: widget.onWifi,
                    onDeviceSettings: (section) =>
                        widget.onDeviceSettings?.call(section),
                    onSettings: () => _openFromControls(
                      quickContext,
                      () => _controls(fullSettings: true),
                    ),
                    onWallpaper: widget.onWallpaper == null
                        ? null
                        : () => _openFromControls(
                            quickContext,
                            widget.onWallpaper!,
                          ),
                    onApps: () =>
                        _openFromControls(quickContext, _minimalLibrary),
                    onSearch: () => _openFromControls(quickContext, _search),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }
    final contentKey = GlobalKey();
    showLumaDialog<void>(
      context: context,
      fromSide: true,
      barrierDismissible: false,
      reducedMotion: widget.reducedMotion,
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: _settingsRevision,
        builder: (_, revision, child) => WallpaperAccentScope(
          color: (_homePreferences?.accent ?? false) ? _wallpaperAccent : null,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            // One large sheet: sections on the left, options on the right.
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width - 112,
              height: MediaQuery.sizeOf(context).height - 72,
              child: _glass(
                QuickSettingsContent(
                  key: contentKey,
                  initialCategory: initialCategory,
                  soundSettings: widget.soundSettings,
                  aboutSettings: widget.aboutSettings,
                  mode: widget.mode,
                  onSearch: widget.mode == LauncherMaterial.minimal
                      ? () => _search()
                      : null,
                  onPlayNext: widget.mode == LauncherMaterial.minimal
                      ? _minimalPlayNext
                      : null,
                  minimalBackground: widget.minimalBackground,
                  onMinimalBackgroundChanged: widget.onMinimalBackgroundChanged,
                  reducedMotion: widget.reducedMotion,
                  onMaterialChanged: widget.onMaterialChanged,
                  onReducedMotionChanged: widget.onReducedMotionChanged,
                  onWifi: widget.onWifi,
                  loadConnectionStatus: widget.loadConnectionStatus,
                  onBluetoothStatusPermission:
                      widget.onBluetoothStatusPermission,
                  timeFormat: widget.timeFormat,
                  clockStyle: widget.clockStyle,
                  clockSize: widget.clockSize,
                  onClockStyleChanged: widget.onClockStyleChanged,
                  onClockSizeChanged: widget.onClockSizeChanged,
                  onTimeFormatChanged: widget.onTimeFormatChanged,
                  networkStatus: widget.networkStatus,
                  bluetoothStatus: widget.bluetoothStatus,
                  defaultHomeStatus: widget.defaultHomeStatus,
                  onLayout: widget.mode == LauncherMaterial.minimal
                      ? _homeLayoutSettings
                      : widget.onLayout,
                  onBackup: widget.onBackup,
                  fullSettings: true,
                  preview: widget.preview,
                  onSolidColorChanged: widget.onSolidColorChanged,
                  performanceMode: widget.performanceMode,
                  onPerformanceChanged: widget.onPerformanceChanged,
                  liteMode: widget.liteMode,
                  liteModeActive: widget.liteModeActive,
                  onLiteModeChanged: widget.onLiteModeChanged,
                  depthClock: widget.depthClock,
                  onDepthClockChanged: widget.onDepthClockChanged,
                  keepScreenOn: widget.keepScreenOn,
                  onKeepScreenOnChanged: widget.onKeepScreenOnChanged,
                  selectedMinimalBackground:
                      widget.selectedMinimalBackground ??
                      widget.minimalBackground,
                  showWatchNext: widget.showWatchNext,
                  showFromApps: _homePreferences?.visible('watch') ?? true,
                  onFromAppsChanged: (value) async {
                    if (_homePreferences == null) await _loadHomePreferences();
                    final preferences = _homePreferences;
                    if (!mounted || preferences == null) return;
                    await preferences.storage.setBool('home_show_watch', value);
                    if (!mounted) return;
                    if (value) widget.onWatchNextChanged?.call(true);
                    _updateHome(() {});
                    _settingsRevision.value++;
                  },
                  onWatchNextChanged: widget.onWatchNextChanged,
                  onHomeSettings: widget.onHomeSettings,
                  onManage: widget.onManage,
                  onProfiles: widget.onProfiles,
                  profileName: widget.profile?.name,
                  onFontStyle: _customization == null ? null : _fontSettings,
                  onRemoteShortcuts: _customization == null
                      ? null
                      : _shortcutSettings,
                  onSettings: widget.onSettings,
                  onWallpaper: widget.onWallpaper,
                  onDeviceSettings: (section) =>
                      widget.onDeviceSettings?.call(section),
                ),
                sheet: true,
                frostedSheet: true,
                radius: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFromControls(BuildContext routeContext, VoidCallback open) {
    final route = ModalRoute.of(routeContext);
    Navigator.of(routeContext).pop();
    if (route == null) return;
    route.completed.then((_) {
      if (mounted) open();
    });
  }

  List<Widget> _sectionSlivers(LauncherAppSection section) {
    if (section.spacerHeight > 0)
      return [
        SliverToBoxAdapter(
          child: SizedBox(
            height: section.spacerHeight.clamp(0, 1000).toDouble(),
          ),
        ),
      ];
    if (section.apps.isEmpty) return [];
    final columns = section.columns.clamp(3, 8);
    final width = section.horizontal
        ? section.rowHeight.clamp(70, 180) * 16 / 9
        : (MediaQuery.sizeOf(context).width - 96 - 24 * (columns - 1)) /
              columns;
    final height = width * 9 / 16 + _tileLabelExtent(context);
    Widget tile(int index) => LauncherTile(
      key: ValueKey('${section.id}-${section.apps[index].id}'),
      app: section.apps[index],
      reduceMotion: widget.reducedMotion,
      onFocused: () => _trackApp(section.apps[index]),
      onPressed: () => _launch(section.apps[index]),
      onLongPress: () => _options(section.apps[index]),
    );
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 24, 48, 16),
          child: Text(
            section.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      if (section.horizontal)
        SliverToBoxAdapter(
          child: _HorizontalAppRow(
            key: ValueKey('row-${section.id}'),
            section: section,
            tileWidth: width,
            height: height,
            reducedMotion: widget.reducedMotion,
            onFocused: _trackApp,
            onLaunch: _launch,
            onOptions: _options,
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, index) => tile(index),
              childCount: section.apps.length,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: height,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == LauncherMaterial.minimal) return _minimalView(context);
    _scroll.reducedMotion = motionReduced(context, widget.reducedMotion);
    final size = MediaQuery.sizeOf(context);
    final favorites = widget.favorites.toList();
    final labelExtent = _tileLabelExtent(context);
    final dockHeight =
        ((size.width - 168) / 6 - 20) * 9 / 16 + labelExtent + 60;
    final heroHeight = (size.height - dockHeight - 20).clamp(
      76.0,
      double.infinity,
    );
    final columns = widget.gridColumns.clamp(3, 8);
    final gridTileWidth = (size.width - 96 - 24 * (columns - 1)) / columns;
    final gridApps = widget.apps;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FocusHighlightLayer(
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child:
                    widget.background ??
                    Image(
                      image: widget.wallpaper,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Color(0xff172638)),
                    ),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x08000000),
                        Color(0x05000000),
                        Color(0x99030b16),
                      ],
                      stops: [0, .6, 1],
                    ),
                  ),
                ),
              ),
            ),
            FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: LumaEntrance(
                reducedMotion: widget.reducedMotion,
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 76)),
                    SliverToBoxAdapter(
                      child: SizedBox(height: heroHeight - 76),
                    ),
                    if (widget.loading)
                      const SliverToBoxAdapter(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!widget.loading && widget.apps.isEmpty)
                      SliverToBoxAdapter(
                        child: Center(
                          child: Column(
                            children: [
                              const Text('No apps available'),
                              TextButton(
                                onPressed: widget.onManage,
                                child: const Text('Open app settings'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width:
                                ((size.width - 168) / 6) * favorites.length +
                                112,
                            child: _glass(
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    for (int i = 0; i < favorites.length; i++)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          child: SizedBox(
                                            height:
                                                ((size.width - 168) / 6 - 20) *
                                                    9 /
                                                    16 +
                                                labelExtent,
                                            child: LauncherTile(
                                              key: ValueKey(
                                                'favorite-${favorites[i].id}',
                                              ),
                                              app: favorites[i],
                                              autofocus:
                                                  widget.autofocusApps &&
                                                  i == 0,
                                              focusNode: i == 0
                                                  ? _firstAppFocus
                                                  : i == favorites.length - 1
                                                  ? _lastDockFocus
                                                  : null,
                                              onRight: i == favorites.length - 1
                                                  ? _addDockFocus.requestFocus
                                                  : null,
                                              onDown: gridApps.isEmpty
                                                  ? null
                                                  : _showApps,
                                              onFocused: () {
                                                _trackApp(favorites[i]);
                                                if (_scroll.hasClients &&
                                                    _scroll.offset > 0) {
                                                  _scroll.animateTo(
                                                    0,
                                                    duration:
                                                        motionReduced(
                                                          context,
                                                          widget.reducedMotion,
                                                        )
                                                        ? Duration.zero
                                                        : const Duration(
                                                            milliseconds: 280,
                                                          ),
                                                    curve: lumaEase,
                                                  );
                                                }
                                              },
                                              reduceMotion:
                                                  widget.reducedMotion,
                                              onPressed: () =>
                                                  _launch(favorites[i]),
                                              onLongPress: () =>
                                                  _options(favorites[i]),
                                            ),
                                          ),
                                        ),
                                      ),
                                    SizedBox(
                                      width: 70,
                                      height:
                                          ((size.width - 168) / 6 - 20) *
                                              9 /
                                              16 +
                                          labelExtent,
                                      child: Focus(
                                        onKeyEvent: (_, event) {
                                          if (event is KeyDownEvent &&
                                              event.logicalKey ==
                                                  LogicalKeyboardKey
                                                      .arrowLeft &&
                                              favorites.isNotEmpty) {
                                            (favorites.length == 1
                                                    ? _firstAppFocus
                                                    : _lastDockFocus)
                                                .requestFocus();
                                            return KeyEventResult.handled;
                                          }
                                          if (event is KeyDownEvent &&
                                              event.logicalKey ==
                                                  LogicalKeyboardKey
                                                      .arrowDown) {
                                            _showApps();
                                            return KeyEventResult.handled;
                                          }
                                          return KeyEventResult.ignored;
                                        },
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            HomeControlButton(
                                              autofocus:
                                                  widget.autofocusApps &&
                                                  favorites.isEmpty,
                                              focusNode: _addDockFocus,
                                              tooltip: 'Add dock apps',
                                              onPressed: _chooseDockApps,
                                              icon: const Icon(
                                                Icons.add_rounded,
                                                size: 32,
                                              ),
                                            ),
                                            const Text(
                                              'Add apps',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              radius: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (favorites.isNotEmpty)
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    if (gridApps.isNotEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(48, 14, 48, 2),
                          child: Text(
                            'All apps',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 18,
                      ),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final item = gridApps[index];
                          return LauncherTile(
                            key: ValueKey(item.id),
                            app: item,
                            autofocus: false,
                            focusNode: index == 0 ? _gridFocus : null,
                            onUp: index < columns ? _goHome : null,
                            reduceMotion: widget.reducedMotion,
                            onFocused: () {
                              _trackApp(item);
                              if (favorites.isNotEmpty &&
                                  index < columns &&
                                  _scroll.hasClients) {
                                _scroll.animateTo(
                                  (size.height - 80).clamp(
                                    0,
                                    _scroll.position.maxScrollExtent,
                                  ),
                                  duration: widget.reducedMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 280),
                                  curve: lumaEase,
                                );
                              }
                            },
                            onPressed: () => _launch(item),
                            onLongPress: () => _options(item),
                          );
                        }, childCount: gridApps.length),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: gridTileWidth * 9 / 16 + labelExtent,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                        ),
                      ),
                    ),
                    for (final section in widget.sections)
                      ..._sectionSlivers(section),
                    if (widget.continueWatching != null)
                      SliverToBoxAdapter(child: widget.continueWatching),
                    if (widget.preview)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Browser preview · sample apps · Android features are simulated',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 20,
              left: 30,
              right: 30,
              child: AnimatedBuilder(
                animation: _scroll,
                builder: (_, child) {
                  final opacity =
                      1 -
                      ((_scroll.hasClients ? _scroll.offset : 0) / 60).clamp(
                        0.0,
                        1.0,
                      );
                  return ExcludeFocus(
                    excluding: opacity < .5,
                    child: IgnorePointer(
                      ignoring: opacity < .5,
                      child: Opacity(opacity: opacity, child: child),
                    ),
                  );
                },
                child: Row(
                  children: [
                    _glass(
                      HomeControlButton(
                        focusNode: _searchFocus,
                        tooltip: 'Search apps',
                        onPressed: _search,
                        icon: const Icon(Icons.search),
                      ),
                      radius: 100,
                    ),
                    const SizedBox(width: 10),
                    _glass(
                      HomeControlButton(
                        tooltip: 'Control Centre',
                        onPressed: _controls,
                        icon: const Icon(Icons.settings_outlined),
                      ),
                      radius: 100,
                    ),
                    if (widget.createVoiceSession != null) ...[
                      const SizedBox(width: 10),
                      _glass(
                        HomeControlButton(
                          tooltip: 'Voice search',
                          onPressed: _voice,
                          icon: const Icon(Icons.mic_none_rounded),
                        ),
                        radius: 100,
                      ),
                    ],
                    const Spacer(),
                    _glass(
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: LumaClock(
                          pattern: widget.timeFormat,
                          style: widget.clockStyle,
                          size: widget.clockSize,
                        ),
                      ),
                      radius: 100,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HorizontalAppRow extends StatefulWidget {
  const _HorizontalAppRow({
    super.key,
    required this.section,
    required this.tileWidth,
    required this.height,
    required this.reducedMotion,
    required this.onFocused,
    required this.onLaunch,
    required this.onOptions,
  });
  final LauncherAppSection section;
  final double tileWidth, height;
  final bool reducedMotion;
  final ValueChanged<LauncherAppItem> onFocused, onOptions;
  final Future<void> Function(LauncherAppItem) onLaunch;
  @override
  State<_HorizontalAppRow> createState() => _HorizontalAppRowState();
}

class _HorizontalAppRowState extends State<_HorizontalAppRow> {
  final scroll = LumaScrollController();
  final nodes = <String, FocusNode>{};
  int ticket = 0;
  Future<void> move(int index) async {
    final generation = ++ticket;
    if (!scroll.hasClients) return;
    final target =
        (index * (widget.tileWidth + 24) -
                (scroll.position.viewportDimension - widget.tileWidth) / 2 +
                48)
            .clamp(0.0, scroll.position.maxScrollExtent);
    if (motionReduced(context, widget.reducedMotion)) {
      scroll.jumpTo(target);
    } else {
      await scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: lumaEase,
      );
    }
    if (mounted && generation == ticket)
      nodes[widget.section.apps[index].id]?.requestFocus();
  }

  @override
  void didUpdateWidget(_HorizontalAppRow old) {
    super.didUpdateWidget(old);
    final ids = widget.section.apps.map((app) => app.id).toSet();
    for (final id in nodes.keys.where((id) => !ids.contains(id)).toList()) {
      nodes.remove(id)!.dispose();
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    for (final node in nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    scroll.reducedMotion = motionReduced(context, widget.reducedMotion);
    return SizedBox(
      height: widget.height,
      child: ListView.separated(
        controller: scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 48),
        itemCount: widget.section.apps.length,
        separatorBuilder: (_, _) => const SizedBox(width: 24),
        itemBuilder: (_, index) {
          final app = widget.section.apps[index];
          return SizedBox(
            width: widget.tileWidth,
            child: LauncherTile(
              key: ValueKey('${widget.section.id}-${app.id}'),
              app: app,
              focusNode: nodes.putIfAbsent(app.id, () => FocusNode()),
              reduceMotion: widget.reducedMotion,
              onFocused: () => widget.onFocused(app),
              onPressed: () => widget.onLaunch(app),
              onLongPress: () => widget.onOptions(app),
              onLeft: index > 0 ? () => move(index - 1) : null,
              onRight: index + 1 < widget.section.apps.length
                  ? () => move(index + 1)
                  : null,
            ),
          );
        },
      ),
    );
  }
}

/// Explicit remote focus feedback, independent of Material icon splash defaults.
class HomeControlButton extends StatefulWidget {
  const HomeControlButton({
    super.key,
    this.focusNode,
    this.autofocus = false,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });
  final FocusNode? focusNode;
  final bool autofocus;
  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;
  @override
  State<HomeControlButton> createState() => _HomeControlButtonState();
}

class _HomeControlButtonState extends State<HomeControlButton> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: AnimatedScale(
      scale: focused ? 1.12 : 1,
      duration: motionReduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: lumaEase,
      child: AnimatedContainer(
        duration: motionReduced(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused
              ? Colors.white.withValues(alpha: .30)
              : Colors.transparent,
          border: Border.all(
            color: focused ? Colors.white : Colors.transparent,
            width: 2,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: .28),
                    blurRadius: 16,
                  ),
                ]
              : [],
        ),
        child: Focus(
          canRequestFocus: false,
          onFocusChange: (value) => setState(() => focused = value),
          child: IconButton(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            tooltip: widget.tooltip,
            onPressed: widget.onPressed,
            color: focused ? Colors.white : Colors.white70,
            icon: widget.icon,
          ),
        ),
      ),
    ),
  );
}

class LauncherTile extends StatefulWidget {
  const LauncherTile({
    super.key,
    required this.app,
    required this.onPressed,
    this.onLongPress,
    this.onDown,
    this.onUp,
    this.onLeft,
    this.onRight,
    this.autofocus = false,
    this.reduceMotion = false,
    this.onFocused,
    this.quietFocus = false,
    this.focusNode,
  });
  final LauncherAppItem app;
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress, onDown, onUp, onLeft, onRight;
  final bool autofocus, reduceMotion, quietFocus;
  final VoidCallback? onFocused;
  @override
  State<LauncherTile> createState() => _LauncherTileState();
}

class _LauncherTileState extends State<LauncherTile>
    with SingleTickerProviderStateMixin {
  bool focused = false, pressed = false;
  final _ownedFocusNode = FocusNode();
  final _artworkTarget = GlobalKey();
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;
  late Future<ImageProvider?> _artwork;
  late final AnimationController _hold;
  Timer? _pressTimer;
  LogicalKeyboardKey? _heldKey;
  bool _longPressed = false;
  bool get reduce =>
      widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
  @override
  void initState() {
    super.initState();
    _hold = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _artwork = _load();
  }

  Future<ImageProvider?> _load() =>
      tvIconPackArtwork(widget.app.id, widget.app.name) != null
      ? Future.value(tvIconPackArtwork(widget.app.id, widget.app.name))
      : widget.app.loadArtwork?.call() ??
            widget.app.artwork ??
            Future.value(null);
  @override
  void didUpdateWidget(LauncherTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.app, widget.app)) _artwork = _load();
  }

  @override
  void dispose() {
    _pressTimer?.cancel();
    _hold.dispose();
    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    setState(() => pressed = value);
    if (value && widget.onLongPress != null && !reduce) {
      _hold.forward(from: 0);
    } else {
      _hold.stop();
      _hold.value = 0;
    }
  }

  void _focusChanged(bool value) {
    setState(() {
      focused = value;
      if (!value) pressed = false;
    });
    reportFocusTarget(context, _artworkTarget, value);
    if (!value) {
      _pressTimer?.cancel();
      _heldKey = null;
      _hold.stop();
      _hold.value = 0;
      return;
    }
    widget.onFocused?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      final box = context.findRenderObject();
      if (box is! RenderBox) return;
      final navigator = Navigator.of(context).context.findRenderObject();
      if (navigator is! RenderBox) return;
      // Compare in TV-stage coordinates, including a scaled browser preview.
      final bounds = MatrixUtils.transformRect(
        box.getTransformTo(navigator),
        Offset.zero & box.size,
      );
      final top = bounds.top;
      final height = MediaQuery.sizeOf(context).height;
      if (top < 90 || bounds.bottom > height - 28) {
        Scrollable.ensureVisible(
          context,
          alignment: top < 90 ? .12 : .82,
          curve: lumaEase,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.app.name,
    button: true,
    selected: focused,
    child: Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _focusChanged,
      onKeyEvent: (_, event) {
        final key = event.logicalKey;
        final direction = key == LogicalKeyboardKey.arrowDown
            ? widget.onDown
            : key == LogicalKeyboardKey.arrowUp
            ? widget.onUp
            : key == LogicalKeyboardKey.arrowLeft
            ? widget.onLeft
            : key == LogicalKeyboardKey.arrowRight
            ? widget.onRight
            : null;
        if (direction != null) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) direction();
          return KeyEventResult.handled;
        }
        if ([
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.numpadEnter,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.gameButtonA,
        ].contains(key)) {
          if (event is KeyDownEvent) {
            _heldKey = key;
            _longPressed = false;
            _setPressed(true);
            _pressTimer?.cancel();
            _pressTimer = Timer(const Duration(milliseconds: 600), () {
              if (mounted && _heldKey == key && widget.onLongPress != null)
                _longPressed = true;
            });
          }
          if (event is KeyUpEvent) {
            _pressTimer?.cancel();
            _setPressed(false);
            final activate = _heldKey == key;
            _heldKey = null;
            if (activate) {
              if (_longPressed) {
                widget.onLongPress?.call();
              } else {
                widget.onPressed();
              }
            }
          }
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (key == LogicalKeyboardKey.contextMenu ||
                key == LogicalKeyboardKey.gameButtonY)) {
          widget.onLongPress?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (_) {
          if (!_focusNode.hasFocus) _focusNode.requestFocus();
        },
        child: Column(
          children: [
            AspectRatio(
              key: _artworkTarget,
              aspectRatio: 16 / 9,
              child: AnimatedSlide(
                offset: focused && !pressed
                    ? const Offset(0, -.06)
                    : Offset.zero,
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: lumaEase,
                child: AnimatedScale(
                  key: ValueKey('tile-scale-${widget.app.id}'),
                  scale: pressed ? .98 : 1,
                  curve: lumaEase,
                  duration: reduce
                      ? Duration.zero
                      : Duration(milliseconds: pressed ? 90 : 240),
                  child: AnimatedContainer(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: focused
                          ? [
                              const BoxShadow(
                                color: Color(0x80000000),
                                blurRadius: 12,
                                offset: Offset(0, 5),
                              ),
                            ]
                          : [],
                    ),
                    child: Material(
                      color: const Color(0xff151515),
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        canRequestFocus: false,
                        onTap: () {
                          _focusNode.requestFocus();
                          widget.onPressed();
                        },
                        onTapDown: (_) {
                          _focusNode.requestFocus();
                          _setPressed(true);
                        },
                        onTapCancel: () => _setPressed(false),
                        onTapUp: (_) => _setPressed(false),
                        onLongPress: widget.onLongPress,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AppArtworkBuilder(
                              id: widget.app.id,
                              original: () => installedAppArtwork(widget.app),
                              future: _artwork,
                              builder: (context, snapshot) =>
                                  snapshot.data == null
                                  ? Center(
                                      child: Text(
                                        widget.app.name,
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : LayoutBuilder(
                                      builder: (context, size) => Image(
                                        image: ResizeImage(
                                          snapshot.data!,
                                          width:
                                              (size.maxWidth *
                                                      MediaQuery.devicePixelRatioOf(
                                                        context,
                                                      ) *
                                                      1.06)
                                                  .ceil(),
                                          height:
                                              (size.maxHeight *
                                                      MediaQuery.devicePixelRatioOf(
                                                        context,
                                                      ) *
                                                      1.06)
                                                  .ceil(),
                                          policy: ResizeImagePolicy.fit,
                                        ),
                                        fit: BoxFit.contain,
                                        width: double.infinity,
                                        height: double.infinity,
                                        errorBuilder: (_, _, _) => Center(
                                          child: Text(widget.app.name),
                                        ),
                                      ),
                                    ),
                            ),
                            if (pressed &&
                                !reduce &&
                                widget.onLongPress != null)
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 10,
                                child: AnimatedBuilder(
                                  animation: _hold,
                                  builder: (_, _) => LinearProgressIndicator(
                                    value: _hold.value,
                                    minHeight: 3,
                                    color: Colors.white,
                                    backgroundColor: Colors.black45,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 19),
            Text(
              widget.app.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.3,
                fontWeight: focused ? FontWeight.w600 : FontWeight.w400,
                color: focused ? Colors.white : const Color(0xffd4dbe3),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({
    this.initialQuery = '',
    required this.apps,
    required this.mode,
    required this.onLaunch,
    this.blurBuilder,
    this.reducedMotion = false,
    this.autofocusInput = false,
  });
  final String initialQuery;
  final bool reducedMotion;
  final bool autofocusInput;
  final List<LauncherAppItem> apps;
  final LauncherMaterial mode;
  final Future<void> Function(LauncherAppItem) onLaunch;
  final GlassBlurBuilder? blurBuilder;
  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final query = TextEditingController();
  final queryFocus = FocusNode(debugLabel: 'Search query');
  final resultNodes = <String, FocusNode>{};
  final programmeFocus = FocusNode(debugLabel: 'First search programme');
  FocusNode resultNode(String id) => resultNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'Search result $id'),
  );
  final _scroll = LumaScrollController();
  @override
  void initState() {
    super.initState();
    query.text = widget.initialQuery;
    ProgrammeLibrary.shared.ready();
  }

  @override
  void dispose() {
    queryFocus.dispose();
    programmeFocus.dispose();
    for (final node in resultNodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ProgrammeLibrary.shared,
    builder: (_, __) => _buildSearch(context),
  );

  Widget _buildSearch(BuildContext context) {
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0;
    final programmes = ProgrammeLibrary.shared.search(query.text);
    _scroll.reducedMotion = motionReduced(context, widget.reducedMotion);
    final results = widget.apps
        .where(
          (app) =>
              app.name.toLowerCase().contains(query.text.trim().toLowerCase()),
        )
        .toList();
    return FloatingSearchPanel(
      mode: widget.mode,
      blurBuilder: widget.blurBuilder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Search',
                  style: TextStyle(
                    fontSize: compact ? 24 : 32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close search',
                autofocus: !widget.autofocusInput && results.isEmpty,
                visualDensity: compact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 20),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                if (results.isNotEmpty)
                  resultNode(results.first.id).requestFocus();
                else if (programmes.isNotEmpty)
                  programmeFocus.requestFocus();
                SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
              },
            },
            child: TextField(
              focusNode: queryFocus,
              autofocus: widget.autofocusInput,
              controller: query,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (results.isNotEmpty) {
                  resultNode(results.first.id).requestFocus();
                } else if (programmes.isNotEmpty) {
                  programmeFocus.requestFocus();
                }
                SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
              },
              decoration: InputDecoration(
                isDense: compact,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: compact ? 12 : 18,
                ),
                hintText: 'Search apps, movies and shows',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          query.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.cancel_outlined),
                      ),
                filled: true,
                fillColor: MinimalPalette.of(
                  context,
                ).text.withValues(alpha: .06),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: MinimalPalette.of(
                      context,
                    ).text.withValues(alpha: .65),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: MinimalPalette.of(
                      context,
                    ).text.withValues(alpha: .16),
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 8 : 24),
          SizedBox(height: compact ? 8 : 16),
          Expanded(
            child: ListView(
              controller: _scroll,
              children: [
                if (results.isEmpty && programmes.isEmpty)
                  const Text(
                    'No results. Only programmes shared by supported apps are searchable.',
                  ),
                if (results.isNotEmpty) ...[
                  const Text(
                    'Apps',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) => FocusHighlightLayer(
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisExtent:
                              ((constraints.maxWidth - 60) / 4) * 9 / 16 +
                              _tileLabelExtent(context),
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: results.length,
                        itemBuilder: (context, index) => LauncherTile(
                          key: ValueKey('search-result-${results[index].id}'),
                          focusNode: resultNode(results[index].id),
                          autofocus: !widget.autofocusInput && index == 0,
                          onUp: () => index < 4
                              ? queryFocus.requestFocus()
                              : resultNode(
                                  results[index - 4].id,
                                ).requestFocus(),
                          onDown: () {
                            if (index + 4 < results.length)
                              resultNode(results[index + 4].id).requestFocus();
                            else if (programmes.isNotEmpty)
                              programmeFocus.requestFocus();
                          },
                          onLeft: () {
                            if (index > 0)
                              resultNode(results[index - 1].id).requestFocus();
                          },
                          onRight: () {
                            if (index + 1 < results.length)
                              resultNode(results[index + 1].id).requestFocus();
                          },
                          app: results[index],
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onLaunch(results[index]);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
                if (programmes.isNotEmpty) ...[
                  const Text(
                    'Movies & shows',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ProgrammeRail(
                    itemCount: programmes.length,
                    itemBuilder: (_, index) => LibraryProgrammeCard(
                      focusNode: index == 0 ? programmeFocus : null,
                      key: ValueKey(programmes[index].key),
                      entry: programmes[index],
                    ),
                  ),
                ],
                TextButton.icon(
                  icon: const Icon(Icons.bookmarks_outlined),
                  label: const Text('Watchlist & hidden titles'),
                  onPressed: () => showLumaDialog<void>(
                    context: context,
                    builder: (context) => const LumaMenuDialog(
                      title: Text('Your programmes'),
                      content: SizedBox(
                        width: 510,
                        child: ProgrammeShelf(
                          title: 'Saved and shared programmes',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Edits the persistent favourites used by the dock without dismissing the menu.
class DockAppPicker extends StatefulWidget {
  const DockAppPicker({
    super.key,
    required this.apps,
    required this.favorites,
    required this.onToggle,
    this.onRestore,
    this.onMove,
  });
  final Future<void> Function(LauncherAppItem app, int index)? onRestore;
  final Future<void> Function(LauncherAppItem app, int offset)? onMove;
  final List<LauncherAppItem> apps;
  final Set<String> favorites;
  final Future<void> Function(LauncherAppItem) onToggle;
  @override
  State<DockAppPicker> createState() => _DockAppPickerState();
}

class _DockAppPickerState extends State<DockAppPicker> {
  Set<String> selected = {};
  final search = TextEditingController();
  final searchFocus = FocusNode(debugLabel: 'Search dock apps');
  final choiceNodes = <String, FocusNode>{};
  final doneFocus = FocusNode(debugLabel: 'Dock apps Done');
  FocusNode choiceNode(String id) => choiceNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'Dock choice $id'),
  );
  void enterResults(List<LauncherAppItem> results) {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    (results.isEmpty ? doneFocus : choiceNode(results.first.id)).requestFocus();
  }

  final scroll = LumaScrollController();
  bool busy = false, started = false;
  String? message;
  String query = '';
  MenuUndo? undo;
  @override
  void initState() {
    super.initState();
    selected = {...widget.favorites};
    WidgetsBinding.instance.addPostFrameCallback((_) => started = true);
  }

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    doneFocus.dispose();
    for (final node in choiceNodes.values) {
      node.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  void filter(String value) {
    setState(() => query = value.trim().toLowerCase());
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> toggle(LauncherAppItem app) async {
    if (busy) return;
    final removing = selected.contains(app.id);
    final before = selected.toList();
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.onToggle(app);
      if (!mounted) return;
      setState(() {
        if (removing) {
          selected.remove(app.id);
        } else {
          selected.add(app.id);
        }
        undo = removing
            ? MenuUndo('Removed ${app.name} from dock', () async {
                if (busy) throw StateError('An edit is still saving');
                busy = true;
                try {
                  if (widget.onRestore != null) {
                    await widget.onRestore!(app, before.indexOf(app.id));
                  } else {
                    await widget.onToggle(app);
                  }
                  if (mounted) setState(() => selected = {...before});
                } finally {
                  busy = false;
                }
              })
            : null;
      });
    } catch (_) {
      if (mounted)
        setState(() => message = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    scroll.reducedMotion = motionReduced(context);
    final results = widget.apps
        .where((app) => app.name.toLowerCase().contains(query))
        .toList();
    return LumaMenuDialog(
      title: Text('Dock apps · ${selected.length}'),
      content: SizedBox(
        width: 480,
        height: (MediaQuery.sizeOf(context).height - 270).clamp(160.0, 340.0),
        child: FocusHighlightLayer(
          menu: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      enterResults(results),
                },
                child: TextField(
                  controller: search,
                  focusNode: searchFocus,
                  textInputAction: TextInputAction.search,
                  onChanged: filter,
                  onEditingComplete: () {},
                  onSubmitted: (_) => enterResults(results),
                  decoration: InputDecoration(
                    labelText: 'Search apps',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear app search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              search.clear();
                              filter('');
                              searchFocus.requestFocus();
                            },
                          ),
                  ),
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    message!,
                    semanticsLabel: message,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ScrollEdgeFade(
                  backdropFade: false,
                  child: results.isEmpty
                      ? const Center(child: Text('No apps match your search.'))
                      : ListView(
                          controller: scroll,
                          children: [
                            for (final app in results)
                              Focus(
                                canRequestFocus: false,
                                onKeyEvent: (_, event) {
                                  final up =
                                      event.logicalKey ==
                                      LogicalKeyboardKey.arrowUp;
                                  final down =
                                      event.logicalKey ==
                                      LogicalKeyboardKey.arrowDown;
                                  if (!up && !down)
                                    return KeyEventResult.ignored;
                                  if (event is KeyDownEvent ||
                                      event is KeyRepeatEvent) {
                                    final next =
                                        results.indexOf(app) + (down ? 1 : -1);
                                    (next < 0
                                            ? searchFocus
                                            : next >= results.length
                                            ? doneFocus
                                            : choiceNode(results[next].id))
                                        .requestFocus();
                                  }
                                  return KeyEventResult.handled;
                                },
                                child: TvMenuRow(
                                  focusNode: choiceNode(app.id),
                                  key: ValueKey('dock-choice-${app.id}'),
                                  autofocus:
                                      !started && app == widget.apps.first,
                                  title: app.name,
                                  selected: selected.contains(app.id),
                                  subtitle: selected.contains(app.id)
                                      ? 'In dock'
                                      : 'Add to dock',
                                  onPressed: () => toggle(app),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (undo != null)
          SizedBox(
            width: 360,
            child: MenuUndoNotice(
              undo: undo!,
              onRestored: () => setState(() => undo = null),
            ),
          ),
        TextButton(
          focusNode: doneFocus,
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
