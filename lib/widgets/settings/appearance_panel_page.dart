import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import '../../ronits/glass_surface.dart';
import 'package:provider/provider.dart';

class AppearancePanelPage extends StatelessWidget {
  static const String routeName = "appearance_panel";

  const AppearancePanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final settingsService = Provider.of<SettingsService>(context);

    return Column(
      children: [
        Text(
          localizations.appearanceSettings,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              RadioGroup<String>(
                groupValue: settingsService.launcherMaterial,
                onChanged: (value) {
                  if (value != null) settingsService.setLauncherMaterial(value);
                },
                child: Column(
                  children: [
                    for (final mode in LauncherMaterial.values)
                      RadioListTile<String>(
                        title: Text(mode.label),
                        value: mode.name,
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('New TV home'),
                value: settingsService.useRonitsHome,
                onChanged: settingsService.setUseRonitsHome,
              ),
              SwitchListTile(
                title: const Text('Reduce motion'),
                value: settingsService.reduceMotion,
                onChanged: settingsService.setReduceMotion,
              ),
              SwitchListTile(
                title: const Text('Performance mode'),
                subtitle: const Text(
                  'Shared lightweight blur. Turn off for live glass (higher GPU use).',
                ),
                value: settingsService.performanceMode,
                onChanged: settingsService.setPerformanceMode,
              ),

              if (!settingsService.useRonitsHome) ...[
                RoundedSwitchListTile(
                  autofocus: true,
                  value: !settingsService.dockBackdropFilterDisabled,
                  onChanged: (value) =>
                      settingsService.setDockBackdropFilterDisabled(!value),
                  title: Text(
                    localizations.dockBlur,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  secondary: const Icon(Icons.blur_circular),
                ),
                RoundedSwitchListTile(
                  value: !settingsService.backgroundBlurDisabled,
                  onChanged: (value) =>
                      settingsService.setBackgroundBlurDisabled(!value),
                  title: Text(
                    localizations.backgroundBlur,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  secondary: const Icon(Icons.blur_on),
                ),
                RoundedSwitchListTile(
                  value: settingsService.dockShadowEnabled,
                  onChanged: settingsService.setDockShadowEnabled,
                  title: Text(
                    localizations.dockShadow,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  secondary: const Icon(Icons.layers),
                ),
                RoundedSwitchListTile(
                  value: settingsService.dockDarkBackground,
                  onChanged: settingsService.setDockDarkBackground,
                  title: Text(
                    localizations.dockDarkBackground,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  secondary: const Icon(Icons.dark_mode),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
