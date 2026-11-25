/// Sharing a screen in a call (GMFB-27, from the Uplink gap review: UplinkWeb shipped screen sharing in v2.0.3): the
/// button's work, the computer's choice of screen or window, the large view of someone's screen, and the line saying
/// who is sharing.
///
/// The screen goes out in the camera's place (lib/voice/rtc.dart, RtcMedia.setScreen), so it reaches everyone already
/// connected with nothing worked out again; each member's 'me' says it is a screen ('s'), and it is drawn whole, never
/// cropped or mirrored.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/settings_type.dart';
import '../platform_info.dart';
import '../sms.dart';
import '../voice/channels.dart';
import '../voice/voice.dart';
import 'common.dart';
import 'voice_screen.dart' show StreamView;

/// What the button says: "Share screen", or "Stop sharing" while this device shares.
String screenShareLabel(VoiceSession s) => s.screen ? 'Stop sharing' : 'Share screen';

/// The button's work: stops sharing, or starts. A computer asks which screen or window first; a phone's system asks
/// itself. Says so where it did not start.
Future<void> toggleScreenShare(BuildContext context, VoiceSession s) async {
  if (s.screen) {
    await s.setScreen(false);
    return;
  }
  if (!s.canShareScreen) {
    toast(context, 'This device can\'t share its screen');
    return;
  }
  if (s.videoLocked) {
    toast(context, 'Your role in this space can\'t share video');
    return;
  }
  // Taken now: the menu this was pressed in may be gone by the time there is something to say.
  final toasts = GlacierToast.of(context);
  String? source;
  if (Sms.computer) {
    final media = s.media;
    if (media is! ScreenMedia) return;
    source = await pickScreen(context, (media as ScreenMedia).screenSources);
    if (source == null) return;
  }
  final started = await s.setScreen(true, source: source);
  if (!started) toasts.toast(message: const Text('Your screen wasn\'t shared'));
}

/// Asks which screen or window to share, from [sources]: each with a picture of it. The chosen one's id; null if
/// none was chosen.
///
/// The sheet opens at once and looks for the screens itself (Matt, 2026-11-23: "screen sharing on mac and pc doesn't
/// show anything to select"). It used to ask [sources] first and open afterwards, and by then the menu the press
/// came from (the call page closes its menu as it runs a row) had gone, its context with it, so
/// nothing opened and nothing was said. [mac] is for the tests: the words for an empty list on a Mac.
Future<String?> pickScreen(BuildContext context, Future<List<ScreenSource>> Function() sources, {bool? mac}) async {
  String? chosen;
  await showChoices(
    context,
    title: 'Share your screen',
    header: ScreenChoices(sources: sources, mac: mac, onPick: (id) => chosen = id),
    choices: [Choice('Cancel', Lucide.x, () {})],
  );
  return chosen;
}

/// The inside of [pickScreen]'s sheet: looks for the screens and windows, says so while it does, shows them, and
/// keeps looking while it is open. Never blank: with nothing found it says why and what to do, with Try again.
class ScreenChoices extends StatefulWidget {
  const ScreenChoices({super.key, required this.sources, required this.onPick, this.mac});
  final Future<List<ScreenSource>> Function() sources;

  /// Told the chosen one's id; the sheet is closed here.
  final void Function(String id) onPick;

  /// Whether the words for an empty list are a Mac's (its Screen Recording permission). Null: as this device is.
  final bool? mac;

  /// How many times an empty answer is asked again before saying nothing was found, and how long between: the
  /// system's list can come a moment after it is first asked for (flutter_webrtc reports screens as it finds them).
  static const tries = 4;
  static const soon = Duration(milliseconds: 500);

  /// How often the list is asked for again while the sheet is open: a window opened since, a picture that was not
  /// ready the first time, the permission just given.
  static const again = Duration(seconds: 2);

  @override
  State<ScreenChoices> createState() => _ScreenChoicesState();
}

