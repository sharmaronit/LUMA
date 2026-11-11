import 'package:flutter/material.dart';
import 'glass_surface.dart';

/// Shared, stable geometry for typing and voice. Results do not resize the panel.
class FloatingSearchPanel extends StatelessWidget {
  const FloatingSearchPanel({
    super.key,
    required this.child,
    required this.mode,
    this.blurBuilder,
  });
  final Widget child;
  final LauncherMaterial mode;
  final GlassBlurBuilder? blurBuilder;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: 850,
      height: (MediaQuery.sizeOf(context).height * .8).clamp(280.0, 640.0),
      child: GlassSurface(
        mode: mode,
        sheet: true,
        radius: 28,
        blurBuilder: blurBuilder,
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.viewInsetsOf(context).bottom > 0 ? 16 : 24,
          ),
          child: child,
        ),
      ),
    ),
  );
}
