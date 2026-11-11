import 'package:luma/ronits/motion.dart';
import 'package:luma/ronits/menu_dialog.dart';
import 'package:flutter/material.dart';
import 'package:luma/l10n/app_localizations.dart';

Future<void> showUpdateProgressDialog(
  BuildContext context, {
  required String label,
}) {
  return showLumaDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => LumaMenuDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(label)),
        ],
      ),
    ),
  );
}

Future<void> showNoUpdateDialog(
  BuildContext context,
  AppLocalizations localizations, {
  required String currentVersion,
}) {
  return showLumaDialog<void>(
    context: context,
    builder: (dialogContext) => LumaMenuDialog(
      title: Text(localizations.updateNoUpdateTitle),
      content: Text(localizations.updateNoUpdateBody(currentVersion)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
        ),
      ],
    ),
  );
}

Future<bool> showUpdateAvailableDialog(
  BuildContext context,
  AppLocalizations localizations, {
  required String latestVersion,
  required String currentVersion,
}) async {
  return await showLumaDialog<bool>(
        context: context,
        builder: (dialogContext) => LumaMenuDialog(
          title: Text(localizations.updateAvailableTitle),
          content: Text(
            localizations.updateAvailableBody(latestVersion, currentVersion),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(localizations.updateDownloadButton),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> showReadyToInstallDialog(
  BuildContext context,
  AppLocalizations localizations, {
  required String latestVersion,
}) async {
  return await showLumaDialog<bool>(
        context: context,
        builder: (dialogContext) => LumaMenuDialog(
          title: Text(localizations.updateReadyToInstallTitle),
          content: Text(localizations.updateReadyToInstallBody(latestVersion)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(localizations.updateInstallButton),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> showInstallPermissionDialog(
  BuildContext context,
  AppLocalizations localizations, {
  required VoidCallback onOpenPermissionSettings,
}) {
  return showLumaDialog<void>(
    context: context,
    builder: (dialogContext) => LumaMenuDialog(
      title: Text(localizations.updateInstallPermissionTitle),
      content: Text(localizations.updateInstallPermissionBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            MaterialLocalizations.of(dialogContext).cancelButtonLabel,
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onOpenPermissionSettings();
          },
          child: Text(localizations.updateOpenPermissionSettingsButton),
        ),
      ],
    ),
  );
}
