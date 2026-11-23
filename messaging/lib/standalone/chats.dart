import 'dart:convert';
import 'dart:typed_data';

import '../friends/buddies.dart';
import '../friends/friends.dart';
import '../net/crypto.dart';
import '../sms.dart';

/// Conversations with friends by username (Matt, 2026-11-15: "roll a version of the app that works without sms", then
/// "Yes, Android next": an iPhone and an Android phone texting each other). Kept here in Dart, since no store of the
/// phone's has room for someone with no number: on an iPhone of its own as all its conversations
/// (StandaloneCalls), and on an Android phone beside its texts (OverlayCalls).
///
/// Each friend is a conversation addressed `@username` ([addressOf]); [Friends] carries what is written by the routes
/// as it does for a phone-number friend, and keeps it here (`netTextOut`, `netTextIn`). Ids are made from [base] up,
/// so a phone's own conversations and rows, numbered from 1, never meet them.
class UsernameChats {
  UsernameChats({this.base = 0, required this.save, required this.buddies});

  /// Where this store's conversation and row ids start: 0 on an iPhone, which has no others; high on a phone.
  final int base;

  /// Called after every change: the owner writes [toJson] where it keeps things.
  final void Function() save;

  /// The friends by username, as they are kept now.
  final List<Buddy> Function() buddies;

  /// Every conversation kept here, by its id.
  final Map<int, ChatThread> threads = {};

  /// The id the next row gets: one counter for every thread, so a row's id alone finds it.
  late int _nextRow = base + 1;

  /// The thread open on the screen: what comes into it is not unread.
  int open = -1;

  /// A friend's address here is their username with an @ before it, which no phone number has.
  static String addressOf(String username) => '@$username';
  static bool isUsername(String address) => address.startsWith('@');

  /// Takes what [toJson] wrote, in place of whatever is held.
  void load(Map j) {
    threads.clear();
    _nextRow = (j['next'] as num?)?.toInt() ?? base + 1;
    for (final t in (j['threads'] as List?) ?? const []) {
      final thread = ChatThread.fromJson(t as Map);
      threads[thread.id] = thread;
    }
  }

  Map<String, Object?> toJson() => {'next': _nextRow, 'threads': [for (final t in threads.values) t.toJson()]};

  /// Whether a conversation or a row is one of these, not the phone's own: how OverlayCalls decides who answers.
  bool ownsThread(int id) => threads.containsKey(id);
  bool ownsRow(int id) => _threadOfRow(id) != null;

  // --- friends by username ---------------------------------------------------------------------------------------

  /// The friend an `@username` address names, whatever its case; null for a number or a stranger.
  Buddy? buddyAt(String address) {
    if (!isUsername(address)) return null;
    final name = address.substring(1).toLowerCase();
    for (final b in buddies()) {
      if (b.username.toLowerCase() == name) return b;
    }
    return null;
  }

  /// The friend at [address] in the shape the phone gives a person of a conversation.
  Map<String, Object?> person(String address) {
    final b = buddyAt(address);
    return {'address': address, 'name': b?.shown};
  }

  /// Where things stand with each friend, as the phone's encryption record has it: on, and friends.
  List<Map<String, Object?>> states() => [
        for (final b in buddies())
          if (b.state == 'yes') {'address': addressOf(b.username), 'state': 'on', 'friend': 'yes', 'hasGhost': true, 'person': person(addressOf(b.username))},
      ];

  /// Those the routes reach, sealed with [keys] (an iPhone's own; android Buddies.peers works it out on a phone):
  /// friends who said yes, and those asked or asking, so a sealed yes can be opened.
  static List<Map<String, Object>> peersOf(List<Buddy> list, NetKeys keys) {
    final out = <Map<String, Object>>[];
    for (final b in list) {
      if (b.state != 'yes' && b.state != 'asked' && b.state != 'invited') continue;
      Uint8List pub;
      try {
        pub = base64Decode(b.key);
      } catch (_) {
        continue;
      }
      if (pub.length != 33 || NetCrypto.idOf(pub) != b.id) continue;
      final pair = NetCrypto.conversationKey(keys, pub);
      if (pair == null) continue;
      out.add({'id': b.id, 'address': b.state == 'yes' ? addressOf(b.username) : '', 'key': NetCrypto.netKey(pair)});
    }
    return out;
  }

