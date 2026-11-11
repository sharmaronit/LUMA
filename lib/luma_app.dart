import 'package:luma/ronits/profiles.dart';
import 'ronits/app_customization.dart';
import 'ronits/navigation_sounds.dart';
import 'ronits/glass_surface.dart';
import 'ronits/wallpaper_tone.dart';
import 'widgets/cached_blur_backdrop.dart';
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

import 'package:luma/actions.dart';
import 'package:luma/providers/apps_service.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/providers/launcher_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'luma.dart';
import 'ronits/native_home.dart';
import 'ronits/solid_theme_scope.dart';

class LumaApp extends StatefulWidget {
  const LumaApp({super.key});
  @override
  State<LumaApp> createState() => _LumaAppState();
}

class _LumaAppState extends State<LumaApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const PrioritizedIntents _backIntents = PrioritizedIntents(
    orderedIntents: [DismissIntent(), BackIntent()],
  );

  static const MaterialColor _swatch = MaterialColor(0xFF011526, <int, Color>{
    50: Color(0xFF36A0FA),
    100: Color(0xFF067BDE),
    200: Color(0xFF045CA7),
    300: Color(0xFF033662),
    400: Color(0xFF022544),
    500: Color(0xFF011526),
    600: Color(0xFF000508),
    700: Color(0xFF000000),
    800: Color(0xFF000000),
    900: Color(0xFF000000),
  });

  @override
  void initState() {
    super.initState();
    // Once at startup; resume and back navigation refresh it afterwards.
    // (Previously ran on every rebuild of the app root.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LauncherState>().refresh(context.read<AppsService>());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Selector<SettingsService, Color>(
      selector: (_, settings) => settings.accentColor,
      builder: (context, accentColor, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            overscroll: false,
          ),
          shortcuts: {
            ...WidgetsApp.defaultShortcuts,
            const SingleActivator(LogicalKeyboardKey.escape): _backIntents,
            const SingleActivator(LogicalKeyboardKey.gameButtonB): _backIntents,
            const SingleActivator(LogicalKeyboardKey.select):
                const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.numpadEnter):
                const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.gameButtonA):
                const ActivateIntent(),
          },
          actions: {
            ...WidgetsApp.defaultActions,
            BackIntent: BackAction(context, navigatorKey: _navigatorKey),
            DirectionalFocusIntent: SoundFeedbackDirectionalFocusAction(
              context,
            ),
          },
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          title: 'Luma',
          builder: (context, child) =>
              Selector<SettingsService, (bool, String?, String, bool, String)>(
                selector: (_, settings) => (
                  settings.reduceMotion,
                  settings.solidThemeColorHex,
                  settings.launcherMaterial,
                  settings.performanceMode,
                  settings.minimalBackground,
                ),
                builder: (context, preferences, _) => SolidThemeScope(
                  color: solidThemeColor(preferences.$2),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      disableAnimations:
                          preferences.$1 ||
                          MediaQuery.disableAnimationsOf(context),
                    ),
                    child: MenuAppearanceScope(
                      economyGlass: preferences.$4,
                      minimalBackground: preferences.$5,
                      mode: LauncherMaterial.fromName(preferences.$3),
                      blurBuilder: (child, sigma, saturation) =>
                          CachedBlurBackdrop(
                            sigma: sigma,
                            saturation: saturation,
                            child: child,
                          ),
                      child: ValueListenableBuilder<WallpaperTone>(
                        valueListenable: WallpaperTone.notifier,
                        builder: (_, tone, child) =>
                            WallpaperToneScope(tone: tone, child: child!),
                        child: NavigationSounds(
                          child: LauncherCustomization(child: child!),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          theme: ThemeData(
            fontFamily: 'Inter',
            focusColor: Colors.white.withValues(alpha: .18),
            hoverColor: Colors.white.withValues(alpha: .10),
            useMaterial3: true,
            brightness: Brightness.dark,
            // Use ColorScheme based on accent color
            colorScheme: ColorScheme.fromSeed(
              seedColor: accentColor,
              brightness: Brightness.dark,
              primary: accentColor,
              secondary: accentColor,
              surface: const Color(0xFF1E1E1E),
              background: const Color(0xFF121212),
            ),
            cardColor: const Color(0xFF1E1E1E), // Dark surface color
            canvasColor: const Color(0xFF121212),
            scaffoldBackgroundColor: const Color(0xFF121212), // Dark background
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                enableFeedback: false,
                foregroundColor:
                    Colors.white, // Revert to white for settings list
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: const ButtonStyle(enableFeedback: false),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: const ButtonStyle(enableFeedback: false),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: const ButtonStyle(enableFeedback: false),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: const Color(0xFF1E1E1E),
              titleTextStyle: Typography.material2018().white.titleLarge
                  ?.copyWith(fontFamily: 'Inter'),
              contentTextStyle: Typography.material2018().white.bodyMedium
                  ?.copyWith(fontFamily: 'Inter'),
            ),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              backgroundColor: Colors.transparent,
            ),
            typography: Typography.material2018(),
            inputDecorationTheme: InputDecorationTheme(
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
              labelStyle: Typography.material2018().white.bodyMedium?.copyWith(
                fontFamily: 'Inter',
              ),
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: accentColor,
              selectionColor: accentColor.withOpacity(0.4),
              selectionHandleColor: accentColor,
            ),
            progressIndicatorTheme: ProgressIndicatorThemeData(
              color: accentColor,
            ),
            sliderTheme: SliderThemeData(
              activeTrackColor: accentColor,
              thumbColor: accentColor,
              inactiveTrackColor: accentColor.withOpacity(0.3),
            ),
            toggleButtonsTheme: ToggleButtonsThemeData(
              selectedColor: accentColor,
              fillColor: accentColor.withOpacity(0.1),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return accentColor;
                return null;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected))
                  return accentColor.withOpacity(0.5);
                return null;
              }),
            ),
            tabBarTheme: TabBarThemeData(indicatorColor: accentColor),
          ),
          home: Builder(
            builder: (context) => PopScope(
              canPop: false,
              child: Selector<SettingsService, bool>(
                selector: (_, settings) => settings.useRonitsHome,
                // A profile switch swaps the stored settings, so the home is
                // rebuilt from scratch to read them again.
                builder: (context, modern, __) => modern
                    ? KeyedSubtree(
                        key: ValueKey(
                          'home-${context.select<ProfileService?, int>((profiles) => profiles?.generation ?? 0)}',
                        ),
                        child: const NativeLauncherHome(),
                      )
                    : Luma(),
              ),
              onPopInvoked: (didPop) {
                final settings = context.read<SettingsService>();
                if (didPop ||
                    (settings.useRonitsHome &&
                        settings.launcherMaterial == 'minimal'))
                  return;
                LauncherState launcherState = context.read<LauncherState>();
                launcherState.handleBackNavigation(context);
              },
            ),
          ),
        );
      },
    );
  }
}
