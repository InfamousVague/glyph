import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A person in a conversation: their number (or email address, for an MMS) and what the phone's contacts know of them.
class Person {
  const Person({required this.address, this.name, this.photo});
  final String address;
  final String? name;
  final String? photo;

  String get label => (name != null && name!.isNotEmpty) ? name! : address;

  factory Person.from(Map m) => Person(address: (m['address'] as String?) ?? '', name: m['name'] as String?, photo: m['photo'] as String?);
}

class Conversation {
  const Conversation({
    required this.id,
    required this.date,
    required this.people,
    required this.snippet,
    required this.unread,
    required this.error,
    required this.archived,
    this.pinned = false,
    this.muted = false,
    this.blocked = false,
    this.draft,
    this.encrypted = false,
  });
  final int id;
  final DateTime date;
  final List<Person> people;
  final String snippet;
  final bool unread;
  final bool error;
  final bool archived;
  final bool pinned;
  final bool muted;

  /// This conversation with its archive or its pin changed: what the list shows at once, before Android answers.
  Conversation copyWith({bool? archived, bool? pinned}) => Conversation(
        id: id,
        date: date,
        people: people,
        snippet: snippet,
        unread: unread,
        error: error,
        archived: archived ?? this.archived,
        pinned: pinned ?? this.pinned,
        muted: muted,
        blocked: blocked,
        draft: draft,
        encrypted: encrypted,
      );

  /// The one person of the conversation is on Android's blocked list.
  final bool blocked;

  /// What was typed here and not sent.
  final String? draft;

  /// Encryption is on with the one person of the conversation.
  final bool encrypted;

  String get title => people.isEmpty ? 'Unknown' : people.map((p) => people.length > 1 ? p.label.split(' ').first : p.label).join(', ');
  bool get group => people.length > 1;

  factory Conversation.from(Map m) => Conversation(
        id: (m['id'] as num).toInt(),
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
        people: [for (final p in (m['people'] as List? ?? const [])) Person.from(p as Map)],
        snippet: (m['snippet'] as String?) ?? '',
        unread: m['unread'] == true,
        error: m['error'] == true,
        archived: m['archived'] == true,
        pinned: m['pinned'] == true,
        muted: m['muted'] == true,
        blocked: m['blocked'] == true,
        draft: m['draft'] as String?,
        encrypted: m['encrypted'] == true,
      );
}

class Attachment {
  const Attachment({required this.id, required this.type, this.name});
  final int id;
  final String type;
  final String? name;
  bool get isImage => type.startsWith('image/');

  /// Sound: a voice message (android Voice.kt records them), drawn with a player.
  bool get isAudio => type.startsWith('audio/') || type == 'application/ogg';

  /// One of Ghost Messaging's stickers (android Sender.sendSticker names them so): drawn small, on the page.
  bool get isSticker => isImage && (name ?? '').split('/').last.startsWith('ghost-sticker');
}

/// A lot of conversations, and the row of Android's list the next lot starts at: null at the end.
class ConversationPage {
  const ConversationPage(this.items, this.next);
  final List<Conversation> items;
  final int? next;
}

/// What is shown of [fresh] laid over [old]: a conversation read again replaces the one held, and all of them stand
/// newest first. [only], where given, are the conversations still there: any other has gone.
List<Conversation> mergeConversations(List<Conversation>? old, List<Conversation> fresh, {Set<int>? only}) {
  final byId = <int, Conversation>{for (final c in old ?? const <Conversation>[]) c.id: c, for (final c in fresh) c.id: c};
  final all = [for (final c in byId.values) if (only == null || only.contains(c.id)) c];
  all.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  });
  return all;
}

/// sending, sent, delivered, failed, received, and for a picture message the carrier has announced that is not here:
/// downloading (being brought down now), pending_download (it could not be: the conversation offers to try again).
class Message {
  const Message({
    required this.id,
    required this.kind,
    required this.address,
    required this.body,
    required this.date,
    required this.outgoing,
    required this.state,
    this.attachments = const [],
    this.edited = false,
    this.original,
    this.encrypted = false,
    this.notice,
    this.why,
  });
  final int id;
  final String kind;
  final String address;
  final String body;
  final DateTime date;
  final bool outgoing;
  final String state;
  final List<Attachment> attachments;

  /// Changed on this phone after it was sent ([Sms.editMessage]); [original] is what it first said.
  final bool edited;
  final String? original;

  /// It travelled sealed by Ghost Messaging's own encryption and was opened here.
  final bool encrypted;

