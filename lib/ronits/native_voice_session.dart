import 'dart:async';
import '../luma_channel.dart';
import 'voice_session.dart';

class NativeVoiceSession implements VoiceSession {
  final _channel = LumaChannel();
  @override
  Stream<VoiceEvent> get events => _channel.voiceEvents.map(
    (event) => VoiceEvent(
      event['phase'] as String? ?? 'error',
      text: event['text'] as String? ?? '',
      message: event['message'] as String? ?? '',
      level: (event['level'] as num?)?.toDouble() ?? 0,
    ),
  );
  @override
  Future<void> start() => _channel.startVoiceSearch();
  @override
  Future<void> stop() => _channel.stopVoiceSearch();
  @override
  Future<void> dispose() => stop();
}
