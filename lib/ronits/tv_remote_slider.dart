import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV sliders reserve vertical arrows for leaving the control.
class TvRemoteSlider extends StatefulWidget {
  const TvRemoteSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    required this.divisions,
    this.semanticFormatterCallback,
    this.onChangeEnd,
  });
  final double value, min, max;
  final int divisions;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final SemanticFormatterCallback? semanticFormatterCallback;
  @override
  State<TvRemoteSlider> createState() => _TvRemoteSliderState();
}

class _TvRemoteSliderState extends State<TvRemoteSlider> {
  final node = FocusNode(debugLabel: 'TV slider');
  bool focused = false;
  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    canRequestFocus: widget.onChanged != null,
    onFocusChange: (value) => setState(() => focused = value),
    onKeyEvent: (_, event) {
      final key = event.logicalKey;
      if (!const [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ].contains(key))
        return KeyEventResult.ignored;
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (key == LogicalKeyboardKey.arrowUp) {
          node.previousFocus();
        } else if (key == LogicalKeyboardKey.arrowDown) {
          node.nextFocus();
        } else if (widget.onChanged != null) {
          final step = (widget.max - widget.min) / widget.divisions;
          final next =
              (widget.value +
                      (key == LogicalKeyboardKey.arrowRight ? step : -step))
                  .clamp(widget.min, widget.max);
          if ((next - widget.value).abs() > .000001) {
            widget.onChanged!(next);
            widget.onChangeEnd?.call(next);
          }
        }
      }
      return KeyEventResult.handled;
    },
    child: Listener(
      onPointerDown: (_) {
        if (widget.onChanged != null) node.requestFocus();
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: focused
              ? Colors.white.withValues(alpha: .10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExcludeFocus(
          child: Slider(
            value: widget.value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            semanticFormatterCallback: widget.semanticFormatterCallback,
            onChanged: widget.onChanged,
            onChangeEnd: widget.onChangeEnd,
          ),
        ),
      ),
    ),
  );
}
