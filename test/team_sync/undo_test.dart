// An undo in a team's note is a change like any other (docs/PARITY.md, Differs 26): this is the code that syncs a
// team's notes, so what an undo does to the note's log, to the queue a restart reads back, and to a member who was
// away is held here, through the service in memory (test/support/fake_service.dart) with the REAL document
// (tool/build-native.sh host).
//
// The undo is the document's own while the note's editor is bound (lib/live/editor_binding.dart; yrs's
// `UndoManager` in native/src/crdt.rs), and it only ever ADDS to the document: the letters it takes back are
// deleted as a key would delete them, and a run it puts back is put in as new letters beside the old. So:
//
// - it is one more update at the end of the note's log, sealed like the rest, after the typing it takes back and
//   never in its place: nothing already on the log changes;
// - it waits in the document's queue like any change made here until a pass posts it, and through the app being
//   closed and opened;
// - a member who was away reads the typing and the undo off the log and holds the words; so does a device that
//   starts from nothing, and so does Yjs itself, given the row and the log;
// - the steps do not outlive the editor: after a restart there is nothing to take back, and what was taken back
//   stays taken back.
//
// What the undo answers, step for step beside another member, is test/live/undo_beside_others_test.dart's.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/input/input.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/live/editor_binding.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';

import '../feed/signed.dart' show apiOf, testAccount;
import '../live/undo_support.dart' show Page, pageSkip;
import '../support/fake_service.dart';
import 'support.dart';

