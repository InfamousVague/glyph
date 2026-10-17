/// Incoming webhooks (docs/INTEGRATIONS.md, §1; glyph-api's server/src/hooks.rs): a URL of glyph-api's that adds to a
/// note, and the step of a sync pass that does the adding.
///
/// glyph-api takes a post in the clear, as any server must, seals it at once to the account's encryption PUBLIC key
/// (ECIES on P-256, exactly core/orgs/wrap.ts's `wrapFor`, with `hook:<hook id>` as its context) as
/// `{ hook, note, text, as, title?, at }` (`note` already the hook's default where the post named none, `at` in ms),
/// keeps only the seal, and answers 202. So a device opens it with what it already has ([openSealedHook]): the
/// account's pair, through the core's `unwrap_bytes_with` (the core's `unwrap_with` holds a wrap to an organization
/// key's 32 bytes; the web's reads any length, and so does this).
///
/// [syncHooks] is a step of the pass (lib/sync/engine.dart `hooksIn`), beside the mail and before the notes: the inbox
/// read a hundred at a time, oldest first, and each item opened and put into its note the way the app's own "add to a
/// note" puts words (capture/list_append.dart [placeWords]): `task` a to-do on the note's list, `item` an item of it,
/// `paragraph` a paragraph of its own, `note` a new note named `title` (or `note`) holding `text`, and nothing said,
/// wherever the words fit. A note that is not there is made; with no note named at all, it is a new note titled by the
/// words' first line. The note is written into the library through the same door a note from another device comes in
/// by ([LocalNotes.apply]), so the notes step of the same pass sends it on as any change, and the item is deleted from
/// the inbox. What was added is remembered here by the item's id, so a delete that fails, or a pass cut short after
/// the note was written, never adds it twice; a new note's id is made from the item's ([hookNoteId]) for the same
/// reason across devices.
///
/// [IncomingHooks] is the pane's: the account's hooks as glyph-api lists them (with no URL: the service keeps only its
/// token's digest, so a URL is shown once, as the hook is made), a new one (the account's encryption key seen to
/// first, since every post is sealed to it), and Delete.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../../account/api.dart';
import '../../account/crypto_api.dart';
import '../../account/enc_key.dart';
import '../../account/ui_state.dart' show AccountServices;
import '../../capture/list_append.dart' show Placing, PlacingHow, placeWords;
import '../../core/note.dart';
import '../../core/note_text.dart' show listMarker, noteTitle, taskBoxPattern;
import '../../core/preferences.dart';
import '../../core/stored.dart';
import '../../sync/notes.dart' show LocalNotes;

/// The context a hook's post is sealed in.
String hookContext(String hookId) => 'hook:$hookId';

/// How a post asks for its words to be put: [fits] where it said nothing.
enum HookAs { task, item, paragraph, note, fits }

/// One post, opened: the note it goes to (by title), its words, how they go in, a new note's own title, and when it
/// came.
@immutable
class HookItem {
  const HookItem({this.note, required this.text, this.as = HookAs.fits, this.title, this.at});

  final String? note;
  final String text;
  final HookAs as;
  final String? title;

  /// Milliseconds since the epoch.
  final int? at;

