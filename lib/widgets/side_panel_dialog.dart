import 'package:luma/actions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_service.dart';
import '../ronits/glass_surface.dart';
import 'cached_blur_backdrop.dart';

class SidePanelDialog extends StatelessWidget {
  final Widget child;
  final double width;
  final bool isRightSide;

  const SidePanelDialog({
    required this.child,
    this.width = 250,
    this.isRightSide = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final content = SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Actions(
          actions: {BackIntent: BackAction(context)},
          child: child,
        ),
      ),
    );
    return Align(
      alignment: isRightSide ? Alignment.centerRight : Alignment.centerLeft,
      child: settings.useRonitsHome
          ? GlassSurface(
              mode: LauncherMaterial.fromName(settings.launcherMaterial),
              frostedSheet: true,
              sheet: true,
              radius: 28,
              blurBuilder: settings.performanceMode
                  ? (child, sigma, saturation) => CachedBlurBackdrop(
                      sigma: sigma,
                      saturation: saturation,
                      child: child,
                    )
                  : null,
              child: content,
            )
          : Material(
              color: const Color(0xff1e1e1e),
              elevation: 24,
              borderRadius: BorderRadius.horizontal(
                right: isRightSide ? Radius.zero : const Radius.circular(28),
                left: isRightSide ? const Radius.circular(28) : Radius.zero,
              ),
              child: content,
            ),
    );
  }
}
