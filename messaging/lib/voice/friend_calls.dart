/// Calling one friend, the way you would a phone (GMFB-28, from the Uplink gap review: "Ring one friend with a voice or
/// video call, the way you would a phone, without making a space first").
///
/// A call between two friends by username is a channel of its own that only the two of them can work out: its seed is
/// made from their two names ([channelWith]), so the call is the existing WebRTC call of a space (lib/voice/rtc.dart,
/// with the relay's TURN server where the two can't reach each other), with no space made and nothing listed.
///
/// Ringing is said in sealed `voice` envelopes, as a group's ringing is (lib/voice/channels.dart):
///
/// - **call** (`t: call`, its id, whether video): the caller is in the call already and hears it ring out; every device
///   of the friend's rings (one identity, so the relay hands it to each that is connected).
/// - **decline**: the friend said no; the caller's call ends.
/// - **cancel**: the caller hung up, or nobody answered in [ringFor]; the friend's ringing stops, and a missed call is
///   kept in the chat.
/// - **answered**, to this account's own other devices (Net.mine, GMFB-21): one of them answered or declined, so the
///   rest stop ringing.
///
/// Each side keeps a line in the conversation with the friend ([CallNotes]): a missed call, a declined one, no answer.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../friends/buddies.dart';
import '../me/me.dart';
import '../net/carrier.dart' show Peer;
import '../net/crypto.dart';
import '../net/net.dart';
import '../net/packet.dart';
import '../net/switchboard.dart';
import '../sms.dart';
import '../sounds.dart';
import 'channels.dart';
import 'voice.dart';

/// Where a conversation's call lines are kept (the username chats, lib/standalone/chats.dart, through the app's calls).
abstract class CallNotes {
  void note(String address, String words, {required bool out});
}

class _SmsCallNotes implements CallNotes {
  @override
  void note(String address, String words, {required bool out}) =>
      unawaited(Sms.instance.callNote(address, words, DateTime.now().millisecondsSinceEpoch, out: out).catchError((_) {}));
}

/// What [FriendCalls] sends with and through: the routes, this install's name. A test gives its own.
abstract class FriendCallsPort {
  String? get myId;
  Peer? peerOf(String id);
  Future<bool> send(Peer peer, Envelope envelope, {bool urgent = false});
  Future<void> sendMine(Envelope envelope);
}

class _NetPort implements FriendCallsPort {
  @override
  String? get myId => Net.instance.id;
  @override
  Peer? peerOf(String id) => Net.instance.byId(id);
  @override
  Future<bool> send(Peer peer, Envelope envelope, {bool urgent = false}) async => (await Net.instance.send(peer, envelope, urgent: urgent)).sent;
  @override
  Future<void> sendMine(Envelope envelope) async {
    final board = Net.instance.board;
    final me = await Net.instance.mine();
    if (board == null || me == null) return;
    await board.send(me, envelope, only: const {'hub'});
  }
}

/// A call to a friend this device made and that nobody has answered yet.
class _Outgoing {
  _Outgoing(this.id, this.buddy, this.video, this.channel);
  final String id;
  final Buddy buddy;
  final bool video;
  final VoiceChannel channel;
  Timer? gives;
}

class FriendCalls {
  FriendCalls({FriendCallsPort? port, CallNotes? notes})
      : _port = port ?? _NetPort(),
        _notes = notes ?? _SmsCallNotes();
  static FriendCalls instance = FriendCalls();

  final FriendCallsPort _port;
  final CallNotes _notes;

  /// How long a call rings before it is a missed call.
  static const ringFor = Duration(seconds: 35);

  /// The marker a call's channel carries in place of a group's id: it is nobody's space, and is listed nowhere.
  static const groupMark = 'call';

  _Outgoing? _out;

  /// The call this device is ringing out, while it is.
  String? get ringingOut => _out?.id;

  /// Told when a call this device made ends unanswered, with why ("declined", "no answer"): the screen says so.
  final ValueNotifier<String?> ended = ValueNotifier(null);

  /// The channel of a call between this install and [other] (install names): the same on both sides, whoever calls.
  static VoiceChannel channelWith(String me, String other, String name) {
    final pair = ([me, other]..sort()).join('|');
    return VoiceChannel(seed: NetCrypto.hex(NetCrypto.sha256(utf8.encode('ghost-voice call|$pair'))), name: name, group: groupMark);
  }

  /// Whether [c] is a call between two friends.
  static bool isCall(VoiceChannel c) => c.group == groupMark;

  static String _addressOf(Buddy b) => '@${b.username}';

  String get _myName => Me.instance.shownName.isEmpty ? 'Someone' : Me.instance.shownName;

  /// Calls [buddy]: this device goes into the call's channel, and the friend's devices ring. False where they can't be
  /// reached now (no way to them, or the send failed); this device is then not left waiting in the call.
  Future<bool> call(Buddy buddy, {bool video = false, Future<void> Function(VoiceChannel c, bool video)? join}) async {
    final me = _port.myId;
    final peer = _port.peerOf(buddy.id);
    if (me == null || peer == null) return false;
    final c = channelWith(me, buddy.id, buddy.shown);
    await (join ?? (c, v) => Voice.instance.join(c, video: v))(c, video);
    final id = NetCrypto.hex(NetCrypto.randomBytes(8));
    final sent = await _port.send(peer, Envelope(kind: 'voice', body: {'t': 'call', 'i': id, 'v': video, 'n': _myName}), urgent: true);
    if (!sent) return false;
    final out = _out = _Outgoing(id, buddy, video, c);
    Sounds.instance.loop(UiSound.ringOut);
    out.gives = Timer(ringFor, () => _unanswered(out, 'no answer'));
    return true;
  }

