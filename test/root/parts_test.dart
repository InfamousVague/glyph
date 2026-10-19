// The root builds what changed, and not everything (lib/root/selected.dart, lib/root/ghost_root.dart): each part of
// what is on screen is built again when what it reads is another value.
//
// Before this the root was one builder over the notes, the workspaces, the trash, the preferences and the account,
// and every change to any of them, and every turn of a runner, built the home page, the open note and Settings
// again. The home page is still taken down under a note and made anew on the way back, as the web app's is
// (lib/shell/app_shell.dart): that is held here too, since for an afternoon it was kept alive there and came back
// scrolled, searched and with nothing arriving, which the page never does.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/banner.dart';
import 'package:ghost_md/aside/aside.dart' show asideContent;
import 'package:ghost_md/book/chapter_number.dart' show chapterOf;
import 'package:ghost_md/canvas/json_canvas.dart' show isCanvasBody;
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_parts.dart' show Arrive;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/notes/note_menu.dart' show NoteMenuHost;
import 'package:ghost_md/notes/notices.dart' show AcademyCard;
import 'package:ghost_md/root/note_desk.dart' show NoteDesk;
import 'package:ghost_md/shell/screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/selected.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/simple/simple_home.dart';

import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  group('a part', () {
    testWidgets('is built when what it selects is another value, and handed back as it was when it is not', (tester) async {
      final tick = RootTick();
      var a = 1, other = 0, built = 0;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Selected<(int,)>(
          listenable: tick,
          select: () => (a,),
          builder: (context, value) {
            built += 1;
            return Text('a ${value.$1}');
          },
        ),
      ));
      expect(built, 1);
      // Told of a change to something it does not read: nothing is built, and no frame is asked for.
      other += 1;
      tick.tell();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump();
      expect((built, other), (1, 1));
      a = 2;
      tick.tell();
      // Two tellings before the frame are one build.
      tick.tell();
      await tester.pump();
      expect(built, 2);
      expect(find.text('a 2'), findsOneWidget);
      // A value that changed and changed back before the frame is no build at all.
      a = 3;
      tick.tell();
      a = 2;
      tick.tell();
      await tester.pump();
      expect(built, 2);
      tick.dispose();
    });

    testWidgets('is built again when whatever holds it is, only if what it selects changed', (tester) async {
      final tick = RootTick();
      var a = 1, built = 0;
      Widget held() => Directionality(
            textDirection: TextDirection.ltr,
            child: Selected<int>(
              listenable: tick,
              select: () => a,
              builder: (context, value) {
                built += 1;
                return Text('a $value');
              },
            ),
          );
      await tester.pumpWidget(held());
      await tester.pumpWidget(held());
      expect(built, 1);
      a = 2;
      await tester.pumpWidget(held());
      expect(built, 2);
      tick.dispose();
    });

    testWidgets('is built again when something inherited its builder reads is another, whatever it selects', (tester) async {
      final tick = RootTick();
      var built = 0;
      Widget held(double width) => Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(size: Size(width, 600)),
              child: Selected<int>(
                listenable: tick,
                select: () => 1,
                builder: (context, value) {
                  built += 1;
                  return Text('${MediaQuery.sizeOf(context).width}');
                },
              ),
            ),
          );
      await tester.pumpWidget(held(400));
      await tester.pumpWidget(held(400));
      expect(built, 1);
      await tester.pumpWidget(held(900));
      expect(built, 2);
      expect(find.text('900.0'), findsOneWidget);
      tick.dispose();
    });
  });

  group('the root', () {
    Future<void> settle(WidgetTester tester, [int beats = 6]) async {
      for (var i = 0; i < beats; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<SampleLibrary> open(WidgetTester tester, {Preferences prefs = const Preferences(theme: 'light')}) async {
      final library = SampleLibrary.seeded();
      await pumpApp(
        tester,
        prefs: prefs,
        home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
      );
      await tester.pump(const Duration(milliseconds: 100));
      return library;
    }

    Future<void> close(WidgetTester tester) async {
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    }

    HomeScreen home(WidgetTester tester) => tester.widget<HomeScreen>(find.byType(HomeScreen, skipOffstage: false));

    testWidgets('lists the Academy card among home\'s notices in simple mode while it is due, and its cross puts it away (GHST-103)', (tester) async {
      useStored(MemoryStored());
      await open(tester, prefs: const Preferences(theme: 'light', experience: 'simple', experienceChosen: true));
      // Simple mode's home page is lib/simple/simple_home.dart since GHST-105; the notices are the same list.
      SimpleHome simple() => tester.widget<SimpleHome>(find.byType(SimpleHome, skipOffstage: false));
      expect(find.byType(HomeScreen), findsNothing);
      expect(simple().notices.whereType<AcademyCard>(), hasLength(1));
      expect(find.byKey(const ValueKey('academy-card')), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Not now'));
      await tester.pump();
      expect(academyBannerDue(), isFalse);
      expect(simple().notices.whereType<AcademyCard>(), isEmpty);
      await close(tester);
    });

    testWidgets('lists no Academy card in advanced mode', (tester) async {
      useStored(MemoryStored());
      await open(tester, prefs: const Preferences(theme: 'light', experience: 'advanced', experienceChosen: true));
      expect(home(tester).notices.whereType<AcademyCard>(), isEmpty);
      await close(tester);
    });

    testWidgets('builds the home page for what the home page shows, and not for a preference it does not read', (tester) async {
      final library = await open(tester);
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      final page = home(tester);
      final settings = tester.widget<SettingsSheet>(find.byType(SettingsSheet));
      // Choices no screen of notes is handed: the note's view, the model, a version kept.
      preferences.update((now) => now.copyWith(noteView: 'formatted'));
      preferences.update((now) => now.copyWith(versions: const {'n1': true}));
      await tester.pump();
      expect(identical(tester.widget<AppShell>(find.byType(AppShell)), shell), isTrue, reason: 'the shell is not built again');
      expect(identical(home(tester), page), isTrue, reason: 'nor the home page');
      expect(identical(tester.widget<SettingsSheet>(find.byType(SettingsSheet)), settings), isTrue, reason: 'nor Settings');
      // Its layout is one it reads.
      preferences.update((now) => now.copyWith(homeLayout: 'list', homeLayoutChosen: true));
      await tester.pump();
      expect(identical(home(tester), page), isFalse);
      expect(home(tester).layout.name, 'list');
      expect(identical(tester.widget<AppShell>(find.byType(AppShell)), shell), isTrue);
      // And so are the notes.
      final listed = home(tester);
      library.create('# A new one\n\nwords');
      await tester.pump();
      expect(identical(home(tester), listed), isFalse);
      expect(home(tester).notes.any((note) => note.body.startsWith('# A new one')), isTrue);
      await close(tester);
    });

    testWidgets('builds neither the shell nor the note\'s desk for the note\'s own save, and both for another note\'s', (tester) async {
      final library = await open(tester);
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      AppShell shellWidget() => tester.widget<AppShell>(find.byType(AppShell));
      NoteDesk desk() => tester.widget<NoteDesk>(find.byType(NoteDesk));
      // A note of plain words: no notebook, no page of one, no numbered chapter, so nothing stands beside it.
      final note = library.value.firstWhere((each) => each.body.trim().isNotEmpty && asideContent(library.value, each) == null && !isCanvasBody(each.body) && chapterOf(noteTitle(each.body)) == null);
      final other = library.value.firstWhere((each) => each.id != note.id && each.body.trim().isNotEmpty);
      shell.openNote(note.id);
      await settle(tester);
      final built = shellWidget();
      final desked = desk();
      // Saved, as its editor saves it a moment after the typing stops: its words are others, its title the same.
      var saved = await library.update(note.id, '${note.body}\n\nMore words.', note.revision);
      await tester.pump();
      saved = await library.update(note.id, '${saved.body}\n\nAnd more.', saved.revision);
      await tester.pump();
      expect(identical(shellWidget(), built), isTrue, reason: 'the shell draws nothing of the save');
      expect(identical(desk(), desked), isTrue, reason: 'nor does the screen the note was opened with');
      // And yet the shell is not behind: what its screens list, and what it opens by an id, is the note as saved.
      expect(shell.notes.firstWhere((each) => each.id == note.id).body, endsWith('And more.'));
      shell.openNote(note.id);
      expect((shell.screen as ScreenNote).note.body, endsWith('And more.'));
      await settle(tester, 2);
      final again = shellWidget();
      // Its first line changed: its tab's name is the shell's to draw.
      saved = await library.update(note.id, '# Another name altogether\n\n${saved.body}', saved.revision);
      await tester.pump();
      expect(identical(shellWidget(), again), isFalse, reason: 'a title is a tab\'s name');
      // Another note saved (a sync, a query's tick): the titles that are taken and the lists are other.
      final renamed = shellWidget();
      final before = desk();
      await library.update(other.id, '# Changed elsewhere\n\n${other.body}', other.revision);
      await tester.pump();
      expect(identical(shellWidget(), renamed), isFalse);
      expect(identical(desk(), before), isFalse);
      // Left, the home page lists the note as it was last saved.
      shell.backToList();
      await settle(tester);
      expect(home(tester).notes.firstWhere((each) => each.id == note.id).body, startsWith('# Another name altogether'));
      await close(tester);
    });

    testWidgets('a note\'s menu and the palette are made with the notes as they are when each opens', (tester) async {
      final library = await open(tester);
      final menu = tester.widget<NoteMenuHost>(find.byType(NoteMenuHost));
      final made = library.create('# Made a moment ago\n\nwords');
      await tester.pump();
      // Shut, the menu is not built again for a note made.
      expect(identical(tester.widget<NoteMenuHost>(find.byType(NoteMenuHost)), menu), isTrue);
      home(tester).onNoteMenu!(made.id, Offset.zero);
      await settle(tester, 4);
      expect(tester.widget<NoteMenuHost>(find.byType(NoteMenuHost)).notes.any((each) => each.id == made.id), isTrue);
      expect(find.text('Made a moment ago'), findsWidgets);
      await close(tester);
    });

    testWidgets('takes the home page down under a note and makes it anew on the way back, as the page does: at its top, its search empty, its rows arriving', (tester) async {
      final library = await open(tester);
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      final state = tester.state(find.byType(HomeScreen));
      // The page is searched and scrolled before it is left.
      await tester.enterText(find.byType(EditableText).first, 'pack');
      await settle(tester, 2);
      final scroller = find.descendant(of: find.byType(HomeScreen), matching: find.byType(Scrollable)).first;
      tester.state<ScrollableState>(scroller).position.jumpTo(40);
      await tester.pump();
      final note = library.value.firstWhere((each) => each.body.trim().isNotEmpty);
      shell.openNote(note.id);
      await settle(tester);
      expect(find.byType(NoteScreen), findsOneWidget);
      // Under the note there is no home page at all, on screen or off it (App.tsx: `noteScreen ?? … home`).
      expect(find.byType(HomeScreen, skipOffstage: false), findsNothing);
      library.create('# Made while away\n\nwords');
      await settle(tester, 2);
      shell.backToList();
      await tester.pump();
      // A page made anew: another state, nothing typed in its search, at its top, with the note made meanwhile.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.state(find.byType(HomeScreen)), isNot(same(state)));
      expect(tester.widget<EditableText>(find.byType(EditableText).first).controller.text, isEmpty);
      final back = find.descendant(of: find.byType(HomeScreen), matching: find.byType(Scrollable)).first;
      expect(tester.state<ScrollableState>(back).position.pixels, 0);
      expect(home(tester).notes.any((each) => each.body.startsWith('# Made while away')), isTrue);
      // And its cards and rows are arriving: the entrance of each is its own first frames (lib/home/home_parts.dart).
      expect(tester.widgetList<Opacity>(find.descendant(of: find.byType(Arrive), matching: find.byType(Opacity))).any((it) => it.opacity < 1), isTrue);
      await settle(tester, 12);
      expect(tester.widgetList<Opacity>(find.descendant(of: find.byType(Arrive), matching: find.byType(Opacity))).every((it) => it.opacity == 1), isTrue);
      // The seams the root hands the page are the functions they were.
      final first = home(tester);
      shell.openNote(note.id);
      await settle(tester);
      shell.backToList();
      await settle(tester);
      expect(identical(home(tester).headerEdge, first.headerEdge), isTrue);
      expect(identical(home(tester).dockHalo, first.dockHalo), isTrue);
      expect(identical(home(tester).ghost, first.ghost), isTrue);
      await close(tester);
    });
  });
}
