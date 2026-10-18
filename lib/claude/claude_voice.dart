/// Talking to Claude (docs/CLAUDE_APP.md, "Talking to Claude"). Matt, 2026-10-17: "Add the AI voice input back in
/// add a microphone icon to the dock bar ... When talking show the sound ripples then show claudes or whatever AI
/// agent were using thought process and then follow along automatically".
///
/// One ask said aloud, from the dock's Talk to Claude ring or the phone's assistant gesture, through four stages:
///
/// 1. **Listening**: an ear is opened ([ClaudeEar], the recorder's own Whisper over the phone's microphone,
///    lib/claude/claude_ear.dart), its level sent to the ripples (capture/voice_level.dart `publishVoiceLevel`, which
///    the recorder's rings hear) and its words shown as they come. It ends on a tap ([ClaudeVoice.done]), on a pause
///    once something has been said (the recorder's own "stop when I go quiet", capture/quiet.dart [QuietWatch], with
///    a shorter wait: an ask is a sentence, not a note), after a minute at most, or after ten seconds of nothing.
/// 2. **Thinking**: the words go to the app's own Claude, in the chat's own conversation, so they are in the chat
///    afterwards (lib/claude/claude_runner.dart). Its thinking is shown as it comes (lib/claude/claude_run.dart,
///    "Claude's thinking, shown"), with what each tool did.
/// 3. **Following**: once Claude starts writing in a note, the run opens it and types into it as it does for the chat;
///    the sheet makes way, down to a strip, so the note is watched. Claude's own Follow is the run's ([ClaudeRun.
///    following]); the strip's Stop stops Claude.
/// 4. **Answered**: Claude's last words, with the way into the chat. A sheet that made way closes by itself a few
///    seconds after.
///
/// With no API key on this device, the words go to the "Ask Claude" note instead, as the chat sends them ([inbox]),
/// for an AI working through the connector; and where one is online now (lib/live/follow.dart [FollowAi.ais]), it is
/// followed at once, and the strip says what it is doing as it does it.
///
/// **No always-on microphone, ever.** The ear is opened by [start], which only a press (or the phone's assistant
/// gesture, which is a press) calls, and is let go by the end of listening, [cancel] or [dispose]. Nothing here
/// listens for a word.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../capture/quiet.dart';
import '../capture/voice_level.dart' show publishVoiceLevel;
import '../live/follow.dart';
import '../live/presence.dart' show AiOnline;
import 'claude_run.dart';
import 'claude_runner.dart';

/// What an ear tells whoever opened it.
@immutable
class ClaudeHeard {
  const ClaudeHeard({required this.level, required this.words, required this.problem, this.ended, this.download});

  /// The microphone's level for a chunk, 0 to 1 for drawing, and the RMS it came from.
  final void Function(double level, double rms) level;

  /// Everything heard so far, the words committed and the guess at the ones still coming, as one line.
  final void Function(String words) words;

  /// The ear could not open, or failed, in words a person reads.
  final void Function(String message) problem;

  /// The microphone closed by itself (the phone took it): listening is over, with what was heard.
  final VoidCallback? ended;

  /// The voice model's download, while one is under way.
  final void Function(int received, int total)? download;
}

/// An ear that is open.
abstract interface class ClaudeHearing {
  /// Stops listening and answers the words heard, the transcriber's last and best where it has one.
  Future<String> finish();

  /// Stops listening and keeps nothing.
  void cancel();
}

/// Opens an ear, at once: the microphone is listening before the transcriber is ready, as the recorder's is.
typedef ClaudeEar = ClaudeHearing Function(ClaudeHeard heard);

/// Where a talk is.
enum ClaudeVoiceStage {
  listening,

  /// The words heard are being made final, then sent.
  sending,
  thinking,

  /// Claude writes in a note, or an AI through the connector is followed: the sheet has made way.
  following,
  answered,

  /// Written into the "Ask Claude" note, with no AI online to follow.
  sent,
  failed,
}

/// How long a pause ends listening once words have been heard.
const int claudeQuietMs = 2000;

/// The longest one ask listens.
const int claudeLongestMs = 60000;

/// How long listening waits for a first word.
const int claudeNothingMs = 10000;

/// How long a sheet that made way, or one that sent the words on, stays once it is over.
const Duration claudeLinger = Duration(seconds: 6);

/// One ask said aloud: see the library's header.
class ClaudeVoice extends ChangeNotifier {
  ClaudeVoice({
    required this.runner,
    required this.ear,
    this.follow,
    this.inbox,
    this.about,
    this.onEnd,
    this.quietMs = claudeQuietMs,
    this.longestMs = claudeLongestMs,
    this.nothingMs = claudeNothingMs,
  });

