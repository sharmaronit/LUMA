import 'dart:async';
import 'package:flutter/material.dart';
import 'liquid_glass_v2.dart';
import 'glass_surface.dart';
import 'motion.dart';
import 'tv_controls.dart';
import 'profiles.dart';

/// Quick settings in the style of Apple's Control Center: a dark translucent
/// material, a connectivity platter of round toggles that light up when on,
/// rounded modules, and a focus "lift" (white fill + scale) for the remote.
class ReferenceControlCenter extends StatefulWidget {
  const ReferenceControlCenter({
    super.key,
    required this.onWifi,
    required this.onDeviceSettings,
    required this.onSettings,
    required this.onApps,
    required this.onSearch,
    this.onWallpaper,
    this.loadStatus,
    this.blurBuilder,
    this.timeFormat,
    this.tvControls,
    this.onRecents,
    this.onStandby,
    this.onNotifications,
    this.notificationCount = 0,
    this.profiles = const [],
    this.activeProfile,
    this.onProfileSelected,
  });

  /// Who is watching. The tile shows when there is more than one person and
  /// opens a drop-down list of everyone.
  final VoidCallback? onRecents;

  /// Starts StandBy now.
  final VoidCallback? onStandby;

  /// Opens the notification card; the home bell only shows when there is
  /// something new, so this is always the way in.
  final VoidCallback? onNotifications;
  final int notificationCount;
  final List<Profile> profiles;
  final Profile? activeProfile;
  final ValueChanged<Profile>? onProfileSelected;

  /// Sleep timer and input switching; the modules hide without it.
  final TvControls? tvControls;
  final VoidCallback onWifi, onSettings, onApps, onSearch;

  /// The home clock's intl pattern (e.g. 'HH:mm'), so both clocks agree.
  final String? timeFormat;
  final VoidCallback? onWallpaper;
  final ValueChanged<String> onDeviceSettings;
  final Future<Map<String, dynamic>> Function()? loadStatus;
  final GlassBlurBuilder? blurBuilder;

  @override
  State<ReferenceControlCenter> createState() => _ReferenceControlCenterState();
}

/// Monochrome: "on" toggles are a brighter frosted grey; focus is solid white.
const _activeFill = Color(0x66ffffff);
const _ink = Color(0xff111316);