void main() {
  // A caret put back is scrolled to, which asks for a frame.
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = coreSkip;
  late GhostCore core;
  late Crdt crdt;
  late FakeService service;
  late String orgId;
  late SealKey orgKey;
  final made = <TeamDevice>[];

  /// The time the documents' undo reads.
  var clock = 1000;

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await openCore();
    crdt = Crdt(core.invoke);
  });

  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  setUp(() async {
    if (!coreBuilt) return;
    service = await FakeService.start(seed: testAccount);
    final answer = await apiOf(service).callMap('POST', 'orgs', token: service.signedIn(), body: {'name': 'Ghost', 'hue': 'sea'});
    orgId = (answer['org'] as Map)['id'] as String;
    orgKey = await service.crypto.importSealKey(service.crypto.randomBytes(32));
  });

  tearDown(() async {
    for (final device in made) {
      await device.docs.forget();
    }
    made.clear();
  });

  TeamDevice device({TeamDocStore? store}) {
    final one = TeamDevice(crdt: crdt, api: apiOf(service), crypto: service.crypto, token: service.signedIn, orgId: orgId, orgKey: orgKey, store: store);
    made.add(one);
    return one;
  }

  /// The note open on [on]: its editor bound to its document, as the desk binds it (lib/live/open.dart), every
  /// update the document makes written down, and the note saved from the editor as the desk saves it.
  Future<({TeamDoc doc, EditorView view, LiveBinding binding, List<Uint8List> updates, Future<void> Function() quiet})> open(TeamDevice on, String id) async {
    final doc = (await on.docs.doc(id, seedWords: on.notes[id]!.body))!;
    await doc.reconcile(on.notes[id]!.body);
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc.words, extensions: Extension.list(<Extension>[editorInput(), liveBindingSlot()])))..setFocused(true);
    final binding = LiveBinding(view, doc, now: () => clock)..bind();
    final updates = <Uint8List>[];
    doc.onUpdate(updates.add);
    Future<void> quiet() async {
      for (var round = 0; round < 20; round += 1) {
        await doc.settled();
        await binding.undone();
        await Future<void>.delayed(Duration.zero);
      }
      // The desk saves the editor's words a moment after they change.
      on.write(id, view.state.doc.toString());
    }

    return (doc: doc, view: view, binding: binding, updates: updates, quiet: quiet);
  }

  /// A key, a while after the last: another step of the undo.
  Future<void> type(({TeamDoc doc, EditorView view, LiveBinding binding, List<Uint8List> updates, Future<void> Function() quiet}) note, int at, String insert, {int remove = 0}) async {
    clock += 2000;
    note.view.dispatch(TransactionSpec(changes: Change(from: at, to: at + remove, insert: insert), selection: EditorSelection.single(at + insert.length), userEvent: 'input.type'));
    await note.quiet();
  }

  Future<List<Uint8List>> logOf(String id) async => [for (final update in service.teamUpdates(orgId, id)) await service.crypto.openBytes(orgKey, fromBase64Url(update.blob), 'org:$orgId:note:$id:update')];

  test('an undo is one more update at the end of the note\'s log, after the typing it takes back; nothing on the log changes; a member who was away, a device from nothing and Yjs itself read both and hold the words', () async {
    final phone = device();
    phone.put('n1', 'Buy milk');
    await phone.sync();
    final mac = device();
    await mac.sync();
    expect(mac.notes['n1']!.body, 'Buy milk');
    final row = (await service.crypto.open(orgKey, service.teamNotes(orgId)['n1']!.blob!, 'org:$orgId:note:n1') as Map)['state'] as String;

    // Typed on the phone, and posted: one update on the log.
    final note = await open(phone, 'n1');
    await type(note, 8, ' and eggs');
    expect(note.updates, hasLength(1));
    await phone.sync();
    final first = service.teamUpdates(orgId, 'n1').toList();
    expect(first, hasLength(1));
    expect(await logOf('n1'), [note.updates[0]]);
    await mac.sync();
    expect(mac.notes['n1']!.body, 'Buy milk and eggs');

    // Taken back: a change made here like any other. It waits in the document's queue, as the update it is.
    expect(undoNote(note.view), isTrue);
    await note.quiet();
    expect(note.view.state.doc.toString(), 'Buy milk');
    expect(note.updates, hasLength(2));
    expect(await note.doc.pending(), [note.updates[1]]);
    expect(await crdt.lacks(await (await mac.docs.doc('n1'))!.crdt.stateVector(), await note.doc.crdt.stateVector()), isFalse, reason: 'an undo of typing writes no new letters: it deletes, as a key would');
    await phone.sync();
    expect(await note.doc.pending(), isEmpty);

    // On the log it is the second update, after the first, which is as it was: its seq, its bytes.
    final second = service.teamUpdates(orgId, 'n1').toList();
    expect(second, hasLength(2));
    expect((second[0].seq, second[0].blob), (first[0].seq, first[0].blob), reason: 'history is not rewritten');
    expect(second[1].seq, first[0].seq + 1);
    expect(await logOf('n1'), [note.updates[0], note.updates[1]]);

    // The member who was away reads it off the log, and a device with nothing reads the note whole.
    await mac.sync();
    expect(mac.notes['n1']!.body, 'Buy milk');
    final late_ = device();
    await late_.sync();
    expect(late_.notes['n1']!.body, 'Buy milk');

    // Put in again: a third update, of new letters this time, read the same way.
    expect(redoNote(note.view), isTrue);
    await note.quiet();
    expect(note.view.state.doc.toString(), 'Buy milk and eggs');
    expect(await note.doc.pending(), [note.updates[2]]);
    await phone.sync();
    expect(await logOf('n1'), note.updates);
    final third = service.teamUpdates(orgId, 'n1').toList();
    expect([for (final update in third.take(2)) (update.seq, update.blob)], [for (final update in second) (update.seq, update.blob)]);
    await mac.sync();
    await late_.sync();
    expect(mac.notes['n1']!.body, 'Buy milk and eggs');
    expect(late_.notes['n1']!.body, 'Buy milk and eggs');

    // And Yjs, given the row as it was first put and the log as the service holds it, reads the same words after
    // each: the web app's members are told nothing this app's are not.
    if (pageSkip == null) {
      final page = await Page.start();
      final log = [for (final update in await logOf('n1')) toBase64Url(update)];
      expect((await page.ask({'do': 'read', 'updates': [row, log[0]]}))['text'], 'Buy milk and eggs');
      expect((await page.ask({'do': 'read', 'updates': [row, log[0], log[1]]}))['text'], 'Buy milk');
      expect((await page.ask({'do': 'read', 'updates': [row, ...log]}))['text'], 'Buy milk and eggs');
      await page.close();
    }
    note.binding.unbind();
  }, skip: skip);

  test('an undo made with no service to post it to is kept with the document, comes back after the app is closed and opened, and is posted then; its steps do not come back', () async {
    final store = MemoryDocs();
    final phone = device(store: store);
    phone.put('n1', 'one two three');
    await phone.sync();
    final mac = device();
    await mac.sync();

    // Typed over a word and taken back, twice over, with nothing sent.
    final note = await open(phone, 'n1');
    await type(note, 4, 'TWO', remove: 3);
    await type(note, 13, ' four');
    expect(undoNote(note.view), isTrue);
    await note.quiet();
    expect(undoNote(note.view), isTrue);
    await note.quiet();
    expect(redoNote(note.view), isTrue);
    await note.quiet();
    expect(note.view.state.doc.toString(), 'one TWO three');
    expect(note.updates, hasLength(5));
    expect(await note.doc.pending(), note.updates);
    expect(service.teamUpdates(orgId, 'n1'), isEmpty);

    // Kept, and the app closed: the queue is in the store, in the order made.
    await note.doc.flush();
    note.binding.unbind();
    expect(store.held['n1']!.pending, note.updates);
    await phone.reopened();
    final again = (await phone.docs.doc('n1'))!;
    expect(again.words, 'one TWO three');
    expect(await again.pending(), note.updates);

    // Opened again: nothing to take back (the page's `Y.UndoManager` is its editor's and goes with it), and the
    // key changes nothing.
    final reopened = await open(phone, 'n1');
    expect((canUndoNote(reopened.view.state), canRedoNote(reopened.view.state)), (false, false));
    expect(undoNote(reopened.view), isTrue);
    await reopened.quiet();
    expect(reopened.view.state.doc.toString(), 'one TWO three');
    expect(reopened.updates, isEmpty);

    // The pass posts all five, in order, and the member who was away holds the words.
    await phone.sync();
    expect(await logOf('n1'), note.updates);
    expect(await again.pending(), isEmpty);
    await mac.sync();
    expect(mac.notes['n1']!.body, 'one TWO three');
    reopened.binding.unbind();
  }, skip: skip);

  test('two members take back at once what each wrote, each hearing the other only by the log: both hold the same words, and neither loses a letter of the other\'s', () async {
    final phone = device();
    phone.put('n1', '- eggs\n- milk\n');
    await phone.sync();
    final mac = device();
    await mac.sync();

    final a = await open(phone, 'n1'), b = await open(mac, 'n1');
    await type(a, 6, ' (six)');
    await type(a, 0, '# List\n');
    await type(b, 13, ' (oat)');
    await type(b, b.view.state.doc.length, '- bread\n');
    // Each takes back the last thing they did, before either has heard the other.
    undoNote(a.view);
    undoNote(b.view);
    await a.quiet();
    await b.quiet();
    expect(a.view.state.doc.toString(), '- eggs (six)\n- milk\n');
    expect(b.view.state.doc.toString(), '- eggs\n- milk (oat)\n');
    for (var pass = 0; pass < 3; pass += 1) {
      await phone.sync();
      await mac.sync();
      await a.quiet();
      await b.quiet();
    }
    expect(a.view.state.doc.toString(), '- eggs (six)\n- milk (oat)\n');
    expect(b.view.state.doc.toString(), a.view.state.doc.toString());
    expect(mac.notes['n1']!.body, phone.notes['n1']!.body);
    // And each puts theirs in again: the other's is still there.
    redoNote(a.view);
    redoNote(b.view);
    await a.quiet();
    await b.quiet();
    for (var pass = 0; pass < 3; pass += 1) {
      await phone.sync();
      await mac.sync();
      await a.quiet();
      await b.quiet();
    }
    expect(a.view.state.doc.toString(), '# List\n- eggs (six)\n- milk (oat)\n- bread\n');
    expect(b.view.state.doc.toString(), a.view.state.doc.toString());
    // Every update either made is on the log once, in the order each made them.
    final log = await logOf('n1');
    expect(log, hasLength(a.updates.length + b.updates.length));
    expect([for (final update in log) if (a.updates.any((mine) => _same(mine, update))) update], a.updates);
    expect([for (final update in log) if (b.updates.any((mine) => _same(mine, update))) update], b.updates);
    a.binding.unbind();
    b.binding.unbind();
  }, skip: skip);
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
