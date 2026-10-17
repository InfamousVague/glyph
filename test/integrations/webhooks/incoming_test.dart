// Incoming webhooks (lib/integrations/webhooks/incoming.dart, docs/INTEGRATIONS.md §1): a post glyph-api sealed, and
// one the web's own wrapFor wrapped (fixtures/hook_seal.json, from tauri/src/app/core/orgs/hookSeal.fixture.json,
// which server/src/hooks_tests.rs and hookSeal.test.ts hold both halves of), opened with the account's private key
// through the Rust core, and with no other key or context; then the sync step over an inbox in memory and the fake
// crypto: a task, an item, a paragraph and a new note put where "add to a note" puts them, a missing note made, the
// inbox read page by page and emptied, and nothing added twice when a delete fails.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/integrations/webhooks/incoming.dart';

import '../../support/fake_crypto.dart';
import '../../support/sync_device.dart' show DeviceNotes;

const _library = 'native/target/debug/libghost_core.dylib';

/// An inbox as glyph-api keeps one (server/src/hooks.rs): oldest first, a page at a time, `after` an id.
class Inbox {
  final List<Map<String, Object?>> items = [];
  final List<String> calls = [];
  int page = inboxPage;
  bool refuseDeletes = false;
  bool noRoutes = false;

  Future<FetchResponse> fetch(FetchRequest request) async {
    final path = request.url.path.replaceFirst('/api/v1/', '');
    calls.add('${request.method} $path${request.url.hasQuery ? '?${request.url.query}' : ''}');
    if (noRoutes) return FetchResponse.json(404, {'error': 'no such route'});
    if (request.bearer != 'token') return FetchResponse.json(401, {'error': 'Sign in again.'});
    if (request.method == 'GET' && path == 'hooks/inbox') {
      final after = request.url.queryParameters['after'];
      final from = after == null ? 0 : items.indexWhere((each) => each['id'] == after) + 1;
      return FetchResponse.json(200, items.skip(from).take(page).toList());
    }
    if (request.method == 'DELETE' && path.startsWith('hooks/inbox/')) {
      if (refuseDeletes) return FetchResponse.json(500, {'error': 'Try again.'});
      items.removeWhere((each) => each['id'] == path.substring('hooks/inbox/'.length));
      return FetchResponse(204);
    }
    return FetchResponse.json(404, {'error': 'no such route'});
  }
}

