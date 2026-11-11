import 'package:luma/ronits/menu_dialog.dart';
/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:luma/l10n/app_localizations.dart';

class LumaAboutDialog extends StatelessWidget {
  final PackageInfo packageInfo;

  LumaAboutDialog({Key? key, required this.packageInfo})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return LumaMenuDialog(
      title: const Text('Luma'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('v${packageInfo.version} (${packageInfo.buildNumber})'),
          const SizedBox(height: 16),
          const Text('Created by Ronit Sharma · GPL-3.0-or-later'),
          const SizedBox(height: 16),
          Text(
            localizations.textAboutDialog(
              'https://github.com/sharmaronit/LUMA',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'Luma'),
          child: const Text('Licences & credits'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
      ],
    );
  }
}
