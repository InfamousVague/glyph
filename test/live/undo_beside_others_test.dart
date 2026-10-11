// Undo in a live note, beside another member's writing (docs/PARITY.md, Differs 26): this app held to Ghost.md
// itself, step for step.
//
// Ghost.md swaps CodeMirror's history for Yjs's own in a live note (editor/liveBinding.ts: `new Y.UndoManager(
// session.text)`, handed to y-codemirror's `yCollab`, with `yUndoManagerKeymap`), which takes back this person's
// own letters by what they are in the document. So does this app now: while an editor is bound its undo is the
// document's (lib/live/editor_binding.dart; yrs's `UndoManager` in native/src/crdt.rs), and a note that is not live
// keeps the editor's history.
//
// Nothing the page does is written down here. Every case is done twice, a step at a time: to the page's own editor
// and document (tool/yjs_undo.mjs: CodeMirror under jsdom, bound by the web app's `bindLive`, Yjs 13 and
// y-codemirror as it ships them) and to this app's (the app's editor and input layer, the binding, a team note's
// document in the real core), and after every step every member's words are the page's, letter for letter, in
// the editor and in the document, with what can be taken back and put in again (test/live/undo_support.dart). The
// words each case expects are there to say what the case is about; that they are also Yjs's is the test.
//
// - The cases an editor's own history got wrong, which is what Differs 26 was: a run this person deleted, or
//   typing they took back, put back at a place another member has written at since. Yjs puts it where its letters
//   stood, before, among or after the other's; a history that knows the run only by where it was hears the same
//   "X at 3" in each.
// - What the page's undo is besides: typing less than half a second apart is one step, an undo ends the step, the
//   selection goes back to where it stood before the step, the keys are y-codemirror's, the steps go when the note
//   is left, what was typed before the note went live cannot be taken back in it, and words that reach the note
//   without the editor are no step.
// - Three hundred interleavings of two members' typing, deleting, undoing and redoing, each hearing the other
//   late and in pieces, drawn from a seed, and each run twice, with the first member's client id the lower and the
//   higher; and at the end of each, Yjs reads what this app wrote and this app reads what Yjs wrote.
// - WHERE THE TWO DIFFER, three cases, each done to both sides with both answers written down, so that whoever
//   closes one sees it here: words that reach a note while its editor is bound; letters of two steps deleted
//   together and put back twice; a run put back after another member wrote into its place. Each is yrs 0.26 not
//   being Yjs, said at `Undo` in native/src/crdt.rs. A longer look at the drawn scenarios meets the last two:
//   of 2,000, each run both ways, 7 runs part from the page (GHOST_UNDO_SCENARIOS=2000: scenarios 438, 696 and
//   1424 either way, 328 one way), none of them among the three hundred here.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/input/keymap.dart';

import 'support.dart';
import 'undo_support.dart';

