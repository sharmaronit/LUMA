import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/apps_service.dart';
import '../providers/settings_service.dart';
import 'first_run_guide.dart';
import 'menu_dialog.dart';
import 'motion.dart';
import 'focus_feedback.dart';

/// Shared by automatic first run and the Settings entry, with live preferences.
class ConfiguredFirstRunGuide extends StatelessWidget {
  const ConfiguredFirstRunGuide({super.key, required this.onComplete});
  final Future<void> Function() onComplete;
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    return FirstRunGuide(
      onComplete: onComplete,
      initialBackground: settings.selectedMinimalBackground,
      initialSounds: settings.appKeyClickEnabled,
      soundVolume: settings.navigationSoundVolume,
      onBackgroundChanged: settings.setMinimalBackground,
      onSoundsChanged: settings.setAppKeyClickEnabled,
      onChooseFavorites: () => showLumaDialog<void>(
        context: context,
        builder: (dialogContext) => Consumer<AppsService>(
          builder: (_, service, __) => LumaMenuDialog(
            title: const Text('Choose dock apps'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Press OK to add or remove an app. Your changes save immediately.',
                ),
                const SizedBox(height: 12),
                for (final (index, app) in service.applications.indexed)
                  TvMenuRow(
                    key: ValueKey('setup-favourite-${app.packageName}'),
                    autofocus: index == 0,
                    title: app.name,
                    selected: service.isAppInFavorites(app),
                    trailing: Icon(
                      service.isAppInFavorites(app)
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                    ),
                    onPressed: () async {
                      try {
                        if (service.isAppInFavorites(app)) {
                          await service.removeFromFavorites(app);
                        } else {
                          await service.addToFavorites(app);
                        }
                      } catch (_) {
                        if (dialogContext.mounted)
                          ScaffoldMessenger.maybeOf(
                            dialogContext,
                          )?.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not save favourites. Please try again.',
                              ),
                            ),
                          );
                      }
                    },
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