class _ReferenceControlCenterState extends State<ReferenceControlCenter>
    with WidgetsBindingObserver {
  Map<String, dynamic> status = {};
  bool refreshing = false;
  Timer? _clock;
  List<TvInput> inputs = const [];
  DateTime? sleepEnd;

  Future<void> _loadTv() async {
    final tv = widget.tvControls;
    if (tv == null) return;
    try {
      final results = await Future.wait([tv.inputs(), tv.sleepEnd()]);
      if (!mounted) return;
      setState(() {
        inputs = results[0] as List<TvInput>;
        sleepEnd = results[1] as DateTime?;
      });
    } catch (_) {
      // Older TVs without these services simply show the sleep timer as off.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    unawaited(_loadTv());
    // Keep the header clock current while the panel is open.
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> refresh() async {
    if (refreshing || widget.loadStatus == null) return;
    refreshing = true;
    try {
      final result = await widget.loadStatus!();
      if (mounted) setState(() => status = result);
    } catch (_) {
      if (mounted)
        setState(
          () => status = {
            'network': 'Open network settings',
            'bluetooth': 'Open accessories',
          },
        );
    } finally {
      refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final network = status['network']?.toString() ?? '';
    final bluetooth = status['bluetooth']?.toString() ?? '';
    final online = network.contains('Internet available');
    final ethernet = network.startsWith('Ethernet');
    final offline = network.startsWith('Disconnected');
    final networkCaption = online
        ? 'Connected'
        : offline
        ? 'Offline'
        : network.contains('No validated')
        ? 'No Internet'
        : 'Wi-Fi';
    final bluetoothOn = bluetooth.startsWith('On');
    final paired = RegExp(r'(\d+) paired').firstMatch(bluetooth)?.group(1);
    final bluetoothCaption = bluetoothOn
        ? (paired == null ? 'On' : '$paired paired')
        : bluetooth == 'Bluetooth off'
        ? 'Off'
        : 'Bluetooth';

    return Semantics(
      key: const ValueKey('reference-control-center'),
      label: 'Quick settings',
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      child: LiquidGlassV2(
        blurBuilder: widget.blurBuilder,
        radius: 26,
        band: WallpaperBand.top,
        // Control Center always reads as a dark material, whatever the
        // wallpaper; bright wallpapers deepen it further.
        minScrim: .55,
        contrastTarget: .30,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // One row of round toggles.
              _Platter(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                child: Row(
                  children: [
                    _RoundToggle(
                      label: 'Wi-Fi',
                      caption: networkCaption,
                      icon: offline
                          ? Icons.wifi_off_rounded
                          : ethernet
                          ? Icons.settings_ethernet_rounded
                          : Icons.wifi_rounded,
                      active: online,
                      autofocus: true,
                      onPressed: widget.onWifi,
                    ),
                    _RoundToggle(
                      label: 'Bluetooth',
                      caption: bluetoothCaption,
                      icon: bluetoothOn
                          ? Icons.bluetooth_rounded
                          : Icons.bluetooth_disabled_rounded,
                      active: bluetoothOn,
                      onPressed: () => widget.onDeviceSettings('bluetooth'),
                    ),
                    _RoundToggle(
                      label: 'Sound',
                      caption: 'Sound',
                      icon: Icons.volume_up_rounded,
                      onPressed: () => widget.onDeviceSettings('sound'),
                    ),
                  ],
                ),
              ),
              // Slim tiles, two to a row.
              ..._tileRows([
                if (widget.tvControls != null && inputs.isNotEmpty)
                  _wideModule(
                    label: 'Input',
                    caption: inputs.length == 1
                        ? inputs.first.label
                        : '${inputs.length} sources',
                    icon: Icons.settings_input_hdmi_rounded,
                    onPressed: () =>
                        showInputPicker(context, widget.tvControls!, inputs),
                  ),
                if (widget.tvControls != null)
                  _wideModule(
                    label: 'Sleep timer',
                    caption: sleepLabel(sleepEnd),
                    icon: Icons.bedtime_rounded,
                    onPressed: () async {
                      final end = await showSleepTimerPicker(
                        context,
                        widget.tvControls!,
                        sleepEnd,
                      );
                      if (mounted) setState(() => sleepEnd = end);
                    },
                  ),
                if (widget.onWallpaper != null)
                  _wideModule(
                    label: 'Wallpapers',
                    caption: 'Browse and apply',
                    icon: Icons.wallpaper_rounded,
                    onPressed: widget.onWallpaper!,
                  ),
                if (widget.onStandby != null)
                  _wideModule(
                    label: 'StandBy',
                    caption: 'Show the clock',
                    icon: Icons.nightlight_round,
                    onPressed: widget.onStandby!,
                  ),
                if (widget.profiles.length > 1 &&
                    widget.activeProfile != null &&
                    widget.onProfileSelected != null)
                  Builder(
                    builder: (tileContext) => _wideModule(
                      label: 'Profile',
                      caption: widget.activeProfile!.name,
                      icon: Icons.person_rounded,
                      trailing: Icons.expand_more_rounded,
                      onPressed: () => _chooseProfile(tileContext),
                    ),
                  ),
              ]),
              ..._tileRows([
                _wideModule(
                  label: 'Luma settings',
                  caption: 'Look and profiles',
                  icon: Icons.settings_rounded,
                  onPressed: widget.onSettings,
                ),
                _wideModule(
                  label: 'TV settings',
                  caption: 'Wi-Fi and display',
                  icon: Icons.tv_rounded,
                  onPressed: () => widget.onDeviceSettings('all'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// Drop-down list of people, opened under the "Who's watching" tile.
  /// Focus starts on the person watching now; Down and Up move through the
  /// list, OK chooses and Back closes it.
  Future<void> _chooseProfile(BuildContext tileContext) async {
    final box = tileContext.findRenderObject() as RenderBox;
    final screen = MediaQuery.sizeOf(tileContext);
    final origin = box.localToGlobal(Offset.zero);
    const rowHeight = 44.0, padding = 6.0;
    final height = widget.profiles.length * rowHeight + padding * 2;
    // Opens below the tile, or above it when there is no room below.
    final below = origin.dy + box.size.height + 6;
    final top = below + height <= screen.height - 8
        ? below
        : (origin.dy - 6 - height).clamp(8.0, screen.height);
    final chosen = await showDialog<Profile>(
      context: tileContext,
      barrierColor: Colors.transparent,
      builder: (menuContext) => Stack(
        children: [
          Positioned(
            left: origin.dx,
            top: top,
            width: box.size.width,
            child: Material(
              key: const ValueKey('who-watching-list'),
              color: const Color(0xf21f232b),
              elevation: 12,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(padding),
                child: FocusTraversalGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final profile in widget.profiles)
                        _ProfileChoice(
                          key: ValueKey('who-watching-${profile.id}'),
                          profile: profile,
                          active: profile.id == widget.activeProfile?.id,
                          onPressed: () => Navigator.pop(menuContext, profile),
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
    if (chosen != null && chosen.id != widget.activeProfile?.id) {
      widget.onProfileSelected?.call(chosen);
    }
  }

  /// Lays slim tiles out two to a row; a leftover tile takes the full width.
  List<Widget> _tileRows(List<Widget> tiles) => [
    for (var i = 0; i < tiles.length; i += 2) ...[
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(child: tiles[i]),
          if (i + 1 < tiles.length) ...[
            const SizedBox(width: 6),
            Expanded(child: tiles[i + 1]),
          ],
        ],
      ),
    ],
  ];

  Widget _wideModule({
    required String label,
    required String caption,
    required IconData icon,
    required VoidCallback onPressed,
    IconData? trailing,
  }) => SizedBox(
    height: 46,
    child: _Module(
      label: label,
      radius: 14,
      lift: 1.02,
      onPressed: onPressed,
      builder: (foreground) => Row(
        children: [
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  caption,
                  key: ValueKey('quick-control-$label-caption'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: .72),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) Icon(trailing, size: 16, color: foreground),
        ],
      ),
    ),
  );
}

/// The lighter rounded group that sits inside the panel (Control Center's
/// "platter").
/// The look of glass for a tile at rest: a soft light gradient with a thin
/// bright rim, like the panel it sits on. Static, so it costs nothing.
ShapeDecoration _glass(ShapeBorder shape) => ShapeDecoration(
  shape: shape,
  gradient: const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x33ffffff), Color(0x0dffffff), Color(0x1affffff)],
    stops: [0, .55, 1],
  ),
);

ShapeBorder _rim(ShapeBorder shape) => switch (shape) {
  CircleBorder() => const CircleBorder(
    side: BorderSide(color: Color(0x47ffffff), width: .8),
  ),
  RoundedRectangleBorder(:final borderRadius) => RoundedRectangleBorder(
    borderRadius: borderRadius,
    side: const BorderSide(color: Color(0x47ffffff), width: .8),
  ),
  _ => shape,
};

class _Platter extends StatelessWidget {
  const _Platter({required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: _glass(
      _rim(RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// Focus feedback shared by toggles and modules: lifts (scales up) and casts
/// a soft shadow, like tvOS focus, unless motion is reduced.
class _FocusLift extends StatelessWidget {
  const _FocusLift({
    required this.focused,
    required this.child,
    this.scale = 1.06,
  });
  final bool focused;
  final double scale;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: focused ? scale : 1,
    duration: motionReduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 150),
    curve: Curves.easeOutCubic,
    // Its own layer: growing on focus moves this tile only, without
    // repainting the glass panel around it.
    child: RepaintBoundary(child: child),
  );
}

class _RoundToggle extends StatefulWidget {
  const _RoundToggle({
    required this.label,
    required this.caption,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.autofocus = false,
  });
  final String label, caption;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active, autofocus;
  @override
  State<_RoundToggle> createState() => _RoundToggleState();
}

class _RoundToggleState extends State<_RoundToggle> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final fill = focused
        ? Colors.white
        : widget.active
        ? _activeFill
        : Colors.transparent;
    final glyph = focused ? _ink : Colors.white;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FocusLift(
            focused: focused,
            scale: 1.1,
            child: Container(
              width: 40,
              height: 40,
              decoration: focused || widget.active
                  ? null
                  : _glass(_rim(const CircleBorder())),
              child: TextButton(
                key: ValueKey('quick-control-${widget.label}'),
                autofocus: widget.autofocus,
                onPressed: widget.onPressed,
                onFocusChange: (value) => setState(() => focused = value),
                style: ButtonStyle(
                  animationDuration: Duration.zero,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                  shape: const WidgetStatePropertyAll(CircleBorder()),
                  backgroundColor: WidgetStatePropertyAll(fill),
                  foregroundColor: WidgetStatePropertyAll(glyph),
                  elevation: const WidgetStatePropertyAll(0),
                ),
                child: Semantics(
                  label: '${widget.label}, ${widget.caption}',
                  child: Icon(widget.icon, size: 19, color: glyph),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          ExcludeSemantics(
            child: Text(
              widget.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: focused ? 1 : .78),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One person in the "Who's watching" drop-down list.
class _ProfileChoice extends StatefulWidget {
  const _ProfileChoice({
    super.key,
    required this.profile,
    required this.active,
    required this.onPressed,
  });
  final Profile profile;
  final bool active;
  final VoidCallback onPressed;
  @override
  State<_ProfileChoice> createState() => _ProfileChoiceState();
}

class _ProfileChoiceState extends State<_ProfileChoice> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final foreground = focused ? _ink : Colors.white;
    return SizedBox(
      height: 44,
      child: TextButton(
        autofocus: widget.active,
        onPressed: widget.onPressed,
        onFocusChange: (value) => setState(() => focused = value),
        style: ButtonStyle(
          animationDuration: Duration.zero,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12),
          ),
          backgroundColor: WidgetStatePropertyAll(
            focused ? Colors.white : Colors.transparent,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              widget.active
                  ? Icons.check_rounded
                  : Icons.person_outline_rounded,
              size: 18,
              color: foreground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Module extends StatefulWidget {
  const _Module({
    required this.label,
    required this.onPressed,
    required this.builder,
    this.radius = 20,
    this.keyed = true,
    this.lift = 1.06,
  });
  final String label;
  final VoidCallback onPressed;
  final Widget Function(Color foreground) builder;
  final double radius;
  final bool keyed;

  /// Wide modules lift less so they stay inside the panel.
  final double lift;
  @override
  State<_Module> createState() => _ModuleState();
}

class _ModuleState extends State<_Module> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final foreground = focused ? _ink : Colors.white;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.radius),
    );
    return _FocusLift(
      focused: focused,
      scale: widget.lift,
      child: DecoratedBox(
        decoration: focused ? const BoxDecoration() : _glass(_rim(shape)),
        child: TextButton(
          key: widget.keyed ? ValueKey('quick-control-${widget.label}') : null,
          onPressed: widget.onPressed,
          onFocusChange: (value) => setState(() => focused = value),
          style: ButtonStyle(
            animationDuration: Duration.zero,
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
            minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
            backgroundColor: WidgetStatePropertyAll(
              focused ? Colors.white : Colors.transparent,
            ),
            foregroundColor: WidgetStatePropertyAll(foreground),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.radius),
              ),
            ),
          ),
          child: widget.builder(foreground),
        ),
      ),
    );
  }
}