  /// Someone came into the call this device is ringing out: answered.
  void joined(VoiceChannel c) {
    final out = _out;
    if (out == null || out.channel.room != c.room) return;
    out.gives?.cancel();
    _out = null;
    Sounds.instance.stopLoop(UiSound.ringOut);
  }

  /// This device left [c]: a call it was still ringing out is called off, and the friend's devices stop ringing.
  void left(VoiceChannel c) {
    final out = _out;
    if (out == null || out.channel.room != c.room) return;
    _cancel(out, 'cancelled');
  }

  void _unanswered(_Outgoing out, String why) {
    if (!identical(_out, out)) return;
    _cancel(out, why);
    if (Voice.instance.session?.channel.room == out.channel.room) unawaited(Voice.instance.leave());
  }

  void _cancel(_Outgoing out, String why) {
    out.gives?.cancel();
    _out = null;
    Sounds.instance.stopLoop(UiSound.ringOut);
    final peer = _port.peerOf(out.buddy.id);
    if (peer != null) unawaited(_port.send(peer, Envelope(kind: 'voice', body: {'t': 'cancel', 'i': out.id})).catchError((_) => false));
    final kind = out.video ? 'video call' : 'call';
    _notes.note(_addressOf(out.buddy), why == 'no answer' ? 'No answer · $kind' : 'Cancelled $kind', out: true);
    if (why == 'no answer') ended.value = '${out.buddy.shown} didn\'t answer';
  }

  /// A `voice` envelope for calls; true where it was one ([Voice] passes on what it doesn't take itself).
  bool received(Received r, {required bool mine}) {
    final b = r.envelope.body;
    final id = b['i'];
    if (id is! String) return false;
    final v = Voice.instance;
    switch (b['t']) {
      case 'call':
        final buddy = Buddies.instance.byId(r.peer.id);
        final me = _port.myId;
        // Only a friend's, and only someone this install knows.
        if (buddy == null || buddy.state != 'yes' || me == null) return true;
        // A ring that stopped ringing before it got here (held, or sent again late): missed, not rung (GMFB-26). A
        // little slack for the two clocks.
        if (DateTime.now().millisecondsSinceEpoch - r.envelope.at > (ringFor + const Duration(seconds: 30)).inMilliseconds) {
          _missed(buddy, VoiceRing(channelWith(me, buddy.id, buddy.shown), buddy.shown, DateTime.fromMillisecondsSinceEpoch(r.envelope.at), call: id, video: b['v'] == true, caller: buddy.id));
          return true;
        }
        final c = channelWith(me, buddy.id, buddy.shown);
        final ring = VoiceRing(c, buddy.shown, DateTime.now(), call: id, video: b['v'] == true, caller: buddy.id);
        v.ringFor(ring, ringFor, onUnanswered: () => _missed(buddy, ring));
        return true;
      case 'cancel':
        final ring = v.ringing;
        if (ring == null || ring.call != id) return true;
        final buddy = Buddies.instance.byId(r.peer.id);
        v.clearRing(ring);
        if (buddy != null) _missed(buddy, ring);
        return true;
      case 'decline':
        final out = _out;
        if (out == null || out.id != id || out.buddy.id != r.peer.id) return true;
        out.gives?.cancel();
        _out = null;
        Sounds.instance.stopLoop(UiSound.ringOut);
        _notes.note(_addressOf(out.buddy), 'Declined · ${out.video ? 'video call' : 'call'}', out: true);
        ended.value = '${out.buddy.shown} declined';
        if (v.session?.channel.room == out.channel.room) unawaited(v.leave());
        return true;
      case 'answered':
        // Another device of this account answered or declined: this one stops ringing, with no missed call kept.
        if (!mine) return true;
        final ring = v.ringing;
        if (ring != null && ring.call == id) v.clearRing(ring);
        return true;
    }
    return false;
  }

  void _missed(Buddy buddy, VoiceRing ring) => _notes.note(_addressOf(buddy), 'Missed ${ring.video ? 'video call' : 'call'}', out: false);

  /// The friend's ring answered here: the other devices of this account stop ringing.
  void answered(VoiceRing ring) {
    final id = ring.call;
    if (id == null) return;
    unawaited(_port.sendMine(Envelope(kind: 'voice', body: {'t': 'answered', 'i': id})).catchError((_) {}));
  }

  /// The friend's ring declined here: the caller is told, and this account's other devices stop ringing.
  void decline(VoiceRing ring) {
    final id = ring.call, caller = ring.caller;
    if (id == null || caller == null) return;
    final peer = _port.peerOf(caller);
    if (peer != null) unawaited(_port.send(peer, Envelope(kind: 'voice', body: {'t': 'decline', 'i': id})).catchError((_) => false));
    answered(ring);
  }
}
