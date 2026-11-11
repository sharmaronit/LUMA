import '../models/watch_next_item.dart';
import 'programme_library.dart';
import 'programme_browser.dart';
import 'package:flutter/material.dart';
import 'glass_surface.dart';
import 'programme_rail.dart';
import 'menu_dialog.dart';
import 'motion.dart';

/// Fictional programmes: a visual fixture, never a TV provider's viewing data.
class PreviewShows extends StatelessWidget {
  const PreviewShows({super.key});

  static const shows = [
    (
      'Beyond the Peaks',
      'S1 E3 · The hidden valley',
      'Documentary · 4K',
      'assets/wallpapers/alpine-lake.jpg',
      .62,
      '18 min left',
    ),
    (
      'Wild Earth',
      'S2 E1 · Into the forest',
      'Nature · 4K',
      'assets/wallpapers/forest.jpg',
      .28,
      '32 min left',
    ),
    (
      'Coastlines',
      'S1 E5 · Where oceans meet',
      'Travel · HD',
      'assets/wallpapers/coast.jpg',
      .81,
      '9 min left',
    ),
    (
      'The Quiet Planet',
      'S1 E2 · Sands of time',
      'Documentary · 4K',
      'assets/wallpapers/desert.jpg',
      .45,
      '24 min left',
    ),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Demo library',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: MinimalPalette.of(context).text,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Sample shows and progress · real TV results depend on supported apps.',
        style: TextStyle(fontSize: 12, color: MinimalPalette.of(context).muted),
      ),
      const SizedBox(height: 20),
      ProgrammeRail(
        itemCount: shows.length,
        itemBuilder: (context, index) {
          final show = shows[index];
          return ProgrammeCard(
            key: ValueKey('demo-show-$index'),
            title: show.$1,
            subtitle: show.$2,
            footer: '${show.$6} · ${show.$3}',
            progress: show.$5,
            artwork: AssetImage(show.$4),
            onPressed: () => showLumaDialog<void>(
              context: context,
              builder: (dialogContext) => LumaMenuDialog(
                title: Text(show.$1),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        show.$4,
                        width: 480,
                        height: 220,
                        fit: BoxFit.cover,
                        cacheWidth: 720,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(show.$2),
                    const SizedBox(height: 8),
                    Text('${show.$3} · ${show.$6}'),
                    const SizedBox(height: 16),
                    const Text(
                      'Demo programme. On your TV, selecting a supported programme opens its streaming app.',
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );
}

/// Official promotional stills for layout preview, not account recommendations.
/// Source attribution: docs/preview-programme-artwork.md.
class PreviewArtworkShelf extends StatelessWidget {
  const PreviewArtworkShelf({super.key});
  static const programmes = [
    ('Wednesday', 'Netflix', 'wednesday'),
    ('Fallout', 'Prime Video', 'fallout'),
    ('ONE PIECE', 'Netflix', 'one-piece'),
    ('Reacher', 'Prime Video', 'reacher'),
  ];
  static void register() {
    final library = ProgrammeLibrary.shared;
    library.refreshSources = null;
    library.requestSourceAccess = null;
    library.registerSources({});
    library.launch = (entry, appOnly) async => false;
    library.replace([
      for (var i = 0; i < programmes.length; i++)
        ProgrammeEntry(
          WatchNextItem(
            id: i,
            title: programmes[i].$1,
            packageName: 'preview.${programmes[i].$2}',
            contentId: programmes[i].$3,
            description:
                'Promotional artwork preview. Playback is available only on Android with supported apps.',
          ),
          programmes[i].$2,
          asset: 'assets/preview/show-${programmes[i].$3}.jpg',
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => const ProgrammeShelf(
    title: 'From your apps',
    caption: 'Artwork preview · sample titles, not your viewing history',
  );
}