class _ScreenChoicesState extends State<ScreenChoices> {
  /// What was found; null while still looking the first time (or after Try again).
  List<ScreenSource>? _found;
  int _asked = 0;
  Timer? _next;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_look());
  }

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
  }

  Future<void> _look() async {
    if (_asking) return;
    _asking = true;
    _next?.cancel();
    List<ScreenSource> list;
    try {
      list = await widget.sources();
    } catch (e) {
      debugPrint('screen share: the screens could not be listed: $e');
      list = const [];
    }
    _asking = false;
    if (!mounted) return;
    _asked++;
    // An empty answer is not believed until it has been given [ScreenChoices.tries] times.
    final sure = list.isNotEmpty || _asked >= ScreenChoices.tries;
    // Once something was found, a later empty answer (a list asked for mid-change) does not blank the sheet.
    final keep = list.isEmpty && (_found?.isNotEmpty ?? false);
    if (sure && !keep) setState(() => _found = list);
    _next = Timer(sure ? ScreenChoices.again : ScreenChoices.soon, () => unawaited(_look()));
  }

  void _retry() {
    setState(() {
      _found = null;
      _asked = 0;
    });
    unawaited(_look());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final found = _found;
    Widget words(String s) => Padding(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(2)),
          child: Text(s, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.4)),
        );
    if (found == null) return words('Looking for your screens and windows…');
    if (found.isEmpty) {
      final mac = widget.mac ?? PlatformInfo.isMacOS;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        words(mac
            ? 'No screens or windows were found. Your Mac has to allow it: open System Settings › Privacy & Security › Screen & System Audio Recording and turn on Ghost Messaging. If macOS asks, quit and reopen Ghost Messaging, then try again.'
            : 'No screens or windows were found. Try again; if there is still nothing, close Ghost Messaging, open it again and share from there.'),
        Padding(
          padding: EdgeInsets.fromLTRB(t.space(4), 0, t.space(4), t.space(2)),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GlacierPressable(
              onPressed: _retry,
              semanticLabel: 'Try again',
              builder: (context, state) => Container(
                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                decoration: BoxDecoration(color: t.color(state.pressed || state.hovered ? 'app-paper-3' : 'app-paper'), borderRadius: BorderRadius.circular(999), border: Border.all(color: t.color('app-rule'))),
                child: Text('Try again', style: pageText(t, t.fontSize('sm'), weight: 'bold', color: t.color('app-ink'))),
              ),
            ),
          ),
        ),
      ]);
    }
    return ScreenPicker(
      sources: found,
      onPick: (id) {
        widget.onPick(id);
        // The sheet's own navigator, from the sheet's own context: the one that asked may be gone.
        Navigator.of(context).pop();
      },
    );
  }
}

/// The screens, then the windows, two across, each a picture and its name.
class ScreenPicker extends StatelessWidget {
  const ScreenPicker({super.key, required this.sources, required this.onPick});
  final List<ScreenSource> sources;
  final void Function(String id) onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final screens = [for (final s in sources) if (!s.window) s];
    final windows = [for (final s in sources) if (s.window) s];
    Widget heading(String words) => Padding(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(1)),
          child: Text(words, style: pageText(t, t.fontSize('xs'), weight: 'bold', color: t.color('app-ink-3'))),
        );
    Widget grid(List<ScreenSource> list) => Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(3)),
          child: LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - t.space(2)) / 2;
            return Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
              for (final s in list) SizedBox(width: w, child: _SourceTile(source: s, onPick: () => onPick(s.id))),
            ]);
          }),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (screens.isNotEmpty) ...[heading('Screens'), grid(screens)],
      if (windows.isNotEmpty) ...[heading('Windows'), grid(windows)],
      SizedBox(height: t.space(2)),
    ]);
  }
}

