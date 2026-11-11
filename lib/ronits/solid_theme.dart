import 'package:flutter/material.dart';
import 'focus_feedback.dart';
import 'glass_surface.dart';
import 'motion.dart';
import 'solid_theme_scope.dart';
export 'solid_theme_scope.dart';

Future<void> showSolidThemeColors(
  BuildContext context, {
  required ValueChanged<String> onChanged,
}) => showLumaDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => Dialog(
    backgroundColor: Colors.transparent,
    child: SizedBox(
      width: 400,
      height: 430,
      child: GlassSurface(
        mode: LauncherMaterial.solid,
        sheet: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Minimal background colour',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Back to settings',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Choose a matte background. Dark shades keep text readable.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FocusHighlightLayer(
                menu: true,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    for (final item in solidThemeColors)
                      TvMenuRow(
                        autofocus: item == solidThemeColors.first,
                        title: item.name,
                        selected:
                            SolidThemeScope.of(context) ==
                            solidThemeColor(item.hex),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (SolidThemeScope.of(context) ==
                                solidThemeColor(item.hex))
                              const Icon(Icons.check_rounded),
                            const SizedBox(width: 12),
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: solidThemeColor(item.hex),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white54),
                              ),
                            ),
                          ],
                        ),
                        onPressed: () => onChanged(item.hex),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
