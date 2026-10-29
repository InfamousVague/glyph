/// Whether the voice model is on the phone, and getting it there if not. A port of the logic of
/// `src/app/capture/useVoiceModel.ts`.
///
/// The model is about 60 MB and the first press of the side key should never wait for it, so it is fetched as soon
/// as the app opens. That fetch used to be fire-and-forget with its error swallowed, and on the Fold it failed
/// without a trace: the app was installed, the phone locked a minute later, Android froze the backgrounded process
/// mid-download, and the partial file was cleaned up - leaving an empty `models/` folder and nothing on screen to
/// say so. A voice feature whose first use silently cannot work is worse than one that says it is not ready.
///
/// So the state is visible, the failure is logged with its real message, and the fetch is retried every time the
/// app comes back to the screen until it succeeds. The retry-on-return is the part that fixes the freeze: a download
/// killed by the phone locking resumes the next time the app is looked at.
///
/// A file is fetched here, and nothing listens: no microphone is opened by the model being there.
///
/// What differs: the web's is a React hook; this is the plain class a widget will wrap, a `ValueListenable` of the
/// hook's `state` with its `retry`. The hook's effect is [VoiceModel.start] and the effect's cleanup
/// [VoiceModel.close]. What the hook imports is given: whether there is a native core (`isTauri()`), whether this
/// platform records at all (`core/platform.ts` `recordsVoice`), `ensureModel` (engine.dart), the app coming back to
/// the screen (the document's `visibilitychange`, when it says `visible`), and where the failure is logged.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/background_jobs.dart';

/// Where the voice model is.
sealed class VoiceModelState {
  const VoiceModelState();

  /// The web's `kind`.
  String get kind;
}

final class VoiceModelStateUnsupported extends VoiceModelState {
  const VoiceModelStateUnsupported();

  @override
  String get kind => 'unsupported';

  @override
  bool operator ==(Object other) => other is VoiceModelStateUnsupported;

  @override
  int get hashCode => kind.hashCode;
}

final class VoiceModelStateChecking extends VoiceModelState {
  const VoiceModelStateChecking();

  @override
  String get kind => 'checking';

  @override
  bool operator ==(Object other) => other is VoiceModelStateChecking;

  @override
  int get hashCode => kind.hashCode;
}

final class VoiceModelStateDownloading extends VoiceModelState {
  const VoiceModelStateDownloading({required this.received, required this.total});

  final int received;
  final int total;

  @override
  String get kind => 'downloading';

  @override
  bool operator ==(Object other) => other is VoiceModelStateDownloading && other.received == received && other.total == total;

  @override
  int get hashCode => Object.hash(kind, received, total);

  @override
  String toString() => 'VoiceModelStateDownloading(received: $received, total: $total)';
}

final class VoiceModelStateReady extends VoiceModelState {
  const VoiceModelStateReady();

  @override
  String get kind => 'ready';

  @override
  bool operator ==(Object other) => other is VoiceModelStateReady;

  @override
  int get hashCode => kind.hashCode;
}

final class VoiceModelStateFailed extends VoiceModelState {
  const VoiceModelStateFailed({required this.message});

  final String message;

  @override
  String get kind => 'failed';

  @override
  bool operator ==(Object other) => other is VoiceModelStateFailed && other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'VoiceModelStateFailed(message: $message)';
}

/// The voice model's fetch, as the app follows it (what `useVoiceModel` answers: its `state`, and `retry`).
class VoiceModel extends ChangeNotifier implements ValueListenable<VoiceModelState> {
  VoiceModel({
    required this.native,
    this.recordsVoice = true,
    required this.ensureModel,
    this.onVisible,
    this.warn,
  }) : _state = native && recordsVoice ? const VoiceModelStateChecking() : const VoiceModelStateUnsupported();

  /// Whether there is a native core (`isTauri()`).
  final bool native;

  /// Whether this platform records at all: the iPhone app records nothing yet, so no model is looked for, and none
  /// is missed.
  final bool recordsVoice;

  /// `ensureModel` (engine.dart): the model there, fetched if it was not, its progress told as it comes.
  final Future<Object?> Function([void Function(int received, int total)? onProgress]) ensureModel;

  /// Calls its listener each time the app comes back to the screen; answers the way to stop.
  final VoidCallback Function(VoidCallback listener)? onVisible;

  /// Where a failed fetch is written down, so it reaches the log; the screen shows a short version and a retry.
  final void Function(String line)? warn;

  VoiceModelState _state;
  bool _running = false;
  bool _ready = false;
  bool _closed = false;
  VoidCallback? _offVisible;

  /// The hook's `state`.
  VoiceModelState get state => _state;

  @override
  VoiceModelState get value => _state;

  void _setState(VoiceModelState next) {
    _state = next;
    if (!_closed) notifyListeners();
  }

  Future<void> _fetchModel() async {
    if (!native || !recordsVoice || _running || _ready) return;
    _running = true;
    // On the app's record of running work once it is really downloading (a model already here is no job): a ring
    // filling, green, as far as it has come (lib/core/background_jobs.dart; docs/ACTIVITY.md).
    JobHandle? job;
    try {
      await ensureModel((received, total) {
        _setState(VoiceModelStateDownloading(received: received, total: total));
        job ??= activity.begin(voiceModelJobId, kind: JobKind.downloads, title: 'Downloading the voice model', line: 'Downloading', fraction: 0);
        if (total > 0) job!.progress(fraction: received / total, steps: downloadSteps(received, total));
      });
      _ready = true;
      _setState(const VoiceModelStateReady());
      job?.done(tally: const JobTally('model downloaded', 'models downloaded'));
    } catch (error) {
      final message = _failureText(error);
      warn?.call('[glyph] voice model download failed: $message');
      _setState(VoiceModelStateFailed(message: message));
      // Tried again each time the app comes back to the screen, so a blip goes quietly; Retry is the screen's own.
      if (job != null && isNetworkBlip(error)) {
        job!.stopped();
      } else {
        job?.failed(message, fix: JobFix(JobFixKind.retry, retry));
      }
    } finally {
      _running = false;
    }
  }

  /// Asks for the model now, and again each time the app comes back to the screen (the hook's effect).
  void start() {
    _closed = false;
    unawaited(_fetchModel());
    _offVisible = onVisible?.call(() => unawaited(_fetchModel()));
  }

  /// Stops following the app's return to the screen (the effect's cleanup).
  void close() {
    _closed = true;
    _offVisible?.call();
    _offVisible = null;
  }

  /// The retry the screen offers.
  void retry() => unawaited(_fetchModel());
}

/// The voice model's download on the app's record of running work.
const String voiceModelJobId = 'voice-model';

/// A caught thing as words (`core/failure.ts` `failureText`): an error's message, or the thing itself as text.
String _failureText(Object failure) {
  if (failure is String) return failure;
  final text = failure.toString();
  for (final lead in const ['Exception: ', 'Bad state: ']) {
    if (text.startsWith(lead)) return text.substring(lead.length);
  }
  return text;
}