void main() {
  final fixture = (jsonDecode(File('test/integrations/webhooks/fixtures/hook_seal.json').readAsStringSync()) as Map).cast<String, Object?>();

  group('the seal, through the core', () {
    final built = File(_library).existsSync();
    final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';
    late GhostCore core;
    late CoreCrypto crypto;

    setUpAll(() async {
      if (!built) return;
      core = await GhostCore.open(libraryPath: File(_library).absolute.path);
      crypto = CoreCrypto(core.invoke);
    });

    tearDownAll(() async {
      if (built) await core.close();
    });

    test('a post glyph-api sealed, and one the web\'s wrapFor wrapped, open with the account\'s key into their words', () async {
      final pair = await crypto.importEncryptionKey((fixture['jwk'] as Map).cast<String, Object?>());
      expect(await crypto.encryptionPublicKeyOf(pair), fixture['public']);
      final rust = (fixture['rust'] as Map).cast<String, Object?>();
      final fromRust = await openSealedHook(crypto, pair, hookId: rust['hook'] as String, sealed: rust['sealed'] as String);
      expect((fromRust.note, fromRust.text, fromRust.as, fromRust.title, fromRust.at), ('Groceries', 'Pomegranate jam ✓, “quoted”, and a line\nbreak', HookAs.item, 'From Rust', 1792275541000));
      final web = (fixture['typescript'] as Map).cast<String, Object?>();
      final fromWeb = await openSealedHook(crypto, pair, hookId: web['hook'] as String, sealed: web['sealed'] as String);
      expect((fromWeb.note, fromWeb.text, fromWeb.as, fromWeb.title), ('Trip', 'Passports, “both”, ✓', HookAs.task, null));
    }, skip: skip);

    test('no other key opens it, nor the same seal as another hook\'s; the core\'s own unwrap_with holds to 32 bytes', () async {
      final pair = await crypto.importEncryptionKey((fixture['jwk'] as Map).cast<String, Object?>());
      final web = (fixture['typescript'] as Map).cast<String, Object?>();
      final stranger = await crypto.newEncryptionKey();
      await expectLater(openSealedHook(crypto, stranger, hookId: web['hook'] as String, sealed: web['sealed'] as String), throwsA(anything));
      await expectLater(openSealedHook(crypto, pair, hookId: 'another-hook', sealed: web['sealed'] as String), throwsA(anything));
      await expectLater(crypto.unwrapWith(pair, web['sealed'] as String, hookContext(web['hook'] as String)), throwsA(anything));
    }, skip: skip);
  });

  group('placing the words', () {
    test('a task is a to-do on the note\'s list, boxed even on a list of plain items', () {
      expect(placedHook('# Groceries\n\n- milk\n- eggs', 'Oat milk', HookAs.task), '# Groceries\n\n- milk\n- eggs\n- [ ] Oat milk');
      expect(placedHook('# Todo\n\n1. [ ] Call', 'Write', HookAs.task), '# Todo\n\n1. [ ] Call\n2. [ ] Write');
      expect(placedHook('# Trip\n', 'Passports', HookAs.task), '# Trip\n\n- [ ] Passports\n');
    });

    test('an item is an item of the list, each line one; a paragraph its own; nothing said, where it fits', () {
      expect(placedHook('# Groceries\n\n- milk', 'Oat milk\nBread', HookAs.item), '# Groceries\n\n- milk\n- Oat milk\n- Bread');
      expect(placedHook('# Todo\n\n- [ ] Call', 'Plumber', HookAs.item), '# Todo\n\n- [ ] Call\n- Plumber');
      expect(placedHook('# Groceries\n\n- milk', 'Remember the shop shuts early on Sunday', HookAs.paragraph), '# Groceries\n\n- milk\n\nRemember the shop shuts early on Sunday.\n');
      expect(placedHook('# Groceries\n\n- milk', 'bread', HookAs.fits), '# Groceries\n\n- milk\n- Bread');
      expect(placedHook('# Diary\n\nA day.', 'It rained', HookAs.fits), '# Diary\n\nA day.\n\nIt rained.\n');
      expect(placedHook('# Diary', '  ', HookAs.fits), '# Diary');
    });

    test('a body that is not the sealed JSON is all words', () {
      final plain = HookItem.read('Call the plumber');
      expect((plain.note, plain.text, plain.as), (null, 'Call the plumber', HookAs.fits));
      final json = HookItem.read('{"hook":"h","note":null,"text":"x","as":null,"at":5}');
      expect((json.note, json.as, json.at), (null, HookAs.fits, 5));
    });
  });

  group('the sync step', () {
    late FakeCrypto crypto;
    late EncryptionKey pair;
    late String pub;
    late Inbox inbox;
    late DeviceNotes notes;
    late MemoryStored kept;
    late PreferencesStore prefs;
    var n = 0;

    setUp(() async {
      crypto = FakeCrypto();
      pair = await crypto.newEncryptionKey();
      pub = await crypto.encryptionPublicKeyOf(pair);
      inbox = Inbox();
      notes = DeviceNotes();
      kept = MemoryStored();
      prefs = PreferencesStore()..startWithoutStorage();
    });

    Future<void> posted(Map<String, Object?> payload, {String hook = 'h1', String? id}) async {
      n += 1;
      final sealed = await crypto.wrapFor(pub, utf8.encode(jsonEncode({'hook': hook, 'at': 1792275541000, ...payload})), hookContext(hook));
      inbox.items.add({'id': id ?? 'item-$n', 'hook': hook, 'at': 1792275541000, 'sealed': sealed});
    }

    HookPassContext ctx() => HookPassContext(
          token: 'token',
          api: Api(base: 'http://hooks.test/api', fetcher: inbox.fetch),
          crypto: crypto,
          pair: () async => pair,
          notes: notes,
          now: () => 9000,
          prefs: () => prefs.value,
          kept: kept,
        );

    test('each item goes into its note as it asks, a missing note is made, and the inbox is emptied', () async {
      notes.held['g'] = const Note(id: 'g', body: '# Groceries\n\n- milk', createdAt: 1, updatedAt: 2);
      await posted({'note': 'groceries', 'text': 'Oat milk', 'as': 'task'});
      await posted({'note': 'Groceries', 'text': 'Bread', 'as': 'item'});
      await posted({'note': 'Trip', 'text': 'Passports', 'as': 'task'});
      await posted({'note': 'Ideas', 'text': 'A garden shed', 'as': 'note', 'title': 'Shed'});
      await posted({'note': null, 'text': 'Call the plumber', 'as': null});
      await posted({'note': null, 'text': 'Holiday\nBook the ferry', 'as': 'task'});
      expect(await syncHooks(ctx()), 6);
      expect(notes.held['g']!.body, '# Groceries\n\n- milk\n- [ ] Oat milk\n- Bread');
      expect(notes.held['g']!.updatedAt, 9000);
      Note titled(String title) => notes.held.values.singleWhere((note) => note.body.startsWith('# $title\n'));
      expect(titled('Trip').body, '# Trip\n\n- [ ] Passports\n');
      expect(titled('Trip').id, hookNoteId('item-${n - 3}'));
      expect(titled('Trip').createdAt, 1792275541000);
      expect(titled('Shed').body, '# Shed\n\nA garden shed\n');
      expect(titled('Call the plumber').body, '# Call the plumber\n');
      expect(titled('Holiday').body, '# Holiday\n\n- [ ] Book the ferry\n');
      expect(inbox.items, isEmpty);
      expect(inbox.calls.where((call) => call.startsWith('DELETE')), hasLength(6));
    });

    test('nothing is added twice: a delete that fails is tried again on the next pass, and the note stays as it was', () async {
      notes.held['g'] = const Note(id: 'g', body: '# Groceries\n\n- milk', createdAt: 1, updatedAt: 2);
      await posted({'note': 'Groceries', 'text': 'Oat milk', 'as': 'item'});
      await posted({'note': 'Ideas', 'text': 'Shed', 'as': 'note'});
      inbox.refuseDeletes = true;
      expect(await syncHooks(ctx()), 2);
      expect(inbox.items, hasLength(2));
      final after = notes.held['g']!.body;
      inbox.refuseDeletes = false;
      expect(await syncHooks(ctx()), 0);
      expect(notes.held['g']!.body, after);
      expect(notes.held, hasLength(2));
      expect(inbox.items, isEmpty);
      // Another device that added the new note already: its id is the item's, so it is not made twice.
      await posted({'note': 'Ideas', 'text': 'Shed', 'as': 'note'}, id: 'item-$n');
      kept.write('glyph-hooks-applied', null);
      expect(await syncHooks(ctx()), 0);
      expect(notes.held, hasLength(2));
    });

    test('the inbox is read a page at a time, after the last item read', () async {
      for (var i = 0; i < 205; i += 1) {
        await posted({'note': 'Log', 'text': 'Line $i', 'as': 'paragraph'}, id: 'p$i');
      }
      inbox.refuseDeletes = true;
      expect(await syncHooks(ctx()), 205);
      expect([for (final call in inbox.calls) if (call.startsWith('GET')) call], ['GET hooks/inbox', 'GET hooks/inbox?after=p99', 'GET hooks/inbox?after=p199']);
      final body = notes.held.values.single.body;
      expect(body, startsWith('# Log\n\nLine 0.\n\nLine 1.\n'));
      expect(body, endsWith('Line 203.\n\nLine 204.\n'));
    });

    test('an item that will not open is left waiting; a trashed note is not written to; no routes is no work', () async {
      notes.held['old'] = const Note(id: 'old', body: '# Groceries\n\n- milk', createdAt: 1, updatedAt: 2);
      prefs.update((now) => now.copyWith(trash: {'old': 5}));
      inbox.items.add({'id': 'bad', 'hook': 'h1', 'at': 1, 'sealed': 'AAAA'});
      await posted({'note': 'Groceries', 'text': 'Oat milk', 'as': 'item'});
      expect(await syncHooks(ctx()), 1);
      expect(notes.held['old']!.body, '# Groceries\n\n- milk');
      expect(notes.held.values.where((note) => note.id != 'old').single.body, '# Groceries\n\n- Oat milk\n');
      expect([for (final item in inbox.items) item['id']], ['bad']);
      inbox.noRoutes = true;
      expect(await syncHooks(ctx()), 0);
    });
  });
}
