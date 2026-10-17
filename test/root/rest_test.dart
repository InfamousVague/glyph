import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor_widget.dart' show Editor;
import 'package:ghost_md/editor/media/clip_refs.dart' show Clip;
import 'package:ghost_md/editor/media/clips.dart' show clipPlayer, tapeSource;
import 'package:ghost_md/academy/academy_screen.dart';
import 'package:ghost_md/account/api.dart' show FetchRequest;
import 'package:ghost_md/core/book.dart' show isGuideBook;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/link_preview.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/guide/guide.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/guide/guide_state.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/plugins/link_marks.dart';
import 'package:ghost_md/plugins/marks.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart' show ContextBand;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/note_desk.dart';
import 'package:ghost_md/root/plugin_ground.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';
import 'package:ghost_md/tapes/note_tape.dart';
import 'package:ghost_md/tapes/player.dart' show TapePlayer;
import 'package:ghost_md/tapes/transcript_words.dart';

import '../support/render.dart';
import '../tapes/fake_player.dart';

/// Stage 9's pieces in the app put together (lib/root): the Academy through the shell, the titles of linked pages,
/// Developer's benches, and the plugins put on the phone.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late List<String> asked;

  Future<SampleLibrary> open(WidgetTester tester, {bool previews = false, GuideController? guide, TapePlayer? tapePlayer, TapePlayer? clipPlayer}) async {
    final library = SampleLibrary.seeded();
    asked = [];
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: MemoryStored(),
        guide: guide,
        tapePlayer: tapePlayer,
        clipPlayer: clipPlayer,
        previewFetch: previews
            ? (url) async {
                asked.add(url);
                return LinkPreview(url: url, title: 'An example', site: 'Example');
              }
            : null,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  group('the Academy', () {
    testWidgets('takes the whole window from Settings, and its arrow goes home', (tester) async {
      await open(tester);
      tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onAcademy!();
      await settle(tester);
      expect(shellOf(tester).screen, isA<ScreenAcademy>());
      expect(find.byType(AcademyScreen), findsOneWidget);
      expect(tester.widget<SettingsSheet>(find.byType(SettingsSheet)).open, isFalse);
      tester.widget<AcademyScreen>(find.byType(AcademyScreen)).onDone();
      await settle(tester);
      expect(shellOf(tester).screen, isA<ScreenList>());
      await close(tester);
    });

    testWidgets('sends its contents\' cheat sheet to Settings at that page', (tester) async {
      await open(tester);
      shellOf(tester).show(const Screen.academy());
      await settle(tester);
      tester.widget<AcademyScreen>(find.byType(AcademyScreen)).onCheatSheet();
      await settle(tester);
      final sheet = tester.widget<SettingsSheet>(find.byType(SettingsSheet));
      expect(sheet.open, isTrue);
      expect(sheet.toPage?.id, 'cheatsheet');
      expect(shellOf(tester).screen, isA<ScreenList>());
      tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onClose();
      await settle(tester, 3);
      await close(tester);
    });
  });

  group('the walkthrough', () {
    testWidgets('is up on a first launch, closes for good, and comes back from Settings', (tester) async {
      useStored(MemoryStored());
      addTearDown(() => useStored(MemoryStored()));
      final guide = GuideController();
      expect(guide.open, isTrue);
      await open(tester, guide: guide);
      expect(find.byType(Guide), findsOneWidget);
      tester.widget<Guide>(find.byType(Guide)).onClose();
      await settle(tester, 3);
      expect(find.byType(Guide), findsNothing);
      expect(GuideController().open, isFalse, reason: 'seen: it does not open by itself again');
      tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onGuide!();
      await settle(tester, 3);
      expect(find.byType(Guide), findsOneWidget);
      // Its last page's other way out is the Academy.
      tester.widget<Guide>(find.byType(Guide)).onAcademy();
      await settle(tester);
      expect(find.byType(Guide), findsNothing);
      expect(shellOf(tester).screen, isA<ScreenAcademy>());
      await close(tester);
    });

    testWidgets('is not there in an app that was given none', (tester) async {
      await open(tester);
      expect(find.byType(Guide), findsNothing);
      expect(tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onGuide, isNull);
      await close(tester);
    });
  });

  group('the guide as a notebook', () {
    testWidgets('is added once from Settings and opened, and a second press opens the first', (tester) async {
      final library = await open(tester);
      final before = library.value.length;
      await tester.runAsync(() async {
        tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onGuideBook!();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester);
      final book = library.noteOf(shellOf(tester).shown!)!;
      expect(isGuideBook(book), isTrue);
      final after = library.value.length;
      expect(after, greaterThan(before + 1), reason: 'its chapters and its index');
      shellOf(tester).backToList();
      await settle(tester, 2);
      await tester.runAsync(() async {
        tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onGuideBook!();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester);
      expect(library.value.length, after);
      expect(shellOf(tester).shown, book.id);
      await close(tester);
    });
  });

  group('the plugins in a note', () {
    testWidgets('have their place at its top, and the note\'s More sheet behind its press', (tester) async {
      final library = await open(tester);
      shellOf(tester).openNote(library.value.firstWhere((note) => noteTitle(note.body) == 'Packing').id);
      await settle(tester);
      expect(find.byType(NoteScreen), findsOneWidget);
      expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).seams.head, isNotNull);
      expect(find.byType(LinkMarks, skipOffstage: false), findsOneWidget);
      expect(tester.widget<LinkMarks>(find.byType(LinkMarks, skipOffstage: false)).onPress, isNotNull);
      await close(tester);
    });
  });

  group('a spoken note', () {
    /// Packing, given a recording of four seconds and its two phrases.
    Future<Note> tapedIn(WidgetTester tester, SampleLibrary library, {String more = ''}) async {
      final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
      final taped = Note(
        id: note.id,
        body: note.body + more,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        source: NoteSource.capture,
        recordingMs: 4000,
        segments: const [Segment(text: 'Bring the long lens', startMs: 0, endMs: 2000), Segment(text: 'and the tripod', startMs: 2000, endMs: 4000)],
        revision: note.revision,
      );
      await tester.runAsync(() => library.apply(taped));
      await settle(tester, 2);
      return library.noteOf(note.id)!;
    }

    testWidgets('wears its tape at its top where there is a player to play it, and no phrases while the tape is still', (tester) async {
      final player = FakeTapePlayer(lengths: const {});
      final library = await open(tester, tapePlayer: player);
      final taped = await tapedIn(tester, library);
      shellOf(tester).openNote(taped.id);
      await settle(tester);
      expect(find.byType(NoteTape, skipOffstage: false), findsOneWidget);
      expect(find.byType(TranscriptWords, skipOffstage: false), findsNothing);
      expect(player.calls, isEmpty, reason: 'a tape nobody plays asks the phone for nothing');
      // A note that was not spoken has none.
      shellOf(tester).openNote(library.value.firstWhere((note) => noteTitle(note.body) == 'Launch week').id);
      await settle(tester);
      expect(find.byType(NoteTape, skipOffstage: false), findsNothing);
      await close(tester);
    });

    testWidgets('plays a voice memo left in its words on the memos\' own player, a stretch of its own recording', (tester) async {
      final player = FakeTapePlayer(lengths: const {}), memos = FakeTapePlayer(lengths: const {});
      final library = await open(tester, tapePlayer: player, clipPlayer: memos);
      final taped = await tapedIn(tester, library);
      shellOf(tester).openNote(taped.id);
      await settle(tester);
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      expect(view.state.facet(tapeSource).src, taped.id, reason: 'the editor is told whose recording its memos are stretches of');
      final clips = view.state.facet(clipPlayer)!;
      // The fake has no such recording to load: the press fails, having asked for this note's.
      await tester.runAsync(() => clips.play(taped.id, const Clip(startMs: 1000, endMs: 3000)).then<void>((_) {}, onError: (Object _) {}));
      expect(memos.calls, ['load ${taped.id}']);
      expect(player.calls, isEmpty, reason: 'the tape\'s player is not the memos\'');
      expect(clips.playing, isNull);
      // A note that was not spoken has no tape for a memo to be a stretch of.
      shellOf(tester).openNote(library.value.firstWhere((note) => noteTitle(note.body) == 'Launch week').id);
      await settle(tester);
      expect(tester.state<NoteScreenState>(find.byType(NoteScreen)).view!.state.facet(tapeSource).src, isNull);
      await close(tester);
    });

    // docs/PARITY.md, Differs 8. NoteScreen.tsx: `shown = tape.length && tape.playing ? 'transcript' : 'raw'`. Playing
    // takes the screen for the transcript, under a tape that stays; the note waits hidden under it, and is back
    // where it was left when the tape stops.
    testWidgets('while its tape plays the transcript has the page and the words wait hidden; stopped, the note is back, at its bookmark as when it opens', (tester) async {
      final lengths = <String, int>{};
      final player = FakeTapePlayer(lengths: lengths);
      final library = await open(tester, tapePlayer: player);
      final taped = await tapedIn(tester, library, more: [for (var i = 0; i < 80; i++) '\n\nline $i of a note long enough to scroll${i == 40 ? ' §§' : ''}'].join());
      lengths[taped.id] = 4000;
      shellOf(tester).openNote(taped.id);
      await settle(tester);
      final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
      ScrollPosition page() => Scrollable.of(tester.element(find.byType(Editor, skipOffstage: false))).position;
      expect(find.byType(Editor), findsOneWidget);
      expect(find.byType(TranscriptWords, skipOffstage: false), findsNothing, reason: 'the phrases are not listed under the note');
      // The note opened at its bookmark, far down; it is brought back up to its tape.
      final marked = page().pixels;
      expect(marked, greaterThan(400));
      page().jumpTo(30);
      await settle(tester, 8);

      await tester.tap(find.bySemanticsLabel('Play the recording'));
      await settle(tester, 2);
      expect(find.byType(TranscriptWords), findsOneWidget);
      expect(find.text('Bring the long lens'), findsOneWidget);
      expect(find.byType(NoteTape), findsOneWidget, reason: 'the tape stays over the transcript');
      expect(find.byType(Editor), findsNothing, reason: 'the words wait hidden');
      expect(find.byType(Editor, skipOffstage: false), findsOneWidget, reason: 'and are still there');
      expect(page().pixels, 0, reason: 'the page holds still under the transcript');
      expect(page().physics, isA<NeverScrollableScrollPhysics>());
      // The transcript fills the page under the tape, and scrolls inside itself.
      final words = tester.getRect(find.byType(TranscriptWords));
      expect(words.top, greaterThanOrEqualTo(tester.getRect(find.byType(NoteTape)).bottom - 0.5));
      expect(words.bottom, inInclusiveRange(800, 844), reason: 'down to the foot of the page, less the phone\'s own inset');
      // What the page offers only over the words is not offered over the transcript.
      expect(screen.view!.hasFocus, isFalse);
      // A phrase tapped takes the tape there.
      await tester.tap(find.text('and the tripod'));
      await tester.pump();
      expect(player.calls, containsAllInOrder(<String>['load ${taped.id}', 'play', 'seek 2000']));

      await tester.tap(find.bySemanticsLabel('Pause the recording'));
      await settle(tester, 8);
      expect(find.byType(TranscriptWords, skipOffstage: false), findsNothing);
      expect(find.byType(Editor), findsOneWidget);
      // `useNotePlace(..., shown === 'raw' && !at)` begins again as the words return: a bookmark wins, as at an opening.
      expect(page().pixels, closeTo(marked, 2), reason: 'the note is back at its bookmark');
      expect(page().physics, isNot(isA<NeverScrollableScrollPhysics>()));
      await close(tester);
    });

    // docs/PARITY.md, Differs 17. The page made an `<audio>` for a memo beside the tape's own (editor/clips.ts:91;
    // tapes/useTape.ts), so a memo played never moved the tape: Play afterwards went on from where the tape was.
    testWidgets('a voice memo played leaves the tape\'s playhead alone: Play afterwards starts where the tape was, not where the memo stopped', (tester) async {
      // The fakes are told the recording's length once the note has its id.
      final lengths = <String, int>{};
      final tape = FakeTapePlayer(lengths: lengths), clip = FakeTapePlayer(lengths: lengths);
      final library = await open(tester, tapePlayer: tape, clipPlayer: clip);
      final taped = await tapedIn(tester, library);
      lengths[taped.id] = 4000;
      shellOf(tester).openNote(taped.id);
      await settle(tester);
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      final clips = view.state.facet(clipPlayer)!;
      // The memo plays its stretch, 1.0 s to 3.0 s, and stops at its end.
      await clips.play(taped.id, const Clip(startMs: 1000, endMs: 3000));
      await tester.pump(const Duration(milliseconds: 2100));
      expect(clips.playing, isNull);
      expect(clip.calls, ['load ${taped.id}', 'seek 1000', 'play', 'pause']);
      expect(clip.position.value, 3000);
      expect(tape.calls, isEmpty, reason: 'the memo took nothing from the tape');
      // Play on the tape: from its own start.
      await tester.tap(find.bySemanticsLabel('Play the recording'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tape.calls, ['load ${taped.id}', 'play']);
      expect(tape.position.value, lessThan(1000), reason: 'not where the memo stopped');
      // And a memo pressed while the tape plays sounds over it: the tape goes on.
      await clips.play(taped.id, const Clip(startMs: 1000, endMs: 3000));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tape.playing.value, isTrue);
      expect(clip.playing.value, isTrue);
      clips.stop();
      await tester.tap(find.bySemanticsLabel('Pause the recording'));
      await tester.pump();
      await close(tester);
    });

    testWidgets('draws no tape in an app with no player', (tester) async {
      final library = await open(tester);
      final taped = await tapedIn(tester, library);
      shellOf(tester).openNote(taped.id);
      await settle(tester);
      expect(find.byType(NoteTape, skipOffstage: false), findsNothing);
      await close(tester);
    });
  });

  group('a linked page\'s title', () {
    testWidgets('is asked for a note\'s links only with Link previews on and nothing kept to the phone', (tester) async {
      await open(tester, previews: true);
      shellOf(tester).openNote(SampleLibrary.seeded().value.first.id);
      await settle(tester);
      final previewer = tester.widget<NoteDesk>(find.byType(NoteDesk)).world.previewer!;
      expect(previewer, isA<KeptLinkPreviews>());
      preferences.value = preferences.value.copyWith(localOnly: true);
      previewer.wantPreview('https://example.com/a');
      await settle(tester, 2);
      expect(asked, isEmpty, reason: 'nothing leaves the phone');
      preferences.value = preferences.value.copyWith(localOnly: false, linkPreviews: false);
      previewer.wantPreview('https://example.com/a');
      await settle(tester, 2);
      expect(asked, isEmpty, reason: 'Link previews is off');
      preferences.value = preferences.value.copyWith(linkPreviews: true);
      previewer.wantPreview('https://example.com/a');
      await settle(tester, 2);
      expect(asked, ['https://example.com/a']);
      expect(previewer.previewFor('https://example.com/a')?.title, 'An example');
      await close(tester);
    });

    testWidgets('is asked of nowhere in a build given no reader', (tester) async {
      await open(tester);
      shellOf(tester).openNote(SampleLibrary.seeded().value.first.id);
      await settle(tester);
      final previewer = tester.widget<NoteDesk>(find.byType(NoteDesk)).world.previewer!;
      previewer.wantPreview('https://example.com/a');
      await settle(tester, 2);
      expect(previewer.previewFor('https://example.com/a'), isNull);
      await close(tester);
    });
  });

  group('Developer\'s benches', () {
    testWidgets('can be pressed', (tester) async {
      await open(tester);
      final features = tester.widget<SettingsSheet>(find.byType(SettingsSheet)).features;
      expect(features.onSmokeBench, isNotNull);
      expect(features.onPlayScene, isNotNull);
      // Without the whole core, the three pages over it say what a build without them says.
      expect((features.libraryFolder, features.backup, features.export), (null, null, null));
      await close(tester);
    });
  });

  group('the plugins on the phone', () {
    tearDown(() {
      usePlugins(createRegistry(const []));
      usePluginGround(PluginGround());
    });

    // Unwired 16 (docs/PARITY.md): the band's send row was built nowhere, so a list item could be sent to a plugin
    // only by its swipe or the quiet word (editor/NoteScreen.tsx:1465 `send={itemSend(note.id, editing)}`).
    testWidgets('give the press-and-hold band its send row where one takes the note\'s items, and none where none does', (tester) async {
      final library = await open(tester);
      final packing = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
      final ran = <String>[];
      usePlugins(createRegistry([
        GlyphPlugin(
          manifest: const PluginManifest(id: 'testboard', name: 'Testboard', description: 'Stands in.', version: '1', author: 'test', standard: true, permissions: [PluginPermission(Permission.notes, 'Sends items.')], storage: []),
          icon: 'square-kanban',
          itemAction: ItemAction(id: 'send', label: 'Send to Testboard', busyLabel: 'Sending…', available: (noteId) => noteId == packing.id, run: (text, editing) async => ran.add('${editing.noteId}: $text')),
        ),
      ], store: MemorySwitches()));
      shellOf(tester).openNote(packing.id);
      await settle(tester);
      final send = tester.widget<ContextBand>(find.byType(ContextBand)).send;
      expect(send?.label, 'Send to Testboard');
      await tester.runAsync(() async => send!.run('Passports'));
      expect(ran, ['${packing.id}: Passports']);
      // A note no plugin takes the items of has no such row.
      shellOf(tester).openNote(library.value.firstWhere((note) => noteTitle(note.body) == 'Launch week').id);
      await settle(tester);
      expect(tester.widget<ContextBand>(find.byType(ContextBand)).send, isNull);
      await close(tester);
    });

    test('are the ones that ship, over the ground they are given', () {
      final ground = PluginGround();
      final registry = installPlugins(ground: ground, prefs: PreferencesStore());
      expect(identical(pluginGround, ground), isTrue);
      expect(identical(plugins, registry), isTrue);
      expect(registry.all().map((plugin) => plugin.manifest.id), ['notion', 'github', 'marks', 'claude', 'slack', 'place-reminders', 'calendar', 'contacts', 'rich-embeds', 'todoist', 'things']);
    });

    test('give a note\'s editor, its band and its + their formattings: the switched-on plugins\', read as each is made', () {
      // With nothing ever put in the registry (a note built without the app's launch), the app's own marks.
      expect(identical(noteFormats(), marks), isTrue);
      expect(bandFormats().map((format) => format.name), marks.map((mark) => mark.name));

      final registry = installPlugins(ground: PluginGround(), prefs: PreferencesStore());
      expect(noteFormats().map((format) => format.name), marks.map((mark) => mark.name));
      // Each under its own icon, and Wave under the waves the set now answers to.
      final wave = bandFormats().firstWhere((format) => format.name == 'Wave');
      expect(identical(wave.icon, Lucide.all['waves']), isTrue);
      expect(plusEffects().map((effect) => effect.name), [for (final mark in marks) if (mark.look is EffectLook) mark.name]);

      // Ghost.md's own marks switched off: the next note's editor parses none, and neither list offers one.
      registry.setEnabled('marks', false);
      expect(noteFormats(), isEmpty);
      expect(bandFormats(), isEmpty);
      expect(plusEffects(), isEmpty);
      registry.setEnabled('marks', true);
      expect(noteFormats(), hasLength(marks.length));
    });

    test('never ask the real service from a build that is not a release', () async {
      final fetch = pluginFetcher(debug: true);
      for (final url in ['https://ghostmarkdown.com/api/x', 'https://attack.fm/glyph/api/x', 'https://www.ghostmarkdown.com/']) {
        await expectLater(fetch(FetchRequest(method: 'GET', url: Uri.parse(url))), throwsStateError, reason: url);
      }
    });
  });
}
