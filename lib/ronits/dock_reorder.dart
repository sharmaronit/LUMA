part of 'launcher_home.dart';

extension _DockReordering on _LauncherHomeState {
  Future<void> _beginDockMove(LauncherAppItem app) async {
    if (widget.onMoveFavorite == null) return;
    cancelPendingMenuFocusRestores();
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _goHome();
    if (!mounted || !widget.favorites.any((item) => item.id == app.id)) return;
    _updateHome(() {
      _dockMoveId = app.id;
      _dockMoveExitRequested = false;
      _dockMoveQueue.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _dockMoveId == app.id) _dockMoveFocus.requestFocus();
    });
  }

  void _finishDockMove() {
    _dockMoveQueue.clear();
    if (_dockMoveBusy) {
      _dockMoveExitRequested = true;
      return;
    }
    final id = _dockMoveId;
    if (id == null || !mounted) return;
    _updateHome(() => _dockMoveId = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.favorites.toList().indexWhere((app) => app.id == id);
      if (index < 0) return;
      (index == 0
              ? _firstAppFocus
              : index == widget.favorites.length - 1
              ? _lastDockFocus
              : _nodeFor(id, false))
          .requestFocus();
    });
  }

  Future<void> _moveDockApp(int direction) async {
    if (_dockMoveId == null || _dockMoveExitRequested) return;
    if (_dockMoveQueue.length < 3) _dockMoveQueue.add(direction);
    if (_dockMoveBusy) return;
    _dockMoveBusy = true;
    try {
      while (mounted && _dockMoveId != null && _dockMoveQueue.isNotEmpty) {
        final offset = _dockMoveQueue.removeAt(0);
        final app = widget.favorites
            .where((app) => app.id == _dockMoveId)
            .firstOrNull;
        if (app == null) break;
        // Serialize writes, including repeated keys, and follow the app identity
        // rather than whichever position used to own focus.
        await widget.onMoveFavorite!(app, offset);
        if (!mounted) return;
        WidgetsBinding.instance.ensureVisualUpdate();
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && _dockMoveId != null && !_dockMoveFocus.hasFocus) {
          _dockMoveFocus.requestFocus();
        }
      }
    } catch (_) {
      if (mounted) _message('Could not save this move. Please try again.');
      _dockMoveExitRequested = true;
      _dockMoveQueue.clear();
    } finally {
      _dockMoveBusy = false;
      if (mounted && _dockMoveExitRequested) _finishDockMove();
    }
  }
}