  // --- the conversations -----------------------------------------------------------------------------------------

  /// The thread with [address], made where there is none.
  ChatThread threadWith(String address) {
    for (final t in threads.values) {
      if (t.address.toLowerCase() == address.toLowerCase()) return t;
    }
    // An odd id made from the address, stepped by two past any thread already there.
    var id = base + ((address.toLowerCase().hashCode & 0x3fffffff) | 1);
    while (threads.containsKey(id)) {
      id += 2;
    }
    final made = ChatThread(id: id, address: address);
    threads[id] = made;
    return made;
  }

  ChatRow? _row(int id) {
    for (final t in threads.values) {
      for (final r in t.rows) {
        if (r.id == id) return r;
      }
    }
    return null;
  }

  ChatThread? _threadOfRow(int id) {
    for (final t in threads.values) {
      if (t.rows.any((r) => r.id == id)) return t;
    }
    return null;
  }

  /// Saves, and tells the screens which conversation changed, as the phone does for its own (-1: the list).
  void _changed(int thread) {
    save();
    Sms.instance.changes.add(thread);
  }

  /// A thread as a row of the conversation list, in the shape the phone's own conversations have.
  Map<String, Object?> conversation(ChatThread t) {
    final last = t.rows.isEmpty ? null : t.rows.last;
    return {
      'id': t.id,
      'date': (last?.at ?? t.made),
      'people': [person(t.address)],
      'snippet': last == null ? '' : (last.out ? 'You: ${last.body}' : last.body),
      'unread': t.unread,
      'error': last?.state == 'failed',
      'archived': t.archived,
      'pinned': t.pinned,
      'muted': t.muted,
      'blocked': false,
      'draft': t.draft,
      'encrypted': true,
    };
  }

  /// When a thread last had something written in it, or was made: what the list is sorted by.
  int _at(ChatThread t) => t.rows.isEmpty ? t.made : t.rows.last.at;

  /// The conversations shown (those with something in them), newest first.
  List<ChatThread> sorted({bool archived = false}) {
    final list = [
      for (final t in threads.values)
        if (t.archived == archived && (t.rows.isNotEmpty || t.draft != null)) t,
    ];
    list.sort((a, b) => _at(b).compareTo(_at(a)));
    return list;
  }

  /// The newest [limit] rows of a thread (all of them at 0), newest first, in the shape of the phone's messages.
  List<Map<String, Object?>> messages(int thread, int limit) {
    final t = threads[thread];
    if (t == null) return const [];
    final rows = limit > 0 && t.rows.length > limit ? t.rows.sublist(t.rows.length - limit) : t.rows;
    return [
      for (final r in rows.reversed)
        {'id': r.id, 'kind': 'sms', 'address': t.address, 'body': r.body, 'date': r.at, 'outgoing': r.out, 'state': r.state, 'encrypted': true, 'via': 'net'},
    ];
  }

  /// What friends write, kept here as [Friends] sends and receives it.
  int textOut(String address, String body) {
    final t = threadWith(address);
    final row = ChatRow(id: _nextRow++, body: body, at: DateTime.now().millisecondsSinceEpoch, out: true, state: 'sending');
    t.rows.add(row);
    t.draft = null;
    _changed(t.id);
    return row.id;
  }

  /// What became of a row from [textOut]: 'sent', 'delivered' or 'failed'.
  void textState(int id, String state) {
    final row = _row(id);
    if (row == null) return;
    row.state = state;
    _changed(_threadOfRow(id)!.id);
  }

  void dropRow(int id) {
    final t = _threadOfRow(id);
    if (t == null) return;
    t.rows.removeWhere((r) => r.id == id);
    _changed(t.id);
  }

  /// What a friend wrote, at [at] (milliseconds): unread unless their thread is the one open.
  void textIn(String address, String body, int at) {
    final t = threadWith(address);
    t.rows.add(ChatRow(id: _nextRow++, body: body, at: at, out: false, state: 'received'));
    if (t.id != open) t.unread = true;
    _changed(t.id);
  }

