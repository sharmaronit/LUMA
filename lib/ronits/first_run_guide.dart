import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'menu_dialog.dart';

/// A short setup that works with a TV remote and never requires permissions.
class FirstRunGuide extends StatefulWidget {
  const FirstRunGuide({
    super.key,
    required this.onComplete,
    this.onChooseFavorites,
    this.onBackgroundChanged,
    this.onSoundsChanged,
    this.initialBackground = 'glass',
    this.initialSounds = true,
    this.soundVolume = .35,
  });
  final Future<void> Function() onComplete;
  final Future<void> Function()? onChooseFavorites;
  final Future<void> Function(String)? onBackgroundChanged;
  final Future<void> Function(bool)? onSoundsChanged;
  final String initialBackground;
  final bool initialSounds;
  final double soundVolume;
  @override
  State<FirstRunGuide> createState() => _FirstRunGuideState();
}

class _FirstRunGuideState extends State<FirstRunGuide>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('app.luma.tvlauncher/method');
  static const titles = [
    'Welcome to Luma',
    'Choose your favourites',
    'Make it feel yours',
    'Make Luma your Home',
    'Your Home is ready',
  ];
  final nextFocus = FocusNode(debugLabel: 'Setup continue');
  int step = 0;
  bool busy = false;
  late bool sounds = widget.initialSounds;
  late String background = widget.initialBackground;
  Map<String, dynamic> status = {};
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    nextFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    try {
      final value = await channel.invokeMapMethod<String, dynamic>(
        'getSetupStatus',
      );
      if (mounted) setState(() => status = value ?? {});
    } catch (_) {
      /* Unsupported TV features never block setup. */
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await refresh();
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not complete that action. You can continue and try again in Settings.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void move(int value) {
    setState(() {
      step = value;
      error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) nextFocus.requestFocus();
    });
  }

  Widget option(
    String label,
    Future<void> Function()? action, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: OutlinedButton(
      onPressed: busy || action == null ? null : () => run(action),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            const Icon(Icons.check_rounded, size: 18),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(label)),
        ],
      ),
    ),
  );

  @override
  // Back is handled once, at route level. A Back key shortcut as well made a
  // single press both close the guide and act on the screen underneath it.
  Widget build(BuildContext context) => Builder(
    builder: (context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) {
          if (step > 0) {
            move(step - 1);
          } else {
            run(widget.onComplete);
          }
        }
      },
      child: LumaMenuDialog(
        title: Text(titles[step]),
        content: SizedBox(
          width: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Step ${step + 1} of ${titles.length}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 16),
              if (step == 0)
                const Text(
                  'Use Left and Right to move within a row. Press Down to see programme cards from your apps.\n\n'
                  'Press OK to open. Hold OK, or press Menu, for quick actions, favourites and artwork.\n\n'
                  'Press Back to go back one screen. Open quick settings and Luma Settings by selecting the clock. The bell shows your notifications.',
                ),
              if (step == 1) ...[
                const Text(
                  'Choose the apps you want in your dock. You can add as many as you like; scroll left and right to see them.\n\n'
                  'Later, hold OK on an app and choose Move. Use the arrows to rearrange it; each move saves automatically.',
                ),
                option('Choose dock apps', widget.onChooseFavorites),
              ],
              if (step == 2) ...[
                const Text(
                  'Choose your menu appearance and gentle navigation sounds. You can change both later.',
                ),
                option(
                  'Liquid glass',
                  widget.onBackgroundChanged == null
                      ? null
                      : () async {
                          await widget.onBackgroundChanged!('glass');
                          if (mounted) setState(() => background = 'glass');
                        },
                  selected: background == 'glass' || background == 'glass-real',
                ),
                option(
                  'Simple dark',
                  widget.onBackgroundChanged == null
                      ? null
                      : () async {
                          await widget.onBackgroundChanged!('charcoal');
                          if (mounted) setState(() => background = 'charcoal');
                        },
                  selected: background == 'charcoal',
                ),
                option(
                  sounds ? 'Navigation sounds: On' : 'Navigation sounds: Off',
                  widget.onSoundsChanged == null
                      ? null
                      : () async {
                          await widget.onSoundsChanged!(!sounds);
                          if (mounted) setState(() => sounds = !sounds);
                        },
                ),
                option(
                  'Preview sound',
                  sounds
                      ? () async {
                          await channel.invokeMethod('playNavigationSound', {
                            'sound': 'select',
                            'volume': widget.soundVolume,
                          });
                        }
                      : null,
                ),
              ],
              if (step == 3) ...[
                Text(
                  status['home'] == true
                      ? 'Luma already opens with the Home button on your remote.'
                      : 'Choose Luma in the Android Home app screen, then return here.\n\n'
                            'Some TVs lock their original launcher. If the Home button still opens it, extra device setup may be needed.',
                ),
                option(
                  status['home'] == true
                      ? 'Luma is your Home'
                      : 'Choose default Home app',
                  status['home'] == true
                      ? null
                      : () async {
                          await channel.invokeMethod(
                            'requestSetupPermission',
                            'home',
                          );
                        },
                  selected: status['home'] == true,
                ),
              ],
              if (step == 4) ...[
                const Text(
                  'Enjoy your new Home.\n\n'
                  'Hold OK on an app, then choose Quick actions to see what it supports. '
                  'Use Down for From your apps and Settings.\n\n'
                  'Microphone, photos and TV content access are optional. Luma asks when you use a feature that needs them. '
                  'You can reopen this setup from Settings > About > User guide & setup.',
                ),
              ],
              if (error != null) ...[const SizedBox(height: 12), Text(error!)],
            ],
          ),
        ),
        actions: [
          if (step > 0)
            TextButton(
              onPressed: busy ? null : () => move(step - 1),
              child: const Text('Back'),
            ),
          if (step < titles.length - 1)
            TextButton(
              onPressed: busy ? null : () => run(widget.onComplete),
              child: const Text('Set up later'),
            ),
          FilledButton(
            focusNode: nextFocus,
            autofocus: true,
            onPressed: busy
                ? null
                : () {
                    if (step == titles.length - 1) {
                      run(widget.onComplete);
                    } else {
                      move(step + 1);
                    }
                  },
            child: Text(step == titles.length - 1 ? 'Start Luma' : 'Continue'),
          ),
        ],
      ),
    ),
  );
}