  /// Not words to show in a bubble: 'key' (it carried an encryption key) or 'undecryptable' (sealed, and the key to
  /// open it is not here).
  final String? notice;

  /// Why it was not sent, where it was not and the phone knows (a picture message: android/.../MmsWhy.kt).
  final String? why;

  String get key => '$kind:$id';

  factory Message.from(Map m) => Message(
        id: (m['id'] as num).toInt(),
        kind: m['kind'] as String,
        address: (m['address'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
        outgoing: m['outgoing'] == true,
        state: (m['state'] as String?) ?? 'sent',
        attachments: [
          for (final p in (m['parts'] as List? ?? const []))
            Attachment(id: ((p as Map)['id'] as num).toInt(), type: (p['type'] as String?) ?? '', name: p['name'] as String?),
        ],
        edited: m['edited'] == true,
        original: m['original'] as String?,
        encrypted: m['encrypted'] == true,
        notice: m['notice'] as String?,
        why: m['why'] as String?,
      );
}

/// What stands between this phone and picture messages (android/.../MmsDiag.kt), and how the last ones went.
class MmsStatus {
  const MmsStatus({this.dataOn, this.carrier, this.sim = true, this.allowed, this.maxBytes, this.lastSend, this.lastDownload, this.waiting = 0});

  /// Mobile data is on: picture messages go over it, even on Wi-Fi. Null where Android would not say.
  final bool? dataOn;
  final String? carrier;
  final bool sim;

  /// The carrier's settings on this phone allow picture messages. Null where Android would not say.
  final bool? allowed;
  final int? maxBytes;
  final MmsAttempt? lastSend;
  final MmsAttempt? lastDownload;

  /// Picture messages announced and not yet fetched.
  final int waiting;

  factory MmsStatus.from(Map m) => MmsStatus(
        dataOn: m['dataOn'] as bool?,
        carrier: m['carrier'] as String?,
        sim: m['sim'] != false,
        allowed: m['allowed'] as bool?,
        maxBytes: (m['maxBytes'] as num?)?.toInt(),
        lastSend: m['lastSend'] == null ? null : MmsAttempt.from(m['lastSend'] as Map),
        lastDownload: m['lastDownload'] == null ? null : MmsAttempt.from(m['lastDownload'] as Map),
        waiting: (m['waiting'] as num?)?.toInt() ?? 0,
      );

  /// What would stop one going, in a line; null where nothing is seen to.
  String? get obstacle => !sim
      ? 'There is no SIM for texts'
      : allowed == false
          ? 'The carrier has picture messaging switched off for this SIM'
          : dataOn == false
              ? 'Mobile data is off. Picture messages need it, even on Wi-Fi'
              : null;

  /// All of it as text, to copy and send to whoever is helping.
  String report(String version) => [
        'Ghost Messaging $version, picture messages',
        'Carrier: ${carrier ?? 'not said'}',
        'SIM for texts: ${sim ? 'yes' : 'none'}',
        'Mobile data: ${dataOn == null ? 'not said' : (dataOn! ? 'on' : 'off')}',
        'Allowed by the carrier\'s settings: ${allowed == null ? 'not said' : (allowed! ? 'yes' : 'no')}',
        'Largest message: ${maxBytes == null ? 'not said' : '${maxBytes! ~/ 1024} KB'}',
        'Last sent: ${lastSend == null ? 'none yet' : lastSend!.line}',
        'Last fetched: ${lastDownload == null ? 'none yet' : lastDownload!.line}',
        'Waiting to be fetched: $waiting',
      ].join('\n');
}

/// How one picture message went: sent or fetched, or why not.
class MmsAttempt {
  const MmsAttempt({required this.at, required this.ok, required this.detail});
  final DateTime at;
  final bool ok;
  final String detail;
  factory MmsAttempt.from(Map m) => MmsAttempt(at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()), ok: m['ok'] == true, detail: (m['detail'] as String?) ?? '');
  String get line => '${ok ? 'worked' : 'failed'}: $detail (${at.toIso8601String().substring(0, 16).replaceFirst('T', ' ')})';
}

class SmsStatus {
  const SmsStatus({required this.isDefault, required this.contacts, required this.notifications, required this.phone});
  final bool isDefault;
  final bool contacts;
  final bool notifications;
  final bool phone;
  factory SmsStatus.from(Map m) => SmsStatus(isDefault: m['isDefault'] == true, contacts: m['contacts'] == true, notifications: m['notifications'] == true, phone: m['phone'] == true);
}

/// Where Ghost Messaging's own encryption stands with one person (android/.../E2e.kt): none, offered (your key sent,
/// theirs awaited), pending (theirs here, your yes awaited), on.
class E2eState {
  const E2eState({this.address = '', this.state = 'none', this.verified = false, this.changed = false, this.safety, this.person, this.hasGhost = false, this.declined = false});
  final String address;
  final String state;
  final bool verified;