  static String? _words(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

  /// A post as glyph-api sealed it, `{ hook, note, text, as, title?, at }`; anything that is not that JSON is all
  /// words.
  static HookItem read(String opened) {
    Object? json;
    try {
      json = jsonDecode(opened);
    } on FormatException {
      json = null;
    }
    if (json is! Map) return HookItem(text: opened.trim());
    final text = json['text'], at = json['at'];
    return HookItem(
      note: _words(json['note']),
      text: text is String ? text.trim() : (text == null ? '' : '$text'),
      as: switch (json['as']) { 'task' => HookAs.task, 'item' => HookAs.item, 'paragraph' => HookAs.paragraph, 'note' => HookAs.note, _ => HookAs.fits },
      title: _words(json['title']),
      at: at is num ? at.toInt() : null,
    );
  }
}

/// A hook's post out of [sealed], with the account's [pair].
Future<HookItem> openSealedHook(AccountCrypto crypto, EncryptionKey pair, {required String hookId, required String sealed}) async {
  final context = hookContext(hookId);
  final bytes = switch (crypto) {
    final UnwrapsBytes any => await any.unwrapBytesWith(pair, sealed, context),
    _ => await crypto.unwrapWith(pair, sealed, context),
  };
  return HookItem.read(utf8.decode(bytes, allowMalformed: true));
}

/// The id of the note an item makes: a UUID v4 drawn from its id, so two devices, or a pass cut short, make one.
String hookNoteId(String itemId) {
  final b = Uint8List.fromList(crypto.sha256.convert(utf8.encode('ghost-hook-note:$itemId')).bytes.sublist(0, 16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = [for (final byte in b) byte.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final RegExp _unboxed = RegExp('^(\\s*$listMarker\\s+)(?!$taskBoxPattern)');
final RegExp _boxed = RegExp('^(\\s*$listMarker\\s+)$taskBoxPattern\\s*');

/// [body] with [text] put in as [as] asks, the way "add to a note" puts words ([placeWords]). A task is always a
/// to-do, boxed even on a list of plain items, and an item never is one, even on a list of to-dos. Each line of a
/// task's or an item's words is one.
String placedHook(String body, String text, HookAs as) {
  if (text.trim().isEmpty) return body;
  final lines = [for (final line in text.split('\n')) if (line.trim().isNotEmpty) line.trim()];
  switch (as) {
    case HookAs.task || HookAs.item:
      final task = as == HookAs.task;
      final placed = placeWords(body, text, Placing(how: PlacingHow.item, task: task, many: lines.length > 1, items: lines));
      if (placed.added.isEmpty) return placed.body;
      final out = placed.body.split('\n');
      // The lines added are together, the last of them at its last place in the body. A task has its box; an item
      // has none, even at the end of a list of to-dos.
      final end = out.lastIndexOf(placed.added.last);
      for (var at = end - placed.added.length + 1; at <= end; at += 1) {
        if (at < 0) continue;
        out[at] = task ? out[at].replaceFirstMapped(_unboxed, (match) => '${match.group(1)}[ ] ') : out[at].replaceFirstMapped(_boxed, (match) => match.group(1)!);
      }
      return out.join('\n');
    case HookAs.paragraph:
      return placeWords(body, text, const Placing(how: PlacingHow.paragraph, task: false, many: false)).body;
    case HookAs.fits || HookAs.note:
      return placeWords(body, text, const Placing(how: PlacingHow.leave, task: false, many: false)).body;
  }
}

/// A note's body made for [title] and nothing else yet.
String titledBody(String title) => '# $title\n';

/// What the hooks step works with.
class HookPassContext {
  const HookPassContext({required this.token, required this.api, required this.crypto, required this.pair, required this.notes, required this.now, required this.prefs, required this.kept});
  final String token;
  final Api api;
  final AccountCrypto crypto;

  /// The account's encryption pair, asked for only when there is something to open.
  final Future<EncryptionKey> Function() pair;
  final LocalNotes notes;
  final int Function() now;

  /// The settings now: what is in the trash.
  final Preferences Function() prefs;

  /// This device's memory, for the items already added.
  final Stored kept;
}

/// One hooks step, as the engine is handed it: answers how many notes it changed.
typedef HookPass = Future<int> Function(HookPassContext ctx);

const String _appliedKey = 'glyph-hooks-applied';

/// How many added items' ids are remembered: more than the inbox holds (500).
const int _appliedKept = 1000;

/// The most items one page of the inbox carries.
const int inboxPage = 100;

List<String> _applied(Stored kept) {
  final raw = kept.read<Object?>(_appliedKey, null);
  return [if (raw is List) ...raw.whereType<String>()];
}

void _remember(Stored kept, List<String> ids) => kept.write(_appliedKey, ids.length > _appliedKept ? ids.sublist(ids.length - _appliedKept) : ids);

String _key(String title) => title.trim().toLowerCase();

/// The hooks step (see the header). Quiet against a service that has no hook routes yet.
Future<int> syncHooks(HookPassContext ctx) async {
  final prefs = ctx.prefs();
  final applied = _applied(ctx.kept);
  EncryptionKey? pair;
  Map<String, Note>? byTitle;
  var changed = 0;

  Future<Map<String, Note>> titles() async {
    if (byTitle != null) return byTitle!;
    final notes = [for (final note in await ctx.notes.list()) if (!prefs.trash.containsKey(note.id)) note]..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    // The newest of two notes of one title is the one written to.
    return byTitle = {for (final note in notes) _key(noteTitle(note.body)): note};
  }

  /// [text] into the note titled [title], made where there is none, under the id [made].
  Future<void> into(String title, String text, HookAs as, {required String made, required int at}) async {
    final known = (await titles())[_key(title)];
    final target = known ?? await ctx.notes.get(made);
    final before = target?.body ?? titledBody(title);
    final body = placedHook(before, text, as);
    if (target != null && body == target.body) return;
    final note = target == null ? Note(id: made, body: body, createdAt: at, updatedAt: ctx.now()) : target.copyWith(body: body, updatedAt: ctx.now());
    (await titles())[_key(title)] = await ctx.notes.apply(note);
    changed += 1;
  }

  /// A new note titled [title] holding [text], unless the item made it already.
  Future<void> made(String title, String text, {required String id, required int at}) async {
    if (title.isEmpty || await ctx.notes.get(id) != null) return;
    final body = text.isEmpty ? titledBody(title) : '${titledBody(title)}\n$text\n';
    (await titles())[_key(title)] = await ctx.notes.apply(Note(id: id, body: body, createdAt: at, updatedAt: ctx.now()));
    changed += 1;
  }

  String? after;
  for (;;) {
    final Object? listed;
    try {
      listed = await ctx.api.call('GET', after == null ? 'hooks/inbox' : 'hooks/inbox?after=${Uri.encodeQueryComponent(after)}', token: ctx.token);
    } catch (failure) {
      if (notYet(failure)) return changed;
      rethrow;
    }
    if (listed is! List || listed.isEmpty) break;
    for (final each in listed) {
      if (each is! Map || each['id'] is! String) continue;
      final id = each['id'] as String;
      after = id;
      if (!applied.contains(id)) {
        final hook = each['hook'], sealed = each['sealed'];
        if (hook is! String || sealed is! String) continue;
        final HookItem item;
        try {
          item = await openSealedHook(ctx.crypto, pair ??= await ctx.pair(), hookId: hook, sealed: sealed);
        } catch (failure) {
          // Left waiting: a newer app may read what this one cannot.
          debugPrint('[hooks] an item would not open: $failure');
          continue;
        }
        final listedAt = each['at'];
        final at = item.at ?? (listedAt is num ? listedAt.toInt() : ctx.now());
        final note = hookNoteId(id);
        final lines = item.text.split('\n');
        final first = lines.first.trim(), rest = lines.skip(1).join('\n').trim();
        if (item.as == HookAs.note) {
          // Named by its title, or the note it names; with neither, by the words' first line, the rest its body.
          final title = item.title ?? item.note;
          await made(title ?? first, title == null ? rest : item.text, id: note, at: at);
        } else if (item.note != null) {
          await into(item.note!, item.text, item.as, made: note, at: at);
        } else if (rest.isEmpty) {
          // No note named, and the hook has none: a note of its own, titled by the words.
          await made(first, '', id: note, at: at);
        } else {
          await into(first, rest, item.as, made: note, at: at);
        }
        applied.add(id);
        _remember(ctx.kept, applied);
      }
      // Added, here or before: the item goes from the inbox. One that will not go is tried on the next pass, and is
      // not added again.
      try {
        await ctx.api.call('DELETE', 'hooks/inbox/${Uri.encodeComponent(id)}', token: ctx.token);
      } on ApiError catch (failure) {
        if (failure.status == 401) rethrow;
        if (failure.status != 404) debugPrint('[hooks] an item was not taken off the inbox: $failure');
      }
    }
    if (listed.length < inboxPage) break;
  }
  return changed;
}

// ---- the pane's ----------------------------------------------------------------------------------------------------

/// A hook as glyph-api lists it.
@immutable
class IncomingHook {
  const IncomingHook({required this.id, required this.name, this.url, this.createdAt, this.lastUsedAt, this.note});

  final String id;
  final String name;

  /// The secret URL a post goes to: said once, when the hook is made, and never listed.
  final String? url;

  /// Milliseconds since the epoch.
  final int? createdAt;
  final int? lastUsedAt;

  /// The default note: where a post that names none goes.
  final String? note;

  static IncomingHook? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final name = raw['name'], url = raw['url'], note = raw['note'], made = raw['createdAt'], used = raw['lastUsedAt'];
    return IncomingHook(
      id: raw['id'] as String,
      name: name is String && name.isNotEmpty ? name : 'Webhook',
      url: url is String && url.isNotEmpty ? url : null,
      createdAt: made is num ? made.toInt() : null,
      lastUsedAt: used is num ? used.toInt() : null,
      note: note is String && note.isNotEmpty ? note : null,
    );
  }
}

/// The examples the pane shows for a hook's [url], each a name and what to paste.
List<({String name, String text})> hookExamples(String url, {String? note}) {
  final title = note ?? 'Groceries';
  final json = jsonEncode({'note': title, 'text': 'Oat milk', 'as': 'item'});
  return [
    (name: 'curl', text: "curl -X POST '$url' \\\n  -H 'Content-Type: application/json' \\\n  -d '$json'"),
    (name: 'curl, plain text', text: "curl -X POST '$url' \\\n  -H 'Content-Type: text/plain' \\\n  --data 'Call the plumber'"),
    (name: 'Zapier', text: 'Webhooks by Zapier › POST\nURL: $url\nPayload Type: json\nData: note = $title, text = (a field from your trigger), as = task'),
    (name: 'Make', text: 'HTTP › Make a request\nURL: $url\nMethod: POST\nBody type: Raw, JSON\nRequest content: $json'),
    (name: 'IFTTT', text: 'Webhooks › Make a web request\nURL: $url\nMethod: POST\nContent Type: application/json\nBody: {"note":"$title","text":"{{Text}}","as":"task"}'),
  ];
}

/// The account's incoming hooks, for the pane: as glyph-api last listed them, a new one, Delete.
class IncomingHooks extends ChangeNotifier {
  IncomingHooks({required this.api, required String? Function() token, required Future<void> Function() seeToKey})
      : _token = token,
        _seeToKey = seeToKey;

  /// Over the account [services] hold: its service, its session, and its encryption key seen to as email to a note's
  /// is (lib/mail/mail_in.dart `newAddress`).
  factory IncomingHooks.of(AccountServices services) {
    final account = services.account;
    return IncomingHooks(
      api: account.api,
      token: () => account.session?.token,
      seeToKey: () async {
        final token = account.session?.token;
        final accountKey = await account.accountKey();
        if (token == null || accountKey == null) throw const ApiError(409, 'Sign in again on this device first: its key is not here.');
        await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: account.keys, api: account.api, crypto: account.crypto));
      },
    );
  }

  final Api api;
  final String? Function() _token;
  final Future<void> Function() _seeToKey;

  List<IncomingHook>? _hooks;

  /// As last listed; null until they have been.
  List<IncomingHook>? get hooks => _hooks;

  /// The hook made last on this device, with its URL, until the pane is left: the one time it is said.
  IncomingHook? get made => _made;
  IncomingHook? _made;

  /// Whether the service has hooks at all: an older one does not.
  bool get available => _available;
  bool _available = true;

  String _signedIn() {
    final token = _token();
    if (token == null) throw const ApiError(401, 'Sign in under Settings › Account first.');
    return token;
  }

  /// What the service says now.
  Future<List<IncomingHook>> refresh() async {
    final Object? said;
    try {
      said = await api.call('GET', 'hooks', token: _signedIn());
    } catch (failure) {
      if (!notYet(failure)) rethrow;
      _available = false;
      _hooks = const [];
      notifyListeners();
      return _hooks!;
    }
    _available = true;
    _hooks = List.unmodifiable([
      if (said is List)
        for (final each in said) ?IncomingHook.fromJson(each),
    ]);
    notifyListeners();
    return _hooks!;
  }

  /// A new hook called [name], what names no note going to [note]: the account's encryption key seen to first.
  /// Answers it with its URL, said this once.
  Future<IncomingHook> create(String name, {String? note}) async {
    final token = _signedIn();
    final called = name.trim().isEmpty ? 'Webhook' : name.trim();
    final into = note?.trim();
    await _seeToKey();
    final said = await api.callMap('POST', 'hooks', token: token, body: {'name': called, if (into != null && into.isNotEmpty) 'note': into});
    final made = IncomingHook.fromJson(said);
    if (made == null || made.url == null) throw const ApiError(500, 'The service answered without a hook.');
    _made = made;
    _hooks = List.unmodifiable([...?_hooks?.where((each) => each.id != made.id), made]);
    notifyListeners();
    return made;
  }

  /// The hook off: its URL takes nothing more. What it already took is still added.
  Future<void> delete(String id) async {
    await api.call('DELETE', 'hooks/${Uri.encodeComponent(id)}', token: _signedIn());
    if (_made?.id == id) _made = null;
    _hooks = List.unmodifiable([...?_hooks?.where((each) => each.id != id)]);
    notifyListeners();
  }
}
