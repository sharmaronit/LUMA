import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'glass_surface.dart';
import 'luma_glass_theme.dart';
import 'motion.dart';
import 'voice_session.dart';

String voiceAppQuery(String transcript) => transcript
    .trim()
    .replaceFirst(
      RegExp(
        r'^(?:please\s+)?(?:open|launch|find|search\s+for)\s+',
        caseSensitive: false,
      ),
      '',
    )
    .replaceAll(RegExp(r'[.!?]+$'), '')
    .trim();

class VoiceSearchDialog extends StatefulWidget {
  const VoiceSearchDialog({
    super.key,
    required this.session,
    required this.mode,
    required this.onSearch,
    this.blurBuilder,
    this.preview = false,
    this.reducedMotion = false,
  });
  final VoiceSession session;
  final LauncherMaterial mode;
  final GlassBlurBuilder? blurBuilder;
  final ValueChanged<String> onSearch;
  final bool preview, reducedMotion;
  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  final _level = ValueNotifier<double>(0);
  StreamSubscription<VoiceEvent>? _subscription;
  Timer? _timeout, _completion;
  String phase = 'starting', transcript = '', message = '';
  bool _leaving = false;
  bool get listening => phase == 'listening' || phase == 'partial';
  bool get active => const [
    'starting',
    'permission',
    'listening',
    'partial',
    'processing',
  ].contains(phase);
  bool get current =>
      mounted && !_leaving && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.session.events.listen(
      _event,
      onError: (_) => _fail('Voice unavailable'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (current) _start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission prompts can make the app inactive; allow their results through.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _fail('Voice paused. Try again when you return.');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion();
  }

  void _motion() {
    if (listening && !motionReduced(context, widget.reducedMotion)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  Future<void> _start() async {
    if (!current || phase == 'result') return;
    _timeout?.cancel();
    _completion?.cancel();
    setState(() {
      phase = 'starting';
      transcript = '';
      message = '';
      _level.value = 0;
    });
    _motion();
    _timeout = Timer(const Duration(seconds: 25), () => _fail('Nothing heard'));
    try {
      await widget.session.start();
    } catch (_) {
      _fail('Voice unavailable');
    }
  }

  void _event(VoiceEvent event) {
    if (!current || !active) return;
    if (event.phase == 'level') {
      _level.value = event.level.clamp(0, 1);
      return;
    }
    if (event.phase == 'error') {
      _fail(event.message);
      return;
    }
    final words = event.text.isNotEmpty ? event.text : transcript;
    if (event.phase == 'result' && voiceAppQuery(words).isEmpty) {
      _fail('Nothing heard');
      return;
    }
    setState(() {
      phase = event.phase;
      transcript = words;
      if (event.message.isNotEmpty) message = event.message;
      _level.value = event.level.clamp(0, 1);
    });
    _motion();
    if (event.phase == 'result') {
      _timeout?.cancel();
      final query = voiceAppQuery(words);
      // Briefly retain the final words, then search without another remote press.
      _completion = Timer(
        const Duration(milliseconds: 350),
        () => _finish(query),
      );
    }
  }

  void _fail(String error) {
    if (!current) return;
    _timeout?.cancel();
    _completion?.cancel();
    setState(() {
      phase = 'error';
      message = error;
      _level.value = 0;
    });
    _motion();
    widget.session.stop().catchError((_) {});
  }

  void _finish([String? query]) {
    if (!current) return;
    _leaving = true;
    _completion?.cancel();
    _timeout?.cancel();
    widget.session.stop().catchError((_) {});
    Navigator.pop(context);
    if (query != null) widget.onSearch(query);
  }

  String get _errorLabel {
    final error = message.toLowerCase();
    if (error.contains('permission') ||
        error.contains('denied') ||
        error.contains('access'))
      return 'Microphone access needed';
    if (error.contains('nothing') || error.contains('no speech'))
      return 'Nothing heard';
    return 'Voice unavailable';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeout?.cancel();
    _completion?.cancel();
    _subscription?.cancel();
    widget.session.dispose().catchError((_) {});
    _level.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = motionReduced(context, widget.reducedMotion);
    final palette = MinimalPalette.of(context);
    final words = phase == 'error'
        ? _errorLabel
        : transcript.isNotEmpty
        ? transcript
        : phase == 'permission'
        ? 'Microphone access'
        : phase == 'processing'
        ? 'Searching…'
        : widget.preview
        ? 'Listening · demo'
        : 'Listening…';
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: AnimatedContainer(
          key: const ValueKey('voice-island'),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
          curve: lumaEase,
          width: transcript.isNotEmpty ? 520 : 340,
          child: LumaGlassPanel(
            enabled: palette.glass,
            radius: 30,
            child: Material(
              color: palette.glass ? Colors.transparent : palette.surface,
              borderRadius: BorderRadius.circular(30),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_pulse, _level]),
                        child: _VoiceDockButton(
                          key: const ValueKey('voice-dock-mic'),
                          tooltip: phase == 'error'
                              ? 'Try again'
                              : widget.preview
                              ? 'Voice preview · simulated speech'
                              : 'Microphone',
                          icon: phase == 'error'
                              ? Icons.refresh_rounded
                              : phase == 'result'
                              ? Icons.check_rounded
                              : Icons.mic_none_rounded,
                          reducedMotion: reduce,
                          onPressed: phase == 'error' ? _start : null,
                          color: palette.text,
                        ),
                        builder: (_, child) => Transform.scale(
                          scale: listening && !reduce
                              ? 1 +
                                    math.sin(_pulse.value * math.pi * 2) *
                                        .035 +
                                    _level.value * .025
                              : 1,
                          child: child,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        label: phase == 'error' ? message : null,
                        child: Text(
                          words,
                          key: const ValueKey('voice-transcript'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                            color: palette.text,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: .5,
                      height: 24,
                      color: palette.text.withValues(alpha: .18),
                    ),
                    const SizedBox(width: 8),
                    _VoiceDockButton(
                      autofocus: true,
                      tooltip: 'Close voice search',
                      icon: Icons.close_rounded,
                      reducedMotion: reduce,
                      color: palette.text,
                      onPressed: _finish,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceDockButton extends StatefulWidget {
  const _VoiceDockButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.reducedMotion,
    required this.color,
    this.onPressed,
    this.autofocus = false,
  });
  final String tooltip;
  final IconData icon;
  final bool reducedMotion, autofocus;
  final Color color;
  final VoidCallback? onPressed;
  @override
  State<_VoiceDockButton> createState() => _VoiceDockButtonState();
}

class _VoiceDockButtonState extends State<_VoiceDockButton> {
  bool focused = false, hovered = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (value) => setState(() => focused = value),
    child: MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedScale(
        scale: focused || (hovered && widget.onPressed != null) ? 1.12 : 1,
        duration: widget.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 140),
        curve: lumaEase,
        child: IconButton(
          autofocus: widget.autofocus,
          tooltip: widget.tooltip,
          onPressed: widget.onPressed,
          icon: Icon(widget.icon, size: 23, color: widget.color),
          style: IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            foregroundColor: widget.color,
            disabledForegroundColor: widget.color,
            focusColor: widget.color.withValues(alpha: .18),
            hoverColor: widget.color.withValues(alpha: .10),
            shape: const CircleBorder(),
          ),
        ),
      ),
    ),
  );
}