  /// A different key arrived from someone already exchanged with.
  final bool changed;

  /// Thirty digits, the same on both phones when nobody is in the middle.
  final String? safety;
  final Person? person;

  /// They are known to have Ghost Messaging: a text only the app writes has come from them (its invisible hello,
  /// a key, a background).
  final bool hasGhost;

  /// The person here turned encryption off with them: it is not offered again.
  final bool declined;

  bool get on => state == 'on';

  /// Both phones have the app and nothing has been exchanged yet: the conversation offers encryption.
  bool get offerable => state == 'none' && hasGhost && !declined;

  factory E2eState.from(Map m) => E2eState(
        address: (m['address'] as String?) ?? '',
        state: (m['state'] as String?) ?? 'none',
        verified: m['verified'] == true,
        changed: m['changed'] == true,
        safety: m['safety'] as String?,
        person: m['person'] == null ? null : Person.from(m['person'] as Map),
        hasGhost: m['hasGhost'] == true,
        declined: m['declined'] == true,
      );
}

/// Coming from another texting app (android/.../Arriving.kt): what can be seen of the app being left and of Android's
/// own store of texts. Android tells no app whether RCS is on for a number, so that is never among it.
class Arriving {
  const Arriving({this.old, this.oldLabel, this.oldInstalled = false, this.oldHasRcs = false, this.texts, this.recentTexts, this.pictures, this.lastReceived, this.samsungChats, this.sideloaded = false, this.android = 0});

  /// The app being left, by its package and its name; null where none is known.
  final String? old;
  final String? oldLabel;
  final bool oldInstalled;

  /// It is one that keeps RCS chats of its own (Google Messages, Samsung Messages).
  final bool oldHasRcs;

  /// How many texts Android's store holds, how many of them are of the last thirty days, and how many picture
  /// messages; null until this app holds the SMS role.
  final int? texts;
  final int? recentTexts;
  final int? pictures;
  final DateTime? lastReceived;

  /// RCS chats Samsung Messages keeps, where its store will say how many.
  final int? samsungChats;

  /// This copy was installed from a file, not by a store: Android may refuse it the SMS role or a permission until
  /// "Allow restricted settings" is chosen on its page.
  final bool sideloaded;
  final int android;

  String get app => oldLabel ?? 'your old texting app';

  /// RCS is worth talking about: the app being left keeps RCS chats, and is still on the phone.
  bool get rcsLikely => oldHasRcs && oldInstalled;

  factory Arriving.from(Map m) => Arriving(
        old: m['old'] as String?,
        oldLabel: m['oldLabel'] as String?,
        oldInstalled: m['oldInstalled'] == true,
        oldHasRcs: m['oldHasRcs'] == true,
        texts: (m['texts'] as num?)?.toInt(),
        recentTexts: (m['recentTexts'] as num?)?.toInt(),
        pictures: (m['pictures'] as num?)?.toInt(),
        lastReceived: m['lastReceived'] == null ? null : DateTime.fromMillisecondsSinceEpoch((m['lastReceived'] as num).toInt()),
        samsungChats: (m['samsungChats'] as num?)?.toInt(),
        sideloaded: m['sideloaded'] == true,
        android: (m['android'] as num?)?.toInt() ?? 0,
      );
}

/// Where the app's own update stands: idle, disabled, checking, upToDate, available, downloading, ready, installing,
/// failed.
class UpdateState {
  const UpdateState({this.phase = 'idle', this.current = '', this.available, this.progress, this.error, this.auto = true, this.canInstall = true, this.source = ''});
  final String phase;
  final String current;
  final String? available;
  final double? progress;
  final String? error;
  final bool auto;
  final bool canInstall;
  final String source;

  factory UpdateState.from(Map m) => UpdateState(
        phase: (m['phase'] as String?) ?? 'idle',
        current: (m['current'] as String?) ?? '',
        available: m['available'] as String?,
        progress: (m['progress'] as num?)?.toDouble(),
        error: m['error'] as String?,
        auto: m['auto'] != false,
        canInstall: m['canInstall'] != false,
        source: (m['source'] as String?) ?? '',
      );
}

/// What a notification or another app asked to open.
class OpenRequest {
  const OpenRequest({this.thread, this.addresses = const [], this.body, this.computers = false, this.pairing});
  final int? thread;
  final List<String> addresses;
  final String? body;

