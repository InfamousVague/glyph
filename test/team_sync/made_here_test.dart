// Which changes to a team note's document were made on this device (lib/team/doc.dart `TeamDocs.onMade`), over the
// REAL CRDT in the Mac's core: a key pressed in its editor, words reconciled into it, an undo are told, with the words
// before and after; what another member's device sent never is. So a mention typed is told by the device that typed
// it (lib/mentions/mention_notices.dart; Matt, 2026-10-30: "add all 12"), and by no other.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/mentions/mention_notices.dart';
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

  test('a change made here is told, before and after; one from another device is not', () async {
    final told = <String>[];
    final mac = TeamDocs(crdt: crdt, store: MemoryDocs(), onMade: (id, before, after) => told.add('$id: "$before" -> "$after"'));
    final phone = TeamDocs(crdt: crdt, store: MemoryDocs(), onMade: (id, before, after) => told.add('phone $id'));
    final here = (await mac.doc('n1', seedWords: 'Plan'))!;
    expect(told, isEmpty, reason: 'a document seeded from the note is not a change typed');
    await here.reconcile('Plan\nAsk @sam');
    await here.edit(const [CrdtEdit(13, insert: ' now')]);
    expect(told, ['n1: "Plan" -> "Plan\nAsk @sam"', 'n1: "Plan\nAsk @sam" -> "Plan\nAsk @sam now"']);
    // The phone takes the Mac's updates: its words change, and nothing is told there.
    final there = await phone.adopt('n1', await here.snapshot(), 1);
    expect(there.words, 'Plan\nAsk @sam now');
    await there.applyRemote(await here.pending());
    expect(told.where((line) => line.startsWith('phone')), isEmpty);
    await mac.forget();
    await phone.forget();
  }, skip: skip);

  test('the mention typed on the Mac is owed by the Mac alone', () async {
    final macLedger = MentionLedger(kept: MemoryStored()), phoneLedger = MentionLedger(kept: MemoryStored());
    final mac = TeamDocs(crdt: crdt, store: MemoryDocs(), onMade: (id, before, after) => macLedger.made(7, 'o1', id, before, after));
    final phone = TeamDocs(crdt: crdt, store: MemoryDocs(), onMade: (id, before, after) => phoneLedger.made(7, 'o1', id, before, after));
    final here = (await mac.doc('n1', seedWords: '# Plan\n'))!;
    await here.reconcile('# Plan\nAsk @sam to look');
    final there = await phone.adopt('n1', await here.snapshot(), 1);
    expect(there.words, '# Plan\nAsk @sam to look');
    expect(macLedger.owedIn(7, 'o1').map((o) => '${o.handle}#${o.n}'), ['sam#1']);
    expect(phoneLedger.owedIn(7, 'o1'), isEmpty);
    // The phone types on the same line: its own change, but no mention it added.
    await there.edit(const [CrdtEdit(23, insert: ' today')]);
    expect(phoneLedger.owedIn(7, 'o1'), isEmpty);
    await mac.forget();
    await phone.forget();
  }, skip: skip);
}
