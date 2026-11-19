import 'dart:async';
import '../names.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../files/file_kinds.dart';
import '../files/files_model.dart';
import '../mentions.dart';
import '../net/crypto.dart';
import '../net/hub_carrier.dart';
import 'channels.dart' show AppHangoutStore;
import 'roles.dart';
import 'voice.dart';
import '../me/me.dart' show Me;
import '../me/pictures.dart';
import 'polls.dart';

export 'polls.dart';

/// A hangout's chat, and its roles kept and enforced (Matt, 2026-11-15: "Implement a permissions system similar to
/// discord for hangouts and add a chat to hangouts so the whole group can send messages to the hangout as well as
/// voice and video, make default roles such as admin, moderator, member").
///
/// **Its room.** Beside the call's room each hangout has a chat room on the hub (VoiceChannel.chatRoom), sealed with
/// the same key, which anyone looking at the hangout is in, in the call or not. Everything here goes through it:
/// messages, deletions, the roster (lib/voice/roles.dart) and what moderators do.
///
/// **History.** The hub keeps nothing. Each device keeps the last [keep] messages it saw ([HangoutStore]); coming in,
/// it asks for what it missed and the one there with the lowest id answers, so one copy comes back, not one from each.
/// The roster comes the same way, from anyone whose is newer and checks out.
///
/// **Enforcement.** Each device does what the roster says of what it hears: a message from someone who may not write
/// is not shown, a deletion by someone who may not delete is ignored, someone muted for everyone is silenced on every
/// device ([onRoster]: lib/voice/channels.dart), someone banned is not answered at all, and a device told to leave by
/// someone above it with the right to remove people leaves.
class HangoutRoom extends ChangeNotifier {
  /// Someone not heard here at all besides the banned: put out of the circle this space is in (Voice sets it).
  bool Function(String id)? shut;

  HangoutRoom({required this.channel, required this.route, required this.name, this.username, this.signer, HangoutStore? store})
      : store = store ?? MemoryHangoutStore() {
    roster = this.store.roster(channel.chatRoom) ?? Roster.first(channel.owner, kind: channel.kind);
    if (roster.owner != channel.owner) roster = Roster.first(channel.owner, kind: channel.kind);
    messages = this.store.messages(channel.chatRoom);
    _loadAbout();
    _loadVotes();
  }

  static const keep = 300;

  /// The space: replaced, same seed, when the circle it is in changes its kind ([updateChannel]).
  VoiceChannel channel;
  final VoiceRoute route;
  final HangoutStore store;

  /// What this install signs rosters with; null where it can't (it then changes nothing).
  final NetSigner? signer;
  String name;
  String? username;

  late Roster roster;
  late List<HangoutMessage> messages;

  /// Who is in the chat room now, with what they said of themselves.
  final Map<String, HangoutPerson> present = {};

  /// The username each install here has said it goes by, kept after it leaves: one person's phone and paired computer
  /// are two installs here under one username.
  final Map<String, String> usernames = {};

  /// Whether [m] mentions the person on this device: this install, or another install of theirs (their phone, their
  /// computer), known by saying the same username as this one does (Matt, 2026-11-19: "Add mentions support to spaces
  /// and circles with the @user prefix").
  bool mentionsMe(HangoutMessage m) {
    if (m.mentions.isEmpty || m.from == me) return false;
    final mine = username;
    // Written by another install of this person's: not a mention to be told of.
    if (mine != null && mine.isNotEmpty && usernames[m.from] == mine) return false;
    return m.mentions.any((x) => x.id == me || (mine != null && mine.isNotEmpty && usernames[x.id] == mine));
  }

  /// Set when someone with the right to told this device to leave, or it was banned: why.
  String? putOut;
  bool opened = false;

  /// Told when the roster changes, to do what it says in the call (who is heard, who is seen).
  void Function(Roster roster)? onRoster;

  /// Told of the messages the chat takes in that it did not have, sent here or heard (a mention's notification:
  /// lib/voice/mention_alerts.dart).
  void Function(List<HangoutMessage> fresh)? onFresh;

  /// Told of the words between an SMS space's texting phone and its members' phones, each a map whose `t` is `sms?`
  /// or `sms#` (lib/circles/sms_space.dart): said to one device alone, never kept, ignored by an older build.
  void Function(String from, Map<String, dynamic> said)? onSignal;

  /// Says [what] to the chat room, for [onSignal]'s words: with `to`, to that one person's devices alone.
  void signal(Map<String, Object?> what) => _say(what);

  final List<StreamSubscription<Object?>> _subs = [];

  String get me => route.me;
  bool can(Perm p) => roster.can(me, p);

  Future<void> open() async {
    if (opened) return;
    opened = true;
    putOut = roster.banned.contains(me) ? 'You were banned from this space.' : null;
    _subs.add(route.packets.where((p) => p.room == channel.chatRoom).listen((p) => _heard(p.from, p.bytes)));
    _subs.add(route.events.where((e) => e.room == channel.chatRoom).listen(_event));
    final List<String> there;
    try {
      there = await route.join(channel.chatRoom, channel.chatToken);
    } catch (_) {
      // Not in yet (the relay server slow to answer): in as soon as it is, when [_event] hears who is here.
      _dropped = true;
      return;
    }
    for (final id in there) {
      present[id] = present[id] ?? HangoutPerson(id);
    }
    _hi(ask: true);
    _say({'t': 'sync?', 'since': messages.isEmpty ? 0 : messages.last.at, 'v': roster.version, 'av': _about?.version ?? 0});
    notifyListeners();
  }

  Future<void> close() async {
    if (!opened) return;
    opened = false;
    route.leave(channel.chatRoom);
    // Taken out first: an open() while these are cancelled starts a list of its own.
    final subs = [..._subs];
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
    present.clear();
    notifyListeners();
  }

  /// Said again when this device goes in or out of the call, or its name changes.
  void sayMe({bool? inVoice}) {
    if (inVoice != null) _inVoice = inVoice;
    _hi();
  }

  bool _inVoice = false;

  /// Says who this is. [ask]: on coming in, those here answer with theirs. The relay tells the room someone came only
  /// with their first device, so a person's second device (one identity on a phone and its computer) was greeted by
  /// nobody and saw those here without their names until they spoke.
  void _hi({bool ask = false}) {
    final me = Me.instance;
    _say({'t': 'hi', 'n': name, if (username != null) 'u': username, 'a': _inVoice, if (ask) 'q': true, if (me.status.isNotEmpty) 'st': me.status, if (me.picture.isNotEmpty) 'ph': ProfilePictures.hashOf(me.picture)});
  }

