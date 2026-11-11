import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'focus_feedback.dart';
import 'glass_surface.dart';
import 'motion.dart';
import 'menu_dialog.dart';
import 'clock_settings.dart';
import 'programme_browser.dart';
import 'solid_theme.dart';
import 'scroll_edge_fade.dart';
import 'privacy_text.dart';
import 'tv_cleaner.dart';
import 'standby.dart';

class QuickSettingsContent extends StatefulWidget {
  const QuickSettingsContent({
    super.key,
    required this.mode,
    required this.reducedMotion,
    required this.onMaterialChanged,
    this.onReducedMotionChanged,
    required this.onWifi,
    required this.onSettings,
    this.onWallpaper,
    required this.onDeviceSettings,
    this.loadConnectionStatus,
    this.onBluetoothStatusPermission,
    this.timeFormat = 'h:mm a',
    this.clockStyle = 'digital',
    this.clockSize = 'medium',
    this.onClockStyleChanged,
    this.onClockSizeChanged,
    this.onTimeFormatChanged,
    this.networkStatus = 'Checking connection…',
    this.bluetoothStatus = 'Open accessory settings',
    this.defaultHomeStatus,
    this.onLayout,
    this.onBackup,
    this.fullSettings = false,
    this.preview = false,
    this.onSolidColorChanged,
    this.minimalBackground = 'charcoal',
    this.onMinimalBackgroundChanged,
    this.onManage,
    this.onProfiles,
    this.profileName,
    this.onRemoteShortcuts,
    this.onFontStyle,
    this.performanceMode = true,
    this.onPerformanceChanged,
    this.liteMode = 'auto',
    this.liteModeActive = false,
    this.onLiteModeChanged,
    this.depthClock = true,
    this.onDepthClockChanged,
    this.keepScreenOn = true,
    this.onKeepScreenOnChanged,
    this.selectedMinimalBackground,
    this.showWatchNext = false,
    this.onWatchNextChanged,
    this.onHomeSettings,
    this.onSearch,
    this.onPlayNext,
    this.showFromApps = true,
    this.onFromAppsChanged,
    this.soundSettings,
    this.aboutSettings,
    this.initialCategory,
  });
  final Future<Map<String, dynamic>> Function()? loadConnectionStatus;
  final Future<void> Function()? onBluetoothStatusPermission;
  final String timeFormat, networkStatus, bluetoothStatus;
  final String clockStyle, clockSize;
  final ValueChanged<String>? onClockStyleChanged, onClockSizeChanged;
  final String? defaultHomeStatus;
  final VoidCallback? onLayout, onBackup;
  final ValueChanged<String>? onTimeFormatChanged;
  final bool fullSettings, preview, performanceMode, showWatchNext;
  final VoidCallback? onWallpaper,
      onManage,
      onHomeSettings,
      onRemoteShortcuts,
      onFontStyle;
  final VoidCallback? onSearch, onPlayNext;
  final Widget? soundSettings, aboutSettings;
  final String? initialCategory;
  final bool showFromApps;
  final ValueChanged<bool>? onFromAppsChanged;
  final String minimalBackground;
  final ValueChanged<String>? onMinimalBackgroundChanged;
  final ValueChanged<String>? onSolidColorChanged;
  final ValueChanged<bool>? onPerformanceChanged, onWatchNextChanged;
  final String liteMode;
  final bool liteModeActive;
  final ValueChanged<String>? onLiteModeChanged;
  final bool depthClock;
  final ValueChanged<bool>? onDepthClockChanged;
  final bool keepScreenOn;
  final ValueChanged<bool>? onKeepScreenOnChanged;
  final VoidCallback? onProfiles;
  final String? profileName;
  final String? selectedMinimalBackground;
  final LauncherMaterial mode;
  final bool reducedMotion;
  final ValueChanged<LauncherMaterial> onMaterialChanged;
  final ValueChanged<bool>? onReducedMotionChanged;
  final VoidCallback onWifi, onSettings;
  final ValueChanged<String> onDeviceSettings;
  @override
  State<QuickSettingsContent> createState() => _QuickSettingsContentState();
}