  /// The "Paired with …" notification was tapped: Settings › Computers.
  final bool computers;

  /// A computer's pairing link was opened (the phone's camera read its QR code): the pairing page, with it.
  final String? pairing;
  factory OpenRequest.from(Map m) => OpenRequest(
        thread: (m['thread'] as num?)?.toInt(),
        addresses: [for (final a in (m['addresses'] as List? ?? const [])) a as String],
        body: m['body'] as String?,
        computers: m['desk'] == true,
        pairing: m['pair'] as String?,
      );
}

/// A computer this phone is paired with (android/.../Desk.kt, docs/desktop.md).
class Computer {
  const Computer({required this.id, required this.name, this.mode = 'both', this.relay = '', this.since, this.seen, this.via});
  final String id;
  final String name;

  /// How the two connect: both (the local network first, the relay when that fails), local, relay.
  final String mode;
  final String relay;
  final DateTime? since;
  final DateTime? seen;

  /// How it is connected now: local, relay, or null when it is not.
  final String? via;

  factory Computer.from(Map m) => Computer(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? 'A computer',
        mode: (m['mode'] as String?) ?? 'both',
        relay: (m['relay'] as String?) ?? '',
        since: (m['since'] as num?) == null || m['since'] == 0 ? null : DateTime.fromMillisecondsSinceEpoch((m['since'] as num).toInt()),
        seen: (m['seen'] as num?) == null || m['seen'] == 0 ? null : DateTime.fromMillisecondsSinceEpoch((m['seen'] as num).toInt()),
        via: m['via'] as String?,
      );
}

/// A pairing with a computer while it is being made: none, waiting (for the computer to connect), code (both show
/// six digits to compare), done, failed.
class PairingState {
  const PairingState({this.phase = 'none', this.name = '', this.mode = 'both', this.offered = 'both', this.relay = '', this.code, this.mine = false, this.theirs = false, this.error});
  final String phase;
  final String name;

  /// How the two will connect, chosen here; [offered] is what the computer chose, and how it is reached to pair.
  final String mode;
  final String offered;
  final String relay;
  final String? code;

  /// "They match" was said here, and on the computer.
  final bool mine;
  final bool theirs;
  final String? error;

  factory PairingState.from(Map m) => PairingState(
        phase: (m['phase'] as String?) ?? 'none',
        name: (m['name'] as String?) ?? '',
        mode: (m['mode'] as String?) ?? 'both',
        offered: (m['offered'] as String?) ?? 'both',
        relay: (m['relay'] as String?) ?? '',
        code: m['code'] as String?,
        mine: m['mine'] == true,
        theirs: m['theirs'] == true,
        error: m['error'] as String?,
      );
}

/// Where the screens' calls go. On the phone, Android's channel. On the Mac (lib/desktop), the link to the phone:
/// the same calls by the same names, answered by the phone, so the conversations are drawn by the same screens.
abstract class SmsCalls {
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]);
}

class _ChannelCalls implements SmsCalls {
  const _ChannelCalls();
  static const _channel = MethodChannel('ghost_messaging/sms');

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) => _channel.invokeMethod<T>(method, arguments);
}

/// Where the voice message being played has got to (android/.../Voice.kt): its part, and whether it is playing now.
class VoicePlayback {
  const VoicePlayback({required this.part, required this.position, required this.length, required this.playing});
  final int part;
  final Duration position;
  final Duration length;
  final bool playing;

  factory VoicePlayback.from(Map m) => VoicePlayback(
        part: (m['part'] as num?)?.toInt() ?? -1,
        position: Duration(milliseconds: (m['position'] as num?)?.toInt() ?? 0),
        length: Duration(milliseconds: (m['duration'] as num?)?.toInt() ?? 0),
        playing: m['playing'] == true,
      );
}

/// The native side (android/.../MainActivity.kt): Android's SMS database, sending, the SMS role.
class Sms {
  Sms._();
  static final Sms instance = Sms._();

  static SmsCalls _calls = const _ChannelCalls();
  static const _events = EventChannel('ghost_messaging/events');

  /// The Mac sets this to its link to the phone before anything is drawn (lib/desktop/remote.dart).
  static set calls(SmsCalls calls) => _calls = calls;

  /// These screens are on a computer, not the phone: what only the phone can do is not offered.
  static bool get remote => _calls is! _ChannelCalls;

  /// The conversation that changed, each time one does (-1: some conversation, which is not known).
  final changes = StreamController<int>.broadcast();
  final opens = StreamController<OpenRequest>.broadcast();

