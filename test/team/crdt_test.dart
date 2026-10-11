// lib/team/crdt.dart over the Rust core's real C functions, on the Mac (tool/build-native.sh host): documents and
// rooms by handle, bytes either way, UTF-16 offsets as a Dart String counts them, and the wire held here too to
// what the web's own Yjs wrote (native/tests/fixtures/yjs_web.json, tool/yjs_vectors.mjs). What yrs does with an
// update is Rust's to test (native/src/crdt.rs, native/tests/yjs_vectors.rs).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/team/crdt.dart';

const _library = 'native/target/debug/libghost_core.dylib';

void main() {
  final built = File(_library).existsSync();
  final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';
  final web = (jsonDecode(File('native/tests/fixtures/yjs_web.json').readAsStringSync()) as Map).cast<String, Object?>();
  Map<String, Object?> part(String name) => (web[name] as Map).cast<String, Object?>();
  List<Uint8List> updates(Object? list) => [for (final update in list as List) fromBase64Url(update as String)];

  late GhostCore core;
  late Crdt crdt;

  setUpAll(() async {
    if (!built) return;
    // No `init`: a document asks nothing of the library.
    core = await GhostCore.open(libraryPath: File(_library).absolute.path);
    crdt = Crdt(core.invoke);
  });

  tearDownAll(() async {
    if (built) await core.close();
  });

  test('a note\'s words are seeded, reconciled and queued, and a second device follows from the updates alone', () async {
    final mine = await crdt.open(words: '# Plan\n\nFirst.\n', clientId: 7);
    expect(mine.clientId, 7);
    expect(await mine.words(), '# Plan\n\nFirst.\n');
    final seeded = await mine.pending();
    expect(seeded, hasLength(1));
    expect(seeded.single, await mine.snapshot(), reason: 'doc.ts: the whole of a seeded document is pending');

    final theirs = await crdt.open();
    expect(theirs.clientId, lessThanOrEqualTo(0xffffffff), reason: 'a client id as Yjs draws one');
    expect(await theirs.pending(), isEmpty);
    expect(await theirs.applyRemote(seeded), '# Plan\n\nFirst.\n');
    expect(await theirs.applyRemote(seeded), isNull, reason: 'an update heard twice changes nothing');
    expect(await theirs.pending(), isEmpty, reason: 'what arrives is not owed back');
    expect(await mine.posted(1), 0);

    // Both change the note at once; each hears the other; both end with both changes.
    final a = await mine.reconcile('# Plan for Saturday\n\nFirst.\n');
    final b = await theirs.reconcile('# Plan\n\nFirst.\nThen 😀.\n');
    expect(a.changed && b.changed, isTrue);
    expect(await mine.pending(), [a.update]);
    await mine.applyRemote([b.update!]);
    await theirs.applyRemote([a.update!]);
    expect(await mine.words(), '# Plan for Saturday\n\nFirst.\nThen 😀.\n');
    expect(await theirs.words(), await mine.words());
    expect((await mine.reconcile(await mine.words())).changed, isFalse);

    expect(await crdt.lacks(await mine.stateVector(), await theirs.stateVector()), isFalse);
    expect(await crdt.lacks(Uint8List(0), await theirs.stateVector()), isTrue);
    final late_ = await crdt.open(clientId: 9);
    await late_.applyRemote([await mine.stateFor(await late_.stateVector())]);
    expect(await late_.words(), await mine.words());
    for (final doc in [mine, theirs, late_]) {
      await doc.close();
    }
    await expectLater(mine.words(), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'That document is not held any more.')));
  }, skip: skip);

  test('offsets are a Dart String\'s own, an editor\'s changes are one update, and a kept document comes back', () async {
    final doc = await crdt.open(words: 'a😀b', clientId: 11);
    expect('a😀b'.length, 4);
    final swapped = await doc.reconcile('a😁b');
    expect(swapped.text, 'a😁b');
    final edited = await doc.edit(const [CrdtEdit(3, insert: 'é'), CrdtEdit(0, remove: 1)]);
    expect(edited.text, '😁éb');
    expect(edited.text.substring(2, 3), 'é');
    await expectLater(doc.edit(const [CrdtEdit(1, insert: 'x')]), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'A change may not split a character in two.')));
    await expectLater(doc.edit(const [CrdtEdit(3, remove: 9)]), throwsA(isA<CoreError>()));
    expect(await doc.words(), '😁éb');

    final state = await doc.snapshot(), pending = await doc.pending();
    expect(pending, hasLength(3));
    await doc.close();
    final again = await crdt.open(state: state, pending: pending, clientId: 11);
    expect(await again.words(), '😁éb');
    expect(await again.pending(), pending);
    expect(await again.posted(2), 1);
    await again.close();
  }, skip: skip);

  test('a caret stays with its character, in the JSON Yjs writes', () async {
    final doc = await crdt.open(words: 'hello world', clientId: 5);
    final anchor = await doc.relative(6), head = await doc.relative(11);
    expect(anchor, {'tname': 'body', 'item': {'client': 5, 'clock': 6}, 'assoc': 0});
    expect(head, {'tname': 'body', 'assoc': 0});
    expect(await doc.relative(6, assoc: -1), {'tname': 'body', 'item': {'client': 5, 'clock': 5}, 'assoc': -1});
    await doc.reconcile('oh, hello world');
    expect(await doc.absolute(anchor), 10);
    expect(await doc.caretIndexes({'anchor': anchor, 'head': head}), (anchor: 10, head: 15));
    // A head that cannot be placed is the anchor; an anchor that cannot be is no caret.
    final stranger = {'tname': 'body', 'item': {'client': 99, 'clock': 3}, 'assoc': 0};
    expect(await doc.caretIndexes({'anchor': anchor, 'head': stranger}), (anchor: 10, head: 10));
    expect(await doc.caretIndexes({'anchor': stranger, 'head': head}), isNull);
    expect(await doc.caretIndexes({'anchor': 'not a position', 'head': head}), isNull);
    expect(await doc.caretIndexes(null), isNull);
    await doc.close();
  }, skip: skip);

  test('a room is who is here and where, by y-protocols\' rules', () async {
    final mine = await crdt.room(21), theirs = await crdt.room(22);
    final user = {'name': 'matt', 'hue': 'moss', 'color': 'var(--app-ink)'};
    final said = await mine.setField('user', user);
    expect((await theirs.apply(said!)).added, [21]);
    final caret = {
      'anchor': {'tname': 'body', 'item': {'client': 5, 'clock': 6}, 'assoc': 0},
      'head': {'tname': 'body', 'assoc': 0},
    };
    final moved = await theirs.apply((await mine.setField('cursor', caret))!);
    expect(moved.updated, [21]);
    expect(moved.changed, isTrue);
    final again = await theirs.apply(await mine.setLocal({'user': user, 'cursor': caret}));
    expect(again.updated, isEmpty, reason: 'said again unchanged');
    expect(again.touched, [21]);
    expect(again.changed, isFalse);
    final states = await theirs.states();
    expect([for (final one in states) one.client], [21, 22]);
    expect(states.first.state, {'user': user, 'cursor': caret});
    expect(states.first.clock, 3);

    // A device that has just joined is told of everyone who has said something.
    await theirs.setField('user', {'name': 'sam'});
    final late_ = await crdt.room(23);
    expect((await late_.apply(await theirs.encode())).added, [21, 22]);
    expect((await late_.tick()).removed, isEmpty);
    expect(await late_.remove([22, 99]), [22]);

    final left = await mine.setLocal(null);
    expect((await theirs.apply(left)).removed, [21]);
    expect(await mine.setField('cursor', caret), isNull, reason: 'nothing to set a field of once it has left');
    for (final room in [mine, theirs, late_]) {
      await room.close();
    }
  }, skip: skip);

  group('what the web\'s Yjs wrote (native/tests/fixtures/yjs_web.json)', () {
    test('two members\' changes merge to the words Yjs arrived at, either way round', () async {
      final c = part('concurrent');
      final b = (c['b'] as Map)['updates'], cs = (c['c'] as Map)['updates'];
      for (final order in [
        [...updates(b), ...updates(cs)],
        [...updates(cs), ...updates(b)],
      ]) {
        final doc = await crdt.open(state: fromBase64Url(c['base'] as String));
        await doc.applyRemote(order);
        expect(await doc.words(), c['merged']);
        await doc.close();
      }
      // What Yjs answered B's state vector is all B lacked.
      final onlyB = await crdt.open(state: fromBase64Url(c['base'] as String));
      await onlyB.applyRemote(updates(b));
      expect(await onlyB.words(), (c['b'] as Map)['text']);
      expect(await crdt.lacks(await onlyB.stateVector(), fromBase64Url((c['c'] as Map)['vector'] as String)), isTrue);
      expect(await onlyB.applyRemote([fromBase64Url(c['diffForB'] as String)]), c['merged']);
      await onlyB.close();
    }, skip: skip);

    test('three devices\' 240 steps end with Yjs\'s words, in order and backwards', () async {
      final r = part('random');
      final all = [for (final one in r['updates'] as List) fromBase64Url((one as Map)['update'] as String)];
      final forwards = await crdt.open(), backwards = await crdt.open();
      await forwards.applyRemote(all);
      for (final update in all.reversed) {
        await backwards.applyRemote([update]);
      }
      expect(await forwards.words(), r['text']);
      expect(await backwards.words(), r['text']);
      expect((await forwards.words()).length, r['length']);
      await forwards.close();
      await backwards.close();
    }, skip: skip);

    test('a caret is written as Yjs writes it and placed where Yjs places it', () async {
      final p = part('positions');
      final doc = await crdt.open(state: fromBase64Url(p['state'] as String));
      final at = (p['at'] as List).cast<Map>();
      for (final one in at) {
        expect(await doc.relative(one['index'] as int, assoc: one['assoc'] as int), one['json']);
      }
      await doc.applyRemote(updates(p['then']));
      expect(await doc.words(), p['textAfter']);
      final after = p['after'] as List;
      for (var i = 0; i < at.length; i += 1) {
        expect(await doc.absolute(at[i]['json']), after[i], reason: '${at[i]['json']}');
      }
      await doc.close();
    }, skip: skip);

    test('awareness from y-protocols is heard as y-protocols hears it', () async {
      final a = part('awareness');
      final room = await crdt.room(a['hearer'] as int);
      for (final step in (a['steps'] as List).cast<Map>()) {
        final heard = await room.apply(fromBase64Url(step['update'] as String));
        final change = step['change'] as Map;
        expect([heard.added, heard.updated, heard.removed], [change['added'], change['updated'], change['removed']], reason: '${step['label']}');
        final states = {for (final one in await room.states()) if (one.client != a['hearer']) '${one.client}': one.state};
        expect(states, step['states'], reason: '${step['label']}');
      }
      await room.close();
    }, skip: skip);

    test('a change from the web that splits a character is read as the web reads it: U+FFFD twice where the emoji was', () async {
      final s = part('splitCharacter');
      final doc = await crdt.open(state: fromBase64Url(s['base'] as String));
      expect(await doc.words(), 'a😀b');
      expect(await doc.applyRemote([fromBase64Url(s['update'] as String)]), s['heard']);
      expect((await doc.words()).codeUnits, s['heardUnits']);
      expect((await doc.words()).codeUnits, [97, 0xFFFD, 0xFFFD, 98]);
      // And it is typed in after, a whole character between the two.
      expect((await doc.edit(const [CrdtEdit(2, insert: '😁')])).text, 'a\uFFFD😁\uFFFDb');
      await doc.close();
    }, skip: skip);
  });
}
