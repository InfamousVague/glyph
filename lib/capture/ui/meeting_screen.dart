/// A meeting being recorded by the phone's own service: the cassette turning, the counter, the line that says the
/// screen can go off, and Discard and Done. A port of `src/app/capture/MeetingScreen.tsx` and
/// MeetingScreen.module.css.
///
/// Its own small screen rather than the recorder, because a meeting is recorded and not read: no live words, no
/// reader, no cues, nothing of the note, since the side key can open it over the lock screen.
///
/// It holds nothing the recorder holds. No `setCapturing`, which keeps the screen on and stops the take when the
/// screen goes off - "the screen can go off" is this screen's whole point - and no hold on the queues. The service
/// has the microphone and the wake lock; this screen reads its state once a second (capture/meeting_live.dart) and
/// asks it two things. Done stops the recording, and the service carries on as the write-up. Discard stops it and
/// deletes the WAV, and the app deletes the note itself. Back only leaves: the recording goes on, stoppable here or
/// from the notification, and a locked phone goes back behind its lock screen. This is a meeting the person started
/// and can see in the notification the whole time: no always-on microphone, and this screen opens none.
///
/// Other apps' sound (native generation 25), when the meeting was started with "Include sound from other apps": a
/// line that says it is in the recording, and that calls are not (Android never lets an app hear one), or, when
/// sharing was declined or stopped from the status bar, that the microphone is recording on its own.
///
/// Under the cassette, until it has been asked once on this device, the way to be told when the meeting is written
/// up (the meeting's own notification prompt, never the update alerts'), and, refused - the phone blocking the
/// prompt, or the prompt answered no, now or on an earlier meeting - the line that says the notification's Stop is
/// not coming.
///
/// What differs:
/// - Everything the web imports that is not a widget is a function of a [MeetingScreenHost]: `core/host.ts`'s
///   `isLocked`, `endCapture`, `stopMeetingOnHost`, `discardMeetingOnHost` and `requestNotifications`,
///   `core/store.ts`'s `deleteNote`, `ai/summaries.ts`'s `dropSummary`, and the two lines that took the note out of
///   `preferences().meetings` (`forgetMeeting`). The meeting's state is the [MeetingLive] it is given.
/// - `requestNotifications` answers a [NotificationsAnswer], the web's three words.
/// - The clock is the host's `now`, else the [MeetingLive]'s own, so a test's clock is one clock.
/// - `data-recording` is the cassette's `playing`; no rule read it.
/// - The app's shell already answers back for this screen by going home; this screen's own answer is registered
///   after it and so is the one asked, which is the same leaving with the lock screen's word said first.
/// - A body taller than the window scrolls, where the page's ran over its edges.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app/widgets.dart';
import 'capture_cards.dart' show PageWord;
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/back.dart';
import '../../core/stored.dart';
import '../../shell/header_pane.dart';
import '../../tapes/tape_art.dart';
import '../meeting_live.dart';
import '../tape.dart';

/// What the phone says when asked to let Ghost.md notify (`NotificationsAnswer`, core/host.ts): allowed already,
/// asked (the answer arrives later, as [MeetingLive.notified]), or blocked, which is also the answer where there is
/// nobody to ask.
enum NotificationsAnswer { allowed, asked, blocked }

/// What the meeting screen asks of the phone and the app.
class MeetingScreenHost {
  const MeetingScreenHost({
    required this.isLocked,
    required this.endCapture,
    required this.stopMeeting,
    required this.discardMeeting,
    required this.requestNotifications,
    required this.deleteNote,
    required this.dropSummary,
    required this.forgetMeeting,
    this.haptic,
    this.alertsAsked,
    this.now,
  });

  /// Whether the phone is locked; false wherever there is no host to ask (`isLocked`).
  final bool Function() isLocked;

  /// Tell the activity a capture is over; `leave` returns a locked phone to its lock screen (`endCapture`).
  final void Function(bool leave) endCapture;

  /// Done: the service stops recording and carries on as the write-up (`stopMeetingOnHost`).
  final VoidCallback stopMeeting;

  /// The service stops and deletes the WAV; the note is the app's to delete (`discardMeetingOnHost`).
  final VoidCallback discardMeeting;

  /// Ask to be allowed to notify (`requestNotifications`): the phone's own answer. The page's bridge answered at
  /// once; the phone's channel answers a moment later, so the answer may be one to wait for, and the screen says
  /// nothing of the asking until it has it.
  final FutureOr<NotificationsAnswer> Function() requestNotifications;