  final Map<String, Completer<String?>> _askedPictures = {};

  /// [id]'s profile picture: the one kept here where it is theirs now, else asked of them (`pic?`, answered `pic` by
  /// the person alone); null where they have none, or no answer comes within a few seconds.
  Future<String?> pictureOf(String id) async {
    final hash = present[id]?.pictureHash ?? '';
    // Here and saying no picture: none, whatever was kept from before (they took theirs away).
    if (present.containsKey(id) && hash.isEmpty) return null;
    final kept = ProfilePictures.instance.of(id, hash: hash.isEmpty ? null : hash);
    if (kept != null || hash.isEmpty) return kept;
    final asked = _askedPictures[id] ??= Completer<String?>();
    _say({'t': 'pic?', 'to': id});
    try {
      return await asked.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      return null;
    } finally {
      _askedPictures.remove(id);
    }
  }

  /// When each newcomer was last greeted ([_greet]): once, whether they came with their first device or said hi asking.
  final Map<String, DateTime> _greeted = {};

  void _greet(String id) {
    final at = _greeted[id];
    if (at != null && DateTime.now().difference(at) < const Duration(seconds: 10)) return;
    _greeted[id] = DateTime.now();
    _hi();
  }

  // --- chat --------------------------------------------------------------------------------------------------------

  /// Writes [text] to the hangout; false where this device may not.
  bool send(String text, {List<Mention> mentions = const []}) => sendWith(text: text, mentions: mentions);

  /// Whether this device may write here at all: the roster's Send messages, and not put out. Files and stickers are
  /// part of writing (Matt, 2026-11-18): whoever may write may send them (in a circle its roles say more:
  /// lib/ui/space_chat_files.dart spaceMayAttach).
  bool get mayWrite => can(Perm.chat) && putOut == null;

  /// Writes [text], with [files] that are up already or a [sticker], to the hangout; false where this device may not or
  /// there is nothing to send. [id]: the one an [OutgoingMessage] was shown under.
  /// [mentions]: who is meant by an "@Name" in [text], counted in [text] as given (lib/mentions.dart).
  bool sendWith({String text = '', List<SpaceFile> files = const [], String? sticker, bool voice = false, String? id, List<Mention> mentions = const []}) {
    var words = text.trim();
    if (sticker != null && !HangoutMessage.stickerPattern.hasMatch(sticker)) return false;
    final extra = files.isNotEmpty || sticker != null;
    if ((words.isEmpty && !extra) || !mayWrite) return false;
    final most = extra ? HangoutMessage.mostWordsWith : 4000;
    if (words.length > most) words = words.substring(0, most);
    final m = fitted(HangoutMessage(
      id: id ?? NetCrypto.hex(NetCrypto.randomBytes(8)),
      from: me,
      name: name,
      text: words,
      at: DateTime.now().millisecondsSinceEpoch,
      files: sticker != null ? const [] : files.take(HangoutMessage.mostFiles).toList(),
      sticker: sticker,
      voice: voice && files.length == 1 && sticker == null,
      // Counted in the words as sent: trimmed, and cut short where too long (a mention past the cut goes).
      mentions: Mention.checked(Mention.trimmed(mentions, text), words),
    ));
    _add([m]);
    _say({'t': 'msg', ...m.toJson()}, keep: true);
    return true;
  }

  // --- polls (Matt, 2026-11-19: "add Polls as a default feature"; lib/voice/polls.dart) --------------------------------

  /// Each poll's votes: by the poll's id, then by the voter's id.
  final Map<String, Map<String, PollVote>> _votes = {};

  /// The most polls whose votes are kept, newest first ([_keepVotes]): older polls' votes go.
  static const pollsKept = 200;

  /// Asks [question] with [poll]'s answers; false where this device may not write here or it is not a poll.
  bool sendPoll(String question, PollSpec poll) {
    var q = question.trim();
    if (q.isEmpty || poll.options.length < PollSpec.least || !mayWrite) return false;
    if (q.length > PollSpec.questionMost) q = q.substring(0, PollSpec.questionMost);
    final m = HangoutMessage(id: NetCrypto.hex(NetCrypto.randomBytes(8)), from: me, name: name, text: q, at: DateTime.now().millisecondsSinceEpoch, poll: poll);
    _add([m]);
    _say({'t': 'msg', ...m.toJson()}, keep: true);
    return true;
  }

  /// Votes for [choices] (answers' indexes) in [poll]; none takes this person's vote back. False where it can't be.
  bool vote(HangoutMessage poll, List<int> choices) {
    final spec = poll.poll;
    if (spec == null || !mayWrite) return false;
    final chosen = PollVote.valid(spec, choices);
    final v = PollVote(chosen, DateTime.now().millisecondsSinceEpoch);
    _takeVote(poll.id, me, v);
    _say({'t': 'vote', 'p': poll.id, 'c': chosen, 'at': v.at}, keep: true);
    _keepVotes();
    notifyListeners();
    return true;
  }

  /// [poll]'s answers counted, each person once (by their username, where they said it, across their devices).
  PollTally tally(HangoutMessage poll) => tallyPoll(poll.poll!, _votes[poll.id] ?? const {}, personOf: _personOf, me: me);

  String _personOf(String id) {
    final u = id == me ? Me.instance.username : usernames[id];
    return u == null || u.isEmpty ? id : 'u:${u.toLowerCase()}';
  }

  /// [v] as [voter]'s vote in [poll], where it is later than the one had.
  bool _takeVote(String poll, String voter, PollVote v) {
    final of = _votes[poll] ??= {};
    final had = of[voter];
    if (had != null && had.at >= v.at) return false;
    of[voter] = v;
    return true;
  }

  void _heardVote(String from, Map<String, dynamic> m) {
    final poll = m['p'], c = m['c'], at = m['at'];
    if (poll is! String || c is! List || at is! int || !roster.can(from, Perm.chat)) return;
    if (_takeVote(poll, from, PollVote([for (final x in c.take(PollSpec.most)) if (x is int) x], at))) {
      _keepVotes();
      notifyListeners();
    }
  }

  void _heardVotes(Object? all) {
    if (all is! Map) return;
    var any = false;
    for (final p in all.entries.take(pollsKept)) {
      if (p.key is! String || p.value is! Map) continue;
      for (final v in (p.value as Map).entries) {
        final vote = PollVote.fromJson(v.value);
        if (v.key is String && vote != null && roster.can(v.key as String, Perm.chat)) any = _takeVote(p.key as String, v.key as String, vote) || any;
      }
    }
    if (any) {
      _keepVotes();
      notifyListeners();
    }
  }