  final ClaudeRunner runner;
  final ClaudeEar ear;

  /// The connector's AIs online, where the build has an account.
  final FollowAi? follow;

  /// Without a key: a request written into the "Ask Claude" note (the chat's own, lib/root/root_claude.dart).
  final Future<void> Function(String request)? inbox;

  /// What the page it was asked from is about (a note's title): the ask is put to Claude as `[[Title]] words`, as
  /// the dock's chat puts it in the field.
  final String? about;

  /// Told when the talk is over and its sheet should go: closed, or lingered after it ended.
  final VoidCallback? onEnd;

  final int quietMs;
  final int longestMs;
  final int nothingMs;

  ClaudeVoiceStage _stage = ClaudeVoiceStage.listening;
  ClaudeVoiceStage get stage => _stage;

  String _words = '';

  /// What was heard, as it comes; once sent, what was asked.
  String get words => _words;

  String? _problem;

  /// Why it failed, in words a person reads.
  String? get problem => _problem;

  /// Whether it failed for want of a key, so the sheet offers the way to add one.
  bool get wantsKey => _wantsKey;
  bool _wantsKey = false;

  ({int received, int total})? _download;

  /// The voice model's download, while listening waits for it.
  ({int received, int total})? get download => _download;

  ClaudeRun? _run;

  /// The run asked, once it is.
  ClaudeRun? get run => _run;

  AiOnline? _ai;

  /// The AI followed through the connector, where the words went to the inbox with one online.
  AiOnline? get ai {
    final key = _ai?.key;
    if (key == null) return null;
    for (final online in follow?.ais ?? const <AiOnline>[]) {
      if (online.key == key) return online;
    }
    return _ai;
  }

  /// Whether the sheet made way for a note: it stays a strip from then until it goes.
  bool _madeWay = false;
  bool get madeWay => _madeWay;

  /// Whether the talk is over (answered, sent, failed), and so closes by itself after [claudeLinger] if it made way
  /// or sent the words on.
  bool get over => _stage == ClaudeVoiceStage.answered || _stage == ClaudeVoiceStage.sent || _stage == ClaudeVoiceStage.failed;

  ClaudeHearing? _hearing;
  Timer? _ticking;
  Timer? _lingering;
  QuietWatch? _quiet;
  int _ms = 0;
  bool _gone = false;
  bool _started = false;

  void _set(void Function() change) {
    if (_gone) return;
    change();
    notifyListeners();
  }

  /// Opens the ear. Once.
  void start() {
    if (_started || _gone) return;
    _started = true;
    _quiet = QuietWatch(quietMs);
    _hearing = ear(ClaudeHeard(
      level: (level, rms) {
        if (_stage != ClaudeVoiceStage.listening) return;
        publishVoiceLevel(level);
        _quiet?.level(rms, _ms);
      },
      words: (words) {
        if (_stage != ClaudeVoiceStage.listening) return;
        if (words.trim().isNotEmpty) _quiet?.words(_ms);
        _set(() {
          _words = words;
          _download = null;
        });
      },
      problem: (message) {
        if (_stage != ClaudeVoiceStage.listening) return;
        _stopListening();
        _hearing?.cancel();
        _fail(message);
      },
      ended: () => unawaited(done()),
      download: (received, total) => _set(() => _download = (received: received, total: total)),
    ));
    // The clock is counted here, a step at a time, rather than read: so a pause is the same length however busy the
    // phone is, and a test's clock is the one it sets.
    const step = 200;
    _ticking = Timer.periodic(const Duration(milliseconds: step), (_) {
      _ms += step;
      final quiet = _quiet?.due(_ms) ?? false;
      final silent = _words.trim().isEmpty && _download == null && _ms >= nothingMs;
      if (quiet || silent || _ms >= longestMs) unawaited(done());
    });
  }

  void _stopListening() {
    _ticking?.cancel();
    _ticking = null;
    publishVoiceLevel(0);
  }

  /// Listening is over (the tap, the pause): the words are made final and sent. Nothing heard is said so.
  Future<void> done() async {
    if (_stage != ClaudeVoiceStage.listening || _gone) return;
    _stopListening();
    _set(() => _stage = ClaudeVoiceStage.sending);
    var heard = '';
    try {
      heard = (await _hearing?.finish())?.trim() ?? '';
    } catch (_) {
      heard = '';
    }
    _hearing = null;
    if (_gone) return;
    final words = heard.isNotEmpty ? heard : _words.trim();
    if (words.isEmpty) return _fail('Nothing was heard. Press the microphone and say what you would like Claude to do.');
    _set(() => _words = words);
    await _send(words);
  }