  /// Where the app's own update stands, each time it moves (android/.../Updater.kt).
  final updates = StreamController<UpdateState>.broadcast();

  /// The person's choices were changed from Android's side (a chat background someone shared): read them again.
  final prefsChanged = StreamController<void>.broadcast();

  /// Something about the computers paired with this phone changed: one connected, a pairing moved on.
  final computersChanged = StreamController<void>.broadcast();

  /// Where the voice message being played has got to, a few times a second while one plays.
  final voice = StreamController<VoicePlayback>.broadcast();

  /// The recording under way is as long as a message may be ([voiceFull]), or was thrown away because the app left
  /// the screen ([voiceStopped]).
  final voiceFull = StreamController<void>.broadcast();
  final voiceStopped = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _sub;

  void listen() {
    _sub ??= _events.receiveBroadcastStream().listen((e) {
      final m = e as Map;
      if (m['type'] == 'changed') changes.add((m['thread'] as num?)?.toInt() ?? -1);
      if (m['type'] == 'open') opens.add(OpenRequest.from(m));
      if (m['type'] == 'update') updates.add(UpdateState.from(m));
      if (m['type'] == 'prefs') prefsChanged.add(null);
      if (m['type'] == 'desk') computersChanged.add(null);
      if (m['type'] == 'voice') voice.add(VoicePlayback.from(m));
      if (m['type'] == 'voiceFull') voiceFull.add(null);
      if (m['type'] == 'voiceStopped') voiceStopped.add(null);
    });
  }

  Future<SmsStatus> status() async => SmsStatus.from(await _calls.invokeMethod('status') as Map);
  Future<bool> requestDefault() async => await _calls.invokeMethod<bool>('requestDefault') ?? false;
  Future<SmsStatus> requestPermissions() async => SmsStatus.from(await _calls.invokeMethod('requestPermissions') as Map);

  Future<OpenRequest?> openRequest() async {
    final m = await _calls.invokeMethod('openRequest');
    return m == null ? null : OpenRequest.from(m as Map);
  }

  Future<List<Conversation>> conversations() async =>
      [for (final c in (await _calls.invokeMethod<List>('conversations')) ?? const []) Conversation.from(c as Map)];

  /// Conversations, the newest first, a lot at a time (Matt, 2026-11-13: "see if we can load by most recent first so
  /// that things are faster"): [limit] of them from the [offset]th row of Android's list. [pinned] adds the pinned
  /// ones wherever they are, for the first lot. [archived]: the archived ones alone, all at once.
  Future<ConversationPage> conversationsPage({int limit = 0, int offset = 0, bool pinned = false, bool archived = false}) async {
    final answer = (await _calls.invokeMethod<Map>('conversationsPage', {'limit': limit, 'offset': offset, 'pinned': pinned, 'archived': archived})) ?? const {};
    return ConversationPage([for (final c in (answer['items'] as List?) ?? const []) Conversation.from(c as Map)], (answer['next'] as num?)?.toInt());
  }

  /// One conversation as the list has it, or null where it is gone.
  Future<Conversation?> conversation(int thread) async {
    final c = await _calls.invokeMethod<Map>('conversation', {'thread': thread});
    return c == null ? null : Conversation.from(c);
  }

  /// How many conversations are archived.
  Future<int> archivedCount() async => ((await _calls.invokeMethod('archivedCount')) as num?)?.toInt() ?? 0;

  Future<List<Message>> messages(int thread, {int limit = 300}) async =>
      [for (final m in (await _calls.invokeMethod<List>('messages', {'thread': thread, 'limit': limit})) ?? const []) Message.from(m as Map)];

  Future<List<Person>> people(int thread) async =>
      [for (final p in (await _calls.invokeMethod<List>('people', {'thread': thread})) ?? const []) Person.from(p as Map)];

  Future<int> threadFor(List<String> addresses) async => ((await _calls.invokeMethod('threadFor', {'addresses': addresses})) as num).toInt();

  Future<int> send(List<String> addresses, String body, {List<String> attachments = const []}) async =>
      ((await _calls.invokeMethod('send', {'addresses': addresses, 'body': body, 'attachments': attachments})) as num).toInt();

  /// Sends one of the app's stickers (lib/stickers.dart) as a picture message: [picture] is its bytes, [name] its
  /// pack and number.
  Future<int> sendSticker(List<String> addresses, Uint8List picture, String name) async =>
      ((await _calls.invokeMethod('sendSticker', {'addresses': addresses, 'picture': picture, 'name': name})) as num).toInt();