  /// The votes of the polls among [of], as a `votes` answer carries them.
  Map<String, Object> _votesOf(Iterable<HangoutMessage> of) => {
        for (final m in of)
          if (m.poll != null && (_votes[m.id]?.isNotEmpty ?? false)) m.id: {for (final e in _votes[m.id]!.entries) e.key: e.value.toJson()},
      };

  void _keepVotes() {
    final s = store;
    if (s is! HangoutVotesStore) return;
    // The newest polls' votes, those of polls still here first.
    final here = {for (final m in messages) if (m.poll != null) m.id};
    final ids = [..._votes.keys.where(here.contains), ..._votes.keys.where((k) => !here.contains(k))].reversed.take(pollsKept);
    (s as HangoutVotesStore).keepVotes(channel.chatRoom, jsonEncode({for (final id in ids) id: {for (final e in _votes[id]!.entries) e.key: e.value.toJson()}}));
  }

  void _loadVotes() {
    final s = store;
    if (s is! HangoutVotesStore) return;
    try {
      final all = jsonDecode((s as HangoutVotesStore).votesOf(channel.chatRoom) ?? '{}');
      if (all is! Map) return;
      for (final p in all.entries) {
        if (p.value is! Map) continue;
        for (final v in (p.value as Map).entries) {
          final vote = PollVote.fromJson(v.value);
          if (vote != null) _takeVote('${p.key}', '${v.key}', vote);
        }
      }
    } catch (_) {}
  }

  /// The most of a message's sealed words that go in one of the hub's packets (60 KB), with room for the sealing.
  static const wireMost = 52 * 1024;

  /// [messages] as they go in a `hist` answer, in lots that each go in one packet.
  static List<List<Map<String, Object>>> histLots(Iterable<HangoutMessage> messages) {
    final lots = <List<Map<String, Object>>>[];
    var lot = <Map<String, Object>>[];
    var bytes = 0;
    for (final x in messages) {
      final j = x.toJson()..['f'] = x.from;
      final n = utf8.encode(jsonEncode(j)).length + 1;
      if (lot.isNotEmpty && bytes + n > wireMost - 128) {
        lots.add(lot);
        lot = [];
        bytes = 0;
      }
      lot.add(j);
      bytes += n;
    }
    if (lot.isNotEmpty) lots.add(lot);
    return lots;
  }

  /// [m], its files' small pictures let go of, the biggest first, until it goes in one packet ([wireMost]).
  static HangoutMessage fitted(HangoutMessage m) {
    int size(HangoutMessage x) => utf8.encode(jsonEncode({'t': 'msg', ...x.toJson()})).length;
    var files = m.files;
    while (size(m.copyWith(files: files)) > wireMost) {
      final withThumb = [for (final f in files) if (f.thumb != null) f];
      if (withThumb.isEmpty) break;
      final biggest = withThumb.reduce((a, b) => a.thumb!.length >= b.thumb!.length ? a : b);
      files = [for (final f in files) f == biggest ? f.withoutThumb() : f];
    }
    return m.copyWith(files: files);
  }

  /// Messages with files on their way up (Matt, 2026-11-18): shown under the rest until they are sent.
  final List<OutgoingMessage> outgoing = [];

  /// Sends [picked] (files on this device) up, sealed, with [text], and the message once they are all there; null where
  /// this device may not write here or nothing could be read. [voice]: the one file is a voice message.
  OutgoingMessage? sendFiles(List<({String path, bool owned})> picked, ChatUploads uploads, {String text = '', bool voice = false, List<Mention> mentions = const []}) {
    if (!mayWrite) return null;
    final files = <OutgoingFile>[];
    for (final p in picked.take(HangoutMessage.mostFiles)) {
      int size;
      try {
        size = File(p.path).lengthSync();
      } catch (_) {
        continue;
      }
      final cleaned = SpaceFile.cleanName(p.path.split(Platform.pathSeparator).last.split('/').last);
      final name = cleaned.isEmpty ? 'File' : cleaned;
      files.add(OutgoingFile(path: p.path, name: name, size: size, mime: FileKind.mimeOf(name), owned: p.owned));
    }
    if (files.isEmpty) return null;
    var words = text.trim();
    if (words.length > HangoutMessage.mostWordsWith) words = words.substring(0, HangoutMessage.mostWordsWith);
    final o = OutgoingMessage(id: NetCrypto.hex(NetCrypto.randomBytes(8)), text: words, files: files, at: DateTime.now().millisecondsSinceEpoch, voice: voice && files.length == 1, mentions: Mention.trimmed(mentions, text));
    outgoing.add(o);
    notifyListeners();
    unawaited(_push(o, uploads));
    return o;
  }

  /// [o] tried again where it failed.
  void retry(OutgoingMessage o, ChatUploads uploads) {
    if (!outgoing.contains(o)) return;
    o.error = null;
    for (final f in o.files) {
      f.error = null;
    }
    notifyListeners();
    unawaited(_push(o, uploads));
  }

  /// [o] not sent after all: its files stopped and let go of.
  void discard(OutgoingMessage o, ChatUploads uploads) {
    if (!outgoing.remove(o)) return;
    for (final f in o.files) {
      if (f.file == null) uploads.drop(f);
    }
    notifyListeners();
  }

  Future<void> _push(OutgoingMessage o, ChatUploads uploads) async {
    // Each file's small picture its share of what a message may carry: a few pictures each get a clear one, ten a
    // smaller one each, and the message still goes in one packet ([fitted] lets go of any that would not).
    final thumbMost = math.min(SpaceFile.maxThumb, (24 * 1024) ~/ o.files.length);
    await Future.wait([
      for (final f in o.files)
        if (f.file == null)
          () async {
            try {
              f.file = await uploads.uploadForChat(channel, f, byName: name, thumbMost: thumbMost, moved: notifyListeners);
              f.error = null;
              f.waiting = null;
            } catch (e) {
              f.error = e.toString().isEmpty ? 'It didn\'t go up.' : e.toString();
            }
            if (outgoing.contains(o)) notifyListeners();
          }(),
    ]);
    if (!outgoing.contains(o) || o.files.any((f) => f.file == null)) return;
    if (sendWith(id: o.id, text: o.text, files: [for (final f in o.files) f.file!], voice: o.voice, mentions: o.mentions)) {
      outgoing.remove(o);
    } else {
      o.error = putOut ?? 'Your role can\'t send messages here.';
    }
    notifyListeners();
  }

