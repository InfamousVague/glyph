/// The Mac's own sound in the meeting recorder: one word in the top line, which says whether this Mac's sound is
/// going into the recording and turns it on or off then and there, the switch (`meetingSound`) with it. A port of
/// `src/app/capture/ComputerSound.tsx`.
///
/// The tap is opened once the capture is running in the core (`live`), and the capture's own stop and cancel close
/// it. It is a tap on what the Mac plays, opened for a meeting the person started and closed with it: this widget
/// opens no microphone, and nothing here listens outside a recording.
///
/// What it says: "With this Mac's sound" while the tap is open, "This Mac's sound: off" when it is not, and nothing
/// on a Mac that cannot (older than 14.2, or a binary before generation 25), whose meetings are the microphone as
/// before. A tap that opened and has heard nothing for a while gets one line, `onSay`, with where macOS keeps the
/// switch, since a refused consent is silence rather than an error; and a tap that would not open says why the same
/// way.
///
/// What differs:
/// - The web reads the preference and the tap from modules. Here the tap is the [SystemSound] it is given, and the
///   preference is `wanted` with `onWanted` to change it (`setPreferences({ meetingSound })`).
/// - `useMeetingSoundSupport` is [SystemSound.meetingSoundSupport], asked once as the word is first drawn.
/// - "Nothing for a while" is counted in the askings themselves (one every 1.5 s, so the sixth is the first past
///   8 s, as on the page) rather than read from the clock, so a test's clock moves it.
/// - `className` is a [TextStyle] laid over the word's own.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app/widgets.dart';
import '../system_sound.dart';

/// `NOTHING_AFTER_MS` and `ASK_EVERY_MS`.
const int _nothingAfterMs = 8000;
const int _askEveryMs = 1500;

class ComputerSound extends StatefulWidget {
  const ComputerSound({super.key, required this.live, required this.sound, required this.wanted, required this.onWanted, required this.onSay, this.style});

  /// The capture is running in the core: the tap may open.
  final bool live;
  final SystemSound sound;

  /// The `meetingSound` preference.
  final bool wanted;
  final ValueChanged<bool> onWanted;

  /// One line for the recorder to say: why the tap would not open, or where the switch is when nothing comes.
  final void Function(String text) onSay;
  final TextStyle? style;

  @override
  State<ComputerSound> createState() => _ComputerSoundState();
}

/// One opening of the tap, from the switch and the capture both being on until either goes.
class _Run {
  bool alive = true;
  bool opened = false;
  Timer? timer;
  int asked = 0;
}

class _ComputerSoundState extends State<ComputerSound> {
  SoundSupport? _support;
  bool _open = false;
  bool _said = false;
  _Run? _run;

  bool get _wanted => widget.wanted && _support?.supported == true;

  @override
  void initState() {
    super.initState();
    widget.sound.meetingSoundSupport().then((support) {
      if (!mounted) return;
      setState(() => _support = support);
      _sync();
    });
  }

  @override
  void didUpdateWidget(ComputerSound old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// The web's effect on `[live, wanted]`: a tap while both, none otherwise.
  void _sync() {
    final want = widget.live && _wanted;
    if (want && _run == null) {
      _start();
    } else if (!want && _run != null) {
      _end();
      if (_open) setState(() => _open = false);
    }
  }

  void _start() {
    final run = _run = _Run();
    final sound = widget.sound;
    sound.startComputerSound().then((started) {
      if (!run.alive) {
        if (started.capturing) sound.stopComputerSound();
        return;
      }
      run.opened = started.capturing;
      setState(() => _open = started.capturing);
      if (!started.capturing) {
        final reason = started.reason;
        if (reason != null && reason.isNotEmpty) widget.onSay(reason);
        return;
      }
      // Asked a few times a second's worth apart until something is heard, or once it is clear nothing will be.
      run.timer = Timer.periodic(const Duration(milliseconds: _askEveryMs), (timer) {
        run.asked += 1;
        final since = run.asked * _askEveryMs;
        sound.computerSoundStatus().then((status) {
          if (!run.alive || status == null) return;
          if (status.heard || !status.capturing) timer.cancel();
          if (!status.capturing) {
            setState(() => _open = false);
          } else if (!status.heard && !_said && since > _nothingAfterMs) {
            _said = true;
            widget.onSay(nothingFromTheMac);
          }
        });
      });
    });
  }

  void _end() {
    final run = _run;
    if (run == null) return;
    _run = null;
    run.alive = false;
    run.timer?.cancel();
    if (run.opened) widget.sound.stopComputerSound();
  }

  @override
  void dispose() {
    _end();
    super.dispose();
  }

  void _toggle() {
    HapticsProvider.of(context)(HapticKind.selection);
    widget.onWanted(!widget.wanted);
  }

  @override
  Widget build(BuildContext context) {
    if (_support?.supported != true) return const SizedBox.shrink();
    final wanted = _wanted;
    // aria-pressed={wanted} title={wanted ? "Stop recording this Mac's sound" : "Record this Mac's sound too"}
    return Semantics(
      toggled: wanted,
      tooltip: wanted ? "Stop recording this Mac's sound" : "Record this Mac's sound too",
      child: AppWord(
        onPressed: _toggle,
        child: Builder(
          builder: (context) => Text(
            wanted ? (_open ? "With this Mac's sound" : "This Mac's sound…") : "This Mac's sound: off",
            style: widget.style == null ? null : DefaultTextStyle.of(context).style.merge(widget.style),
          ),
        ),
      ),
    );
  }
}
