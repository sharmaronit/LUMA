import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'clock_preferences.dart';
import 'clock_widget.dart';
import 'focus_feedback.dart';

class ClockSettings extends StatefulWidget {
  const ClockSettings({
    super.key,
    required this.style,
    required this.size,
    required this.pattern,
    this.onStyleChanged,
    this.onSizeChanged,
    this.onFormatChanged,
  });
  final String style, size, pattern;
  final ValueChanged<String>? onStyleChanged, onSizeChanged, onFormatChanged;
  @override
  State<ClockSettings> createState() => _ClockSettingsState();
}

class _ClockSettingsState extends State<ClockSettings> {
  late String style = widget.style, pattern = widget.pattern;
  late double size = clockSizePosition(widget.size);
  final sliderFocus = FocusNode(debugLabel: 'Clock size slider');
  final styleFocus = FocusNode(debugLabel: 'Clock style');
  final formatFocus = FocusNode(debugLabel: 'Clock format');
  bool sliderSelected = false;
  @override
  void dispose() {
    sliderFocus.dispose();
    styleFocus.dispose();
    formatFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
      final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
      if (!up && !down) return KeyEventResult.ignored;
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (styleFocus.hasFocus &&
            down &&
            (widget.onFormatChanged != null || widget.onSizeChanged != null))
          (widget.onFormatChanged != null ? formatFocus : sliderFocus)
              .requestFocus();
        else if (formatFocus.hasFocus && up && widget.onStyleChanged != null)
          styleFocus.requestFocus();
        else if (formatFocus.hasFocus && down && widget.onSizeChanged != null)
          sliderFocus.requestFocus();
        else
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: style == 'analog'
              ? clockAnalogExtent(size.round().toString()).clamp(80.0, 160.0)
              : 80,
          child: Center(
            child: LumaClock(
              style: style,
              size: size.round().toString(),
              pattern: pattern,
            ),
          ),
        ),
        if (widget.onStyleChanged != null)
          TvMenuRow(
            key: const ValueKey('setting-clock-style'),
            focusNode: styleFocus,
            autofocus: true,
            icon: Icons.watch_outlined,
            title: 'Clock style',
            subtitle: style == 'analog' ? 'Analog' : 'Digital',
            onPressed: () {
              setState(() => style = style == 'analog' ? 'digital' : 'analog');
              widget.onStyleChanged!(style);
            },
          ),
        if (widget.onFormatChanged != null)
          TvMenuRow(
            key: const ValueKey('setting-clock-format'),
            focusNode: formatFocus,
            autofocus: widget.onStyleChanged == null,
            icon: Icons.schedule,
            title: 'Clock format',
            subtitle: pattern.contains('H') ? '24-hour' : '12-hour',
            onPressed: () {
              setState(
                () => pattern = pattern.contains('H') ? 'h:mm a' : 'HH:mm',
              );
              widget.onFormatChanged!(pattern);
            },
          ),
        if (widget.onSizeChanged != null) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Clock size',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              Text('${size.round()}', key: const ValueKey('clock-size-value')),
            ],
          ),
          Focus(
            key: const ValueKey('clock-size-control'),
            focusNode: sliderFocus,
            autofocus:
                widget.onStyleChanged == null && widget.onFormatChanged == null,
            onFocusChange: (focused) =>
                setState(() => sliderSelected = focused),
            onKeyEvent: (_, event) {
              final key = event.logicalKey;
              if (![
                LogicalKeyboardKey.arrowUp,
                LogicalKeyboardKey.arrowDown,
                LogicalKeyboardKey.arrowLeft,
                LogicalKeyboardKey.arrowRight,
              ].contains(key))
                return KeyEventResult.ignored;
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                if (key == LogicalKeyboardKey.arrowUp)
                  (widget.onFormatChanged != null
                          ? formatFocus
                          : widget.onStyleChanged != null
                          ? styleFocus
                          : sliderFocus)
                      .requestFocus();
                else if (key == LogicalKeyboardKey.arrowDown)
                  sliderFocus.nextFocus();
                else {
                  final value =
                      (size + (key == LogicalKeyboardKey.arrowRight ? 5 : -5))
                          .clamp(0.0, 100.0);
                  if (size != value) {
                    setState(() => size = value);
                    widget.onSizeChanged!(value.round().toString());
                  }
                }
              }
              return KeyEventResult.handled;
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: sliderSelected
                    ? Colors.white.withValues(alpha: .10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExcludeFocus(
                child: Slider(
                  key: const ValueKey('setting-clock-size-slider'),
                  value: size,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${size.round()}',
                  semanticFormatterCallback: (value) =>
                      'Clock size ${value.round()} of 100',
                  onChanged: (value) {
                    if (size == value) return;
                    setState(() => size = value);
                    widget.onSizeChanged!(value.round().toString());
                  },
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
