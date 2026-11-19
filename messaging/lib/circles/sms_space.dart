/// SMS spaces: a circle's texting space that people without the app are in by text (Matt, 2026-11-19: "a special space
/// in the circle called a "SMS Space" to text members").
///
/// **Whose phone.** One member's Android phone, the phone's texting app being this one, carries the space to the
/// people who are in it by text: its "texter", named in the space's own entry of the circle's manifest
/// (`CircleSpace.extra['sms'] = {'by': <their id>}`), so every member sees that it is an SMS space and whose phone texts
/// for it. An older build keeps the field unread and shows a texting space.
///
/// **Who is texted** is kept on the texter's phone alone (`sms_space_<seed>`: each person's number and name, and the
/// newest of their texts already brought in): their numbers are never put in the manifest or said to the circle.
///
/// **What goes.** Every message written in the space is texted from the texter's phone to each person by text, as
/// "Name: words" (a file or sticker as words saying so); what each of them texts back comes into the space as
/// "📱 Name: words", written by the texter's app. A text of only STOP takes the person out, and they are told so. The
/// texts are on the texter's plan, as any texts they send.
///
/// The texter's app must be running for texts to go and come (it is kept connected to its circles' spaces).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../sms.dart';
import '../voice/channels.dart';
import '../voice/hangout.dart';
import '../voice/voice.dart';
import 'circles.dart';

/// Someone in an SMS space by text.
@immutable
class TextedPerson {
  const TextedPerson({required this.number, required this.name, this.seen = 0});
  final String number;
  final String name;

  /// When their newest text already brought into the space was sent (ms since 1970): nothing older comes in twice.
  final int seen;

  TextedPerson withSeen(int at) => TextedPerson(number: number, name: name, seen: at);

  Map<String, Object> toJson() => {'n': number, 'm': name, 's': seen};

  static TextedPerson? fromJson(Object? j) {
    if (j is! Map || j['n'] is! String || j['m'] is! String) return null;
    return TextedPerson(number: j['n'] as String, name: j['m'] as String, seen: (j['s'] as num?)?.toInt() ?? 0);
  }
}

/// The mark a message brought in from a text starts with: never texted back out.
const textedMark = '📱 ';

/// Whether [space] is an SMS space, and whose phone texts for it.
String? smsTexterOf(CircleSpace space) {
  final s = space.extra['sms'];
  return s is Map && s['by'] is String ? s['by'] as String : null;
}

/// What a message in the space is texted as: "Name: words", a file or sticker said in words.
String textFor(HangoutMessage m) {
  final parts = <String>[
    if (m.text.trim().isNotEmpty) m.text.trim(),
    if (m.sticker != null) '(a sticker)',
    if (m.files.isNotEmpty) m.voice ? '(a voice message)' : (m.files.length == 1 ? '(a file: ${m.files.first.name})' : '(${m.files.length} files)'),
  ];
  final who = m.name.trim().isEmpty ? 'Someone' : m.name.trim();
  return '$who: ${parts.join(' ')}';
}

/// Whether [m] is one to text out: words or files from anyone, but not one that came in from a text.
bool textsOut(HangoutMessage m) => !m.text.startsWith(textedMark) && (m.text.trim().isNotEmpty || m.files.isNotEmpty || m.sticker != null);

/// What came in by text, as the space shows it.
String broughtIn(String name, String body) => '$textedMark$name: ${body.trim()}';

/// Whether a text says to be taken out.
bool isStop(String body) => const {'stop', 'stop all', 'unsubscribe', 'quit', 'end', 'cancel'}.contains(body.trim().toLowerCase());

class SmsSpaces extends ChangeNotifier {
  SmsSpaces._();
  static final SmsSpaces instance = SmsSpaces._();

  AppState? _app;
  StreamSubscription<int>? _sub;
  final Set<String> _held = {};

  /// The texter's own id: this install's.
  String? get me => Circles.instance.signer?.id;

  /// Starts carrying this phone's SMS spaces: only on a phone that is the texting app.
  void start(AppState app) {
    if (_app != null) return;
    _app = app;
    _sub = Sms.instance.changes.stream.listen((t) => unawaited(_changed(t)));
    Circles.instance.addListener(_hold);
    _hold();
  }

  @visibleForTesting
  void reset() {
    _sub?.cancel();
    Circles.instance.removeListener(_hold);
    _app = null;
    _held.clear();
    _threads.clear();
  }

  /// Every SMS space this phone texts for, with its circle's channel for it.
  List<VoiceChannel> get mine {
    final id = me;
    if (id == null) return const [];
    return [
      for (final c in Circles.instance.all)
        for (final s in c.spaces)
          if (smsTexterOf(s) == id) c.channelOf(s),
    ];
  }

