import 'package:flutter/material.dart';
import 'focus_feedback.dart';

/// A single recent reversible edit. Kept in memory while its menu is open.
class MenuUndo {
  const MenuUndo(this.message, this.restore);
  final String message;
  final Future<void> Function() restore;
}

class MenuUndoNotice extends StatefulWidget {
  const MenuUndoNotice({
    super.key,
    required this.undo,
    required this.onRestored,
    this.onBusyChanged,
    this.autofocus = false,
  });
  final MenuUndo undo;
  final VoidCallback onRestored;
  final ValueChanged<bool>? onBusyChanged;
  final bool autofocus;
  @override
  State<MenuUndoNotice> createState() => _MenuUndoNoticeState();
}

class _MenuUndoNoticeState extends State<MenuUndoNotice> {
  bool busy = false;
  String? error;
  @override
  void didUpdateWidget(MenuUndoNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.undo != widget.undo) error = null;
  }

  Future<void> restore() async {
    if (busy) return;
    final undo = widget.undo;
    setState(() {
      busy = true;
      error = null;
    });
    widget.onBusyChanged?.call(true);
    bool restored = false;
    try {
      await undo.restore();
      restored = true;
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not undo. Select Undo to retry.');
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusyChanged?.call(false);
        if (restored && identical(undo, widget.undo)) widget.onRestored();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: FocusHighlightLayer(
      menu: true,
      child: TvMenuRow(
        autofocus: widget.autofocus,
        icon: Icons.undo_rounded,
        title: busy ? 'Restoring…' : 'Undo',
        subtitle: error ?? widget.undo.message,
        onPressed: restore,
      ),
    ),
  );
}