  /// To a friend by username: by the routes ([Friends.sendText] keeps it here as it goes). Pictures and groups are not
  /// carried this way yet.
  Future<int> send(String address, String body) async {
    if (body.isEmpty) throw StateError('Only words can be sent to a friend by username yet');
    final t = threadWith(address);
    // Not taken by any route: nothing was kept on the way, so a failed row is kept here for it to show.
    if (!await Friends.instance.sendText(address, body)) {
      t.rows.add(ChatRow(id: _nextRow++, body: body, at: DateTime.now().millisecondsSinceEpoch, out: true, state: 'failed'));
      _changed(t.id);
    }
    return t.id;
  }

  void markRead(int thread) {
    final t = threads[thread];
    if (t == null || !t.unread) return;
    t.unread = false;
    _changed(t.id);
  }

  void delete(Iterable<int> ids) {
    var any = false;
    for (final id in ids) {
      any = threads.remove(id) != null || any;
    }
    if (any) _changed(-1);
  }

  void deleteRow(int id) => dropRow(id);

  void archive(int thread, bool on) {
    final t = threads[thread];
    if (t == null) return;
    t.archived = on;
    _changed(t.id);
  }

  /// Sets a thread's 'pinned' or 'muted'; any other name changes nothing.
  void flag(String name, int thread, bool on) {
    final t = threads[thread];
    if (t == null) return;
    switch (name) {
      case 'pinned':
        t.pinned = on;
      case 'muted':
        t.muted = on;
    }
    _changed(t.id);
  }

  String? draft(int thread) => threads[thread]?.draft;

  /// Keeps what is half written in a thread (nothing, where it is empty). Saved, but the screens are not told.
  void setDraft(int thread, String text) {
    final t = threads[thread];
    if (t == null) return;
    t.draft = text.isEmpty ? null : text;
    save();
  }

  /// Friends by username whose name or username has [query] in it, as the phone's contacts are searched.
  List<Map<String, String>> search(String query) {
    final q = query.toLowerCase().replaceAll('@', '');
    return [
      for (final b in buddies())
        if (b.state == 'yes' && (q.isEmpty || b.username.toLowerCase().contains(q) || b.name.toLowerCase().contains(q)))
          {'name': b.shown, 'address': addressOf(b.username)},
    ];
  }
}

/// One conversation with a friend by username, and everything written in it. Kept as JSON under short keys.
class ChatThread {
  ChatThread({required this.id, required this.address, int? made}) : made = made ?? DateTime.now().millisecondsSinceEpoch;
  final int id;

  /// The friend's `@username`.
  final String address;

  /// When the thread was made, in milliseconds: its place in the list until something is written.
  final int made;

  /// What was written, oldest first.
  final List<ChatRow> rows = [];
  bool unread = false;
  bool archived = false;
  bool pinned = false;
  bool muted = false;
  String? draft;

  Map<String, Object?> toJson() => {
        'id': id,
        'a': address,
        'm': made,
        'u': unread,
        'ar': archived,
        'p': pinned,
        'mu': muted,
        'd': draft,
        'rows': [for (final r in rows) r.toJson()],
      };

  factory ChatThread.fromJson(Map j) {
    final t = ChatThread(id: (j['id'] as num).toInt(), address: '${j['a']}', made: (j['m'] as num?)?.toInt());
    t.unread = j['u'] == true;
    t.archived = j['ar'] == true;
    t.pinned = j['p'] == true;
    t.muted = j['mu'] == true;
    t.draft = j['d'] as String?;
    for (final r in (j['rows'] as List?) ?? const []) {
      t.rows.add(ChatRow.fromJson(r as Map));
    }
    return t;
  }
}

/// One message of a [ChatThread].
class ChatRow {
  ChatRow({required this.id, required this.body, required this.at, required this.out, required this.state});
  final int id;
  final String body;

  /// When it was written or came in, in milliseconds.
  final int at;

  /// Whether it is ours.
  final bool out;

  /// 'sending', 'sent', 'delivered' or 'failed' for ours; 'received' for theirs.
  String state;

  Map<String, Object?> toJson() => {'i': id, 'b': body, 't': at, 'o': out, 's': state};

  factory ChatRow.fromJson(Map j) => ChatRow(id: (j['i'] as num).toInt(), body: '${j['b']}', at: (j['t'] as num).toInt(), out: j['o'] == true, state: '${j['s']}');
}
