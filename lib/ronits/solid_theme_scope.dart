import 'package:flutter/material.dart';

const solidThemeColors = <({String name, String hex})>[
  (name: 'Charcoal', hex: '1B1C1E'),
  (name: 'Deep black', hex: '000000'),
  (name: 'Midnight', hex: '172638'),
  (name: 'Graphite', hex: '24262B'),
  (name: 'Ocean', hex: '143A52'),
  (name: 'Forest', hex: '183C32'),
  (name: 'Plum', hex: '392640'),
  (name: 'Burgundy', hex: '482731'),
  (name: 'Espresso', hex: '3B3028'),
  (name: 'Slate', hex: '3D4858'),
];
Color solidThemeColor(String? hex) => Color(
  int.parse(
    'FF${solidThemeColors.any((item) => item.hex == hex) ? hex : solidThemeColors.first.hex}',
    radix: 16,
  ),
);

class SolidThemeScope extends InheritedWidget {
  const SolidThemeScope({super.key, required this.color, required super.child});
  final Color color;
  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SolidThemeScope>()?.color ??
      solidThemeColor(null);
  @override
  bool updateShouldNotify(SolidThemeScope oldWidget) =>
      color != oldWidget.color;
}