  /// Sends a picture message that did not go again, with its own pictures (android Sender.resendMms). [body]: other
  /// words for it, where it was edited first.
  Future<void> resendMms(int id, {String? body}) => _calls.invokeMethod('resendMms', {'id': id, 'body': body});

  /// A line for the app's own log (Settings › Developer; android DevLog.kt). Never a message's words.
  void devLog(String tag, String line) {
    _calls.invokeMethod('devLog', {'tag': tag, 'line': line}).catchError((_) {});
  }

  /// The log's lines, the newest last, and the whole report as text.
  Future<(List<String>, String)> devLogRead(String version) async {
    final m = (await _calls.invokeMethod<Map>('devLogRead', {'version': version})) ?? const {};
    return ([for (final l in (m['lines'] as List?) ?? const []) l as String], (m['report'] as String?) ?? '');
  }

  Future<void> devLogClear() => _calls.invokeMethod('devLogClear');

  /// Hands [text] to Android's share sheet: an email, a note, another app.
  Future<void> shareText(String subject, String text) => _calls.invokeMethod('shareText', {'subject': subject, 'text': text});

  /// Whether picture messages can go from this phone, and how the last ones went.
  Future<MmsStatus> mmsStatus() async => MmsStatus.from((await _calls.invokeMethod<Map>('mmsStatus')) ?? const {});

  /// Asks again for the picture messages announced and never fetched; answers how many.
  Future<int> mmsRetry() async => ((await _calls.invokeMethod('mmsRetry')) as num?)?.toInt() ?? 0;

  Future<void> markRead(int thread) => _calls.invokeMethod('markRead', {'thread': thread});

  /// Tries again to bring down a picture message that could not be ([Message.state] `pending_download`).
  Future<void> retryDownload(Message m) => _calls.invokeMethod('retryDownload', {'id': m.id});
  Future<void> deleteThread(int thread) => _calls.invokeMethod('deleteThread', {'thread': thread});
  Future<void> deleteThreads(List<int> threads) => _calls.invokeMethod('deleteThreads', {'threads': threads});

  /// Coming from another texting app: what can be seen (null where Android will not say), and the ways out.
  Future<Arriving> arriving() async {
    final m = await _calls.invokeMethod('arriving');
    return m is Map ? Arriving.from(m) : const Arriving();
  }

  /// The old app's settings (RCS chats is in them), Android's page for this app (⋮ › Allow restricted settings),
  /// Android's Default apps, and Google's page that turns RCS off for a number with a code it texts.
  Future<void> openOldApp() => _calls.invokeMethod('openOldApp');
  Future<void> openAppInfo() => _calls.invokeMethod('openAppInfo');
  Future<void> openDefaultApps() => _calls.invokeMethod('openDefaultApps');
  Future<void> openRcsOff() => _calls.invokeMethod('openRcsOff');
  Future<void> deleteMessage(Message m) => _calls.invokeMethod('deleteMessage', {'kind': m.kind, 'id': m.id});
  Future<void> editMessage(Message m, String body) => _calls.invokeMethod('editMessage', {'kind': m.kind, 'id': m.id, 'body': body});
  Future<void> archive(int thread, bool archived) => _calls.invokeMethod('archive', {'thread': thread, 'archived': archived});
  Future<void> threadFlag(String name, int thread, bool on) => _calls.invokeMethod('threadFlag', {'name': name, 'thread': thread, 'on': on});
  Future<String?> draft(int thread) => _calls.invokeMethod<String>('draft', {'thread': thread});
  Future<void> setDraft(int thread, String text) => _calls.invokeMethod('setDraft', {'thread': thread, 'text': text});
  Future<void> setBlocked(String address, bool blocked) => _calls.invokeMethod('setBlocked', {'address': address, 'blocked': blocked});

  Future<E2eState> e2e(String address) async => E2eState.from((await _calls.invokeMethod('e2e', {'address': address})) as Map);
  Future<E2eState> e2eOffer(String address) async => E2eState.from((await _calls.invokeMethod('e2eOffer', {'address': address})) as Map);
  Future<void> e2eOff(String address) => _calls.invokeMethod('e2eOff', {'address': address});
  Future<void> e2eVerify(String address, bool verified) => _calls.invokeMethod('e2eVerify', {'address': address, 'verified': verified});
  Future<void> e2eReset() => _calls.invokeMethod('e2eReset');
  Future<String?> e2eMine() => _calls.invokeMethod<String>('e2eMine');
  Future<List<E2eState>> e2eList() async => [for (final m in (await _calls.invokeMethod<List>('e2eList')) ?? const []) E2eState.from(m as Map)];
  Future<List<Person>> blockedNumbers() async => [for (final m in (await _calls.invokeMethod<List>('blockedNumbers')) ?? const []) Person.from(m as Map)];
  Future<void> notificationSettings() => _calls.invokeMethod('notificationSettings');

