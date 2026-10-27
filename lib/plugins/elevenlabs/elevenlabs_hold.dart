/// Keeps the app going while ElevenLabs reads a note, so a voice-over goes on with the app behind another: Lovart's
/// hold (lib/plugins/lovart/lovart_hold.dart; Matt, 2026-10-27: "The lovart generation stops when the app is not in
/// focus please background the task"), for the voice-overs.
///
/// It hears [voiceOverMaking] and, while any note is being read, tells the device of a job of its own,
/// [voiceOverJobId] (lib/core/background_jobs.dart): Android's foreground service with "Making a voice-over" and how
/// far it is, the Mac out of App Nap. When the last is read it lets the device go quietly: the voice-over is in its
/// note, which said so.
library;

import '../../core/background_jobs.dart';
import 'voice_over.dart';

/// The device's name for the voice-overs being made.
const String voiceOverJobId = 'elevenlabs-voice-over';

/// Holds the device while ElevenLabs reads.
class ElevenLabsHold {
  ElevenLabsHold({required this.background});

  final BackgroundJobs background;
  bool _holding = false;
  String? _said;
  bool _started = false;

  /// Starts hearing.
  void start() {
    if (_started) return;
    _started = true;
    voiceOverMaking.addListener(_look);
    _look();
  }

  /// What the device's notification says now: the one note's progress, or how many.
  static String words(Map<String, String> making) => making.length == 1 ? making.values.single : '${making.length} notes';

  void _look() {
    final making = voiceOverMaking.value;
    if (making.isNotEmpty) {
      final text = words(making);
      if (_holding && text == _said) return;
      _holding = true;
      _said = text;
      background.running(voiceOverJobId, title: 'Making a voice-over with ElevenLabs', text: text);
    } else if (_holding) {
      _holding = false;
      _said = null;
      background.ended(voiceOverJobId, title: 'Voice-over made', quiet: true);
    }
  }

  void dispose() {
    if (!_started) return;
    voiceOverMaking.removeListener(_look);
    if (_holding) background.ended(voiceOverJobId, title: 'Voice-over made', quiet: true);
    _holding = false;
  }
}