  /// The notes store's `deleteNote`; a failure is let go, as on the web.
  final Future<void> Function(String noteId) deleteNote;

  /// `ai/summaries.ts` `dropSummary`: the note's write-up, forgotten.
  final void Function(String noteId) dropSummary;

  /// Takes the note out of the preferences' `meetings`.
  final void Function(String noteId) forgetMeeting;

  /// `fireNativeHaptic`; the kit's own where none is given.
  final void Function(HapticKind kind)? haptic;

  /// Asked once on this device: the line offering it goes once it has been answered, or Allow tapped. The app's own
  /// stored flag, `glyph-meeting-alerts-asked`, where none is given.
  final StoredFlag? alertsAsked;

  /// The clock, in milliseconds since the epoch; the [MeetingLive]'s where none is given.
  final int Function()? now;

  StoredFlag get _asked => alertsAsked ?? stored.flag('glyph-meeting-alerts-asked');
}

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key, required this.noteId, required this.fromAssistant, required this.onLeave, required this.live, required this.host});

  final String noteId;

  /// Opened by the side key: leaving hands a locked phone back to its lock screen, as a capture does.
  final bool fromAssistant;

  /// The screen left, however it was left: home.
  final VoidCallback onLeave;
  final MeetingLive live;
  final MeetingScreenHost host;

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  /// Asked on an earlier meeting: an answer that is still no is a refusal, and the offer is not made again.
  late final bool _askedBefore = widget.host._asked.isMarked;

  /// Asked from this screen: the offer goes, and nothing more is said until the phone answers.
  bool _askedNow = false;
  bool _answered = false;
  bool _blocked = false;
  late int _now = _clock();
  Timer? _timer;
  VoidCallback? _offState;
  VoidCallback? _offNotified;

  int _clock() => (widget.host.now ?? widget.live.now)();

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final live = widget.live;
    _askedBefore;
    // useEffect(() => void canNotifyNow(), []), before anything listens for its answer.
    live.canNotifyNow();
    _offState = live.subscribe(_changed);
    live.canNotify.addListener(_changed);
    _offNotified = live.onNotified(() {
      if (mounted) setState(() => _answered = true);
    });
    // The counter runs between the service's answers, from when the meeting began where the service said.
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() => _now = _clock()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _offState?.call();
    _offNotified?.call();
    widget.live.canNotify.removeListener(_changed);
    super.dispose();
  }

  void _haptic(HapticKind kind) => (widget.host.haptic ?? (kind) => HapticsProvider.of(context)(kind))(kind);

  void _leave() {
    if (widget.fromAssistant) widget.host.endCapture(widget.host.isLocked());
    widget.onLeave();
  }

  void _done() {
    _haptic(HapticKind.success);
    widget.host.stopMeeting();
    _leave();
  }

  void _discard() {
    final host = widget.host;
    _haptic(HapticKind.warning);
    host.discardMeeting();
    host.forgetMeeting(widget.noteId);
    host.dropSummary(widget.noteId);
    try {
      host.deleteNote(widget.noteId).catchError((Object _) {});
    } catch (_) {
      // Let go, as a rejection is.
    }
    _leave();
  }

  void _allow() {
    void answered(NotificationsAnswer answer) {
      if (!mounted) return;
      setState(() {
        if (answer == NotificationsAnswer.blocked) {
          _blocked = true;
        } else {
          widget.host._asked.mark();
          _askedNow = true;
        }
      });
      widget.live.canNotifyNow();
    }

    // Marked as asked only once the phone has said it asked: a phone that blocks it outright never showed a prompt.
    final answer = widget.host.requestNotifications();
    if (answer is NotificationsAnswer) return answered(answer);
    unawaited(answer.then<void>(answered, onError: (Object _) => answered(NotificationsAnswer.blocked)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final live = widget.live.state;
    final mine = live != null && live.recording && live.noteId == widget.noteId;
    final canNotify = widget.live.canNotify.value;
    final started = live?.startedAt;
    final num elapsedMs = mine ? (started != null ? math.max(live.elapsedMs, _now - started) : live.elapsedMs) : 0;
    final offer = !canNotify && !_askedBefore && !_askedNow && !_blocked;
    final refused = !canNotify && (_blocked || _askedBefore || _answered);

    final sm = t.fontSize('sm');
    final md = t.fontSize('md');
    final topText = t.textAt(sm, color: t.color('app-ink-2'));
    // .line {
    //   max-inline-size: 28rem;
    //   margin: 0;
    //   font-size: var(--glacier-font-size-md);
    //   line-height: 1.5;
    //   color: var(--app-ink-3);
    // }
    final lineStyle = t.textAt(md, color: t.color('app-ink-3'), height: 1.5);
    Widget line(InlineSpan words, {bool status = false}) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.lenOf('28rem')),
          child: Semantics(liveRegion: status, child: Text.rich(words, textAlign: TextAlign.center, style: lineStyle)),
        );

    final body = <Widget>[
      // .tape { inline-size: min(100%, 22rem); block-size: auto; }
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: t.lenOf('22rem')),
        child: TapeArt(bare: true, playing: mine, positionMs: elapsedMs, lengthMs: math.max(tapeMs, elapsedMs)),
      ),
      line(const TextSpan(text: 'Recording. The screen can go off and you can leave. Stop here or from the notification.')),
      if (mine && live.otherApps == true)
        line(TextSpan(text: '${live.otherAppsHeard == true ? 'Recording sound from other apps too.' : 'Listening for sound from other apps too.'} Media and games, never calls.'), status: true)
      else if (mine && live.otherAppsNote != null && live.otherAppsNote!.isNotEmpty)
        line(TextSpan(text: live.otherAppsNote), status: true),
      if (mine && live.silenced) line(const TextSpan(text: 'Muted by another app.'), status: true),
      if (offer)
        line(
          TextSpan(
            children: [
              const TextSpan(text: 'Let Ghost.md tell you when it is written up. '),
              // .word { font-size: inherit; }
              WidgetSpan(alignment: PlaceholderAlignment.middle, child: AppWord(onPressed: _allow, child: const Text('Allow'))),
            ],
          ),
        ),
      if (refused) line(const TextSpan(text: 'Notifications are off for Ghost.md, so stop it here.')),
    ];

    // .screen {
    //   position: relative;
    //   isolation: isolate;
    //   display: flex;
    //   flex-direction: column;
    //   block-size: 100dvh;
    //   background: var(--glacier-bg);
    //   padding-inline: var(--app-gutter-start) var(--app-gutter-end);
    // }
    return OnBack(
      onBack: _leave,
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.only(left: t.len('app-gutter-start'), right: t.len('app-gutter-end')),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // .body {
                  //   flex: 1;
                  //   min-block-size: 0;
                  //   display: flex;
                  //   flex-direction: column;
                  //   align-items: center;
                  //   justify-content: center;
                  //   gap: var(--glacier-space-4);
                  //   text-align: center;
                  // }
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < body.length; i += 1) ...[if (i > 0) SizedBox(height: t.space(4)), body[i]],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // .footer {
                  //   flex: none;
                  //   display: flex;
                  //   align-items: center;
                  //   justify-content: space-between;
                  //   padding-block: var(--glacier-space-2) calc(var(--app-safe-bottom) + var(--glacier-space-4));
                  // }
                  Padding(
                    padding: EdgeInsets.only(top: t.space(2), bottom: t.lenOf('calc(var(--app-safe-bottom) + var(--glacier-space-4))')),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AppWord(onPressed: _discard, child: const PageWord('Discard')),
                        // <button className="app-pill" aria-label="Stop and write up"><Square size={16} />Done</button>
                        Semantics(
                          label: 'Stop and write up',
                          child: AppPill(onPressed: _done, icon: const AppIcon(Lucide.square, size: 16), child: const Text('Done')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // .top {
            //   display: flex;
            //   align-items: baseline;
            //   gap: var(--glacier-space-4);
            //   min-block-size: var(--glacier-space-10);
            //   padding-inline: var(--app-gutter-start) var(--app-gutter-end);
            //   padding-block: calc(var(--app-safe-top) + var(--glacier-space-3)) var(--glacier-space-2);
            //   font-size: var(--glacier-font-size-sm);
            //   color: var(--app-ink-2);
            // }
            // The pane pads itself down by `--app-safe-top` (shell/header_pane.dart).
            HeaderPane(
              child: Semantics(
                container: true,
                liveRegion: true,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: math.max(0, t.space(10) - t.len('app-safe-top'))),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(t.len('app-gutter-start'), t.space(3), t.len('app-gutter-end'), t.space(2)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        // .where { min-inline-size: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
                        Expanded(child: Text('Meeting', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: topText)),
                        SizedBox(width: t.space(4)),
                        // .counter { flex: none; margin-inline-start: auto; font-variant-numeric: tabular-nums; }
                        Text(
                          counter(elapsedMs),
                          semanticsLabel: 'Recorded ${counter(elapsedMs)}',
                          style: topText.copyWith(fontFeatures: [...?topText.fontFeatures, const FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
