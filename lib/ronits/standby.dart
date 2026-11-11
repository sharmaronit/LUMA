// Luma
// Copyright (C) 2026 Ronit Sharma
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'focus_feedback.dart';
import 'menu_dialog.dart';
import 'motion.dart';

/// StandBy: a full-screen clock that appears when the home screen has been
/// left alone for a while. Any button on the remote closes it.
class StandbySettings {
  StandbySettings(this._prefs);
  final SharedPreferences _prefs;
  static const styles = ['analog', 'solid', 'colour', 'world'];
  static const idle = Duration(minutes: 2);

  /// Told when a setting changes, so the idle watcher picks it up.
  static final changes = ValueNotifier<int>(0);

  bool get enabled => _prefs.getBool('standby_enabled') ?? true;
  String get style {
    final value = _prefs.getString('standby_style');
    return styles.contains(value) ? value! : 'analog';
  }

  /// Follows the clock format chosen for the home screen.
  bool get use24 => (_prefs.getString('time_format') ?? 'H:mm').contains('H');

  Future<void> setEnabled(bool value) async {
    await _prefs.setBool('standby_enabled', value);
    changes.value++;
  }

  Future<void> setStyle(String value) async {
    if (!styles.contains(value)) return;
    await _prefs.setString('standby_style', value);
    changes.value++;
  }
}

String standbyStyleLabel(String style) => switch (style) {
  'solid' => 'Solid',
  'colour' => 'Colour',
  'world' => 'World',
  _ => 'Analogue',
};

String standbyStyleHint(String style) => switch (style) {
  'solid' => 'Large digits in one colour',
  'colour' => 'Each digit in its own colour',
  'world' => 'A map showing where it is day',
  _ => 'A wall clock with a second hand',
};

/// Watches for an idle remote while Luma is on screen and shows StandBy.
/// Wrap the home screen in this.
class StandbyHost extends StatefulWidget {
  const StandbyHost({
    super.key,
    required this.child,
    this.idle = StandbySettings.idle,
    this.settings,
  });
  final Widget child;
  final Duration idle;

  /// Loaded from the device when not given.
  final StandbySettings? settings;
  @override
  State<StandbyHost> createState() => _StandbyHostState();
}

/// True while StandBy is on screen, so it is never stacked twice.
bool _standbyShowing = false;

