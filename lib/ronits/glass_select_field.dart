import 'package:flutter/material.dart';
import 'focus_feedback.dart';
import 'menu_dialog.dart';
import 'motion.dart';

/// Remote-friendly replacement for opaque Material dropdown popups.
class GlassSelectField<T> extends StatelessWidget {
  const GlassSelectField({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.autofocus = false,
    this.isDense = true,
    this.isExpanded = true,
    this.hint,
  });
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;
  final InputDecoration decoration;
  final bool autofocus, isDense, isExpanded;
  final Widget? hint;

  @override
  Widget build(BuildContext context) {
    final current = items
        .where((item) => item.value == initialValue)
        .firstOrNull;
    return TextButton(
      autofocus: autofocus,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        foregroundColor: Colors.white,
      ),
      onPressed: onChanged == null
          ? null
          : () {
              var selected = initialValue;
              showLumaDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (context) => StatefulBuilder(
                  builder: (context, update) => LumaMenuDialog(
                    title: const Text('Choose option'),
                    content: SizedBox(
                      width: 380,
                      child: FocusHighlightLayer(
                        menu: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final item in items)
                              TvMenuRow(
                                title: item.child is Text
                                    ? ((item.child as Text).data ??
                                          '${item.value}')
                                    : '${item.value}',
                                autofocus:
                                    item ==
                                    (items
                                            .where(
                                              (entry) =>
                                                  entry.value == initialValue,
                                            )
                                            .firstOrNull ??
                                        items.firstOrNull),
                                selected: item.value == selected,
                                onPressed: () {
                                  if (!item.enabled) return;
                                  onChanged?.call(item.value);
                                  update(() => selected = item.value);
                                },
                              ),
                          ],
                        ),
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
            },
      child: InputDecorator(
        decoration: decoration,
        child: Row(
          children: [
            Expanded(child: current?.child ?? hint ?? const SizedBox()),
            const Icon(Icons.expand_more_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
