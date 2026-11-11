import 'dart:async';
import 'dart:math' as math;

class VoiceEvent {
  const VoiceEvent(
    this.phase, {
    this.text = '',
    this.message = '',
    this.level = 0,
  });
  final String phase, text, message;
  final double level;
}

abstract class VoiceSession {
  Stream<VoiceEvent> get events;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// Explicitly simulated speech for reviewing the UI without accessing a microphone.
class DemoVoiceSession implements VoiceSession {
  final _events = StreamController<VoiceEvent>.broadcast();
  final _timers = <Timer>[];
  @override
  Stream<VoiceEvent> get events => _events.stream;
  @override
  Future<void> start() async {
    await stop();
    if (_events.isClosed) return;
    _events.add(const VoiceEvent('listening'));
    var frame = 0;
    _timers.add(
      Timer.periodic(const Duration(milliseconds: 90), (_) {
        _events.add(
          VoiceEvent('level', level: .25 + .55 * math.sin(frame++ * .3).abs()),
        );
      }),
    );
    _timers.add(
      Timer(
        const Duration(milliseconds: 1600),
        () => _events.add(const VoiceEvent('partial', text: 'You…')),
      ),
    );
    _timers.add(
      Timer(
        const Duration(milliseconds: 3000),
        () => _events.add(const VoiceEvent('partial', text: 'YouTube')),
      ),
    );
    _timers.add(
      Timer(const Duration(milliseconds: 4000), () {
        stop();
        _events.add(const VoiceEvent('result', text: 'YouTube'));
      }),
    );
  }

  @override
  Future<void> stop() async {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}
