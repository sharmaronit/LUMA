// Desktop remote simulator. This file is only imported by the browser entry.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'launcher_home.dart';

// Flutter web normally maps arrows to scrolling. Override that with TV traversal.
const previewRemoteShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
    TraversalDirection.left,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
    TraversalDirection.right,
  ),
  SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
    TraversalDirection.up,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
    TraversalDirection.down,
  ),
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

class PreviewRemote extends StatefulWidget {
  const PreviewRemote({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.controller,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final LauncherRemoteController controller;
  @override
  State<PreviewRemote> createState() => _PreviewRemoteState();
}

class _PreviewRemoteState extends State<PreviewRemote> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  bool get _editing {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText ||
        context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _key(KeyEvent event) {
    final key = event.logicalKey;
    final back =
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.gameButtonB ||
        (!_editing && key == LogicalKeyboardKey.backspace);
    LauncherRemoteCommand? command;
    if (!_editing) {
      if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.keyH)
        command = LauncherRemoteCommand.home;
      if (key == LogicalKeyboardKey.keyS || key == LogicalKeyboardKey.slash)
        command = LauncherRemoteCommand.search;
      if (key == LogicalKeyboardKey.keyQ)
        command = LauncherRemoteCommand.settings;
      if (key == LogicalKeyboardKey.keyV) command = LauncherRemoteCommand.voice;
      if (key == LogicalKeyboardKey.keyM)
        command = LauncherRemoteCommand.options;
    }
    if (!back && command == null) return false;
    // Consume repeats and releases, but only act once on the initial press.
    if (event is! KeyDownEvent) return true;
    final navigator = widget.navigatorKey.currentState;
    if (back) {
      if (navigator?.canPop() ?? false) {
        navigator!.maybePop();
      } else {
        widget.controller.send(LauncherRemoteCommand.home);
      }
    } else {
      navigator?.popUntil((route) => route.isFirst);
      widget.controller.send(command!);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
