import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A remote's horizontal arrows never leave this row or wrap at its ends.
class RemoteFocusRow extends StatelessWidget {
  const RemoteFocusRow({super.key, required this.child});
  final Widget child;

  static KeyEventResult handle(FocusNode row, KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final nodes =
          row.traversalDescendants
              .where(
                (node) =>
                    node.canRequestFocus &&
                    node.context != null &&
                    node is! FocusScopeNode &&
                    !node.descendants.any(
                      (child) =>
                          child.canRequestFocus && child is! FocusScopeNode,
                    ),
              )
              .toList()
            ..sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));
      final index = nodes.indexWhere((node) => node.hasFocus);
      final next = index + (key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      if (index >= 0 && next >= 0 && next < nodes.length) {
        nodes[next].requestFocus();
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: handle,
    child: child,
  );
}
