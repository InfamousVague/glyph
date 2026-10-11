// A team note's document on a device (lib/team/doc.dart), over the REAL CRDT in the Mac's core: seeded from the
// note's words or read from the store, words from elsewhere reconciled into it as one change, updates pending until
// posted, and kept to the store. A port of `src/app/core/team/doc.test.ts`, case for case, but for its last
// (`applyTextDiff` itself), which is the core's to test (native/src/crdt.rs) and test/team/crdt_test.dart's. The
// store as files is this port's own.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';

import 'support.dart';

void main() {
  final skip = coreSkip;
  late GhostCore core;
  late Crdt crdt;

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await openCore();
    crdt = Crdt(core.invoke);
  });

  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  test('is seeded from the note\'s words with the whole of them pending, kept, and read back', () async {
    final store = MemoryDocs();
    var docs = TeamDocs(crdt: crdt, store: store);
    expect(await docs.doc('n1'), isNull);
    final doc = (await docs.doc('n1', seedWords: '# Roadmap\n- ship'))!;
    expect(doc.words, '# Roadmap\n- ship');
    expect(await doc.pending(), hasLength(1));
    await doc.flush();
    await docs.forget();
    docs = TeamDocs(crdt: crdt, store: store);
    final again = (await docs.doc('n1'))!;
    expect(again.words, '# Roadmap\n- ship');
    expect(await again.pending(), hasLength(1));
    expect([(await store.read('n1'))!.seq, (await store.read('n1'))!.snapshotSeq], [0, 0]);
    // Posted: nothing pending, and the store says so after the flush.
    await again.posted(1);
    await again.flush();
    expect((await store.read('n1'))!.pending, isEmpty);
    await docs.forget();
  }, skip: skip);

  test('a write that failed is told to the one who asked, and does not stop the writes after it', () async {
    final store = _FailsOnce();
    final docs = TeamDocs(crdt: crdt, store: store);
    final doc = (await docs.doc('n1', seedWords: 'a'))!;
    await doc.flush();
    await doc.posted(1);
    store.failNext = true;
    await expectLater(doc.flush(), throwsA(isA<FileSystemException>()));
    // The disk had room again: what was not kept is kept now.
    expect((await store.read('n1'))!.pending, hasLength(1));
    await doc.flush();
    expect((await store.read('n1'))!.pending, isEmpty);
    await docs.forget();
  }, skip: skip);

  test('reconciles words written elsewhere as one change the team can merge with', () async {
    final docs = TeamDocs(crdt: crdt, store: MemoryDocs());
    final doc = (await docs.doc('n1', seedWords: 'a\nb\nc'))!;
    await doc.posted(1);
    String? heard;
    doc.onWords((words) => heard = words);
    expect(await doc.reconcile('a\nB\nc\nd'), isTrue);
    expect(doc.words, 'a\nB\nc\nd');
    expect(heard, 'a\nB\nc\nd');
    expect(await doc.pending(), hasLength(1));
    expect(await doc.reconcile('a\nB\nc\nd'), isFalse);
    // The change was one transaction in the middle: another device's edit at the end merges, nothing lost.
    final other = await crdt.open(state: await doc.snapshot());
    final theirs = await other.reconcile('a\nB\nc\nd\ne');
    expect(await doc.applyRemote([theirs.update!], 7), 'a\nB\nc\nd\ne');
    expect(doc.seq, 7);
    // A remote update is not pending.
    expect(await doc.pending(), hasLength(1));
    await other.close();
    await docs.forget();
  }, skip: skip);

  test('is adopted from the organization\'s row over whatever the device holds, and dropped with the note', () async {
    final store = MemoryDocs();
    final docs = TeamDocs(crdt: crdt, store: store);
    final theirs = await crdt.open(words: 'from the team');
    final adopted = await docs.adopt('n2', await theirs.snapshot(), 12);
    expect([adopted.seq, adopted.snapshotSeq], [12, 12]);
    expect(adopted.words, 'from the team');
    expect(await adopted.pending(), isEmpty);
    expect(docs.held(), ['n2']);
    expect([(await store.read('n2'))!.seq, (await store.read('n2'))!.snapshotSeq], [12, 12]);
    // Adopted again, later: merged, not doubled.
    await theirs.reconcile('from the team, again');
    final again = await docs.adopt('n2', await theirs.snapshot(), 20);
    expect(identical(again, adopted), isTrue);
    expect(again.words, 'from the team, again');
    expect(again.seq, 20);
    await docs.drop('n2');
    expect(docs.held(), isEmpty);
    expect(await store.read('n2'), isNull);
    await theirs.close();
  }, skip: skip);

  test('an editor\'s own changes are pending like any other, and a change rests a moment before it is kept', () async {
    final store = MemoryDocs();
    final docs = TeamDocs(crdt: crdt, store: store, rest: const Duration(milliseconds: 20));
    final doc = (await docs.doc('n3', seedWords: 'hello'))!;
    final typed = await doc.edit([const CrdtEdit(5, insert: ' there')]);
    expect(typed.changed, isTrue);
    expect(doc.words, 'hello there');
    expect(await doc.pending(), hasLength(2));
    // Nothing was flushed by hand: the rest does it. Waited for, not slept for: a busy Mac is only slower.
    final until = DateTime.now().add(const Duration(seconds: 20));
    while ((await store.read('n3'))?.pending.length != 2 && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final kept = (await store.read('n3'))!;
    expect(kept.pending, hasLength(2));
    final again = await crdt.open(state: kept.state);
    expect(await again.words(), 'hello there');
    await again.close();
    await docs.forget();
  }, skip: skip);

  test('documents kept as files in a folder of the app\'s come back whole, and one cut short is no document', () async {
    final folder = await Directory.systemTemp.createTemp('ghost-team-docs');
    addTearDown(() => folder.delete(recursive: true));
    final store = FileDocs.forAccount(folder.path, 7);
    expect(store.folder.path, endsWith('${Platform.pathSeparator}team${Platform.pathSeparator}7'));
    var docs = TeamDocs(crdt: crdt, store: store);
    final doc = (await docs.doc('n1', seedWords: 'kept on the phone 😀'))!;
    doc.seq = 4;
    doc.snapshotSeq = 3;
    await doc.flush();
    expect(File('${store.folder.path}/n1.json').existsSync(), isTrue);
    expect(File('${store.folder.path}/n1.json.new').existsSync(), isFalse);
    await docs.forget();
    docs = TeamDocs(crdt: crdt, store: FileDocs.forAccount(folder.path, 7));
    final again = (await docs.doc('n1'))!;
    expect(again.words, 'kept on the phone 😀');
    expect([again.seq, again.snapshotSeq], [4, 3]);
    expect(await again.pending(), hasLength(1));
    await docs.forget();
    // Another account's folder holds nothing of this one's; a name that could leave the folder is no document.
    expect(await FileDocs.forAccount(folder.path, 8).read('n1'), isNull);
    expect(await store.read('../7/n1'), isNull);
    File('${store.folder.path}/n1.json').writeAsStringSync('{"v":1,"state":"AAEC","se');
    expect(await store.read('n1'), isNull);
    await store.remove('n1');
    await store.remove('n1');
    expect(File('${store.folder.path}/n1.json').existsSync(), isFalse);
    await store.clear();
    expect(store.folder.existsSync(), isFalse);
  }, skip: skip);
}

/// A store whose next write fails once, as a full disk does.
class _FailsOnce extends MemoryDocs {
  bool failNext = false;

  @override
  Future<void> write(String noteId, TeamDocRecord record) async {
    if (failNext) {
      failNext = false;
      throw const FileSystemException('No space left on device');
    }
    return super.write(noteId, record);
  }
}