class _QuickSettingsContentState extends State<QuickSettingsContent>
    with WidgetsBindingObserver {
  Map<String, dynamic> status = {};
  Timer? statusTimer;
  bool fetching = false;

  /// Full settings use two columns: sections on the left, the focused
  /// section's options on the right. Moving through sections previews them;
  /// Right / OK steps into the options, Left / Back steps out again.
  /// Needs room: narrow hosts keep the single drill-down column.
  bool get _twoColumn => widget.fullSettings && _wide;
  bool _wide = true;
  bool _rightActive = false;
  final _rightScope = FocusScopeNode(debugLabel: 'Settings options');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_twoColumn) {
      _rightActive = widget.initialCategory != null;
      category ??= groups.first.$1;
    }
    if (widget.loadConnectionStatus != null) {
      refreshStatus();
      statusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            (ModalRoute.isCurrentOf(context) ?? true) &&
            category == 'Device')
          refreshStatus();
      });
    }
  }

  Future<void> refreshStatus() async {
    if (fetching || widget.loadConnectionStatus == null) return;
    fetching = true;
    try {
      final value = await widget.loadConnectionStatus!();
      if (mounted) setState(() => status = value);
    } catch (_) {
      if (mounted)
        setState(
          () => status = {
            'network': 'Connection status unavailable',
            'bluetooth': 'Accessory status unavailable',
          },
        );
    } finally {
      fetching = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshStatus();
  }

  final _scroll = LumaScrollController();
  @override
  void dispose() {
    statusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _rightScope.dispose();
    for (final node in categoryFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  String _backgroundLabel(String value) => switch (value) {
    'glass' || 'glass-real' => 'Liquid Glass',
    _ => 'Minimal',
  };
  String get _selectedBackground =>
      widget.selectedMinimalBackground ?? widget.minimalBackground;

  void _chooseMinimalBackground() {
    var selected = _selectedBackground;
    showLumaDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => LumaMenuDialog(
          title: const Text('Theme'),
          content: FocusHighlightLayer(
            menu: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in ['glass', 'charcoal'])
                  TvMenuRow(
                    key: ValueKey('minimal-background-$value'),
                    title: _backgroundLabel(value),
                    autofocus:
                        value ==
                        (_selectedBackground == 'wallpaper'
                            ? 'charcoal'
                            : _selectedBackground),
                    selected:
                        value == selected ||
                        (value == 'charcoal' && selected == 'wallpaper'),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final actual =
                          value == 'charcoal' &&
                              prefs.getString('minimal_last_background') ==
                                  'wallpaper'
                          ? 'wallpaper'
                          : value;
                      widget.onMinimalBackgroundChanged!(actual);
                      if (context.mounted) update(() => selected = actual);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  String _liteModeLabel() => switch (widget.liteMode) {
    'on' => 'On · smoother on this TV',
    'off' => 'Off · full glass effects',
    _ =>
      widget.liteModeActive
          ? 'Automatic · on for this TV'
          : 'Automatic · off for this TV',
  };

  void _chooseLiteMode() {
    var selected = widget.liteMode;
    showLumaDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => LumaMenuDialog(
          title: const Text('Lite mode'),
          content: FocusHighlightLayer(
            menu: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (value, title, subtitle) in const [
                  (
                    'auto',
                    'Automatic',
                    'On for TVs with 2.5 GB of memory or less',
                  ),
                  ('on', 'On', 'Plain wallpaper with matte controls'),
                  ('off', 'Off', 'Always use the glass theme you chose'),
                ])
                  TvMenuRow(
                    key: ValueKey('lite-mode-$value'),
                    title: title,
                    subtitle: subtitle,
                    autofocus: value == selected,
                    selected: value == selected,
                    onPressed: () {
                      widget.onLiteModeChanged!(value);
                      update(() => selected = value);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  void _chooseMinimalBackdrop() {
    var selected = widget.minimalBackground;
    showLumaDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, update) => LumaMenuDialog(
          title: const Text('Minimal background'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvMenuRow(
                key: const ValueKey('minimal-use-colour'),
                autofocus: selected != 'wallpaper',
                title: 'Background colour',
                subtitle: 'Matte colour without a wallpaper',
                selected: selected != 'wallpaper',
                onPressed: () {
                  widget.onMinimalBackgroundChanged?.call('charcoal');
                  update(() => selected = 'charcoal');
                  if (widget.onSolidColorChanged != null)
                    showSolidThemeColors(
                      dialogContext,
                      onChanged: widget.onSolidColorChanged!,
                    );
                },
              ),
              TvMenuRow(
                key: const ValueKey('minimal-use-wallpaper'),
                title: 'Use wallpaper',
                subtitle: 'Use your selected wallpaper with matte controls',
                selected: selected == 'wallpaper',
                onPressed: () {
                  widget.onMinimalBackgroundChanged?.call('wallpaper');
                  update(() => selected = 'wallpaper');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget toggle(
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
    IconData? icon,
  }) => TvMenuRow(
    key: ValueKey('toggle-$title'),
    title: title,
    subtitle: subtitle,
    icon: icon,
    selected: value,
    trailing: Icon(value ? Icons.toggle_on : Icons.toggle_off),
    onPressed: () => onChanged(!value),
  );

  late String? category = widget.initialCategory;
  final categoryFocus = <String, FocusNode>{};
  static const groups = <(String, IconData, String)>[
    ('Appearance', Icons.palette_rounded, 'Theme, wallpaper and clock'),
    (
      'Home & Apps',
      Icons.apps_rounded,
      'Favourites, layout and programme sources',
    ),
    (
      'Sound & Motion',
      Icons.volume_up_rounded,
      'Navigation sounds and animations',
    ),
    ('Device', Icons.tv_rounded, 'Wi-Fi, Bluetooth and TV settings'),
    ('About', Icons.info_rounded, 'Help, information and backups'),
  ];
  FocusNode _categoryNode(String name) => categoryFocus.putIfAbsent(name, () {
    final node = FocusNode(debugLabel: 'Settings $name');
    node.addListener(() {
      // Two columns: focusing a section shows its options straight away.
      if (!_twoColumn || !node.hasFocus || !mounted) return;
      if (category == name && !_rightActive) return;
      setState(() {
        category = name;
        _rightActive = false;
      });
      if (name == 'Device') unawaited(refreshStatus());
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    return node;
  });

  void _enterOptions() {
    if (_rightActive) return;
    setState(() => _rightActive = true);
    // Rows normally autofocus; fall back to the first one if none does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_rightActive || _rightScope.hasFocus) return;
      _rightScope.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  void _leaveOptions() {
    setState(() => _rightActive = false);
    categoryFocus[category]?.requestFocus();
  }

  void selectCategory(String value) {
    if (_twoColumn) {
      if (category != value) setState(() => category = value);
      if (value == 'Device') unawaited(refreshStatus());
      _enterOptions();
      return;
    }
    setState(() => category = value);
    if (value == 'Device') unawaited(refreshStatus());
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void back() {
    if (_twoColumn) {
      _leaveOptions();
      return;
    }
    final previous = category;
    setState(() => category = null);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (category == null)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) categoryFocus[previous]?.requestFocus();
      });
  }

  List<Widget> rows(BuildContext context) => switch (category) {
    'Appearance' => [
      if (widget.onMinimalBackgroundChanged != null)
        TvMenuRow(
          key: const ValueKey('minimal-background'),
          autofocus: true,
          title: 'Theme',
          subtitle:
              widget.liteModeActive &&
                  ['glass', 'glass-real'].contains(_selectedBackground)
              ? '${_backgroundLabel(_selectedBackground)} · paused by Lite mode'
              : _backgroundLabel(_selectedBackground),
          icon: Icons.contrast_rounded,
          onPressed: _chooseMinimalBackground,
        ),
      if (widget.onLiteModeChanged != null)
        TvMenuRow(
          key: const ValueKey('setting-lite-mode'),
          title: 'Lite mode',
          subtitle: _liteModeLabel(),
          icon: Icons.speed_rounded,
          onPressed: _chooseLiteMode,
        ),
      if (widget.onWallpaper != null)
        TvMenuRow(
          key: const ValueKey('setting-scenery-wallpapers'),
          title: 'Wallpapers',
          icon: Icons.landscape_rounded,
          onPressed: widget.onWallpaper!,
        ),
      TvMenuRow(
        key: const ValueKey('setting-standby'),
        title: 'StandBy',
        subtitle: 'A full-screen clock when the TV is left idle',
        icon: Icons.nightlight_round,
        onPressed: () => showStandbySettings(context),
      ),
      if (widget.onDepthClockChanged != null)
        toggle(
          'Depth clock',
          widget.depthClock,
          widget.onDepthClockChanged!,
          subtitle: widget.liteModeActive
              ? 'Paused by Lite mode'
              : 'A large clock behind the scenery on Depth wallpapers',
          icon: Icons.layers_rounded,
        ),
      if (!['glass', 'glass-real'].contains(_selectedBackground) &&
          widget.onMinimalBackgroundChanged != null)
        TvMenuRow(
          key: const ValueKey('minimal-backdrop'),
          title: 'Background style',
          subtitle: widget.minimalBackground == 'wallpaper'
              ? 'Wallpaper'
              : 'Colour',
          icon: Icons.palette_rounded,
          onPressed: _chooseMinimalBackdrop,
        ),
      if (widget.onClockStyleChanged != null ||
          widget.onClockSizeChanged != null ||
          widget.onTimeFormatChanged != null)
        TvMenuRow(
          key: const ValueKey('setting-clock-section'),
          title: 'Clock',
          subtitle: 'Style, format and size',
          icon: Icons.schedule_rounded,
          onPressed: () => showLumaDialog<void>(
            context: context,
            barrierDismissible: false,
            reducedMotion: widget.reducedMotion,
            builder: (context) => LumaMenuDialog(
              title: const Text('Clock'),
              content: ClockSettings(
                style: widget.clockStyle,
                size: widget.clockSize,
                pattern: widget.timeFormat,
                onStyleChanged: widget.onClockStyleChanged,
                onSizeChanged: widget.onClockSizeChanged,
                onFormatChanged: widget.onTimeFormatChanged,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      if (widget.onFontStyle != null)
        TvMenuRow(
          key: const ValueKey('setting-font-style'),
          title: 'Font style',
          icon: Icons.text_fields_rounded,
          onPressed: widget.onFontStyle!,
        ),
    ],
    'Home & Apps' => [
      if (widget.onManage != null)
        TvMenuRow(
          key: const ValueKey('setting-manage-apps'),
          autofocus: true,
          title: 'Apps & Favourites',
          subtitle: 'Choose favourites and hidden apps',
          icon: Icons.apps_rounded,
          onPressed: widget.onManage!,
        ),
      if (widget.onLayout != null)
        TvMenuRow(
          key: const ValueKey('setting-categories-and-layout'),
          title: 'Home layout',
          subtitle: 'Card size and remembered selection',
          icon: Icons.view_module_rounded,
          onPressed: widget.onLayout!,
        ),
      if (widget.onProfiles != null)
        TvMenuRow(
          key: const ValueKey('setting-profiles'),
          title: 'Profiles',
          subtitle: widget.profileName == null
              ? 'Own favourites and look for each person'
              : 'Watching now: ${widget.profileName}',
          icon: Icons.people_alt_rounded,
          onPressed: widget.onProfiles!,
        ),
      if (widget.onFromAppsChanged != null)
        toggle(
          'From your apps',
          widget.showFromApps,
          widget.onFromAppsChanged!,
          subtitle: 'Show programme cards on Home',
          icon: Icons.live_tv_rounded,
        ),
      TvMenuRow(
        key: const ValueKey('setting-programme-sources'),
        title: 'Programme sources',
        subtitle: 'Choose which streaming apps share titles',
        icon: Icons.play_circle_rounded,
        onPressed: () => showProgrammeSources(context),
      ),
      if (widget.onRemoteShortcuts != null)
        TvMenuRow(
          key: const ValueKey('setting-remote-shortcuts'),
          title: 'Remote shortcuts',
          icon: Icons.settings_remote_rounded,
          onPressed: widget.onRemoteShortcuts!,
        ),
    ],
    'Sound & Motion' => [
      if (widget.soundSettings != null) widget.soundSettings!,
      if (widget.onReducedMotionChanged != null)
        TvMenuRow(
          key: const ValueKey('toggle-Reduce motion'),
          autofocus: widget.soundSettings == null,
          title: 'Reduce motion',
          subtitle: 'Keep focus changes still',
          selected: widget.reducedMotion,
          icon: Icons.animation_rounded,
          trailing: Icon(
            widget.reducedMotion ? Icons.toggle_on : Icons.toggle_off,
          ),
          onPressed: () =>
              widget.onReducedMotionChanged!(!widget.reducedMotion),
        ),
    ],
    'Device' => [
      TvMenuRow(
        key: const ValueKey('setting-network'),
        autofocus: true,
        title: 'Wi-Fi',
        subtitle: status['network'] as String? ?? widget.networkStatus,
        icon: Icons.wifi_rounded,
        onPressed: widget.onWifi,
      ),
      TvMenuRow(
        key: const ValueKey('setting-bluetooth-and-remotes'),
        title: 'Bluetooth & remotes',
        subtitle: status['bluetooth'] as String? ?? widget.bluetoothStatus,
        icon: Icons.bluetooth_rounded,
        onPressed: () => widget.onDeviceSettings('bluetooth'),
      ),
      if (widget.onHomeSettings != null)
        TvMenuRow(
          key: const ValueKey('setting-default-home-settings'),
          title: 'Default launcher',
          subtitle: status['defaultHome'] == true
              ? 'Luma is the default Home'
              : widget.defaultHomeStatus,
          icon: Icons.home_rounded,
          onPressed: widget.onHomeSettings!,
        ),
      if (!widget.preview)
        TvMenuRow(
          key: const ValueKey('setting-android-tv-settings'),
          title: 'Android TV settings',
          icon: Icons.settings_rounded,
          onPressed: () => widget.onDeviceSettings('all'),
        ),
      if (widget.onKeepScreenOnChanged != null)
        toggle(
          'Keep TV on at Home',
          widget.keepScreenOn,
          widget.onKeepScreenOnChanged!,
          subtitle: 'Stops the screen turning off while Luma is showing',
          icon: Icons.tv_rounded,
        ),
      TvMenuRow(
        key: const ValueKey('setting-clean-tv'),
        title: 'Clean my TV',
        subtitle: 'Switch off ads, tracking and preloaded extras',
        icon: Icons.cleaning_services_rounded,
        onPressed: () => showTvCleaner(context),
      ),
      if (widget.minimalBackground == 'glass-real' &&
          widget.onPerformanceChanged != null)
        toggle(
          'Lower GPU usage',
          widget.performanceMode,
          widget.onPerformanceChanged!,
          subtitle: 'Optimise wallpaper rendering',
        ),
      if (status['bluetoothPermission'] == false &&
          status['bluetoothSupported'] != false &&
          widget.onBluetoothStatusPermission != null)
        TvMenuRow(
          key: const ValueKey('bluetooth-permission'),
          title: 'Allow accessory status',
          subtitle: 'Optional Bluetooth status permission',
          icon: Icons.bluetooth_rounded,
          onPressed: () async {
            await widget.onBluetoothStatusPermission!();
            await refreshStatus();
          },
        ),
    ],
    'About' => [
      if (widget.aboutSettings != null)
        widget.aboutSettings!
      else
        TvMenuRow(
          autofocus: true,
          title: 'About Luma',
          icon: Icons.info_rounded,
          onPressed: widget.onSettings,
        ),
      TvMenuRow(
        key: const ValueKey('setting-privacy'),
        title: 'Privacy',
        subtitle: 'What Luma stores and when it goes online',
        icon: Icons.privacy_tip_rounded,
        onPressed: () => showLumaDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => LumaMenuDialog(
            title: const Text('Privacy'),
            content: const SelectableText(
              lumaPrivacyText,
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
      if (widget.onBackup != null)
        TvMenuRow(
          key: const ValueKey('setting-backup-and-restore'),
          autofocus: true,
          title: 'Backup & restore',
          icon: Icons.backup_rounded,
          onPressed: widget.onBackup!,
        ),
    ],
    _ => [
      for (final group in groups)
        TvMenuRow(
          key: ValueKey('settings-category-${group.$1}'),
          focusNode: _categoryNode(group.$1),
          autofocus: group == groups.first,
          title: group.$1,
          icon: group.$2,
          subtitle: group.$3,
          onPressed: () => selectCategory(group.$1),
        ),
    ],
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = !constraints.hasBoundedWidth || constraints.maxWidth >= 600;
      if (wide != _wide) {
        _wide = wide;
        if (wide) {
          category ??= groups.first.$1;
        } else if (widget.initialCategory == null && !_rightActive) {
          category = null;
        }
      }
      return _content(context);
    },
  );

  Widget _content(BuildContext context) {
    _scroll.reducedMotion = motionReduced(context, widget.reducedMotion);
    void remoteBack() {
      if (_twoColumn ? _rightActive : category != null) {
        back();
      } else {
        Navigator.of(context).maybePop();
      }
    }

    if (_twoColumn) {
      final palette = MinimalPalette.of(context);
      final group = groups.firstWhere((g) => g.$1 == category);
      // Back is handled only at route level: a key shortcut here would also
      // fire when Back closes a dialog opened from this page, throwing the
      // remote out of the options column at the same time.
      return Builder(
        builder: (context) => PopScope(
          canPop: !_rightActive,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _rightActive) _leaveOptions();
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 290,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(30, 30, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.profileName == null
                                ? 'Luma'
                                : 'Luma · ${widget.profileName}',
                            style: TextStyle(
                              fontSize: 13,
                              color: MinimalPalette.of(context).muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(
                              LogicalKeyboardKey.arrowRight,
                            ): _enterOptions,
                          },
                          child: FocusHighlightLayer(
                            menu: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final g in groups)
                                  TvMenuRow(
                                    key: ValueKey('settings-category-${g.$1}'),
                                    focusNode: _categoryNode(g.$1),
                                    autofocus:
                                        !_rightActive && g.$1 == category,
                                    selected: g.$1 == category,
                                    title: g.$1,
                                    icon: g.$2,
                                    trailing: const SizedBox.shrink(),
                                    onPressed: () => selectCategory(g.$1),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 24,
                endIndent: 24,
                color: palette.text.withValues(alpha: .10),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(36, 30, 28, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.$1,
                            key: const ValueKey('settings-section-title'),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            group.$3,
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ExcludeFocus(
                        excluding: !_rightActive,
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.arrowLeft):
                                _leaveOptions,
                          },
                          // A fresh subtree on entry lets the first row's
                          // autofocus take focus.
                          child: KeyedSubtree(
                            key: ValueKey('$category-$_rightActive'),
                            child: Scrollbar(
                              controller: _scroll,
                              child: ScrollEdgeFade(
                                backdropFade: false,
                                child: SingleChildScrollView(
                                  controller: _scroll,
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    0,
                                    22,
                                    20,
                                  ),
                                  child: FocusScope(
                                    key: ValueKey('settings-section-$category'),
                                    node: _rightScope,
                                    child: FocusHighlightLayer(
                                      menu: true,
                                      child: _SettingsGroup(
                                        children: rows(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): remoteBack,
        const SingleActivator(LogicalKeyboardKey.goBack): remoteBack,
        const SingleActivator(LogicalKeyboardKey.gameButtonB): remoteBack,
      },
      child: PopScope(
        canPop: category == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && category != null) back();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  if (category != null)
                    IconButton(
                      tooltip: 'Back to settings',
                      onPressed: back,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        category ?? 'Luma Settings',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close Luma Settings',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: ScrollEdgeFade(
                  backdropFade: false,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: FocusScope(
                      key: ValueKey('settings-section-$category'),
                      child: FocusHighlightLayer(
                        menu: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: rows(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Options in one rounded glass card with hairline dividers, like a grouped
/// list. Only static shapes: nothing here is blurred or animated, so moving
/// through the options costs no more than before.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final line = MinimalPalette.of(context).text.withValues(alpha: .08);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x17ffffff), Color(0x0affffff)],
        ),
        border: Border.all(color: const Color(0x24ffffff), width: .8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 72, right: 14),
                  child: Divider(height: 1, thickness: .6, color: line),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
