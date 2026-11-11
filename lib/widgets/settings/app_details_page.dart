import 'package:luma/ronits/motion.dart';
import '../../ronits/menu_undo.dart';
import 'app_change_undo.dart';

import 'dart:typed_data';

import 'package:luma/models/app.dart';
import 'package:luma/models/category.dart';
import 'package:luma/providers/apps_service.dart';
import 'package:luma/widgets/add_to_category_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:luma/l10n/app_localizations.dart';

class AppDetailsPage extends StatefulWidget {
  static const String routeName = "app_details_page";

  final App application;

  const AppDetailsPage({Key? key, required this.application}) : super(key: key);

  @override
  State<AppDetailsPage> createState() => _AppDetailsPageState();
}

class _AppDetailsPageState extends State<AppDetailsPage> {
  App get application => widget.application;
  MenuUndo? undo;
  bool busy = false;
  String? error;
  Future<void> change(Future<MenuUndo?> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await action();
      if (mounted) setState(() => undo = result);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    AppsService appsService = context.watch<AppsService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FutureBuilder<Uint8List>(
              future: appsService.getAppIcon(application.packageName),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Image.memory(snapshot.data!, width: 50, height: 50);
                }
                return const Icon(Icons.android, size: 50);
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    application.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    "v${application.version}",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        if (error != null) Text(error!),
        if (undo != null)
          MenuUndoNotice(
            undo: undo!,
            onBusyChanged: (value) => setState(() => busy = value),
            onRestored: () => setState(() => undo = null),
          ),
        Expanded(
          child: ListView(
            children: [
              _buildListTile(
                context,
                icon: Icons.open_in_new,
                title: localizations.open,
                onTap: () async {
                  await appsService.launchApp(application);
                  Navigator.of(
                    context,
                  ).pop(); // Close settings after launch? Or stay? Dialog behavior was close.
                },
              ),
              _buildListTile(
                context,
                icon: appsService.isAppInFavorites(application)
                    ? Icons.star
                    : Icons.star_border,
                title: appsService.isAppInFavorites(application)
                    ? 'Remove from Fav'
                    : 'Add to Fav',
                onTap: () => change(
                  () => toggleFavoriteWithUndo(appsService, application),
                ),
              ),
              _buildListTile(
                context,
                icon: application.hidden
                    ? Icons.visibility
                    : Icons.visibility_off_outlined,
                title: application.hidden
                    ? localizations.show
                    : localizations.hide,
                onTap: () => change(
                  () => toggleHiddenWithUndo(appsService, application),
                ),
              ),
              if (!application.hidden)
                _buildListTile(
                  context,
                  icon: Icons.add_box_outlined,
                  title: "Add to Category", // Need localization or string
                  onTap: () => showLumaDialog<Category>(
                    context: context,
                    builder: (_) => AddToCategoryDialog(application),
                  ),
                ),
              const Divider(),
              _buildListTile(
                context,
                icon: Icons.info_outlined,
                title: localizations.appInfo,
                onTap: () => appsService.openAppInfo(application),
              ),
              _buildListTile(
                context,
                icon: Icons.delete_outlined,
                title: localizations.uninstall,
                onTap: () async {
                  await appsService.uninstallApp(application);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      // Add hover/focus color if needed, but default ListTile focus usually works.
      // We can enhance it later if the user requests specific aesthetics for these details too.
    );
  }
}