/// One screen or window to choose: its picture (an icon where there is none) over its name.
class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.onPick});
  final ScreenSource source;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pic = source.thumbnail;
    final icon = Center(child: AppIcon(source.window ? LucideMore.appWindow : LucideMore.monitor, size: 28, wash: false, color: const Color(0xFF8A8A90)));
    return GlacierPressable(
      onPressed: onPick,
      semanticLabel: 'Share ${source.name}',
      builder: (context, state) => Container(
        padding: EdgeInsets.all(t.space(1)),
        decoration: BoxDecoration(
          color: state.pressed || state.hovered ? t.color('app-paper-3') : const Color(0x00000000),
          borderRadius: BorderRadius.circular(t.radius('lg')),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(t.radius('md')),
              child: ColoredBox(
                color: const Color(0xFF1C1C1F),
                // A picture that can't be read (the Mac's are TIFF) is the icon, not a hole.
                child: pic != null && pic.isNotEmpty ? Image.memory(pic, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => icon) : icon,
              ),
            ),
          ),
          SizedBox(height: t.space(1)),
          Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-2'))),
        ]),
      ),
    );
  }
}

/// Who in [s] is sharing a screen now, other than this device, with their picture once it has arrived: the first to
/// have started, as the members are listed.
({String id, String name, MediaStream? stream})? sharerIn(VoiceSession s) {
  final v = Voice.instance;
  for (final m in s.members.values) {
    if (m.screen) return (id: m.id, name: v.nameOf(m.id), stream: v.media?.remote.value[m.id]);
  }
  return null;
}

/// Someone's screen, large: the whole of it on black, their name over it, and a way back to the call.
class ScreenStage extends StatelessWidget {
  const ScreenStage({super.key, required this.name, required this.stream, required this.onBack});
  final String name;

  /// Null until their picture arrives.
  final MediaStream? stream;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final top = MediaQuery.paddingOf(context).top;
    final s = stream;
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(children: [
        Positioned.fill(
          child: s == null
              ? Center(child: Text('Waiting for $name\'s screen…', style: pageText(t, t.fontSize('sm'), color: const Color(0xFFB0B0B6))))
              // One renderer per stream (GMFB-5).
              : StreamView(key: ObjectKey(s), stream: s, contain: true),
        ),
        Positioned(
          top: top + t.space(2),
          left: t.space(3),
          right: t.space(3),
          child: Row(children: [
            Flexible(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const AppIcon(LucideMore.screenShare, size: 16, wash: false, color: Color(0xFFFFFFFF)),
                  SizedBox(width: t.space(2)),
                  Flexible(child: Text('$name\'s screen', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: const Color(0xFFFFFFFF)))),
                ]),
              ),
            ),
            const Spacer(),
            GlacierPressable(
              onPressed: onBack,
              semanticLabel: 'Back to the call',
              builder: (context, state) => Container(
                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                decoration: BoxDecoration(color: Color(state.pressed ? 0xFFDDDDDD : 0xFFFFFFFF), borderRadius: BorderRadius.circular(999)),
                child: Text('Back to call', style: pageText(t, t.fontSize('sm'), weight: 'bold', color: const Color(0xFF000000))),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The line over a call while a screen is shared: this device's own, with Stop; or someone else's, with View, while
/// their screen is not the one shown large ([onView]).
class ScreenShareBanner extends StatelessWidget {
  const ScreenShareBanner({super.key, required this.session, this.onView});
  final VoiceSession session;
  final VoidCallback? onView;

  /// Whether there is anything to say: this device shares, or someone else does and can be viewed.
  static bool shows(VoiceSession s, {bool viewing = false}) => s.screen || (!viewing && sharerIn(s) != null);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = session;
    final other = sharerIn(s);
    final mine = s.screen;
    if (!mine && (other == null || onView == null)) return const SizedBox.shrink();
    const blue = Color(0xFF2F6FDE);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
      padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
      decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(t.radius('lg'))),
      child: Row(children: [
        const AppIcon(LucideMore.screenShare, size: 16, wash: false, color: Color(0xFFFFFFFF)),
        SizedBox(width: t.space(2)),
        Expanded(
          child: Text(mine ? 'You\'re sharing your screen' : '${other!.name} is sharing their screen',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: const Color(0xFFFFFFFF))),
        ),
        GlacierPressable(
          onPressed: mine ? () => unawaited(s.setScreen(false)) : onView,
          semanticLabel: mine ? 'Stop sharing' : 'View their screen',
          builder: (context, state) => Container(
            padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
            decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(999)),
            child: Text(mine ? 'Stop' : 'View', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: blue)),
          ),
        ),
      ]),
    );
  }
}
