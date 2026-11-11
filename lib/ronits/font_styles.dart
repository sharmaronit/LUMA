import 'package:flutter/material.dart';

class LauncherFont {
  const LauncherFont(this.id, this.name, this.family);
  final String id, name, family;

  /// The family as people know it: 'PlusJakartaSans' -> 'Plus Jakarta Sans'.
  String get familyLabel => family.replaceAllMapped(
    RegExp(r'(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])'),
    (_) => ' ',
  );
}

const launcherFonts = [
  LauncherFont('current', 'Luma', 'Inter'),
  LauncherFont('rounded', 'Rounded', 'Nunito'),
  LauncherFont('geometric', 'Geometric', 'Manrope'),
  LauncherFont('classic', 'Classic', 'Lora'),
  LauncherFont('modern', 'Modern', 'Figtree'),
  LauncherFont('elegant', 'Elegant', 'PlusJakartaSans'),
  LauncherFont('display', 'Display', 'Outfit'),
  LauncherFont('soft', 'Soft', 'DMSans'),
];
LauncherFont launcherFont(String? id) =>
    launcherFonts.where((font) => font.id == id).firstOrNull ??
    launcherFonts.first;
ThemeData launcherFontTheme(ThemeData theme, String? id) {
  final family = launcherFont(id).family;
  final button = theme.textButtonTheme.style;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: family),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: family),
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle:
          (theme.dialogTheme.titleTextStyle ?? theme.textTheme.titleLarge)
              ?.copyWith(fontFamily: family),
      contentTextStyle:
          (theme.dialogTheme.contentTextStyle ?? theme.textTheme.bodyMedium)
              ?.copyWith(fontFamily: family),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      labelStyle:
          (theme.inputDecorationTheme.labelStyle ?? theme.textTheme.bodyMedium)
              ?.copyWith(fontFamily: family),
      hintStyle: theme.inputDecorationTheme.hintStyle?.copyWith(
        fontFamily: family,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (button ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStateProperty.resolveWith(
          (states) => (button?.textStyle?.resolve(states) ?? const TextStyle())
              .copyWith(fontFamily: family),
        ),
      ),
    ),
  );
}
