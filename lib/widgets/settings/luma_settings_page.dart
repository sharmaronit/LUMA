import 'package:luma/ronits/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'luma_about_dialog.dart';
import '../../ronits/focus_feedback.dart';
import '../../ronits/menu_dialog.dart';
import '../../ronits/configured_first_run.dart';
import '../../ronits/tv_remote_slider.dart';

/// Kept for legacy routes; modern settings embed the two sections directly.
class LumaSettingsPage extends StatelessWidget {
  const LumaSettingsPage({super.key});
  static const routeName = 'luma_settings';
  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Text(
        'Luma Settings',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      Expanded(
        child: SingleChildScrollView(
          child: Column(children: [LumaSoundSettings(), LumaAboutSettings()]),
        ),
      ),
    ],
  );
}

class LumaSoundSettings extends StatelessWidget {
  const LumaSoundSettings({super.key});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Consumer<SettingsService>(
        builder: (context, settings, _) => Column(
          children: [
            TvMenuRow(
              key: const ValueKey('setting-navigation-sounds'),
              autofocus: true,
              icon: Icons.music_note_rounded,
              title: 'Navigation sounds',
              subtitle: 'Soft tones when moving and selecting',
              selected: settings.appKeyClickEnabled,
              trailing: Icon(
                settings.appKeyClickEnabled
                    ? Icons.toggle_on
                    : Icons.toggle_off,
              ),
              onPressed: () =>
                  settings.setAppKeyClickEnabled(!settings.appKeyClickEnabled),
            ),
            ListTile(
              title: const Text('Navigation volume'),
              subtitle: Text(
                '${(settings.navigationSoundVolume * 100).round()}% of system volume',
              ),
            ),
            TvRemoteSlider(
              semanticFormatterCallback: (value) =>
                  '${(value * 100).round()} percent',
              value: settings.navigationSoundVolume,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: settings.appKeyClickEnabled
                  ? settings.setNavigationSoundVolume
                  : null,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('preview-navigation-sound'),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.focused)
                        ? Colors.white.withValues(alpha: .16)
                        : Colors.transparent,
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Preview sound'),
                onPressed:
                    settings.appKeyClickEnabled &&
                        settings.navigationSoundVolume > 0
                    ? () async {
                        try {
                          await const MethodChannel(
                            'app.luma.tvlauncher/method',
                          ).invokeMethod<void>('playNavigationSound', {
                            'sound': 'select',
                            'volume': settings.navigationSoundVolume,
                          });
                        } catch (_) {
                          if (context.mounted)
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Sound preview is unavailable on this device.',
                                ),
                              ),
                            );
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class LumaAboutSettings extends StatelessWidget {
  const LumaAboutSettings({super.key});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TvMenuRow(
        autofocus: true,
        icon: Icons.help_rounded,
        title: 'User guide & setup',
        onPressed: () => showLumaDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => ConfiguredFirstRunGuide(
            onComplete: () async {
              Navigator.pop(dialogContext);
            },
          ),
        ),
      ),
      TvMenuRow(
        icon: Icons.bug_report_rounded,
        title: 'Report a problem',
        onPressed: () => showLumaDialog<void>(
          context: context,
          builder: (dialogContext) => LumaMenuDialog(
            title: const Text('Report a problem'),
            content: const Text(
              'Copy the template below, fill in what happened and send it with your report. '
              'It includes your Luma version; add your TV model and the steps that led to the problem. '
              'For what Luma stores and when it goes online, see Privacy.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final info = await PackageInfo.fromPlatform();
                  await Clipboard.setData(
                    ClipboardData(
                      text:
                          'Luma ${info.version} (${info.buildNumber})\nDevice:\nAndroid version:\nDisplay resolution / Hz:\nTheme:\nSteps to reproduce:\nExpected:\nActual:\n',
                    ),
                  );
                  if (dialogContext.mounted)
                    ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                      const SnackBar(
                        content: Text('Bug report template copied'),
                      ),
                    );
                },
                child: const Text('Copy report template'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
      TvMenuRow(
        icon: Icons.info_rounded,
        title: 'About Luma & open-source credits',
        onPressed: () async {
          final info = await PackageInfo.fromPlatform();
          if (context.mounted)
            showLumaDialog<void>(
              context: context,
              builder: (_) => LumaAboutDialog(packageInfo: info),
            );
        },
      ),
    ],
  );
}