  Future<UpdateState> update() async => UpdateState.from((await _calls.invokeMethod('update')) as Map);
  Future<void> updateCheck({bool install = false}) => _calls.invokeMethod('updateCheck', {'install': install});
  Future<void> updateInstall() => _calls.invokeMethod('updateInstall');
  Future<void> updateBackground() => _calls.invokeMethod('updateBackground');

  /// A page opened: a look for a newer version, which Android makes no oftener than every five minutes.
  Future<void> updateOnPage() => _calls.invokeMethod('updatePage');
  Future<void> setAutoUpdate(bool on) => _calls.invokeMethod('setAutoUpdate', {'on': on});
  Future<void> allowInstalls() => _calls.invokeMethod('allowInstalls');
  Future<void> setOpenThread(int? thread) => _calls.invokeMethod('setOpenThread', {'thread': thread ?? -1});

  Future<List<Map<String, String?>>> searchContacts(String query) async => [
        for (final c in (await _calls.invokeMethod<List>('searchContacts', {'query': query})) ?? const [])
          {for (final e in (c as Map).entries) e.key as String: e.value as String?},
      ];

  Future<Person> contact(String address) async => Person.from(await _calls.invokeMethod('contact', {'address': address}) as Map);

  final _photos = <String, Future<Uint8List?>>{};
  Future<Uint8List?> photo(String uri) => _photos[uri] ??= _calls.invokeMethod<Uint8List>('photo', {'uri': uri});

  /// A picture's bytes, kept while it is among the last [_partsKept] asked for: a long conversation's pictures are
  /// read again when scrolled back to, where they once stayed in memory for as long as the app ran.
  final _parts = <int, Future<Uint8List?>>{};
  static const _partsKept = 40;
  Future<Uint8List?> part(int id) {
    final had = _parts.remove(id);
    final bytes = had ?? _calls.invokeMethod<Uint8List>('part', {'id': id});
    _parts[id] = bytes;
    while (_parts.length > _partsKept) {
      _parts.remove(_parts.keys.first);
    }
    return bytes;
  }

  // --- voice messages (android/.../Voice.kt) -------------------------------------------------------------------

  /// Starts recording a voice message with the phone's microphone, asking Android for it the first time. Answers the
  /// most seconds one may run (the carrier's limit on a message decides), or null where the microphone was refused.
  Future<int?> startVoice() async {
    final m = await _calls.invokeMethod('voiceStart') as Map?;
    if (m == null || m['ok'] != true) return null;
    return (m['seconds'] as num?)?.toInt() ?? 60;
  }

  /// How loud the microphone hears it right now, 0 to 1.
  Future<double> voiceLevel() async => ((await _calls.invokeMethod('voiceLevel')) as num?)?.toDouble() ?? 0;

  /// Throws the recording away.
  Future<void> cancelVoice() => _calls.invokeMethod('voiceCancel');

  /// Ends the recording and sends it to [addresses] as a picture message with the sound in it. The conversation.
  Future<int> sendVoice(List<String> addresses) async =>
      (((await _calls.invokeMethod('voiceSend', {'addresses': addresses})) as Map)['thread'] as num).toInt();

  /// Plays the sound in a message's part [part] (or goes on with it, where it was paused); [voice] says how far.
  Future<void> playVoice(int part) => _calls.invokeMethod('voicePlay', {'part': part});
  Future<void> pauseVoice() => _calls.invokeMethod('voicePause');

  /// Stops whatever is playing: leaving the conversation.
  Future<void> stopVoice() => _calls.invokeMethod('voiceStop');

  final _voiceLengths = <int, Future<Duration>>{};

  /// How long the sound in part [part] runs; zero where it cannot be read.
  Future<Duration> voiceLength(int part) => _voiceLengths[part] ??= () async {
        try {
          return Duration(milliseconds: ((await _calls.invokeMethod('voiceLength', {'part': part})) as num?)?.toInt() ?? 0);
        } catch (_) {
          return Duration.zero;
        }
      }();

  Future<List<String>> pickImages() async => [for (final u in (await _calls.invokeMethod<List>('pickImages')) ?? const []) u as String];

  Future<String?> ownNumber() => _calls.invokeMethod<String>('ownNumber');
  Future<void> setOwnNumber(String number) => _calls.invokeMethod('setOwnNumber', {'number': number});