  /// Whether this device may delete [m]: its own, or anyone's with Manage messages.
  bool canDelete(HangoutMessage m) => m.from == me || (can(Perm.manageMessages) && roster.outranks(me, m.from)) || roster.isOwner(me);

  void delete(HangoutMessage m) {
    if (!canDelete(m)) return;
    _drop(m.id);
    _say({'t': 'del', 'id': m.id}, keep: true);
  }

  void _add(Iterable<HangoutMessage> fresh) {
    final have = {for (final m in messages) m.id};
    final more = [for (final m in fresh) if (have.add(m.id)) m];
    if (more.isEmpty) return;
    // By when they were written, and two written in the same millisecond by id: each device kept those in the order it
    // happened to hear them, so the writer saw its own first and everyone else the other's (hangout_test's chat case
    // caught the two devices disagreeing).
    messages = [...messages, ...more]..sort((a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.id.compareTo(b.id));
    if (messages.length > keep) messages = messages.sublist(messages.length - keep);
    store.keepMessages(channel.chatRoom, messages);
    notifyListeners();
    onFresh?.call(more);
  }

  void _drop(String id) {
    final before = messages.length;
    messages = [for (final m in messages) if (m.id != id) m];
    if (messages.length == before) return;
    store.keepMessages(channel.chatRoom, messages);
    notifyListeners();
  }

  // --- roles and moderation -------------------------------------------------------------------------------------

  bool get canManage => roster.canManage(me) && signer != null;

  /// Gives [id] [roleId]. Making an admin is the owner's alone: it carries the owner's signature that they are one.
  Future<bool> setRole(String id, String roleId) async {
    if (!canManage || !roster.outranks(me, id)) return false;
    final role = roster.roleById(roleId);
    if (role == null) return false;
    final grants = {...roster.adminGrants};
    if (roleId == Role.admin) {
      if (!roster.isOwner(me)) return false;
      grants[id] = NetCrypto.hex(await signer!.sign(Roster.grantMessage(roster.owner, id)));
    } else {
      grants.remove(id);
      // An admin gives out only roles below their own.
      if (!roster.isOwner(me) && role.rank >= roster.roleOf(me).rank) return false;
    }
    final assigned = {...roster.assigned, id: roleId};
    return _publish(roster.next(assigned: assigned, adminGrants: grants));
  }

  /// Makes [id] an admin, signed by [owner] where that is this space's owner: a paired computer giving what it made
  /// under a key of its own to the identity it speaks as now (Voice.carryOver). True where nothing is left to do.
  Future<bool> grantAdminAs(NetSigner owner, String id) async {
    if (!roster.isOwner(owner.id) || roster.canManage(id)) return true;
    // Not in the room yet: said now it would go nowhere (the relay drops a room's packet from outside it), so not done.
    if (!opened || _dropped) return false;
    final grants = {...roster.adminGrants, id: NetCrypto.hex(await owner.sign(Roster.grantMessage(roster.owner, id)))};
    final next = roster.next(assigned: {...roster.assigned, id: Role.admin}, adminGrants: grants);
    final signed = await next.signedBy(owner.id, owner.publicKey, owner.sign);
    if (!signed.trustedFor(channel.owner)) return false;
    _take(signed);
    _say({'t': 'roster', 'r': signed.toJson()}, keep: true);
    return true;
  }

  /// Mutes [id] for everyone, or lets them speak again.
  Future<bool> muteForAll(String id, bool on) async {
    if (!can(Perm.muteOthers) || !roster.outranks(me, id)) return false;
    // A mute stands in the roster when an admin makes it; a moderator's is said to the room and held while they are.
    if (canManage) {
      final muted = {...roster.muted};
      on ? muted.add(id) : muted.remove(id);
      return _publish(roster.next(muted: muted));
    }
    // Said to everyone (not to them alone): every device holds it.
    _say({'t': 'mute', 'who': id, 'on': on});
    _applyMute(id, on);
    return true;
  }

  /// Moderators' mutes, held on each device while it is in the hangout.
  final Set<String> heldMutes = {};

  void _applyMute(String id, bool on) {
    on ? heldMutes.add(id) : heldMutes.remove(id);
    onRoster?.call(roster);
    notifyListeners();
  }

  /// Whether [id] may be heard: the roster, and any mute a moderator said.
  bool heard(String id) => roster.can(id, Perm.speak) && !heldMutes.contains(id);

  /// Puts [id] out of the hangout now; they can come back.
  bool remove(String id) {
    if (!can(Perm.removeMembers) || !roster.outranks(me, id)) return false;
    _say({'t': 'kick', 'to': id});
    present.remove(id);
    notifyListeners();
    return true;
  }

  /// Bans [id]: kept out for good (in the roster), and put out now.
  Future<bool> ban(String id, {bool on = true}) async {
    if (!can(Perm.ban) || !roster.outranks(me, id) || !canManage) return false;
    final banned = {...roster.banned};
    on ? banned.add(id) : banned.remove(id);
    final ok = await _publish(roster.next(banned: banned));
    if (ok && on) {
      _say({'t': 'kick', 'to': id});
      present.remove(id);
    }
    return ok;
  }

  /// [c], the same space with its kind (or name) changed by its circle: kept here so what the space may do follows it.
  /// Made a Files space, members may add files and moderators and admins manage them, as a new Files space's roles
  /// have; made another kind, the Files permissions go. A roster no one has signed yet is the kind's first roster; a
  /// signed one is changed and signed here where this install may manage it (else by whoever may, as they see it).
  void updateChannel(VoiceChannel c) {
    if (c.seed != channel.seed) return;
    final was = channel.kind;
    channel = c;
    if (c.kind != was) {
      if (roster.version == 0 && roster.sig == null) {
        _take(Roster.first(c.owner, kind: c.kind));
      } else if (canManage) {
        final defaults = {for (final r in Role.defaultsFor(c.kind)) r.id: r};
        final roles = [
          for (final r in roster.ranked)
            r.copyWith(perms: c.kind == SpaceKind.files ? {...r.perms, ...?defaults[r.id]?.perms.intersection(Perm.files)} : r.perms.difference(Perm.files)),
        ];
        unawaited(_publish(roster.next(roles: roles)));
      }
    }
    notifyListeners();
  }

  /// Changes what [role] may do, or its name or rank; or adds it where it is new. Admin keeps every permission.
  Future<bool> saveRole(Role role) async {
    if (!canManage) return false;
    // Only what a space of this kind has: a voice or texting space's roles never name a Files permission (Perm.files).
    final fixed = role.id == Role.admin ? role.copyWith(perms: Perm.of(channel.kind), rank: 30) : role.copyWith(perms: role.perms.intersection(Perm.of(channel.kind)), rank: role.rank.clamp(1, 29));
    final roles = [for (final r in roster.ranked) r.id == role.id ? fixed : r];
    if (!roles.any((r) => r.id == role.id)) roles.add(fixed);
    return _publish(roster.next(roles: roles));
  }

  /// Takes away a role (not admin, not the one newcomers get); whoever had it goes back to the newcomers' role.
  Future<bool> deleteRole(String roleId) async {
    if (!canManage || roleId == Role.admin || roleId == roster.newcomer) return false;
    final roles = [for (final r in roster.ranked) if (r.id != roleId) r];
    final assigned = {for (final e in roster.assigned.entries) if (e.value != roleId) e.key: e.value};
    return _publish(roster.next(roles: roles, assigned: assigned));
  }

  /// The role people have until given another.
  Future<bool> setNewcomer(String roleId) async {
    if (!canManage || roleId == Role.admin || roster.roleById(roleId) == null) return false;
    return _publish(roster.next(newcomer: roleId));
  }

  Future<bool> _publish(Roster next) async {
    final s = signer;
    if (s == null) return false;
    final signed = await next.signedBy(me, s.publicKey, s.sign);
    if (!signed.trustedFor(channel.owner)) return false;
    _take(signed);
    _say({'t': 'roster', 'r': signed.toJson()}, keep: true);
    return true;
  }

  void _take(Roster r) {
    roster = r;
    store.keepRoster(channel.chatRoom, r);
    // A description by someone this roster no longer makes owner or admin goes from under the name: it stayed there
    // on every device after its writer was demoted (Matt, 2026-11-17: "Finish the missing pieces that went
    // unfinished"). It waits, in case they are made one again.
    final shown = _about;
    if (shown != null && !shown.trustedFor(channel.chatRoom, r)) {
      _about = null;
      if (shown.version > (_waitingAbout?.version ?? 0)) _waitingAbout = shown;
    }
    // An about signed by an admin can come before the roster that makes them one: tried again now.
    final waiting = _waitingAbout;
    if (waiting != null && waiting.trustedFor(channel.chatRoom, r)) {
      _waitingAbout = null;
      _takeAbout(waiting);
    }
    if (r.banned.contains(me)) {
      putOut = 'You were banned from this space.';
    }
    onRoster?.call(r);
    notifyListeners();
  }

  // --- the description ---------------------------------------------------------------------------------------------

  /// What the space is for, as its owner or an admin wrote it, shown under its name in the header (Matt, 2026-11-17:
  /// "make the text header for spaces show the icon and the name and an area for a description of the channel").
  /// Null where no one has written one, or it was cleared.
  String? get about => (_about?.text ?? '').isEmpty ? null : _about!.text;

  SpaceAbout? _about;

  /// The newest about heard that the roster doesn't yet trust (its admin's roster not here yet).
  SpaceAbout? _waitingAbout;

  /// Writes [text] as the space's description, for everyone in it; false where this install may not (only the owner
  /// and admins, as with the roster).
  Future<bool> setAbout(String text) async {
    final s = signer;
    if (s == null || !canManage) return false;
    final words = text.trim();
    final next = await SpaceAbout.sign(channel.chatRoom, words.length > SpaceAbout.most ? words.substring(0, SpaceAbout.most) : words, (_about?.version ?? 0) + 1, me, s.publicKey, s.sign);
    if (!next.trustedFor(channel.chatRoom, roster)) return false;
    _takeAbout(next);
    _say({'t': 'about', 'a': next.toJson()}, keep: true);
    return true;
  }

  void _heardAbout(Object? j) {
    final a = SpaceAbout.fromJson(j);
    if (a == null) return;
    // Two admins writing the same version at once: the one whose signature sorts last, on every device alike, rather
    // than whichever each heard first.
    final cur = _about;
    if (cur == null ? a.version <= 0 : (a.version < cur.version || (a.version == cur.version && a.sig.compareTo(cur.sig) <= 0))) return;
    if (a.trustedFor(channel.chatRoom, roster)) {
      _takeAbout(a);
    } else if (a.version > (_waitingAbout?.version ?? 0)) {
      _waitingAbout = a;
    }
  }

  void _takeAbout(SpaceAbout a) {
    _about = a;
    if (_waitingAbout != null && _waitingAbout!.version <= a.version) _waitingAbout = null;
    _keepAbout(a);
    notifyListeners();
  }

  /// The about is kept beside the roster, but not in it: an older build rebuilds a roster's signed bytes from the
  /// fields it knows, so a new field there would have 0.9.2 refuse every roster. The app's store has no slot for it,
  /// so it goes under a key of its own in the same choices (`hangout_<room>_about`), which keep any key.
  static String _aboutKey(String room) => 'hangout_${room}_about';

  void _keepAbout(SpaceAbout a) {
    final s = store, words = jsonEncode(a.toJson());
    if (s is HangoutAboutStore) {
      (s as HangoutAboutStore).keepAbout(channel.chatRoom, words);
    } else if (s is AppHangoutStore) {
      s.app.set(_aboutKey(channel.chatRoom), words);
    }
  }

  void _loadAbout() {
    final s = store;
    String? words;
    if (s is HangoutAboutStore) {
      words = (s as HangoutAboutStore).aboutOf(channel.chatRoom);
    } else if (s is AppHangoutStore) {
      words = s.app.choice(_aboutKey(channel.chatRoom), '');
    }
    if (words == null || words.isEmpty) return;
    try {
      final a = SpaceAbout.fromJson(jsonDecode(words));
      if (a == null) return;
      a.trustedFor(channel.chatRoom, roster) ? _about = a : _waitingAbout = a;
    } catch (_) {}
  }

  // --- the room ------------------------------------------------------------------------------------------------------

  /// The relay dropped this device out of the room ([RoomEvent.closed]); it puts it back in on reconnecting.
  bool _dropped = false;

  void _event(RoomEvent e) {
    if (e.closed) {
      _dropped = true;
      present.clear();
    } else if (e.members != null && _dropped) {
      // Back in after the relay dropped and came back, or in at last after an answer that came late: who is here now,
      // and what was said meanwhile.
      _dropped = false;
      present.clear();
      for (final id in e.members!) {
        present[id] = HangoutPerson(id);
      }
      _hi(ask: true);
      _say({'t': 'sync?', 'since': messages.isEmpty ? 0 : messages.last.at, 'v': roster.version, 'av': _about?.version ?? 0});
    } else if (e.came != null) {
      present[e.came!] = HangoutPerson(e.came!);
      // Who is here and what they call themselves, for the newcomer.
      _greet(e.came!);
    } else if (e.went != null) {
      present.remove(e.went);
      heldMutes.remove(e.went);
    }
    notifyListeners();
  }

  /// Says [what] to everyone in the chat room. [keep]: the hub keeps it for whoever comes in later (a message, a
  /// deletion, the roster, the description), so a phone that was closed when it was said still has it (Matt, 2026-11-18:
  /// "I can't see their messages in spaces within a circle").
  void _say(Map<String, Object?> what, {bool keep = false}) {
    if (!opened) return;
    try {
      final sealed = NetCrypto.seal(channel.key, utf8.encode(jsonEncode(what)));
      final r = route;
      if (keep && r is HubVoiceRoute) {
        r.sendKept(channel.chatRoom, sealed);
      } else {
        r.send(channel.chatRoom, sealed);
      }
    } catch (_) {}
  }

  /// Whether this device is the one to answer [asker]: the lowest id of those here besides them.
  bool _answers(String asker) {
    final ids = [me, ...present.keys.where((id) => id != asker)]..sort();
    return ids.first == me;
  }

  void _heard(String from, Uint8List bytes) {
    final clear = NetCrypto.open(channel.key, bytes);
    if (clear == null) return;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(utf8.decode(clear)) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final to = m['to'];
    if (to != null && to != me) {
      // Others told to leave are gone from here too.
      if (m['t'] == 'kick' && roster.can(from, Perm.removeMembers) && roster.outranks(from, '$to')) {
        present.remove('$to');
        notifyListeners();
      }
      return;
    }
    // Someone banned is not heard at all.
    if (roster.banned.contains(from) || (shut?.call(from) ?? false)) return;
    switch (m['t']) {
      case 'hi':
        // Another device of this identity is this person, not someone else here (counted with "here" otherwise).
        if (from == me) return;
        present[from] = HangoutPerson(from,
            name: bareName('${m['n'] ?? ''}'),
            username: m['u'] is String ? m['u'] as String : null,
            inVoice: m['a'] == true,
            guest: m['g'] == true,
            status: m['st'] is String ? String.fromCharCodes((m['st'] as String).runes.take(Me.statusMost)) : '',
            pictureHash: m['ph'] is String ? m['ph'] as String : '');
        if (m['u'] is String && (m['u'] as String).isNotEmpty) usernames[from] = m['u'] as String;
        notifyListeners();
        // Come in asking who is here (a person's second device, whom the relay announces to nobody): told, once.
        if (m['q'] == true) _greet(from);
      case 'pic?':
        // Someone looking at this person's profile (it came to them alone: `to` above).
        final mine = Me.instance.picture;
        if (mine.isNotEmpty) _say({'t': 'pic', 'to': from, 'p': mine});
      case 'pic':
        final p = m['p'];
        if (p is String) {
          ProfilePictures.instance.keep(from, p);
          final asked = _askedPictures[from];
          if (asked != null && !asked.isCompleted) asked.complete(ProfilePictures.instance.of(from));
        }
      case 'sms?' || 'sms#':
        onSignal?.call(from, m);
      case 'msg':
        final msg = HangoutMessage.fromJson(m, from);
        if (msg != null && roster.can(from, Perm.chat)) _add([msg]);
      case 'vote':
        _heardVote(from, m);
      case 'votes':
        _heardVotes(m['v']);
      case 'del':
        final id = '${m['id']}';
        final msg = messages.where((x) => x.id == id).firstOrNull;
        if (msg != null && (msg.from == from || roster.isOwner(from) || (roster.can(from, Perm.manageMessages) && roster.outranks(from, msg.from)))) _drop(id);
      case 'sync?':
        if (_answers(from)) {
          final since = m['since'] is int ? m['since'] as int : 0;
          final missed = [for (final x in messages) if (x.at > since) x];
          // In as many packets as it takes: one packet holds 60 KB, and a message with files carries their small
          // pictures, so what was missed all in one could be too big to go at all.
          for (final lot in histLots(missed.take(keep))) {
            _say({'t': 'hist', 'to': from, 'm': lot});
          }
          // Every vote in the polls it has, after them: an older build has no case for `votes` and passes over it.
          final votes = _votesOf(messages);
          if (votes.isNotEmpty) _say({'t': 'votes', 'to': from, 'v': votes});
        }
        if (roster.sig != null && (m['v'] is! int || roster.version > (m['v'] as int))) _say({'t': 'roster', 'to': from, 'r': roster.toJson()});
        // The description the same way, after the roster that trusts its writer. An older build's sync? has no `av`
        // and gets it anyway; it has no case for `about` and passes over it (this switch has no default).
        final a = _about;
        if (a != null && (m['av'] is! int || a.version > (m['av'] as int))) _say({'t': 'about', 'to': from, 'a': a.toJson()});
      case 'hist':
        _add([
          for (final j in (m['m'] as List? ?? const []))
            if (j is Map && j['f'] is String) ?HangoutMessage.fromJson(j.cast<String, dynamic>(), j['f'] as String),
        ]);
      case 'roster':
        final r = Roster.fromJson(m['r']);
        if (r != null && r.version > roster.version && r.trustedFor(channel.owner)) _take(r);
      case 'about':
        _heardAbout(m['a']);
      case 'mute':
        if (roster.can(from, Perm.muteOthers) && roster.outranks(from, '${m['who']}')) _applyMute('${m['who']}', m['on'] == true);
      case 'kick':
        if (roster.can(from, Perm.removeMembers) && roster.outranks(from, me)) {
          putOut = roster.banned.contains(me) ? 'You were banned from this space.' : 'You were removed from this space.';
          onRoster?.call(roster);
          notifyListeners();
        }
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

/// Someone in a hangout's chat room, as they said they are.
@immutable
class HangoutPerson {
  const HangoutPerson(this.id, {this.name = '', this.username, this.inVoice = false, this.guest = false, this.status = '', this.pictureHash = ''});
  final String id;
  final String name;
  final String? username;

  /// How they are now, and a mark of their picture (ProfilePictures.hashOf), as their greeting said; '' for none. The
  /// picture itself is asked of them when someone looks at their profile ([HangoutRoom.pictureOf]).
  final String status;
  final String pictureHash;
  final bool inVoice;
  final bool guest;
}

/// One message in a hangout's chat: words, and since 2026-11-18 files, a sticker or a voice message with them (Matt,
/// 2026-11-18: "I also want full support for uploading attachements gifs stickers etc like we support in other chats").
///
/// **On the wire** `{id, x, at, n}`, and with something besides words `w` (the words), `a` (the files, each a
/// [SpaceFile]'s description less who and when, which the message says), `st` (a sticker's name, `love-03`: the
/// sticker is in every app already, so nothing goes up) and `vo` (the one file is a voice message). A build from before
/// reads only `x`, so there it is a line saying what came ([fallback]: "📎 photo.jpg", "Sticker"), the words under it.
///
/// Since 2026-11-19 `mn`, who its words mention ([Mention]: `[start, length, id]` each, counted in the words): a build
/// from before reads the "@Name" in the words as words, and so does anyone where a mention does not check out.
///
/// **The files** are sealed and kept on the relay under the space's own seed, as a Files space's are
/// (lib/files/files_store.dart, [ChatUploads]), but never written in its list: only the message knows of them.
@immutable
class HangoutMessage {
  const HangoutMessage({required this.id, required this.from, required this.name, required this.text, required this.at, this.files = const [], this.sticker, this.voice = false, this.mentions = const [], this.poll});
  final String id;

  /// Who wrote it (their id on the hub, as the hub said), and the name they wrote it under.
  final String from;
  final String name;

  /// The words: all of it for a message of words, any that went with files or a sticker otherwise (often none).
  final String text;

  /// When, in milliseconds since 1970, by the writer's clock.
  final int at;

  /// Pictures, videos, GIFs and any other files with it, at most [mostFiles]; who added them is [from].
  final List<SpaceFile> files;

  /// A sticker the app carries, by its name (stickerName in lib/stickers.dart).
  final String? sticker;

  /// Its one file is a voice message, recorded in the chat.
  final bool voice;

  /// Who its words mention, by where each "@Name" is in [text]; only ones that check out against it (Mention.checked).
  final List<Mention> mentions;

  /// A poll, whose question is [text] (lib/voice/polls.dart); null for any other message.
  final PollSpec? poll;

  /// Whether it mentions [id].
  bool mentionsOf(String id) => Mention.names(mentions, id);

  /// The most files one message carries, and the most words beside them (the message, its small pictures and its words
  /// twice over, in [fallback] and `w`, must go in one of the hub's packets).
  static const mostFiles = 10;
  static const mostWordsWith = 2000;

  /// A sticker's name as it travels: its pack and its number.
  static final stickerPattern = RegExp(r'^[a-z]{1,24}-[0-9a-z_]{1,24}$');

  /// Something besides words.
  bool get extras => files.isNotEmpty || sticker != null || poll != null;

  /// What came, in a line: what a build from before shows, and a preview where there are no words.
  String get what {
    if (sticker != null) return 'Sticker';
    if (poll != null) return '📊 Poll';
    if (voice) return '🎤 Voice message';
    if (files.isEmpty) return '';
    final names = [for (final f in files) f.name];
    if (names.length <= 3) return '📎 ${names.join(', ')}';
    return '📎 ${names.take(2).join(', ')} and ${names.length - 2} more';
  }

  /// `x` for a build from before attachments: what came, and the words under it.
  String get fallback => !extras ? text : (text.isEmpty ? what : '$what\n$text');

  /// The message in a line, for a list's preview: its words, or what came.
  String get summary => !extras ? text : (text.isEmpty ? what : '$what · $text');

  HangoutMessage copyWith({List<SpaceFile>? files}) => HangoutMessage(id: id, from: from, name: name, text: text, at: at, files: files ?? this.files, sticker: sticker, voice: voice, mentions: mentions, poll: poll);

  Map<String, Object> toJson() => {
        'id': id,
        'x': fallback,
        'at': at,
        'n': name,
        if (extras) 'w': text,
        // Who added each file and when are the message's own, so they are not said again for every one.
        if (files.isNotEmpty) 'a': [for (final f in files) f.toJson()..remove('u')..remove('at')],
        'st': ?sticker,
        if (voice && files.isNotEmpty) 'vo': 1,
        if (mentions.isNotEmpty) 'mn': [for (final m in mentions) m.toJson()],
        if (poll != null) 'pl': poll!.toJson(),
      };

  /// From what [from] said: its id, words and time; null where it is not a message. A message whose files and sticker
  /// can't be read is shown as a build from before shows it, by its `x`.
  static HangoutMessage? fromJson(Map<String, dynamic> j, String from) {
    if (j['id'] is! String || j['x'] is! String || j['at'] is! int) return null;
    final at = j['at'] as int;
    final name = j['n'] is String ? bareName(j['n'] as String) : '';
    final files = <SpaceFile>[
      if (j['a'] is List)
        for (final a in (j['a'] as List).take(mostFiles))
          if (a is Map) ?SpaceFile.fromJson({...a, 'u': name}, by: from, at: at),
    ];
    final st = j['st'];
    final sticker = st is String && stickerPattern.hasMatch(st) ? st : null;
    // A poll is its question and answers alone: no files or sticker with it.
    final poll = sticker == null && files.isEmpty ? PollSpec.fromJson(j['pl']) : null;
    final extras = files.isNotEmpty || sticker != null || poll != null;
    final raw = extras ? (j['w'] is String ? j['w'] as String : '') : j['x'] as String;
    final text = raw.trim();
    if (text.isEmpty && (!extras || poll != null)) return null;
    final most = poll != null ? PollSpec.questionMost : (extras ? mostWordsWith : 4000);
    final kept = text.length > most ? text.substring(0, most) : text;
    // Counted in the words as they came, then in the words as kept: trimmed and cut short, a mention past the cut goes.
    final lead = raw.length - raw.trimLeft().length;
    final mentions = Mention.listFromJson(j['mn'], raw).map((m) => m.moved(-lead)).toList();
    return HangoutMessage(
      id: j['id'] as String,
      from: from,
      name: name,
      text: kept,
      at: at,
      files: sticker != null ? const [] : files,
      sticker: sticker,
      voice: j['vo'] == 1 && files.length == 1 && sticker == null,
      mentions: Mention.checked(mentions, kept),
      poll: poll,
    );
  }

  Map<String, Object> toStored() => {...toJson(), 'f': from};
}

/// A file on its way up for a message in a space's chat ([OutgoingMessage]): where it is here, and how far it has got.
class OutgoingFile {
  OutgoingFile({required this.path, required this.name, required this.size, required this.mime, this.owned = false});

  /// Where it is on this device; [owned]: a copy the app made (a phone's pick, a recording), let go once it is up.
  final String path;
  final bool owned;
  final String name;
  final int size;
  final String mime;

  /// From 0 to 1, as it goes up.
  double progress = 0;

  /// What it waits for (the relay, out of reach), while it waits: it goes on by itself.
  String? waiting;

  /// Why it stopped, where it did; and whether a try again could mend that.
  String? error;
  bool retryable = true;

  /// Once it is all there: what the message carries of it.
  SpaceFile? file;

  /// What [ChatUploads] keeps of it between tries.
  Object? handle;

  FileKind get kind => FileKind.of(name, mime);
}

/// A message with files, shown in the chat while they go up (Matt, 2026-11-18): sent once all of them are there, kept
/// with a try again where one fails. Only on this device, and only while the app is open.
class OutgoingMessage {
  OutgoingMessage({required this.id, required this.text, required this.files, required this.at, this.voice = false, this.mentions = const []});
  final String id;
  final String text;

  /// Who [text] mentions, counted in [text].
  final List<Mention> mentions;
  final List<OutgoingFile> files;
  final int at;
  final bool voice;

  /// Why it wasn't sent, where all its files went up and the message itself was refused.
  String? error;

  bool get failed => error != null || files.any((f) => f.error != null);
  bool get retryable => error == null && files.every((f) => f.error == null || f.retryable);

  /// How far all of it has got, by size.
  double get progress {
    final total = files.fold<int>(0, (n, f) => n + f.size);
    if (total <= 0) return files.every((f) => f.file != null) ? 1 : 0;
    return files.fold<double>(0, (n, f) => n + (f.file != null ? 1 : f.progress) * f.size) / total;
  }
}

/// What sends a chat's files up, sealed, into the space's own storage on the relay (FilesStore in the app; a test's
/// own in a test).
abstract class ChatUploads {
  /// [f] up into [c]'s storage: its description once it is all there, with a small picture of no more than
  /// [thumbMost] bytes where it is a picture or a video. [moved] is told as it goes; it fails with why where it stops,
  /// and asked again for the same [f], goes on from where it got to.
  Future<SpaceFile> uploadForChat(VoiceChannel c, OutgoingFile f, {required String byName, required int thumbMost, required void Function() moved});

  /// Stops [f] and lets go of what of it is on the relay.
  void drop(OutgoingFile f);
}

/// A space's description: its words, numbered and signed by the owner or an admin, as the roster is but apart from it
/// ([HangoutRoom.about]). On the wire, in the space's chat room: `{t: about, a: {d, v, by, k, s}}`.
@immutable
class SpaceAbout {
  const SpaceAbout({required this.text, required this.version, required this.by, required this.byKey, required this.sig});

  /// Up to this many characters.
  static const most = 300;

  final String text;
  final int version;

  /// Who signed it: their id on the hub, their public key (hex), their signature (hex) over [signedBytes].
  final String by;
  final String byKey;
  final String sig;

  /// The bytes signed: domain-separated, and naming the space's chat room so an about can't be carried to another.
  static List<int> signedBytes(String room, String text, int version, String by, String byKey) =>
      utf8.encode('ghost-hangout about|${jsonEncode({'c': room, 'd': text, 'v': version, 'by': by, 'k': byKey})}');

  static Future<SpaceAbout> sign(String room, String text, int version, String by, Uint8List publicKey, Future<Uint8List> Function(List<int>) sign) async {
    final key = NetCrypto.hex(publicKey);
    final s = await sign(signedBytes(room, text, version, by, key));
    return SpaceAbout(text: text, version: version, by: by, byKey: key, sig: NetCrypto.hex(s));
  }

  Map<String, Object> toJson() => {'d': text, 'v': version, 'by': by, 'k': byKey, 's': sig};

  static SpaceAbout? fromJson(Object? j) {
    if (j is! Map || j['d'] is! String || j['v'] is! int || j['by'] is! String || j['k'] is! String || j['s'] is! String) return null;
    if ((j['d'] as String).length > most || (j['v'] as int) < 1) return null;
    return SpaceAbout(text: j['d'] as String, version: j['v'] as int, by: j['by'] as String, byKey: j['k'] as String, sig: j['s'] as String);
  }

  /// Whether to believe it in the space whose chat room is [room], by [roster]: signed by the key it names, and that
  /// key the owner's or an admin's the owner made (Roster.canManage, which checks the owner's grant).
  bool trustedFor(String room, Roster roster) {
    if (!roster.hasOwner) return false;
    try {
      final k = NetCrypto.unhex(byKey);
      if (NetCrypto.idOf(k) != by) return false;
      if (!NetCrypto.verify(k, signedBytes(room, text, version, by, byKey), NetCrypto.unhex(sig))) return false;
    } catch (_) {
      return false;
    }
    return roster.canManage(by);
  }
}

/// A store that keeps a space's polls' votes too (JSON: poll's id, then voter's id, to [PollVote.toJson]).
abstract class HangoutVotesStore {
  String? votesOf(String room);
  void keepVotes(String room, String votes);
}

/// A store that keeps a space's description too ([SpaceAbout] as JSON). The app's store ([AppHangoutStore]) does it
/// under a key of its own instead, until it takes this on.
abstract class HangoutAboutStore {
  String? aboutOf(String room);
  void keepAbout(String room, String about);
}

/// Where a device keeps a hangout's chat and roster between visits.
abstract class HangoutStore {
  List<HangoutMessage> messages(String room);
  void keepMessages(String room, List<HangoutMessage> messages);
  Roster? roster(String room);
  void keepRoster(String room, Roster roster);
}

class MemoryHangoutStore implements HangoutStore, HangoutAboutStore, HangoutVotesStore {
  final Map<String, String> _votes = {};
  @override
  String? votesOf(String room) => _votes[room];
  @override
  void keepVotes(String room, String votes) => _votes[room] = votes;
  final Map<String, List<HangoutMessage>> _messages = {};
  final Map<String, Roster> _rosters = {};
  final Map<String, String> _abouts = {};
  @override
  String? aboutOf(String room) => _abouts[room];
  @override
  void keepAbout(String room, String about) => _abouts[room] = about;
  @override
  List<HangoutMessage> messages(String room) => _messages[room] ?? const [];
  @override
  void keepMessages(String room, List<HangoutMessage> messages) => _messages[room] = messages;
  @override
  Roster? roster(String room) => _rosters[room];
  @override
  void keepRoster(String room, Roster roster) => _rosters[room] = roster;
}