  /// Keeps this phone in the chat room of each space it texts for, so their messages come here as they are written.
  void _hold() {
    for (final c in mine) {
      if (_held.add(c.seed)) unawaited(Voice.instance.hold(c));
    }
  }

  // --- who is texted ------------------------------------------------------------------------------------------------

  static String _key(String seed) => 'sms_space_$seed';

  List<TextedPerson> people(String seed) {
    try {
      return [for (final j in jsonDecode(_app?.choice(_key(seed), '[]') ?? '[]') as List) ?TextedPerson.fromJson(j)];
    } catch (_) {
      return const [];
    }
  }

  void _keep(String seed, List<TextedPerson> list) {
    _app?.set(_key(seed), jsonEncode([for (final p in list) p.toJson()]));
    notifyListeners();
  }

  /// Adds [name] at [number] to [space] by text, and texts them to say so.
  Future<bool> add(VoiceChannel space, String name, String number) async {
    final n = number.trim();
    if (n.isEmpty) return false;
    final list = people(space.seed);
    if (list.any((p) => p.number == n)) return false;
    _keep(space.seed, [...list, TextedPerson(number: n, name: name.trim().isEmpty ? n : name.trim(), seen: DateTime.now().millisecondsSinceEpoch)]);
    final circle = Circles.instance.circleOf(space)?.name;
    await _send([n], 'You\'re in ${space.name}${circle == null ? '' : ' in $circle'} by text: what people write there comes to you here, and what you text back goes to all of them. Text STOP to leave.');
    Voice.instance.hangoutFor(space)?.send('$textedMark${name.trim().isEmpty ? n : name.trim()} is in this space by text now.');
    return true;
  }

  /// Takes [number] out of [space]; [tell]: text them that they are out.
  Future<void> remove(VoiceChannel space, String number, {bool tell = true}) async {
    final list = people(space.seed);
    final p = list.where((x) => x.number == number).firstOrNull;
    if (p == null) return;
    _keep(space.seed, [for (final x in list) if (x.number != number) x]);
    if (tell) await _send([number], 'You\'ve left ${space.name}. You won\'t get its messages by text any more.');
    Voice.instance.hangoutFor(space)?.send('$textedMark${p.name} left this space.');
  }

  // --- out: the space's messages, texted ------------------------------------------------------------------------------

  /// Told of each message [room] takes in (Voice's onFresh): those in a space this phone texts for go out by text.
  void heard(HangoutRoom room, List<HangoutMessage> fresh) {
    if (_app == null) return;
    final seed = room.channel.seed;
    if (!mine.any((c) => c.seed == seed)) return;
    final to = [for (final p in people(seed)) p.number];
    if (to.isEmpty) return;
    for (final m in fresh) {
      if (!textsOut(m)) continue;
      // Only what is new: a device coming back into the room is handed history it has seen.
      if (DateTime.now().millisecondsSinceEpoch - m.at > const Duration(minutes: 10).inMilliseconds) continue;
      unawaited(_send(to, textFor(m)));
    }
  }

  /// Each person on their own, so nobody's number goes to the others and a reply comes back to this phone alone.
  Future<void> _send(List<String> numbers, String body) async {
    for (final n in numbers) {
      try {
        await Sms.instance.send([n], body);
      } catch (_) {}
    }
  }

  // --- in: what the texted people send ------------------------------------------------------------------------------

  final Map<String, int> _threads = {};

  Future<int?> _threadOf(String number) async {
    final had = _threads[number];
    if (had != null) return had;
    try {
      return _threads[number] = await Sms.instance.threadFor([number]);
    } catch (_) {
      return null;
    }
  }

  Future<void> _changed(int thread) async {
    for (final c in mine) {
      final list = people(c.seed);
      for (final p in list) {
        final t = await _threadOf(p.number);
        if (t == null || (thread != -1 && t != thread)) continue;
        List<Message> got;
        try {
          got = await Sms.instance.messages(t, limit: 20);
        } catch (_) {
          continue;
        }
        final fresh = [for (final m in got) if (!m.outgoing && m.date.millisecondsSinceEpoch > p.seen && m.body.trim().isNotEmpty) m]..sort((a, b) => a.date.compareTo(b.date));
        if (fresh.isEmpty) continue;
        final now = people(c.seed);
        _keep(c.seed, [for (final x in now) x.number == p.number ? x.withSeen(fresh.last.date.millisecondsSinceEpoch) : x]);
        for (final m in fresh) {
          if (isStop(m.body)) {
            await remove(c, p.number);
            break;
          }
          Voice.instance.hangoutFor(c)?.send(broughtIn(p.name, m.body));
        }
      }
    }
  }
}
