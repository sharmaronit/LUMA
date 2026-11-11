import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_service.dart';

/// Observe remote input without consuming it. A movement tone requires an
/// actual focus change, so boundaries and startup do not make phantom clicks.
class NavigationSounds extends StatefulWidget {
  const NavigationSounds({super.key, required this.child});
  final Widget child;
  @override
  State<NavigationSounds> createState() => _NavigationSoundsState();
}

class _NavigationSoundsState extends State<NavigationSounds>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('app.luma.tvlauncher/method');
  final _clock = Stopwatch()..start();
  int _navigationAt = -1000, _lastMoveAt = -1000;
  int? _selectAt;
  FocusNode? _previousFocus;
  bool _active = true;
  (bool, double)? _configured;
  static final _arrows = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
  };
  static final _select = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.space,
  };

  @override
  void initState() {
    super.initState();
    _previousFocus = FocusManager.instance.primaryFocus;
    HardwareKeyboard.instance.addHandler(_key);
    FocusManager.instance.addListener(_focusChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _editing {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText ||
        context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _key(KeyEvent event) {
    if (!_active || _editing) return false;
    final key = event.logicalKey;
    if (_arrows.contains(key) && event is! KeyUpEvent) {
      _navigationAt = _clock.elapsedMilliseconds;
    } else if (_select.contains(key)) {
      if (event is KeyDownEvent) _selectAt = _clock.elapsedMilliseconds;
      if (event is KeyUpEvent) {
        final began = _selectAt;
        _selectAt = null;
        if (began != null && _clock.elapsedMilliseconds - began < 500) {
          unawaited(_play('select'));
        }
      }
    } else if (event is KeyDownEvent &&
        {
          LogicalKeyboardKey.escape,
          LogicalKeyboardKey.goBack,
          LogicalKeyboardKey.gameButtonB,
        }.contains(key)) {
      unawaited(_play('back'));
    }
    return false;
  }

  void _focusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == _previousFocus) return;
    _previousFocus = focus;
    final now = _clock.elapsedMilliseconds;
    if (!_active || focus == null || _editing || now - _navigationAt > 180)
      return;
    _navigationAt = -1000;
    // Holding an arrow remains quiet and never builds a queue of sounds.
    if (now - _lastMoveAt < 110) return;
    _lastMoveAt = now;
    unawaited(_play('move'));
  }

  Future<void> _play(String sound) async {
    if (!mounted || !_active) return;
    final settings = context.read<SettingsService>();
    if (!settings.appKeyClickEnabled || settings.navigationSoundVolume <= 0)
      return;
    try {
      await _channel.invokeMethod<void>('playNavigationSound', {
        'sound': sound,
        'volume': settings.navigationSoundVolume,
      });
    } on MissingPluginException {
      // Browser preview and widget tests do not have Android audio.
    } on PlatformException {
      // Audio feedback must never interrupt navigation.
    }
  }

  Future<void> _configure(bool enabled, double volume) async {
    try {
      await _channel.invokeMethod<void>('setNavigationSoundSettings', {
        'enabled': enabled,
        'volume': volume,
      });
    } on MissingPluginException {
      // Android-only feedback.
    } on PlatformException {
      // Settings must remain usable if audio is unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _navigationAt = -1000;
    _selectAt = null;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    FocusManager.instance.removeListener(_focusChanged);
    WidgetsBinding.instance.removeObserver(this);
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final config = (
      settings.appKeyClickEnabled,
      settings.navigationSoundVolume,
    );
    if (_configured != config) {
      _configured = config;
      unawaited(_configure(config.$1, config.$2));
    }
    return widget.child;
  }
}