  /// The colours Android takes from the wallpaper (Material You), by name ("accent1_100"…); null before Android 12.
  Future<Map<String, int>?> systemPalette() async {
    final m = await _calls.invokeMethod<Map>('systemPalette');
    return m == null ? null : {for (final e in m.entries) e.key as String: (e.value as num).toInt()};
  }

  /// A copy of the picture at [uri] kept by the app as a chat background, [name] saying whose ("all", or a
  /// conversation's number); the copy's path, or null when the picture could not be read.
  Future<String?> importBackground(String uri, String name) => _calls.invokeMethod<String>('importBackground', {'uri': uri, 'name': name});
  Future<void> deleteBackground(String name) => _calls.invokeMethod('deleteBackground', {'name': name});

  /// Whether Ghost Keyboard is on this phone, signed as it should be (android/.../Codes.kt): sign-in codes are
  /// offered to it and to nothing else.
  Future<bool> keyboardHere() async => await _calls.invokeMethod<bool>('keyboardHere') ?? false;

  /// Whether everyone in [addresses] is known to have Ghost Messaging (android/.../Backgrounds.kt): a text only the
  /// app writes has come from each of them.
  Future<bool> ghostPeers(List<String> addresses) async => await _calls.invokeMethod<bool>('ghostPeers', {'addresses': addresses}) ?? false;

  /// Sends [thread]'s background ([raw], as the choice is kept) to its people as a text their copy of the app wears.
  Future<void> shareBackground(List<String> addresses, int thread, String raw) => _calls.invokeMethod('shareBackground', {'addresses': addresses, 'thread': thread, 'raw': raw});

  // --- paired computers (android/.../Desk.kt) ---------------------------------------------------------------------------

  Future<List<Computer>> computers() async => [for (final m in (await _calls.invokeMethod<List>('deskList')) ?? const []) Computer.from(m as Map)];
  Future<PairingState> pairing() async => PairingState.from((await _calls.invokeMethod('deskState')) as Map);

  /// The name of the computer a pairing code is from, before anything is done with it. Throws when it is not one.
  Future<String> pairingCodeName(String code) async => (((await _calls.invokeMethod('deskPeek', {'code': code})) as Map)['name'] as String?) ?? 'A computer';

  /// The camera, looking for a computer's QR code: its words, or null when the screen was left (or `denied`, when
  /// the camera was refused).
  Future<({String? text, bool denied})> scanPairingCode() async {
    final m = (await _calls.invokeMethod('deskScan')) as Map;
    return (text: m['text'] as String?, denied: m['denied'] == true);
  }

  /// Starts pairing with the computer whose code this is. Throws when it is not a code of ours.
  Future<PairingState> beginPairing(String code, {String? mode}) async => PairingState.from((await _calls.invokeMethod('deskBegin', {'code': code, 'mode': mode})) as Map);
  Future<PairingState> setPairingMode(String mode) async => PairingState.from((await _calls.invokeMethod('deskPendingMode', {'mode': mode})) as Map);
  Future<void> confirmPairing() => _calls.invokeMethod('deskConfirm');
  Future<void> cancelPairing() => _calls.invokeMethod('deskCancel');
  Future<void> pairingShown() => _calls.invokeMethod('deskDone');
  Future<void> unpairComputer(String id) => _calls.invokeMethod('deskUnpair', {'id': id});
  Future<void> setComputerMode(String id, String mode) => _calls.invokeMethod('deskSetMode', {'id': id, 'mode': mode});

  /// Where this phone listens on the local network (`192.168.1.20:47811`), for a computer that cannot find it.
  Future<List<String>> phoneAddresses() async => [for (final a in (await _calls.invokeMethod<List>('deskAddresses')) ?? const []) '$a'];

  /// Whether Android lets the app use the network in deep sleep (its battery setting is "Unrestricted").
  Future<bool> unrestrictedBattery() async => await _calls.invokeMethod<bool>('deskUnrestricted') ?? false;

  /// Whether timings are being written to Android's log (`adb shell setprop log.tag.GhostPerf VERBOSE`).
  Future<bool> perfOn() async => await _calls.invokeMethod<bool>('perfOn') ?? false;

  Future<Map<String, String>> prefs() async => {for (final e in ((await _calls.invokeMethod<Map>('prefs')) ?? const {}).entries) e.key as String: e.value as String};
  Future<void> setPref(String key, String value) => _calls.invokeMethod('setPref', {'key': key, 'value': value});

  @visibleForTesting
  void dispose() => _sub?.cancel();
}
