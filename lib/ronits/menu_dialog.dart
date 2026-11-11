import 'package:flutter/material.dart';
import 'glass_surface.dart';
import 'motion.dart';
import 'menu_focus.dart';
import 'scroll_edge_fade.dart';

/// Compact app actions stay beside their source card instead of centring a sheet.
Future<T?> showAppMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required String title,
  required WidgetBuilder builder,
  bool reducedMotion = false,
}) async {
  final target = FocusManager.instance.primaryFocus;
  final parent = target?.context == null
      ? ModalRoute.of(context)
      : ModalRoute.of(target!.context!);
  final revision = menuFocusRevision;
  final route = RawDialogRoute<T>(
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: motionReduced(context, reducedMotion)
        ? Duration.zero
        : const Duration(milliseconds: 140),
    pageBuilder: (context, _, __) => CustomSingleChildLayout(
      delegate: _AppMenuPosition(anchor),
      child: KeyedSubtree(
        key: const ValueKey('anchored-app-menu'),
        child: GlassSurface(
          mode:
              MenuAppearanceScope.of(context)?.mode ?? LauncherMaterial.minimal,
          sheet: true,
          radius: lumaPanelRadius,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ScrollEdgeFade(
                    backdropFade: false,
                    child: SingleChildScrollView(child: builder(context)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, animation, __, child) => MenuSlideTransition(
      animation: animation,
      begin: const Offset(0, 8),
      child: child,
    ),
  );
  final result = await Navigator.of(
    context,
    rootNavigator: true,
  ).push<T>(route);
  await route.completed;
  restoreMenuFocus(target, parent, revision: revision);
  return result;
}

class _AppMenuPosition extends SingleChildLayoutDelegate {
  _AppMenuPosition(this.anchor);
  final Rect anchor;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - 32).clamp(0, 260),
        maxHeight: (constraints.maxHeight - 32).clamp(0, 420),
      );
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = anchor.bottom + 8;
    final top = below + childSize.height <= size.height - 16
        ? below
        : anchor.top - childSize.height - 8;
    return Offset(
      anchor.left.clamp(
        16,
        (size.width - childSize.width - 16).clamp(16, double.infinity),
      ),
      top.clamp(
        16,
        (size.height - childSize.height - 16).clamp(16, double.infinity),
      ),
    );
  }

  @override
  bool shouldRelayout(_AppMenuPosition old) => old.anchor != anchor;
}

/// TV-sized dialog with the same surface as quick settings, including submenus.
class LumaMenuDialog extends StatelessWidget {
  const LumaMenuDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
  });
  final Widget? title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight:
            MediaQuery.sizeOf(context).height -
            48 -
            MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: GlassSurface(
        mode: LauncherMaterial.ronits,
        sheet: true,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                    ),
                    child: title!,
                  ),
                ),
              if (content != null)
                Flexible(
                  child: ScrollEdgeFade(
                    backdropFade: false,
                    child: SingleChildScrollView(child: content!),
                  ),
                ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
