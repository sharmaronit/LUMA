import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/cinematic_backdrop.dart';
import 'package:luma/ronits/programme_rail.dart';
import 'package:luma/ronits/prepared_backdrop_scope.dart';

void main() {
  testWidgets('focused programme cards drive the cinematic layer', (
    tester,
  ) async {
    final focus = FocusNode();
    final second = FocusNode();
    const image = AssetImage('assets/tv-icons/netflix.png');
    await tester.pumpWidget(
      MaterialApp(
        home: PreparedBackdropScope(
          image: null,
          origin: GlobalKey(),
          fallback: Colors.black,
          child: CinematicBackdropHost(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CinematicWallpaper(
                    child: ColoredBox(color: Colors.black),
                  ),
                ),
                const Positioned.fill(child: CinematicBackdropLayer()),
                Column(
                  children: [
                    SizedBox(
                      width: 300,
                      height: 190,
                      child: ProgrammeCard(
                        title: 'Show',
                        artwork: image,
                        focusNode: focus,
                        onPressed: () {},
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      height: 190,
                      child: ProgrammeCard(
                        title: 'Next',
                        artwork: image,
                        focusNode: second,
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        ResizeImage(
          image,
          width: 960,
          policy: ResizeImagePolicy.fit,
          allowUpscaling: false,
        ),
        tester.element(find.byType(ProgrammeCard).first),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CinematicBackdropLayer),
        matching: find.byType(RawImage),
      ),
      findsOneWidget,
    );
    final rendered = tester.widget<RawImage>(
      find.descendant(
        of: find.byType(CinematicBackdropLayer),
        matching: find.byType(RawImage),
      ),
    );
    final edges = PreparedBackdropScope.of(
      tester.element(find.byType(ProgrammeCard).first),
    );
    expect(
      edges?.image,
      same(rendered.image),
      reason:
          'Edge fades use the cinematic texture instead of the original wallpaper',
    );
    second.requestFocus();
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CinematicBackdropLayer),
        matching: find.byType(RawImage),
      ),
      findsOneWidget,
    );
    focus.requestFocus();
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CinematicBackdropLayer),
        matching: find.byType(RawImage),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    second.dispose();
  });
  testWidgets('backdrop waits for settled focus and clears outside cards', (
    tester,
  ) async {
    late BuildContext source;
    const image = AssetImage('assets/tv-icons/netflix.png');
    await tester.pumpWidget(
      MaterialApp(
        home: CinematicBackdropHost(
          child: Stack(
            children: [
              const Positioned.fill(
                child: CinematicWallpaper(
                  child: ColoredBox(color: Colors.black),
                ),
              ),
              const Positioned.fill(child: CinematicBackdropLayer()),
              Builder(
                builder: (context) {
                  source = context;
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        ResizeImage(
          image,
          width: 960,
          policy: ResizeImagePolicy.fit,
          allowUpscaling: false,
        ),
        source,
      ),
    );
    Finder backdropImages() => find.descendant(
      of: find.byType(CinematicBackdropLayer),
      matching: find.byType(RawImage),
    );
    const ProgrammeArtworkFocus(image).dispatch(source);
    await tester.pump(const Duration(milliseconds: 300));
    expect(backdropImages(), findsNothing);
    // Rapid movement cancels the pending artwork instead of flashing it.
    const ProgrammeArtworkFocus(null).dispatch(source);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(backdropImages(), findsNothing);
    const ProgrammeArtworkFocus(image).dispatch(source);
    await tester.pump(const Duration(milliseconds: 451));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(backdropImages(), findsOneWidget);
    const ProgrammeArtworkFocus(null).dispatch(source);
    await tester.pump(const Duration(milliseconds: 451));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(backdropImages(), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
