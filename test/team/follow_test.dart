// Following a team page (lib/team/follow.dart, lib/team/follow_edit.dart; docs/TEAMSPACES.md, "Follow a doc and
// Updates"; Matt, 2026-10-31: "`watchers:` (the tickets' key) works on any page … Auto-follow when you create, edit or
// are mentioned on a team page"): Follow and Following write `watchers:`; a page's first edit here follows it, once,
// in the same change (one Undo takes both back), never on the keystrokes after, never again after an unfollow, never
// on a ticket or a personal note; a mention follows once per mention; the ledger is the device's, per account.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_watchers.dart' show watchersOf;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/team/follow.dart';
import 'package:ghost_md/team/follow_edit.dart';
import 'package:ghost_md/team/follow_row.dart';

import '../support/render.dart';

void main() {
  group('Follow and Following', () {
    test('write the account into the page’s watchers, and take it off, the rest of the page as it was', () {
      const page = '# Roadmap\n\nQ4.\n';
      final on = withFollowing(page, 'matt', true);
      expect(follows(on, 'matt'), isTrue);
      expect(follows(on, 'Matt'), isTrue, reason: 'a person in any case');
      expect(on, endsWith(page));
      expect(withFollowing(on, 'matt', true), on, reason: 'following twice is following once');
      final both = withFollowing(on, 'sam', true);
      expect(followersOf(both), ['matt', 'sam']);
      final off = withFollowing(both, 'MATT', false);
      expect(followersOf(off), ['sam']);
      expect(follows(off, 'matt'), isFalse);
    });

    testWidgets('the More sheet’s row says Follow or Following, and flips as it is pressed', (tester) async {
      final told = <bool>[];
      await pumpApp(tester, home: Column(mainAxisSize: MainAxisSize.min, children: [FollowSection(following: false, onToggle: told.add)]));
      expect(find.text('Follow'), findsOneWidget);
      await tester.tap(find.byKey(FollowSection.rowKey));
      await tester.pump();
      expect(told, [true]);
      expect(find.text('Following'), findsOneWidget);
      await tester.tap(find.byKey(FollowSection.rowKey));
      await tester.pump();
      expect(told, [true, false]);
      expect(find.text('Follow'), findsOneWidget);
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('auto-follow', () {
    test('a team page’s first edit follows it once; the edits after, and an edit after an unfollow, do not', () {
      final ledger = FollowLedger(MemoryStored());
      const page = '# Roadmap\n';
      final first = autoFollowEdit(noteId: 'n1', before: page, after: '${page}Q4\n', me: 'matt', teamPage: true, ledger: ledger);
      expect(first, isNotNull);
      expect(watchersOf(first!), ['matt']);
      expect(ledger.done('matt', editReason('n1')), isTrue);
      // Unfollowed by hand, then edited again: left as chosen.
      final unfollowed = withFollowing(first, 'matt', false);
      expect(autoFollowEdit(noteId: 'n1', before: unfollowed, after: '${unfollowed}more\n', me: 'matt', teamPage: true, ledger: ledger), isNull);
      // Another page is its own first edit; another account on the device is its own too.
      expect(autoFollowEdit(noteId: 'n2', before: page, after: '${page}x', me: 'matt', teamPage: true, ledger: ledger), isNotNull);
      expect(autoFollowEdit(noteId: 'n1', before: page, after: '${page}x', me: 'sam', teamPage: true, ledger: ledger), isNotNull);
    });

    test('a personal note, a ticket, no account, and a page already followed are not written', () {
      final ledger = FollowLedger(MemoryStored());
      const page = '# Roadmap\n';
      expect(autoFollowEdit(noteId: 'a', before: page, after: '${page}x', me: 'matt', teamPage: false, ledger: ledger), isNull);
      const ticket = '---\ntype: ticket\nid: GHO-1\n---\n# Bug\n';
      expect(autoFollowEdit(noteId: 'b', before: ticket, after: '${ticket}x', me: 'matt', teamPage: true, ledger: ledger), isNull, reason: 'a ticket keeps its own watchers’ rules');
      expect(autoFollowEdit(noteId: 'c', before: page, after: '${page}x', me: null, teamPage: true, ledger: ledger), isNull);
      final followed = withFollowing(page, 'matt', true);
      expect(autoFollowEdit(noteId: 'd', before: followed, after: '${followed}x', me: 'matt', teamPage: true, ledger: ledger), isNull);
      expect(ledger.done('matt', editReason('d')), isTrue, reason: 'counted all the same');
    });

    test('the ledger is kept in the device’s memory, per account', () {
      final memory = MemoryStored();
      FollowLedger(memory).mark('Matt', editReason('n1'));
      final again = FollowLedger(memory);
      expect(again.done('matt', editReason('n1')), isTrue);
      expect(again.done('sam', editReason('n1')), isFalse);
    });

    test('a mention follows once per mention', () {
      final ledger = FollowLedger(MemoryStored());
      expect(autoFollowMention(notificationId: 'm1', me: 'matt', ledger: ledger), isTrue);
      expect(autoFollowMention(notificationId: 'm1', me: 'matt', ledger: ledger), isFalse);
      expect(autoFollowMention(notificationId: 'm2', me: 'matt', ledger: ledger), isTrue, reason: 'a new mention is new');
      expect(autoFollowMention(notificationId: 'm3', me: null, ledger: ledger), isFalse);
    });
  });

  group('the editor follows a team page on its first edit', () {
    const page = '# Roadmap\n\nQ4.\n';
    late FollowLedger ledger;
    var team = true;
    EditorState start([String doc = page]) => EditorState.create(
          doc: doc,
          extensions: Extension.list(<Extension>[history(), followEdits(FollowHooks(noteId: 'n1', me: () => 'matt', teamPage: () => team, ledger: ledger))]),
        );
    setUp(() {
      ledger = FollowLedger(MemoryStored());
      team = true;
    });

    test('in the same change, which one Undo takes back whole; the keystrokes after write nothing more', () {
      var state = start();
      state = state.update(TransactionSpec(changes: ChangeSpec(from: page.length, insert: 'A'), selection: EditorSelection.single(page.length + 1), userEvent: 'input.type')).state;
      final written = state.doc.toString();
      expect(watchersOf(written), ['matt']);
      expect(written, endsWith('${page}A'));
      // The caret stays after what was typed, though the front matter came in above it.
      expect(state.selection.main.head, written.length);
      state = state.update(TransactionSpec(changes: ChangeSpec(from: state.doc.length, insert: 'B'), userEvent: 'input.type')).state;
      expect(state.doc.toString(), '${written}B', reason: 'the second keystroke is only itself');
      final target = StateCommandTarget(state, (tr) => state = tr.state);
      expect(undo(target), isTrue);
      expect(undo(target), isTrue);
      expect(state.doc.toString(), page);
    });

    test('another device’s change, Follow’s own step, an undo, a personal note: none of them follows', () {
      var state = start();
      state = state.update(TransactionSpec(changes: ChangeSpec(from: page.length, insert: 'x'), annotations: Transaction.remote.of(true))).state;
      expect(watchersOf(state.doc.toString()), isEmpty);
      final followed = followChange(state.doc.toString(), withFollowing(state.doc.toString(), 'matt', false));
      expect(followed, isNull, reason: 'nothing to take off');
      team = false;
      state = state.update(TransactionSpec(changes: ChangeSpec(from: state.doc.length, insert: 'y'), userEvent: 'input.type')).state;
      expect(watchersOf(state.doc.toString()), isEmpty);
      expect(ledger.done('matt', editReason('n1')), isFalse, reason: 'a personal note’s edit is not a team page’s first');
    });

    test('Follow’s step writes the least change, as `follow`', () {
      final spec = followChange(page, withFollowing(page, 'matt', true))!;
      var state = start();
      state = state.update(spec).state;
      expect(watchersOf(state.doc.toString()), ['matt']);
      expect(ledger.done('matt', editReason('n1')), isFalse, reason: 'Follow is not an edit');
    });
  });

}
