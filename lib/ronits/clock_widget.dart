import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'glass_surface.dart';
import 'clock_preferences.dart';

class LumaClock extends StatefulWidget {
  const LumaClock({
    super.key,
    this.style = 'digital',
    this.size = 'medium',
    this.pattern = 'h:mm a',
  });
  final String style, size, pattern;
  @override
  State<LumaClock> createState() => _LumaClockState();
}

class _LumaClockState extends State<LumaClock> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    scheduleTick();
  }

  void scheduleTick() {
    final now = DateTime.now();
    timer = Timer(
      Duration(milliseconds: 60000 - now.second * 1000 - now.millisecond),
      () {
        if (!mounted) return;
        setState(() {});
        scheduleTick();
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String text;
    try {
      text = DateFormat(widget.pattern).format(now);
    } catch (_) {
      text = DateFormat('h:mm a').format(now);
    }
    final color = MinimalPalette.of(context).text;
    if (widget.style != 'analog')
      return Text(
        text,
        key: const ValueKey('luma-digital-clock'),
        style: TextStyle(
          fontSize: clockDigitalExtent(widget.size),
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      );
    final side = clockAnalogExtent(widget.size);
    return Semantics(
      label: text,
      child: RepaintBoundary(
        child: SizedBox(
          width: side,
          height: side,
          child: CustomPaint(
            key: const ValueKey('luma-analog-clock'),
            painter: _ClockFace(now.hour, now.minute, color),
          ),
        ),
      ),
    );
  }
}

class _ClockFace extends CustomPainter {
  const _ClockFace(this.hour, this.minute, this.color);
  final int hour, minute;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(
      center,
      radius - 1,
      pen..color = color.withValues(alpha: .45),
    );
    Offset point(double angle, double length) =>
        center + Offset(math.sin(angle), -math.cos(angle)) * length;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawLine(
        point(a, radius * .78),
        point(a, radius * .87),
        pen..color = color.withValues(alpha: .7),
      );
    }
    pen
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    canvas.drawLine(
      center,
      point(((hour % 12) + minute / 60) * math.pi / 6, radius * .46),
      pen,
    );
    canvas.drawLine(
      center,
      point(minute * math.pi / 30, radius * .66),
      pen..strokeWidth = 1.5,
    );
    canvas.drawCircle(center, 1.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ClockFace old) =>
      old.hour != hour || old.minute != minute || old.color != color;
}
