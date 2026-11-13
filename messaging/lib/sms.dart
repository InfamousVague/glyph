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
}

/// sending, sent, delivered, failed, received, pending_download
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
      );
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
  const E2eState({this.address = '', this.state = 'none', this.verified = false, this.changed = false, this.safety, this.person});
  final String address;
  final String state;
  final bool verified;

  /// A different key arrived from someone already exchanged with.
  final bool changed;

  /// Thirty digits, the same on both phones when nobody is in the middle.
  final String? safety;
  final Person? person;

  bool get on => state == 'on';

  factory E2eState.from(Map m) => E2eState(
        address: (m['address'] as String?) ?? '',
        state: (m['state'] as String?) ?? 'none',
        verified: m['verified'] == true,
        changed: m['changed'] == true,
        safety: m['safety'] as String?,
        person: m['person'] == null ? null : Person.from(m['person'] as Map),
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
  const OpenRequest({this.thread, this.addresses = const [], this.body});
  final int? thread;
  final List<String> addresses;
  final String? body;
  factory OpenRequest.from(Map m) => OpenRequest(
        thread: (m['thread'] as num?)?.toInt(),
        addresses: [for (final a in (m['addresses'] as List? ?? const [])) a as String],
        body: m['body'] as String?,
      );
}

/// The native side (android/.../MainActivity.kt): Android's SMS database, sending, the SMS role.
class Sms {
  Sms._();
  static final Sms instance = Sms._();

  static const _calls = MethodChannel('ghost_messaging/sms');
  static const _events = EventChannel('ghost_messaging/events');

  /// The conversation that changed, each time one does (-1: some conversation, which is not known).
  final changes = StreamController<int>.broadcast();
  final opens = StreamController<OpenRequest>.broadcast();

  /// Where the app's own update stands, each time it moves (android/.../Updater.kt).
  final updates = StreamController<UpdateState>.broadcast();

  /// The person's choices were changed from Android's side (a chat background someone shared): read them again.
  final prefsChanged = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _sub;

  void listen() {
    _sub ??= _events.receiveBroadcastStream().listen((e) {
      final m = e as Map;
      if (m['type'] == 'changed') changes.add((m['thread'] as num?)?.toInt() ?? -1);
      if (m['type'] == 'open') opens.add(OpenRequest.from(m));
      if (m['type'] == 'update') updates.add(UpdateState.from(m));
      if (m['type'] == 'prefs') prefsChanged.add(null);
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

  Future<List<Message>> messages(int thread, {int limit = 300}) async =>
      [for (final m in (await _calls.invokeMethod<List>('messages', {'thread': thread, 'limit': limit})) ?? const []) Message.from(m as Map)];

  Future<List<Person>> people(int thread) async =>
      [for (final p in (await _calls.invokeMethod<List>('people', {'thread': thread})) ?? const []) Person.from(p as Map)];

  Future<int> threadFor(List<String> addresses) async => ((await _calls.invokeMethod('threadFor', {'addresses': addresses})) as num).toInt();

  Future<int> send(List<String> addresses, String body, {List<String> attachments = const []}) async =>
      ((await _calls.invokeMethod('send', {'addresses': addresses, 'body': body, 'attachments': attachments})) as num).toInt();

  Future<void> markRead(int thread) => _calls.invokeMethod('markRead', {'thread': thread});
  Future<void> deleteThread(int thread) => _calls.invokeMethod('deleteThread', {'thread': thread});
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

  final _parts = <int, Future<Uint8List?>>{};
  Future<Uint8List?> part(int id) => _parts[id] ??= _calls.invokeMethod<Uint8List>('part', {'id': id});

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

  Future<Map<String, String>> prefs() async => {for (final e in ((await _calls.invokeMethod<Map>('prefs')) ?? const {}).entries) e.key as String: e.value as String};
  Future<void> setPref(String key, String value) => _calls.invokeMethod('setPref', {'key': key, 'value': value});

  @visibleForTesting
  void dispose() => _sub?.cancel();
}