void main() {
  // A caret put back is scrolled to, which asks for a frame.
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = coreSkip ?? pageSkip;
  late GhostCore core;
  late Page page;
  late Both both;

  setUpAll(() async {
    if (skip != null) return;
    core = await openCore();
    page = await Page.start();
    both = Both(page, core);
  });
  tearDownAll(() async {
    if (skip != null) return;
    await both.close();
    await page.close();
    await core.close();
  });

  /// Matt with the note open and sam beside him, both bound, each holding the same words.
  Future<void> two(String words) async {
    both
      ..carets = true
      ..clock = 1000;
    await both.open('matt', words);
    await both.join('sam', 'matt');
    await both.bind('matt');
    await both.bind('sam');
  }

  test('the page is the web app\'s own: Yjs 13 behind y-codemirror', () {
    expect(page.hello['versions'], containsPair('yjs', startsWith('13.')));
    expect(page.hello['versions'], containsPair('y-codemirror.next', isNotEmpty));
  }, skip: skip);

  group('typing taken back beside another member\'s writing', () {
    test('their letter inside the run I typed stays, and my run goes', () async {
      await two('0123456789');
      await both.type('matt', 5, 'abc');
      await both.deliver('matt', 'sam');
      await both.type('sam', 6, 'X');
      await both.deliver('sam', 'matt');
      expect(both.words('matt'), '01234aXbc56789');
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), '01234X56789');
      await both.readEachOther('matt');
    }, skip: skip);

    test('their letter at the end of the run I typed, written at the same moment, stays', () async {
      await two('0123456789');
      await both.type('matt', 5, 'abc');
      await both.type('sam', 5, 'X');
      await both.everyone();
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), '01234X56789');
      await both.readEachOther('matt');
    }, skip: skip);

    test('a letter of mine they deleted is not deleted twice, and comes back with a redo of mine only if it was mine to put back', () async {
      await two('0123456789');
      await both.type('matt', 5, 'abc');
      await both.deliver('matt', 'sam');
      await both.type('sam', 6, '', remove: 1);
      await both.deliver('sam', 'matt');
      expect(both.words('matt'), '01234ac56789');
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), '0123456789');
      await both.redo('matt');
      await both.readEachOther('matt');
    }, skip: skip);

    test('a word I replaced comes back, and what they added to it stays', () async {
      await two('the cat sat');
      await both.type('matt', 4, 'dog', remove: 3);
      await both.deliver('matt', 'sam');
      await both.type('sam', 7, 's');
      await both.deliver('sam', 'matt');
      expect(both.words('matt'), 'the dogs sat');
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), 'the cats sat');
      await both.readEachOther('matt');
    }, skip: skip);
  });

  group('a run put back where another member has written since (what Differs 26 was)', () {
    // What the editor heard was the same in all four: my run gone, then X where it was. Its own history put the
    // run back whole after the letter every time (012X3456789).
    test('written once they had heard of my deleting: the run comes back before the letter', () async {
      await two('0123456789');
      await both.type('matt', 3, '', remove: 3);
      await both.deliver('matt', 'sam');
      await both.type('sam', 3, 'X');
      await both.deliver('sam', 'matt');
      expect(both.words('matt'), '012X6789');
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), '012345X6789');
      await both.redo('matt');
      expect(both.words('matt'), '012X6789');
      await both.readEachOther('matt');
    }, skip: skip);

    for (final (at, where, expected) in [(3, 'between 2 and 3: the letter is before the run', '012X3456789'), (4, 'between 3 and 4: the letter is inside the run', '0123X456789'), (6, 'between 5 and 6: the letter is after the run', '012345X6789')]) {
      test('written at the same moment $where', () async {
        await two('0123456789');
        await both.type('matt', 3, '', remove: 3);
        await both.type('sam', at, 'X');
        await both.everyone();
        expect(both.words('matt'), '012X6789');
        await both.undo('matt', after: 2000);
        expect(both.words('matt'), expected);
        expect(both.words('sam'), '012X6789', reason: 'sam has not heard of it yet');
        await both.readEachOther('matt');
        expect(both.words('sam'), expected);
      }, skip: skip);
    }

    test('typing I took back and put in again goes before what they wrote there meanwhile', () async {
      await two('0123456789');
      await both.type('matt', 5, 'abc');
      await both.undo('matt', after: 2000);
      await both.everyone();
      await both.type('sam', 5, 'X');
      await both.deliver('sam', 'matt');
      expect(both.words('matt'), '01234X56789');
      await both.redo('matt');
      expect(both.words('matt'), '01234abcX56789');
      await both.readEachOther('matt');
    }, skip: skip);

    test('both take back at once what each did to the same words, and both put it in again', () async {
      await two('one two three');
      await both.type('matt', 4, '', remove: 4);
      await both.type('sam', 7, ' and a half');
      await both.everyone();
      await both.undo('matt', after: 2000);
      await both.undo('sam');
      await both.everyone();
      expect(both.words('matt'), 'one two three');
      await both.redo('sam');
      await both.redo('matt');
      await both.readEachOther('matt');
    }, skip: skip);
  });

  group('the page\'s undo, besides', () {
    test('keys less than half a second apart are one step, a key half a second after the last begins another, and an undo ends the step', () async {
      await two('Buy');
      await both.type('matt', 3, ' ');
      await both.type('matt', 4, 'm', after: 200);
      await both.type('matt', 5, 'i', after: 499);
      await both.type('matt', 6, 'l', after: 500);
      await both.type('matt', 7, 'k', after: 100);
      expect(both.words('matt'), 'Buy milk');
      await both.undo('matt', after: 100);
      expect(both.words('matt'), 'Buy mi');
      // Typed at once after an undo: its own step, however soon.
      await both.type('matt', 6, 'nt', after: 10);
      await both.type('matt', 8, 's', after: 10);
      await both.undo('matt', after: 10);
      expect(both.words('matt'), 'Buy mi');
      await both.undo('matt');
      expect(both.words('matt'), 'Buy');
      expect(both.seen('matt').canUndo, isFalse);
      await both.undo('matt');
      await both.redo('matt');
      expect(both.words('matt'), 'Buy mi');
      await both.redo('matt');
      expect(both.words('matt'), 'Buy mints');
      // A key now ends what could be put in again.
      await both.undo('matt');
      await both.type('matt', 6, 'x', after: 2000);
      expect(both.seen('matt').canRedo, isFalse);
      await both.redo('matt');
      expect(both.words('matt'), 'Buy mix');
      await both.readEachOther('matt');
    }, skip: skip);

    test('the selection goes back to where it stood before the step, and a redo to where it stood when the step was taken back', () async {
      await two('one two three four');
      await both.select('matt', 4, 7);
      await both.type('matt', 4, 'TWO', remove: 3);
      await both.select('matt', 18);
      await both.type('matt', 18, '!', after: 2000);
      // sam writes before all of it: every place moves along.
      await both.type('sam', 0, '>> ');
      await both.deliver('sam', 'matt');
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), '>> one TWO three four');
      expect((both.seen('matt').anchor, both.seen('matt').head), (21, 21));
      await both.undo('matt');
      expect(both.words('matt'), '>> one two three four');
      expect((both.seen('matt').anchor, both.seen('matt').head), (7, 10), reason: 'the word that was selected when it was typed over');
      await both.redo('matt');
      expect((both.seen('matt').anchor, both.seen('matt').head), (21, 21));
      await both.redo('matt');
      expect(both.words('matt'), '>> one TWO three four!');
      await both.readEachOther('matt');
    }, skip: skip);

    test('the keys are y-codemirror\'s (Mod-z, Mod-y, Mod-Shift-z), the keyboard\'s own undo is the document\'s too, and no key undoes a selection', () async {
      await two('abc');
      await both.type('matt', 3, 'd');
      await both.type('matt', 4, 'e', after: 2000);
      await both.undo('matt', after: 2000, by: 'key');
      await both.undo('matt', by: 'input');
      expect(both.words('matt'), 'abc');
      await both.redo('matt', by: 'shift');
      await both.redo('matt', by: 'input');
      expect(both.words('matt'), 'abcde');
      await both.undo('matt', by: 'key');
      await both.redo('matt', by: 'key');
      expect(both.words('matt'), 'abcde');
      // The slot holds y-codemirror's three keys while the note is live, and CodeMirror's five when it is not.
      final view = both.members['matt']!.view;
      Future<bool> pageTakes(String key) async => (await page.ask({'do': 'key', 'who': 'matt', 'key': key}))['taken'] as bool;
      expect((await pageTakes('u'), runKey(view, 'Ctrl-u')), (false, false), reason: 'historyKeymap\'s undoSelection is not in a live note\'s slot');
      await both.unbind('matt');
      expect((await pageTakes('u'), runKey(view, 'Ctrl-u')), (true, true), reason: 'and is in the slot of a note on its own');
      await both.readEachOther('matt');
    }, skip: skip);

    test('the steps go when the note is left, the editor\'s own history is back with nothing in it, and bound again there is nothing to take back', () async {
      await two('Buy');
      await both.type('matt', 3, ' milk');
      expect(both.seen('matt').canUndo, isTrue);
      await both.unbind('matt');
      expect(both.seen('matt').canUndo, isFalse);
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), 'Buy milk');
      expect(undoDepth(both.members['matt']!.view.state), 0);
      // On its own it undoes with its own history, and the document hears nothing of it.
      await both.type('matt', 8, ' and eggs', after: 2000);
      expect(both.seen('matt').canUndo, isTrue);
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), 'Buy milk');
      await both.redo('matt');
      expect(both.words('matt'), 'Buy milk and eggs');
      expect(both.seen('matt').text, 'Buy milk');
      // Bound again: brought to the document's words, which cannot be taken back, and nothing before it can.
      await both.bind('matt');
      expect(both.words('matt'), 'Buy milk');
      expect((both.seen('matt').canUndo, both.seen('matt').canRedo), (false, false));
      await both.undo('matt', after: 2000);
      await both.redo('matt');
      expect(both.words('matt'), 'Buy milk');
      await both.type('matt', 8, '!', after: 2000);
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), 'Buy milk');
      await both.readEachOther('matt');
    }, skip: skip);

    test('words that reach the note without the editor are no step of its undo: brought in before the editor is bound, as the app brings them, they stay through every undo', () async {
      both
        ..carets = true
        ..clock = 1000;
      await both.open('matt', '- eggs');
      await both.join('sam', 'matt');
      await both.bind('sam');
      // open.dart: what the note holds is reconciled into the document, and then the editor is bound.
      await both.reconcile('matt', '- eggs\n- bread (from the phone)');
      await both.bind('matt');
      expect(both.seen('matt').canUndo, isFalse);
      await both.type('matt', 6, '\n- milk');
      await both.type('matt', 13, ' (oat)', after: 2000);
      await both.undo('matt', after: 2000);
      await both.undo('matt');
      await both.undo('matt');
      expect(both.words('matt'), '- eggs\n- bread (from the phone)');
      await both.redo('matt');
      await both.readEachOther('matt');
    }, skip: skip);

    test('WHERE THE TWO DIFFER: words that reach a note WHILE its editor is bound. The page keeps the steps made before them; this app lets them go', () async {
      // yrs 0.26 cannot take back a step that such words fell inside (native/src/crdt.rs, `Undo`: the step's
      // letters are then two runs of one block, which it cuts wrongly), so the steps are let go when the words
      // arrive. Nothing in the app does this to a bound note: a pass leaves its words alone while it is being
      // edited (TeamDoc.reconcileKept). Each side is asked on its own here, since they part.
      await two('- eggs');
      await both.type('matt', 6, '\n- milk');
      final matt = both.members['matt']!;
      const arrived = '- eggs\n- milk\n- bread (from the phone)';
      Future<Map<String, Object?>> onPage(Map<String, Object?> command) => page.ask({...command, 'who': 'matt'});
      // The page: no step of its own, and the step before it is still there to take back.
      expect((await onPage({'do': 'reconcile', 'words': arrived}))['undo'], 1);
      await onPage({'do': 'type', 'at': 13, 'insert': ' (oat)', 'now': 5000});
      expect((await onPage({'do': 'undo', 'now': 9000}))['words'], arrived);
      expect((await onPage({'do': 'undo', 'now': 9000}))['words'], '- eggs\n- bread (from the phone)');
      // This app: no step of its own either, and nothing before it can be taken back; what is typed after it can.
      await matt.doc.reconcile(arrived);
      await matt.quiet();
      expect((matt.seen.words, matt.seen.canUndo), (arrived, false));
      both.clock = 5000;
      matt.view.dispatch(TransactionSpec(changes: const Change(from: 13, to: 13, insert: ' (oat)'), selection: EditorSelection.single(19), userEvent: 'input.type'));
      await matt.quiet();
      expect(matt.seen.canUndo, isTrue);
      both.clock = 9000;
      expect(runKey(matt.view, 'Ctrl-z'), isTrue);
      await matt.quiet();
      expect((matt.seen.words, matt.seen.canUndo), (arrived, false));
      expect(runKey(matt.view, 'Ctrl-z'), isTrue);
      await matt.quiet();
      expect(matt.seen.words, arrived, reason: 'the milk stays: its step went when the words arrived');
      // Either way sam, told everything, holds what matt holds.
      final sam = both.members['sam']!;
      await sam.doc.applyRemote(matt.outbox['sam']!);
      await sam.quiet();
      expect(sam.seen.words, arrived);
    }, skip: skip);

    test('WHERE THE TWO DIFFER: letters of two steps deleted together and put back twice. The page then takes back the later step alone; this app takes a letter of the earlier one with it', () async {
      // yrs 0.26 follows a block put in again without its offset (native/src/crdt.rs, `Undo`): `JKL`, deleted in
      // one go, is put back as one block; deleted and put back again, the step that typed `KL` is followed to the
      // head of the newest copy, and the `J` before it goes too. The letter is this person's own, the next undo
      // would have taken it, a redo puts it back and every member holds the same words; it is not the page's
      // answer. native/patches/yrs-0.26.0-undo.patch is what makes it the page's.
      await two('');
      await both.type('sam', 0, 'IJ');
      await both.type('sam', 2, 'KL', after: 2000);
      await both.type('sam', 1, '', remove: 3, after: 2000);
      await both.undo('sam', after: 2000);
      await both.redo('sam');
      await both.undo('sam');
      expect(both.words('sam'), 'IJKL');
      // Each side on its own from here, since they part.
      final sam = both.members['sam']!;
      expect((await page.ask({'do': 'undo', 'who': 'sam', 'now': both.clock}))['words'], 'IJ');
      expect(runKey(sam.view, 'Ctrl-z'), isTrue);
      await sam.quiet();
      expect(sam.seen.words, 'I', reason: 'yrs follows `KL` to the head of the copy of `JKL`; were this `IJ`, the difference is gone and this case is the page\'s');
      // The next undo leaves both with nothing, and matt, told everything, holds what sam holds.
      expect((await page.ask({'do': 'undo', 'who': 'sam', 'now': both.clock}))['words'], '');
      expect(runKey(sam.view, 'Ctrl-z'), isTrue);
      await sam.quiet();
      expect(sam.seen.words, '');
      final matt = both.members['matt']!;
      await matt.doc.applyRemote(sam.outbox['matt']!);
      await matt.quiet();
      expect(matt.seen.words, '');
    }, skip: skip);

    test('WHERE THE TWO DIFFER: a run put back by an undo after another member wrote into its place while it was deleted. The page puts it back as one run; this app as two, and a letter written at its start at that moment can land between them', () async {
      // Yjs joins a block again when what cut it turns out not to lie inside it; yrs 0.26 leaves it cut
      // (store.rs `materialize`, its own "todo"). A deleted run so cut is put back by an undo as two runs, and a
      // letter another member wrote before its first letter, not having heard of any of it, is ordered against
      // the first of them alone. Every letter of both is there and every member holds the same words; the order
      // is not the page's. Met once in four thousand drawn scenarios.
      both
        ..carets = false
        ..clock = 1000
        ..nextClient = 1000
        ..clientStep = 1;
      await both.open('matt', '');
      await both.join('sam', 'matt');
      await both.bind('matt');
      await both.bind('sam');
      await both.type('matt', 0, 'ab');
      await both.deliver('matt', 'sam');
      await both.type('matt', 2, 'cd', after: 100);
      // Sam, who has `ab` alone, writes after it: after `cd` once matt hears, whose letters come first.
      await both.type('sam', 2, 'X');
      await both.type('matt', 0, '', remove: 4, after: 2000);
      await both.deliver('sam', 'matt');
      expect(both.words('matt'), 'X');
      // And before it, still not having heard of `cd` or of its going.
      await both.type('sam', 0, 'K');
      await both.undo('matt', after: 2000);
      expect(both.words('matt'), 'abcdX');
      // Each side on its own from here.
      final matt = both.members['matt']!, sam = both.members['sam']!;
      final theirs = await page.ask({'do': 'deliver', 'from': 'sam', 'to': 'matt'});
      expect(theirs['words'], 'abcdKX');
      await matt.doc.applyRemote(sam.outbox['matt']!);
      await matt.quiet();
      expect(matt.seen.words, 'abKcdX', reason: 'were this `abcdKX`, the difference is gone and this case is the page\'s');
      // Sam, told everything, holds what matt holds, on the page and here.
      expect((await page.ask({'do': 'deliver', 'from': 'matt', 'to': 'sam'}))['words'], 'abcdKX');
      await sam.doc.applyRemote(matt.outbox['sam']!);
      await sam.quiet();
      expect(sam.seen.words, 'abKcdX');
      both.nextClient = null;
    }, skip: skip);

    test('a character of two code units is taken back and put in again whole', () async {
      await two('a😀b');
      await both.type('matt', 3, '👻é');
      await both.type('sam', 0, '🎃');
      await both.type('matt', 1, '', remove: 2, after: 2000);
      await both.everyone();
      await both.undo('matt', after: 2000);
      await both.undo('matt');
      expect(both.words('matt'), '🎃a😀b');
      await both.redo('matt');
      await both.redo('matt');
      expect(both.words('matt'), '🎃a👻éb');
      await both.readEachOther('matt');
    }, skip: skip);
  });

  group('two members, anything in any order', () {
    // Each scenario: a note two members have open, forty steps drawn from the seed. A step is one member typing,
    // deleting or typing over at a place of their own choosing, taking a step back or putting one in again (by a
    // key or by the keyboard's own undo), hearing some of what the other has made so far, or now and then words
    // reaching their note without the editor, or their leaving the note and opening it again; with a little time
    // or a lot before it. After every step both members are the page's.
    // GHOST_UNDO_SCENARIOS=5000 draws more of them, for a longer look.
    final scenarios = int.tryParse(Platform.environment['GHOST_UNDO_SCENARIOS'] ?? '') ?? 300;
    final steps = int.tryParse(Platform.environment['GHOST_UNDO_STEPS'] ?? '') ?? 40;
    // GHOST_UNDO_PLAIN=1 types no character of two code units, and begins no note with one.
    final plain = Platform.environment['GHOST_UNDO_PLAIN'] != null;
    const gaps = [0, 0, 0, 40, 150, 300, 499, 500, 501, 900, 3000];
    const letters = 'abcdefghijklmnopqrstuvwxyz';

    Future<void> scenario(int seed, {required bool firstLower}) async {
      final random = Random(seed);
      both
        // Whose letter comes first, of two written at one spot at one moment, is by the members' client ids: each
        // scenario is run with the first member's the lower, and again with it the higher.
        ..nextClient = firstLower ? 1000 : 2000
        ..clientStep = firstLower ? 1 : -1
        // GHOST_UNDO_CARETS=1 holds every member's selection to the page's after every step too.
        ..carets = Platform.environment['GHOST_UNDO_CARETS'] != null
        ..clock = 1000 + seed;
      await both.open('matt', ['', 'Hello world', '0123456789', plain ? '# Plan\n\n- one\n- two\n' : '# Plan\n\n- one\n- two 😀\n'][seed % 4]);
      await both.join('sam', 'matt');
      await both.bind('matt');
      await both.bind('sam');
      var typed = 0;
      // Who last took a step back, and has done nothing since: the one whose redo will find something.
      String? undid;
      for (var step = 0; step < steps; step += 1) {
        // Half the time after an undo, the same member goes on: another undo, or a redo.
        final again = undid != null && random.nextBool() ? undid : null;
        final who = again ?? (random.nextBool() ? 'matt' : 'sam'), other = who == 'matt' ? 'sam' : 'matt';
        final words = both.words(who);
        // A place between two characters, never inside one.
        int place() {
          var at = random.nextInt(words.length + 1);
          if (at > 0 && at < words.length && (words.codeUnitAt(at) & 0xFC00) == 0xDC00) at -= 1;
          return at;
        }

        String fresh() {
          final count = 1 + random.nextInt(3);
          final out = StringBuffer();
          for (var i = 0; i < count; i += 1) {
            final roll = random.nextInt(20);
            final letter = letters[(typed += 1) % letters.length];
            out.write(roll == 0 && !plain ? '👻' : roll == 1 ? '\n' : who == 'matt' ? letter : letter.toUpperCase());
          }
          return out.toString();
        }

        final gap = gaps[random.nextInt(gaps.length)];
        final roll = again != null ? 54 + random.nextInt(26) : random.nextInt(100);
        final bound = both.members[who]!.bound;
        if (roll >= 54 && roll < 80) {
          undid = who;
        } else if (undid == who) {
          undid = null;
        }
        if (roll < 4 && words.isNotEmpty) {
          // The caret put somewhere, or a stretch selected: where the next step's selection will be put back to.
          final from = place(), to = random.nextBool() ? from : place();
          await both.select(who, from, to);
        } else if (roll < 34) {
          await both.type(who, place(), fresh(), after: gap);
        } else if (roll < 48 && words.isNotEmpty) {
          final from = place();
          var to = (from + 1 + random.nextInt(4)).clamp(0, words.length);
          if (to < words.length && (words.codeUnitAt(to) & 0xFC00) == 0xDC00) to += 1;
          if (to > from) await both.type(who, from, '', remove: to - from, after: gap);
        } else if (roll < 54 && words.isNotEmpty) {
          final from = place();
          var to = (from + 1 + random.nextInt(3)).clamp(0, words.length);
          if (to < words.length && (words.codeUnitAt(to) & 0xFC00) == 0xDC00) to += 1;
          final insert = fresh(), gone = words.substring(from, to);
          // Typed over: this app writes only what differs, the page the whole of it, so one that shares its first
          // or last letter with what it replaces is another change to the document, and not this test's.
          if (to > from && gone.runes.first != insert.runes.first && gone.runes.last != insert.runes.last) await both.type(who, from, insert, remove: to - from, after: gap);
        } else if (roll < 70) {
          await both.undo(who, after: gap, by: random.nextInt(4) == 0 ? 'input' : 'key');
        } else if (roll < 80) {
          await both.redo(who, after: gap, by: const ['key', 'shift', 'input'][random.nextInt(3)]);
        } else if (roll < 96) {
          final waiting = both.members[other]!.outbox[who]!.length;
          if (waiting > 0) await both.deliver(other, who, 1 + random.nextInt(waiting));
        } else if (roll < 98) {
          // Words that reach the note without the editor, as the app brings them in: before the editor is bound.
          if (bound) {
            await both.unbind(who);
            await both.deliver(other, who);
            final held = both.seen(who).text;
            await both.reconcile(who, random.nextBool() ? '$held\n+' : '+ $held');
            await both.bind(who);
            await both.select(who, 0);
          }
        } else {
          // Left and opened again. The page writes the whole note into its editor as it binds one that differs,
          // which leaves its caret at the start; this app writes the stretch that differs, and its caret stays.
          // The caret is put at the start in both, so what follows begins alike.
          if (bound) {
            await both.unbind(who);
            await both.deliver(other, who);
            await both.bind(who);
            await both.select(who, 0);
          }
        }
      }
      await both.readEachOther('matt');
    }

    // GHOST_UNDO_SEED=438 runs that one scenario alone.
    final only = int.tryParse(Platform.environment['GHOST_UNDO_SEED'] ?? '');
    if (only != null) {
      test('scenario $only alone', () async {
        await scenario(only, firstLower: true);
        await scenario(only, firstLower: false);
      }, skip: skip);
      return;
    }
    for (var from = 1; from <= scenarios; from += 50) {
      test('scenarios $from to ${from + 49}', () async {
        // Every one is run, whichever fail: a longer look counts them.
        final failed = <String>[];
        for (var seed = from; seed < from + 50 && seed <= scenarios; seed += 1) {
          for (final firstLower in [true, false]) {
            try {
              await scenario(seed, firstLower: firstLower);
            } on TestFailure catch (failure) {
              failed.add('scenario $seed of $steps steps, the first member\'s client id the ${firstLower ? 'lower' : 'higher'}: ${failure.message}');
            }
          }
        }
        if (failed.isNotEmpty) fail('${failed.length} of them parted from the page:\n${failed.join('\n\n')}');
      }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));
    }

    test('and they were not idle: most undos and redos among them changed the words', () {
      // ignore: avoid_print
      print('held to the page, step for step: ${both.held}');
      final undos = both.held['undo'] ?? 0, changed = both.held['undo that changed the words'] ?? 0;
      expect(undos, greaterThan(scenarios * 3));
      expect(changed, greaterThan(undos ~/ 3));
      expect(both.held['redo that changed the words'] ?? 0, greaterThan(scenarios ~/ 2));
      expect(both.held['deliver'] ?? 0, greaterThan(scenarios * 3));
    }, skip: skip);
  });
}
