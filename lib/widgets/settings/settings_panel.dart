import '../../ronits/menu_focus.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_service.dart';
import '../../ronits/motion.dart';
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

import 'package:luma/widgets/side_panel_dialog.dart';
import 'package:luma/widgets/settings/applications_panel_page.dart';
import 'package:luma/widgets/settings/launcher_sections_panel_page.dart';
import 'package:luma/widgets/settings/gradient_panel_page.dart';
import 'package:luma/widgets/settings/launcher_section_panel_page.dart';
import 'package:luma/widgets/settings/settings_panel_page.dart';
import 'package:luma/widgets/settings/status_bar_panel_page.dart';
import 'package:luma/widgets/settings/wallpaper_panel_page.dart';
import 'package:luma/widgets/settings/wifi_usage_period_page.dart';
import 'package:luma/widgets/settings/back_button_action_page.dart';
import 'package:luma/widgets/settings/date_time_format_page.dart';
import 'package:luma/widgets/settings/app_details_page.dart';
import 'package:luma/widgets/settings/accent_color_page.dart';
import 'package:luma/widgets/settings/brightness_settings_page.dart';
import 'package:luma/widgets/settings/appearance_panel_page.dart';
import 'package:luma/widgets/settings/misc_panel_page.dart';
import 'package:luma/widgets/settings/interface_settings_page.dart';
import 'package:luma/widgets/settings/general_settings_page.dart';
import 'package:luma/widgets/settings/screensaver_clock_style_page.dart';
import 'package:luma/models/app.dart';
import 'package:flutter/material.dart';
import 'luma_settings_page.dart';

class SettingsPanel extends StatefulWidget {
  final String? initialRoute;

  const SettingsPanel({Key? key, this.initialRoute}) : super(key: key);

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final _focusObserver = MenuFocusObserver();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !await _navigatorKey.currentState!.maybePop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Tap outside to close
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
            // The side panel
            SidePanelDialog(
              width: 350,
              isRightSide: false,
              child: Navigator(
                key: _navigatorKey,
                observers: [_focusObserver],
                initialRoute:
                    widget.initialRoute ?? SettingsPanelPage.routeName,
                onGenerateInitialRoutes: (navigator, name) => [
                  navigator.widget.onGenerateRoute!(RouteSettings(name: name))!,
                ],
                onGenerateRoute: (settings) {
                  switch (settings.name) {
                    case LumaSettingsPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => const LumaSettingsPage(),
                      );
                    case SettingsPanelPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => SettingsPanelPage(),
                      );
                    case GeneralSettingsPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => GeneralSettingsPage(),
                      );
                    case InterfaceSettingsPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => InterfaceSettingsPage(),
                      );
                    case WallpaperPanelPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => WallpaperPanelPage(),
                      );
                    case StatusBarPanelPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => StatusBarPanelPage(),
                      );
                    case GradientPanelPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => GradientPanelPage(),
                      );
                    case ApplicationsPanelPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => ApplicationsPanelPage(),
                      );
                    case LauncherSectionsPanelPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => LauncherSectionsPanelPage(),
                      );
                    case LauncherSectionPanelPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => LauncherSectionPanelPage(
                          sectionIndex: settings.arguments as int?,
                        ),
                      );
                    case WifiUsagePeriodPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => WifiUsagePeriodPage(),
                      );
                    case BackButtonActionPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => BackButtonActionPage(),
                      );
                    case DateTimeFormatPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => DateTimeFormatPage(),
                      );
                    case AppearancePanelPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => const AppearancePanelPage(),
                      );
                    case MiscPanelPage.routeName:
                      return _FastPageRoute(builder: (_) => MiscPanelPage());
                    case ScreensaverClockStylePage.routeName:
                      return _FastPageRoute(
                        builder: (_) => const ScreensaverClockStylePage(),
                      );
                    case AccentColorPage.routeName:
                      return _FastPageRoute(builder: (_) => AccentColorPage());
                    case BrightnessSettingsPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => BrightnessSettingsPage(),
                      );
                    case AppDetailsPage.routeName:
                      return _FastPageRoute(
                        builder: (_) => AppDetailsPage(
                          application: settings.arguments as App,
                        ),
                      );
                    default:
                      throw ArgumentError.value(
                        settings.name,
                        "settings.name",
                        "Route not supported.",
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared short slide-only motion for nested settings pages.
class _FastPageRoute<T> extends MaterialPageRoute<T> {
  _FastPageRoute({required super.builder});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (motionReduced(context, context.read<SettingsService>().reduceMotion))
      return child;
    return MenuSlideTransition(
      animation: animation,
      begin: const Offset(18, 0),
      child: child,
    );
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);
}
