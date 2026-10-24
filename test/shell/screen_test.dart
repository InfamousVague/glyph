import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/shell/screen.dart';
import 'package:ghost_md/shell/top_bar.dart';
import 'package:ghost_md/shell/visible_notes.dart';
import 'package:ghost_md/shell/wide_screen.dart';

import '../core/make_note.dart';

/// `shell/screen.test.ts`, `shell/topBar.test.ts` and `shell/useVisibleNotes.test.tsx`, case for case, and the
/// window's shape as core/useWideScreen.ts asks it.
void main() {
  final note = Screen.note(makeNote('a'));

  group('the screens', () {
    test('makes each capture a fresh one, keyed by when it began, into a note only when it was that note’s', () {
      expect(ScreenCapture.fresh(true, now: 1000), const ScreenCapture(key: 1000, fromAssistant: true));
      expect(ScreenCapture.fresh(false, noteId: 'a', now: 2000), const ScreenCapture(key: 2000, fromAssistant: false, noteId: 'a'));
      // Where in the note, only with a note to be in.
      const lead = ('end', '**14:05** ');
      expect(ScreenCapture.fresh(false, noteId: 'a', placing: lead, now: 2000), const ScreenCapture(key: 2000, fromAssistant: false, noteId: 'a', placing: lead));
      expect(ScreenCapture.fresh(false, placing: lead, now: 2000), const ScreenCapture(key: 2000, fromAssistant: false));
      expect(ScreenCapture.fresh(false, now: 1).stop, 0);
      // Each press of the side key is a change.
      expect(ScreenCapture.fresh(false, now: 1).stopped().stop, 1);
      expect(ScreenMeeting.fresh('a', true, now: 5), const ScreenMeeting(noteId: 'a', fromAssistant: true, key: 5));
    });

    test('says which screens are places, and where on the trail each is', () {
      expect(const Screen.list().place, 'list');
      expect(const Screen.notes().place, 'notes');
      expect(note.place, 'note:a');
      expect(ScreenCapture.fresh(false).place, isNull);
      expect(const Screen.academy().place, isNull);
      // An organization (docs/TEAMS.md) is drawn in the pane with the tab row, and is not on the trail.
      expect(const Screen.organization('o').place, isNull);
      expect(const Screen.organization('o', page: OrganizationPage.log).place, isNull);
      expect(
        [
          const Screen.list(),
          const Screen.notes(),
          note,
          ScreenCapture.fresh(false),
          const Screen.academy(),
          const Screen.organization('o'),
          const Screen.organization('o', page: OrganizationPage.log),
        ].map((s) => s.isPlace),
        [true, true, true, false, false, true, true],
      );
    });

    test('names the note on screen, and only a note', () {
      expect(note.noteOnScreen, 'a');
      expect(ScreenCapture.fresh(false, noteId: 'a').noteOnScreen, isNull);
      expect(const Screen.list().noteOnScreen, isNull);
    });

    test('says which take the whole window with a microphone behind them', () {
      expect(ScreenCapture.fresh(false).isRecording, isTrue);
      expect(ScreenMeeting.fresh('a', false).isRecording, isTrue);
      expect([const Screen.list(), note, const Screen.academy()].map((s) => s.isRecording), everyElement(isFalse));
    });

    test('are named as the web names them, and tell one from another', () {
      expect(
        [const Screen.list(), const Screen.notes(), note, ScreenCapture.fresh(false), ScreenMeeting.fresh('a', false), const Screen.academy(), const Screen.organization('o')].map((s) => s.name),
        ['list', 'notes', 'note', 'capture', 'meeting', 'academy', 'organization'],
      );
      expect(const Screen.notes(tapes: true), isNot(const Screen.notes()));
      expect(const Screen.organization('o'), isNot(const Screen.organization('o', page: OrganizationPage.log)));
      // The same note opened at an item is another screen: the note lands on it.
      final same = makeNote('a');
      expect(Screen.note(same, at: '^friday'), isNot(Screen.note(same)));
      expect(Screen.note(same), Screen.note(same));
      expect((Screen.note(same) as ScreenNote).asked(const Keyed('tidy', 7)).ask, const Keyed('tidy', 7));
      expect(const Caret.end().atEnd, isTrue);
      expect(const Caret.at(0), isNot(const Caret.end()));
    });
  });

  group('the top bar’s styles', () {
    test('offers the four the preference knows, Classic first', () {
      expect(TopBarStyle.values.map((s) => s.id), ['classic', 'ledger', 'masthead', 'islands']);
      expect(TopBarStyle.values.map((s) => s.label), ['Classic', 'Ledger', 'Masthead', 'Islands']);
      // A Strip or a Thumb chosen before the cut reads as Classic.
      expect(TopBarStyle.parse('thumb'), TopBarStyle.classic);
      expect(TopBarStyle.parse('islands'), TopBarStyle.islands);
      expect(TopBarStyle.parse(null), TopBarStyle.classic);
    });

    test('is one line or two by the style and whether a note is open', () {
      expect([barRows(TopBarStyle.classic, 0), barRows(TopBarStyle.classic, 2)], [BarRows.on, BarRows.rows]);
      expect([barRows(TopBarStyle.masthead, 0), barRows(TopBarStyle.masthead, 1)], [BarRows.on, BarRows.rows]);
      expect([barRows(TopBarStyle.islands, 0), barRows(TopBarStyle.islands, 1)], [BarRows.on, BarRows.rows]);
      // The Ledger's row of tabs is always there, Home pinned in it.
      expect([barRows(TopBarStyle.ledger, 0), barRows(TopBarStyle.ledger, 3)], [BarRows.rows, BarRows.rows]);
      expect([BarRows.on.stamp, BarRows.rows.stamp], ['on', 'rows']);
    });
  });

  group('the notes a screen may show', () {
    final notes = [makeNote('a', body: '# Apples'), makeNote('b', body: '# Bread'), makeNote('c', body: '# Cheese')];

    test('are all of them with nothing held back or thrown away', () {
      final seen = visibleNotes(notes);
      expect(ids(seen.visible), ['a', 'b', 'c']);
      expect(seen.trashed, isEmpty);
      expect(seen.live, {'a', 'b', 'c'});
    });

    test('leave out a note a pending delete is holding back, from the trash folder too', () {
      var seen = visibleNotes(notes, hidden: {'b', 'c'}, trash: {'c': 1});
      expect(ids(seen.visible), ['a']);
      expect(seen.trashed, isEmpty);
      expect(seen.live, {'a'});
      seen = visibleNotes(notes, trash: {'c': 1});
      expect(ids(seen.visible), ['a', 'b']);
      expect(ids(seen.trashed), ['c']);
    });

    test('follow the trash as notes go into it and come back, the most recently thrown away first', () {
      var seen = visibleNotes(notes, trash: {'a': 1000, 'b': 2000});
      expect(ids(seen.visible), ['c']);
      expect(ids(seen.trashed), ['b', 'a']);
      expect(seen.live.contains('a'), isFalse);
      seen = visibleNotes(notes, trash: {'b': 2000});
      expect(ids(seen.visible), ['a', 'c']);
      expect(ids(seen.trashed), ['b']);
      expect(seen.live.contains('a'), isTrue);
    });
  });

  group('the window’s shape', () {
    test('holds two panes when it is wide and tall, or wide under a mouse', () {
      expect(splitFits(const Size(390, 844), mouse: false), isFalse);
      expect(splitFits(const Size(840, 900), mouse: false), isTrue);
      expect(splitFits(const Size(660, 600), mouse: false), isTrue);
      expect(splitFits(const Size(659, 900), mouse: false), isFalse);
      // A phone held in landscape is a strip: as wide as a small desktop window, with no room beside anything.
      expect(splitFits(const Size(844, 390), mouse: false), isFalse);
      // A short window under a mouse is one the person chose.
      expect(splitFits(const Size(844, 390), mouse: true), isTrue);
    });

    test('sizes its columns as the stylesheet does, and starts the sidebar hidden under a mouse and a finger alike', () {
      expect(simpleListColumn(704), 300);
      expect(simpleListColumn(1280), 360);
      expect(simpleListColumn(800), closeTo(336, 1e-9));
      expect(asideColumn(840), 240);
      expect(asideColumn(1280), closeTo(281.6, 1e-9));
      expect(asideColumn(2000), 320);
      // Matt, 2026-10-24: "just hide it by default".
      expect(sidebarShownAtFirst, isFalse);
      expect(wideScreen(const Size(600, 800)), isTrue);
      expect(wideScreen(const Size(599, 800)), isFalse);
    });
  });
}