class _StandbyHostState extends State<StandbyHost> with WidgetsBindingObserver {
  Timer? _timer;
  StandbySettings? _settings;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    StandbySettings.changes.addListener(_restart);
    _settings = widget.settings;
    if (_settings == null) {
      SharedPreferences.getInstance().then((prefs) {
        if (!mounted) return;
        _settings = StandbySettings(prefs);
        _restart();
      });
    } else {
      _restart();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_key);
    StandbySettings.changes.removeListener(_restart);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _restart();
  }

  // Never consumes the key; it only notes that someone is there.
  bool _key(KeyEvent event) {
    _restart();
    return false;
  }

  void _restart() {
    _timer?.cancel();
    final settings = _settings;
    if (settings == null || !settings.enabled || !_foreground) return;
    _timer = Timer(widget.idle, _show);
  }

  Future<void> _show() async {
    final settings = _settings;
    if (!mounted || settings == null || !_foreground) return;
    await showStandby(context, style: settings.style, use24: settings.use24);
    if (mounted) _restart();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shows StandBy until a button is pressed.
Future<void> showStandby(
  BuildContext context, {
  required String style,
  bool use24 = true,
}) async {
  if (_standbyShowing) return;
  _standbyShowing = true;
  try {
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => StandbyScreen(style: style, use24: use24),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  } finally {
    _standbyShowing = false;
  }
}

/// Starts StandBy straight away with the saved style, for the quick settings
/// shortcut.
Future<void> startStandbyNow(BuildContext context) async {
  final settings = StandbySettings(await SharedPreferences.getInstance());
  if (!context.mounted) return;
  await showStandby(context, style: settings.style, use24: settings.use24);
}

class StandbyScreen extends StatefulWidget {
  const StandbyScreen({
    super.key,
    required this.style,
    this.use24 = true,
    this.now,
  });
  final String style;
  final bool use24;
  final DateTime Function()? now;
  @override
  State<StandbyScreen> createState() => _StandbyScreenState();
}

class _StandbyScreenState extends State<StandbyScreen> {
  late DateTime _time = (widget.now ?? DateTime.now)();
  Timer? _tick;
  final _focus = FocusNode(debugLabel: 'StandBy');

  @override
  void initState() {
    super.initState();
    // Once a second is enough for a second hand that ticks, and costs
    // nothing between ticks. The other faces only repaint each minute.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _time = (widget.now ?? DateTime.now)());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Moves the whole face a few pixels every minute so nothing stays lit in
    // exactly the same place.
    final step = _time.minute % 6;
    final drift = Offset((step - 2.5) * 4, ((step * 2) % 6 - 2.5) * 3);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: ColoredBox(
          key: const ValueKey('standby-screen'),
          color: Colors.black,
          child: Transform.translate(
            offset: drift,
            child: RepaintBoundary(
              child: CustomPaint(
                key: ValueKey('standby-${widget.style}'),
                painter: standbyFace(widget.style, _time, use24: widget.use24),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The painter for a StandBy style. Every face sizes itself from the box it
/// is given, so the same painter draws the full screen and the small preview.
CustomPainter standbyFace(String style, DateTime time, {bool use24 = true}) =>
    switch (style) {
      'solid' => _SolidFace(time, use24),
      'colour' => _ColourFace(time, use24),
      'world' => _WorldFace(time, use24),
      _ => _AnalogFace(time),
    };

String _hour(DateTime time, bool use24) =>
    '${use24 ? time.hour : (time.hour % 12 == 0 ? 12 : time.hour % 12)}';
String _minute(DateTime time) => time.minute.toString().padLeft(2, '0');

TextPainter _layout(
  String value, {
  required double size,
  Color color = Colors.white,
  FontWeight weight = FontWeight.w600,
  String family = 'Inter',
  double? wght,
  double spacing = 0,
}) => TextPainter(
  text: TextSpan(
    text: value,
    style: TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: wght == null ? weight : null,
      fontVariations: wght == null ? null : [ui.FontVariation('wght', wght)],
      height: 1,
      letterSpacing: spacing,
      color: color,
    ),
  ),
  textDirection: ui.TextDirection.ltr,
)..layout();

void _text(
  Canvas canvas,
  String value,
  Offset centre, {
  required double size,
  Color color = Colors.white,
  FontWeight weight = FontWeight.w600,
  Alignment anchor = Alignment.center,
}) {
  final painter = _layout(value, size: size, color: color, weight: weight);
  painter.paint(
    canvas,
    centre -
        Offset(
          painter.width * (anchor.x + 1) / 2,
          painter.height * (anchor.y + 1) / 2,
        ),
  );
  painter.dispose();
}

/// A wall clock that fills the screen: marks run along the edges, with large
/// numerals at 12, 3, 6 and 9, white hands and an orange second hand.
class _AnalogFace extends CustomPainter {
  _AnalogFace(this.time);
  final DateTime time;
  static const _orange = Color(0xffff9f0a), _red = Color(0xffff453a);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final unit = size.height;
    final half = Size(
      size.width / 2 - unit * .02,
      size.height / 2 - unit * .02,
    );

    // Distance from the centre to the screen edge along a direction.
    double reach(double angle) {
      final dx = math.cos(angle).abs(), dy = math.sin(angle).abs();
      return math.min(
        dx < 1e-6 ? double.infinity : half.width / dx,
        dy < 1e-6 ? double.infinity : half.height / dy,
      );
    }

    final minor = Paint()
      ..color = const Color(0x8cffffff)
      ..strokeWidth = unit * .003
      ..strokeCap = StrokeCap.round;
    final major = Paint()
      ..color = Colors.white
      ..strokeWidth = unit * .006
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final angle = i * math.pi / 30 - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final edge = reach(angle);
      final hour = i % 5 == 0;
      canvas.drawLine(
        centre + direction * edge,
        centre + direction * (edge - unit * (hour ? .1 : .04)),
        hour ? major : minor,
      );
    }
    for (final (label, angle) in const [
      ('12', -math.pi / 2),
      ('3', 0.0),
      ('6', math.pi / 2),
      ('9', math.pi),
    ]) {
      final direction = Offset(math.cos(angle), math.sin(angle));
      _text(
        canvas,
        label,
        centre + direction * (reach(angle) - unit * .2),
        size: unit * .11,
      );
    }
    // Day and date sit beside the 3.
    final dateCentre = centre + Offset(half.width - unit * .36, 0);
    _text(
      canvas,
      DateFormat('EEE').format(time).toUpperCase(),
      dateCentre,
      size: unit * .04,
      color: _red,
      weight: FontWeight.w700,
      anchor: Alignment.centerRight,
    );
    _text(
      canvas,
      ' ${time.day}',
      dateCentre,
      size: unit * .04,
      weight: FontWeight.w700,
      anchor: Alignment.centerLeft,
    );

    void hand(double turns, double length, double width, Color color) {
      final angle = turns * 2 * math.pi - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      // A thin stem near the centre, then the full-width hand.
      canvas.drawLine(
        centre,
        centre + direction * unit * .05,
        Paint()
          ..color = color
          ..strokeWidth = width * .35
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        centre + direction * unit * .05,
        centre + direction * length,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    final minutes = time.minute + time.second / 60;
    hand(
      (time.hour % 12 + minutes / 60) / 12,
      unit * .22,
      unit * .02,
      Colors.white,
    );
    hand(minutes / 60, unit * .36, unit * .016, Colors.white);
    // Second hand: a thin orange line with a short tail and a ring.
    final angle = time.second / 60 * 2 * math.pi - math.pi / 2;
    final direction = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      centre - direction * unit * .05,
      centre + direction * unit * .42,
      Paint()
        ..color = _orange
        ..strokeWidth = unit * .004
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(centre, unit * .011, Paint()..color = _orange);
    canvas.drawCircle(centre, unit * .005, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_AnalogFace old) =>
      old.time.second != time.second || old.time.minute != time.minute;
}

/// Draws the hour and minute as heavy rounded digits that almost touch, with
/// two soft dots between them. [colours] gives one colour per digit.
void _paintChunkyTime(
  Canvas canvas,
  Size size,
  DateTime time,
  bool use24,
  List<Color> colours, {
  required Color dots,
}) {
  final digits = '${_hour(time, use24)}${_minute(time)}';
  final hourCount = digits.length - 2;
  TextPainter glyph(String value, double fontSize, Color color) => _layout(
    value,
    size: fontSize,
    color: color,
    family: 'Nunito',
    wght: 1000,
  );
  // Digits overlap slightly; the gap for the dots is a little wider.
  const overlap = -.05, gap = .1;
  double widthAt(double fontSize) {
    var total = 0.0;
    for (var i = 0; i < digits.length; i++) {
      final painter = glyph(digits[i], fontSize, Colors.white);
      total += painter.width;
      painter.dispose();
      if (i < digits.length - 1) {
        total += fontSize * (i == hourCount - 1 ? gap : overlap);
      }
    }
    return total;
  }

  var fontSize = size.height * .78;
  final natural = widthAt(fontSize);
  final maxWidth = size.width * .84;
  if (natural > maxWidth) fontSize *= maxWidth / natural;
  final total = widthAt(fontSize);
  var x = (size.width - total) / 2;
  double? dotsX;
  for (var i = 0; i < digits.length; i++) {
    final painter = glyph(digits[i], fontSize, colours[i % colours.length]);
    // Centre the digits themselves, not the font's taller line box: their
    // height is about 0.7 of the font size, measured up from the baseline.
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.paint(
      canvas,
      Offset(x, size.height / 2 + fontSize * .35 - baseline),
    );
    x += painter.width;
    painter.dispose();
    if (i < digits.length - 1) {
      final step = fontSize * (i == hourCount - 1 ? gap : overlap);
      if (i == hourCount - 1) dotsX = x + step / 2;
      x += step;
    }
  }
  if (dotsX != null) {
    final radius = fontSize * .075;
    for (final dy in [-.16, .16]) {
      final centre = Offset(dotsX, size.height / 2 + fontSize * dy);
      canvas.drawCircle(
        centre,
        radius * 1.5,
        Paint()
          ..color = dots.withValues(alpha: .35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .8),
      );
      canvas.drawCircle(centre, radius, Paint()..color = dots);
    }
  }
}

/// Very large digits in a single colour.
class _SolidFace extends CustomPainter {
  _SolidFace(this.time, this.use24);
  final DateTime time;
  final bool use24;
  @override
  void paint(Canvas canvas, Size size) => _paintChunkyTime(
    canvas,
    size,
    time,
    use24,
    const [Color(0xff1fd6c4)],
    dots: const Color(0xffd9fff9),
  );

  @override
  bool shouldRepaint(_SolidFace old) =>
      old.time.minute != time.minute || old.time.hour != time.hour;
}

/// The same heavy digits, each in its own colour.
class _ColourFace extends CustomPainter {
  _ColourFace(this.time, this.use24);
  final DateTime time;
  final bool use24;
  @override
  void paint(Canvas canvas, Size size) =>
      _paintChunkyTime(canvas, size, time, use24, const [
        Color(0xfff472b6),
        Color(0xffb4a0ff),
        Color(0xffc026d3),
        Color(0xff8b5cf6),
      ], dots: const Color(0xffbdbdc4));

  @override
  bool shouldRepaint(_ColourFace old) =>
      old.time.minute != time.minute || old.time.hour != time.hour;
}

/// Land on a coarse world map: for each latitude, the longitude ranges that
/// are land. Drawn as dots, so it only needs to be roughly right.
const _land = <int, List<(int, int)>>{
  80: [(-90, -20), (95, 105)],
  75: [(-125, -75), (-60, -20), (85, 115), (135, 150)],
  70: [(-165, -140), (-130, -65), (-55, -20), (15, 30), (50, 180)],
  65: [(-168, -60), (-52, -38), (-24, -14), (10, 180)],
  60: [(-165, -140), (-135, -62), (-48, -43), (5, 165)],
  55: [(-165, -155), (-132, -58), (-8, 0), (8, 160)],
  50: [(-128, -55), (-5, 142), (155, 160)],
  45: [(-125, -60), (-2, 140)],
  40: [(-124, -72), (-9, 0), (12, 18), (20, 48), (53, 128), (139, 142)],
  35: [(-121, -76), (-6, 10), (32, 120), (132, 140)],
  30: [(-115, -81), (-10, 122)],
  25: [(-112, -97), (-82, -80), (-15, 57), (60, 120)],
  20: [(-105, -87), (-78, -72), (-17, 40), (42, 58), (72, 87), (92, 110)],
  15: [(-98, -84), (-17, 40), (43, 50), (74, 81), (95, 109), (120, 123)],
  10: [(-86, -75), (-72, -60), (-15, 48), (76, 79), (98, 108), (122, 126)],
  5: [(-77, -52), (-10, 47), (95, 103), (109, 118), (124, 126)],
  0: [(-80, -50), (9, 43), (100, 104), (109, 118), (120, 123), (128, 135)],
  -5: [(-81, -35), (12, 40), (103, 106), (119, 123), (135, 150)],
  -10: [(-78, -36), (13, 40), (142, 147)],
  -15: [(-76, -39), (12, 40), (45, 50), (125, 145)],
  -20: [(-70, -40), (13, 35), (44, 49), (118, 148)],
  -25: [(-70, -48), (15, 35), (45, 47), (114, 153)],
  -30: [(-71, -50), (17, 31), (115, 153)],
  -35: [(-72, -57), (18, 26), (117, 123), (137, 150)],
  -40: [(-73, -62), (145, 148), (173, 177)],
  -45: [(-74, -66), (168, 172)],
  -50: [(-74, -68)],
  -55: [(-70, -66)],
};

bool _isLand(double latitude, double longitude) {
  final band = (latitude / 5).round() * 5;
  for (final (west, east) in _land[band] ?? const <(int, int)>[]) {
    if (longitude >= west && longitude <= east) return true;
  }
  return false;
}

/// A dotted world map, brighter where the sun is up, with the time and the
/// TV's time zone.
class _WorldFace extends CustomPainter {
  _WorldFace(this.time, this.use24);
  final DateTime time;
  final bool use24;
  static const _orange = Color(0xffff9f0a);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height;
    // The map: longitude across the full width, 82N to 58S down 62% of the
    // height.
    final mapTop = unit * .06, mapHeight = unit * .62;
    const step = 3.6;
    final radius = size.width / (360 / step) * .32;
    final utc = time.toUtc();
    // Where the sun is overhead, in degrees east.
    final sun = -((utc.hour + utc.minute / 60) - 12) * 15;
    final day = Paint()..color = const Color(0xe6ffffff);
    final night = Paint()..color = const Color(0x47ffffff);
    for (var latitude = 82.0; latitude >= -58; latitude -= step) {
      for (
        var longitude = -180 + step / 2;
        longitude < 180;
        longitude += step
      ) {
        if (!_isLand(latitude, longitude)) continue;
        final light = math.cos((longitude - sun) * math.pi / 180) > 0;
        canvas.drawCircle(
          Offset(
            (longitude + 180) / 360 * size.width,
            mapTop + (82 - latitude) / 140 * mapHeight,
          ),
          radius,
          light ? day : night,
        );
      }
    }
    // An orange dot marks the TV's own meridian.
    final here = time.timeZoneOffset.inMinutes / 60 * 15;
    canvas.drawCircle(
      Offset(
        (here + 180) / 360 * size.width,
        mapTop + (82 - 25) / 140 * mapHeight,
      ),
      radius * 1.9,
      Paint()..color = _orange,
    );

    final left = size.width * .05;
    final zone = _layout(
      '➤ ${time.timeZoneName}',
      size: unit * .05,
      color: _orange,
      weight: FontWeight.w700,
    );
    final clock = _layout(
      '${_hour(time, use24)}:${_minute(time)}',
      size: unit * .2,
      weight: FontWeight.w600,
    );
    final bottom = unit * .94;
    clock.paint(canvas, Offset(left, bottom - clock.height));
    zone.paint(
      canvas,
      Offset(left, bottom - clock.height - zone.height - unit * .012),
    );
    clock.dispose();
    zone.dispose();
  }

  @override
  bool shouldRepaint(_WorldFace old) =>
      old.time.minute != time.minute || old.time.hour != time.hour;
}

/// A small live picture of a StandBy face, for the settings screen.
class StandbyPreview extends StatelessWidget {
  const StandbyPreview({super.key, required this.style, this.use24 = true});
  final String style;
  final bool use24;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: Colors.black,
        child: RepaintBoundary(
          child: CustomPaint(
            key: ValueKey('standby-preview-$style'),
            painter: standbyFace(style, DateTime.now(), use24: use24),
          ),
        ),
      ),
    ),
  );
}

/// One face in the StandBy picker: a live preview card with its name.
class _StandbyCard extends StatefulWidget {
  const _StandbyCard({
    required this.style,
    required this.use24,
    required this.selected,
    required this.autofocus,
    required this.onPressed,
  });
  final String style;
  final bool use24, selected, autofocus;
  final VoidCallback onPressed;
  @override
  State<_StandbyCard> createState() => _StandbyCardState();
}

class _StandbyCardState extends State<_StandbyCard> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    child: SizedBox(
      width: 190,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: focused ? 1.08 : 1,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: InkWell(
              key: ValueKey('standby-style-${widget.style}'),
              autofocus: widget.autofocus,
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onPressed,
              onFocusChange: (value) {
                setState(() => focused = value);
                if (value) {
                  Scrollable.ensureVisible(
                    context,
                    alignment: .5,
                    duration: const Duration(milliseconds: 160),
                  );
                }
              },
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: focused
                        ? Colors.white
                        : Colors.white.withValues(alpha: .18),
                    width: focused ? 2.5 : 1,
                  ),
                ),
                child: StandbyPreview(style: widget.style, use24: widget.use24),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.selected) ...[
                const Icon(Icons.check_rounded, size: 16),
                const SizedBox(width: 4),
              ],
              Text(
                standbyStyleLabel(widget.style),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: focused || widget.selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Settings > Appearance > StandBy: the faces side by side as live previews.
/// Left and Right move between them, OK chooses one.
Future<void> showStandbySettings(BuildContext context) async {
  final settings = StandbySettings(await SharedPreferences.getInstance());
  if (!context.mounted) return;
  await showLumaDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, update) => LumaMenuDialog(
        title: const Text('StandBy'),
        content: FocusHighlightLayer(
          menu: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FocusTraversalGroup(
                child: SingleChildScrollView(
                  key: const ValueKey('standby-styles'),
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      for (final style in StandbySettings.styles)
                        _StandbyCard(
                          style: style,
                          use24: settings.use24,
                          selected: settings.style == style,
                          autofocus: settings.style == style,
                          onPressed: () async {
                            await settings.setStyle(style);
                            update(() {});
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TvMenuRow(
                key: const ValueKey('standby-enabled'),
                icon: Icons.nightlight_round,
                title: 'Start automatically',
                subtitle: settings.enabled
                    ? 'After 2 minutes without a button press on Home'
                    : 'Off · start it from the clock menu',
                selected: settings.enabled,
                trailing: Icon(
                  settings.enabled ? Icons.toggle_on : Icons.toggle_off,
                ),
                onPressed: () async {
                  await settings.setEnabled(!settings.enabled);
                  update(() {});
                },
              ),
              TvMenuRow(
                key: const ValueKey('standby-preview'),
                icon: Icons.play_arrow_rounded,
                title: 'Show full screen',
                subtitle: standbyStyleLabel(settings.style),
                onPressed: () => showStandby(
                  dialogContext,
                  style: settings.style,
                  use24: settings.use24,
                ),
              ),
            ],
          ),
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