  Future<void> _send(String words) async {
    final about = this.about?.trim() ?? '';
    final prompt = about.isEmpty ? words : '[[$about]] $words';
    await runner.settings.load();
    if (_gone) return;
    if (runner.settings.hasKey) {
      try {
        final run = await runner.ask(prompt);
        if (_gone) return;
        _run = run..addListener(_runChanged);
        _set(() => _stage = ClaudeVoiceStage.thinking);
        _runChanged();
      } catch (error) {
        _fail('$error');
      }
      return;
    }
    final inbox = this.inbox;
    if (inbox == null) {
      _wantsKey = true;
      return _fail('Claude answers here with your own Anthropic API key. Add one in Settings › Plugins › Claude.');
    }
    try {
      await inbox(prompt);
    } catch (error) {
      return _fail('$error');
    }
    if (_gone) return;
    // An AI working through the connector, online now: it is followed, and the strip says what it does.
    final online = follow?.ais ?? const <AiOnline>[];
    if (online.isNotEmpty) {
      final chosen = online.firstWhere((ai) => ai.at != null, orElse: () => online.first);
      _ai = chosen;
      follow!.addListener(_aiChanged);
      follow!.follow(chosen);
      _set(() {
        _madeWay = true;
        _stage = ClaudeVoiceStage.following;
      });
      return;
    }
    _set(() => _stage = ClaudeVoiceStage.sent);
    _linger();
  }

  void _aiChanged() {
    if (_gone) return;
    // The AI gone, or no longer followed (its Stop, or the person's own doing in the note): the strip says so and goes.
    final f = follow;
    if (f == null || f.following?.key != _ai?.key) {
      f?.removeListener(_aiChanged);
      _set(() => _stage = ClaudeVoiceStage.sent);
      _linger();
      return;
    }
    notifyListeners();
  }

  void _runChanged() {
    final run = _run;
    if (run == null || _gone) return;
    if (run.state == ClaudeState.writing && run.following && !_madeWay) {
      _set(() {
        _madeWay = true;
        _stage = ClaudeVoiceStage.following;
      });
      return;
    }
    if (!run.working && run.state != ClaudeState.idle && !over) {
      run.removeListener(_runChanged);
      if (run.state == ClaudeState.failed) {
        _fail(run.problem ?? 'Something went wrong.');
      } else {
        _set(() => _stage = ClaudeVoiceStage.answered);
        if (_madeWay) _linger();
      }
      return;
    }
    notifyListeners();
  }

  void _fail(String message) {
    _set(() {
      _problem = message;
      _stage = ClaudeVoiceStage.failed;
    });
  }

  void _linger() {
    _lingering?.cancel();
    _lingering = Timer(claudeLinger, () {
      if (!_gone) onEnd?.call();
    });
  }

  /// The sheet that made way is kept: its lingering is called off (a press on the strip).
  void stay() {
    _lingering?.cancel();
    _lingering = null;
  }

  /// Stops what is under way: Claude's run, or following the AI.
  void stop() {
    final run = _run;
    if (run != null && run.working) {
      run.stop();
      return;
    }
    if (_ai != null) follow?.stop();
  }

  /// Closes it: listening called off and nothing kept, or, once asked, the sheet put away while Claude goes on (it
  /// is in the chat).
  void cancel() {
    if (_stage == ClaudeVoiceStage.listening) {
      _stopListening();
      _hearing?.cancel();
      _hearing = null;
    }
    onEnd?.call();
  }

  /// What the strip says Claude is doing, in a line.
  String get line {
    final ai = this.ai;
    if (ai != null && _run == null) return '${ai.name} is ${ai.words}';
    final run = _run;
    if (run == null) return '';
    final at = run.at;
    if (over) return run.answer.isEmpty ? 'Done.' : run.answer;
    if (at != null) return '${at.doing[0].toUpperCase()}${at.doing.substring(1)} ${at.title.isEmpty ? 'a note' : at.title}';
    final thought = run.thinking.trim().isNotEmpty ? run.thinking.trim() : run.lastThought;
    return thought.isEmpty ? 'Thinking…' : thought.split('\n').last;
  }

  /// The end of Claude's thought, as much as a few lines hold, while it thinks.
  String get thought {
    final run = _run;
    if (run == null) return '';
    final now = run.thinking.trim().isNotEmpty ? run.thinking.trim() : run.lastThought;
    return now.length <= 320 ? now : '…${now.substring(math.max(0, now.length - 320)).trimLeft()}';
  }

  @override
  void dispose() {
    _gone = true;
    _stopListening();
    _hearing?.cancel();
    _hearing = null;
    _lingering?.cancel();
    _run?.removeListener(_runChanged);
    follow?.removeListener(_aiChanged);
    super.dispose();
  }
}
