// The in-place marks (docs/ACTIVITY.md, In place; Matt, 2026-10-29): a banner's band where it will land, "Writing the
// summary…" at the summary's place with its words streaming in, each note's sync by its title in the lists, the icon
// view, the sidebar and the tabs, and a thin bar where a share's recording, a picture or a recording goes. Each on a
// phone and the Mac, Calm in ink, still under reduced motion, and shown in simple mode; read from the app's record of
// running work and the sync's marks, with fakes for the jobs and the sync state.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/activity/activity_look.dart';
import 'package:ghost_md/activity/activity_tray.dart' show JobBar;
import 'package:ghost_md/activity/banner_shimmer.dart';
import 'package:ghost_md/activity/sync_mark.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/ai/summary_writing.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/images.dart' show KeptPicture;
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/home/note_card.dart';
import 'package:ghost_md/note/note_banner.dart';
import 'package:ghost_md/notes/icon_browser.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/tabs/tab_parts.dart' show NoteTab;
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/sync/notes.dart';
import 'package:ghost_md/sync/sync_marks.dart';
import 'package:glacier/glacier.dart';

import '../notes/bar_support.dart';
import '../support/render.dart';

/// A small picture, as PNG bytes.
Future<Uint8List> png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 160, 90), Paint()..color = const Color(0xFF2A9D8F));
  final image = await recorder.endRecording().toImage(160, 90);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Note makeNote(String id, String body, {int updatedAt = 1}) => Note(id: id, body: body, createdAt: 0, updatedAt: updatedAt);

void main() {
  setUpAll(loadAppFonts);

  const phone = (name: 'phone', size: Size(390, 844));
  const mac = (name: 'mac', size: Size(1280, 800));

  late DateTime now;
  late Activity record;
  late NoteSyncMarks marks;
  setUp(() {
    now = DateTime(2026, 10, 29, 16, 20);
    record = Activity(clock: () => now, store: () => MemoryStored());
    useActivity(record);
    marks = NoteSyncMarks(clock: () => now)..syncing = () => true;
    useNoteSyncMarks(marks);
  });
  tearDown(() {
    useActivity(Activity());
    useNoteSyncMarks(NoteSyncMarks());
  });

  void stillTest(String description, Future<void> Function(WidgetTester tester) body) => testWidgets(description, (tester) async {
        await body(tester);
        debugDisableShadows = true;
      });

  void reducedMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  Tokens tokensAt(WidgetTester tester, Finder finder) => GlacierTheme.of(tester.element(finder));

  group('a banner being made', () {
    for (final window in [phone, mac]) {
      stillTest('is a band at the banner\'s shape where it will land, moving, in the images\' colour (${window.name})', (tester) async {
        await pumpApp(tester, size: window.size, home: const Align(alignment: Alignment.topCenter, child: NoteBannerView(name: null, store: null, making: true, prompt: 'n1')));
        await tester.pump(const Duration(milliseconds: 100));
        final band = tester.getSize(find.byKey(const ValueKey('banner-shimmer')));
        expect(band.height, closeTo(band.width / BannerLook.unread.shape < noteBannerMaxHeight ? band.width / BannerLook.unread.shape : noteBannerMaxHeight, 0.5), reason: 'the shape a banner is drawn at before it is read, no taller than a banner is');
        expect(band.width, closeTo(window.size.width - 2 * tokensAt(tester, find.byType(BannerShimmer)).len('app-gutter'), 0.5), reason: 'the page\'s width, as the banner is');
        expect(tester.state<BannerShimmerState>(find.byType(BannerShimmer)).moving, isTrue);
        final painter = tester.widget<CustomPaint>(find.descendant(of: find.byType(BannerShimmer), matching: find.byType(CustomPaint))).painter! as BannerShimmerPainter;
        expect(painter.from, jobColour(tokensAt(tester, find.byType(BannerShimmer)), JobLook.images));
        final before = painter.beat;
        await tester.pump(const Duration(milliseconds: 300));
        expect((tester.widget<CustomPaint>(find.descendant(of: find.byType(BannerShimmer), matching: find.byType(CustomPaint))).painter! as BannerShimmerPainter).beat, isNot(before), reason: 'the sheen sweeps and the stroke draws');
      });
    }

    stillTest('lands: the band fades away over the picture, then the picture is drawn alone', (tester) async {
      final store = MemoryPictureStore({'lovart-a.png': (await tester.runAsync(png))!});
      final making = ValueNotifier<bool>(true);
      await pumpApp(
        tester,
        size: phone.size,
        home: Align(
          alignment: Alignment.topCenter,
          child: ValueListenableBuilder<bool>(valueListenable: making, builder: (context, on, _) => NoteBannerView(name: on ? null : 'lovart-a.png', store: store, making: on)),
        ),
      );
      expect(find.byType(BannerShimmer), findsOneWidget);
      making.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('note-banner-landing')), findsOneWidget, reason: 'the band still over it, fading');
      expect(find.byKey(const ValueKey('note-banner-lovart-a.png')), findsOneWidget, reason: 'the picture under it');
      final fading = tester.widget<FadeTransition>(find.byKey(const ValueKey('note-banner-landing'))).opacity.value;
      expect(fading, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BannerShimmer), findsNothing);
      expect(find.byKey(const ValueKey('note-banner-lovart-a.png')), findsOneWidget);
    });

    stillTest('under reduced motion the band is still and the picture comes at once', (tester) async {
      reducedMotion(tester);
      final store = MemoryPictureStore({'lovart-a.png': (await tester.runAsync(png))!});
      final making = ValueNotifier<bool>(true);
      await pumpApp(
        tester,
        size: mac.size,
        home: Align(
          alignment: Alignment.topCenter,
          child: ValueListenableBuilder<bool>(valueListenable: making, builder: (context, on, _) => NoteBannerView(name: on ? null : 'lovart-a.png', store: store, making: on)),
        ),
      );
      expect(tester.state<BannerShimmerState>(find.byType(BannerShimmer)).moving, isFalse);
      final painter = tester.widget<CustomPaint>(find.descendant(of: find.byType(BannerShimmer), matching: find.byType(CustomPaint))).painter! as BannerShimmerPainter;
      expect(painter.beat, isNull, reason: 'drawn still: the sheen in the middle, the stroke whole');
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'nothing asks for a frame');
      making.value = false;
      await tester.pump();
      expect(find.byType(BannerShimmer), findsNothing);
      expect(find.byKey(const ValueKey('note-banner-landing')), findsNothing);
    });

    stillTest('Calm draws the band in ink', (tester) async {
      await pumpApp(tester, size: phone.size, prefs: const AppPreferences(theme: 'dark', calm: true), home: const Align(alignment: Alignment.topCenter, child: NoteBannerView(name: null, store: null, making: true)));
      final t = tokensAt(tester, find.byType(BannerShimmer));
      final painter = tester.widget<CustomPaint>(find.descendant(of: find.byType(BannerShimmer), matching: find.byType(CustomPaint))).painter! as BannerShimmerPainter;
      expect(painter.from, t.color('app-ink'));
    });
  });

  group('a summary being written', () {
    JobHandle writing({String steps = '2 of 3 parts'}) =>
        record.begin('summary:n1', kind: JobKind.ai, title: 'Summary of Standup', line: 'Writing the summary')..progress(done: 2, total: 4, steps: steps, line: 'Writing the summary');

    test('the words so far, as a section: the thinking and the heading left out', () {
      expect(summaryWordsSoFar('<think>the meeting was about'), '');
      expect(summaryWordsSoFar('<think>hm</think>\n## Summary\n\nWe agreed'), 'We agreed');
      expect(summaryWordsSoFar('## Summary\nShip on Friday.\n- [ ] Ana: the notes'), 'Ship on Friday.\n- [ ] Ana: the notes');
    });

    for (final window in [phone, mac]) {
      stillTest('says "Writing the summary…" with the sparkle and how far, and the words as they stream in (${window.name})', (tester) async {
        final job = writing();
        await pumpApp(tester, size: window.size, home: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.all(20), child: SummaryWriting(jobId: 'summary:n1', record: record))));
        expect(find.text('Writing the summary…'), findsOneWidget);
        expect(find.text('2 of 3 parts'), findsOneWidget);
        expect(find.byKey(const ValueKey('summary-writing:words')), findsNothing, reason: 'nothing written yet');
        final t = tokensAt(tester, find.text('Writing the summary…'));
        expect(tester.widget<Text>(find.text('Writing the summary…')).style!.color, jobColour(t, JobLook.ai));
        expect(tester.state<JobGlyphState>(find.byType(JobGlyph)).moving, isTrue);
        job.write('## Summary\n\nWe agreed to');
        await tester.pump();
        expect(find.textContaining('We agreed to', findRichText: true), findsOneWidget);
        expect(find.byKey(const ValueKey('summary-writing:caret')), findsOneWidget);
        job.write('## Summary\n\nWe agreed to ship on Friday.');
        await tester.pump();
        expect(find.textContaining('ship on Friday.', findRichText: true), findsOneWidget);
        job.done();
        await tester.pump();
        expect(find.text('Writing the summary…'), findsNothing, reason: 'gone as the write lands');
      });
    }

    stillTest('another device\'s says where it is written', (tester) async {
      record.elsewhere('summary-handoff', [Job(id: 'summary:n1', kind: JobKind.ai, title: 'Summary of Standup', line: 'Writing the summary', steps: '1 of 2 parts', device: 'mac', deviceName: 'Mac', startedAt: now)]);
      await pumpApp(tester, size: phone.size, home: Align(alignment: Alignment.topCenter, child: SummaryWriting(jobId: 'summary:n1', record: record)));
      expect(find.text('1 of 2 parts · on your Mac'), findsOneWidget);
    });

    stillTest('under reduced motion the sparkle is still and the words stand, with no caret', (tester) async {
      reducedMotion(tester);
      writing().write('We agreed');
      await pumpApp(tester, size: mac.size, home: Align(alignment: Alignment.topCenter, child: SummaryWriting(jobId: 'summary:n1', record: record)));
      expect(tester.state<JobGlyphState>(find.byType(JobGlyph)).moving, isFalse);
      expect(find.byKey(const ValueKey('summary-writing:caret')), findsNothing);
      expect(find.textContaining('We agreed', findRichText: true), findsOneWidget);
    });

    stillTest('Calm says it in ink', (tester) async {
      writing();
      await pumpApp(tester, size: phone.size, prefs: const AppPreferences(theme: 'light', calm: true), home: Align(alignment: Alignment.topCenter, child: SummaryWriting(jobId: 'summary:n1', record: record)));
      final t = tokensAt(tester, find.text('Writing the summary…'));
      expect(tester.widget<Text>(find.text('Writing the summary…')).style!.color, t.color('app-ink'));
    });

    // In the note: a block between its title and its transcript, never in its words.
    Future<EditorView> showNote(WidgetTester tester, String doc, Size size) async {
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[summaryWriting(SummaryWritingHooks(jobId: () => 'summary:n1', record: record))])));
      addTearDown(view.destroy);
      await pumpApp(
        tester,
        size: size,
        home: Builder(
          builder: (context) => BackScope(
            child: ColoredBox(
              color: context.tokens.color('app-paper'),
              child: Align(alignment: Alignment.topLeft, child: SizedBox(width: size.width, child: EditorColumn(view: view))),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return view;
    }

    const meeting = '# Standup\n\n## Transcript\n\nAna: Ship it on Friday.\nSam: Agreed.';
    for (final window in [phone, mac]) {
      stillTest('stands in the note where the section will be, under the title and over the transcript, and gives way to it (${window.name})', (tester) async {
        final view = await showNote(tester, meeting, window.size);
        expect(find.byType(SummaryWriting), findsNothing, reason: 'nothing while no summary is being written');
        final job = writing();
        await tester.pump();
        await tester.pump();
        expect(find.text('Writing the summary…'), findsOneWidget);
        final card = tester.getRect(find.byKey(const ValueKey('summary-writing:summary:n1')));
        // The editor's lines, where it draws them, against the card's place in the same column.
        final column = tester.getTopLeft(find.byType(EditorColumn));
        final title = view.coordsAtPos(2)!.shift(column);
        final transcript = view.coordsAtPos(meeting.indexOf('## Transcript') + 3)!.shift(column);
        expect(card.top, greaterThan(title.center.dy), reason: 'under the title');
        expect(card.bottom, lessThanOrEqualTo(transcript.top), reason: 'over the transcript');
        job.write('We agreed to ship on Friday.');
        await tester.pump();
        expect(view.state.doc.toString(), meeting, reason: 'nothing of it is in the note');
        // The write lands: the section is the note's, and the card goes.
        final at = view.state.doc.toString().indexOf('## Transcript');
        view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: '## Summary\n\nWe agreed to ship on Friday.\n\n')));
        await tester.pump();
        await tester.pump();
        expect(find.text('Writing the summary…'), findsNothing);
        job.done();
        await tester.pump();
        expect(find.byType(SummaryWriting), findsNothing);
      });
    }

    stillTest('goes as the job ends, written or not', (tester) async {
      final job = writing();
      await showNote(tester, meeting, phone.size);
      expect(find.text('Writing the summary…'), findsOneWidget);
      job.failed('Claude stopped with an error.');
      await tester.pump();
      await tester.pump();
      expect(find.text('Writing the summary…'), findsNothing);
    });
  });

  group('a note\'s sync by its title', () {
    final sent = makeNote('a', '# Plan\n\nwords');
    final changed = makeNote('b', '# Groceries\n\nmilk');
    final refused = makeNote('c', '# Trip\n\nthe coast');
    final fresh = makeNote('d', '# Reading list\n\nbooks');

    /// The account had all four as they were; b and c changed here since, c was refused, d was just sent.
    void state() {
      marks.account(SyncState(notes: {
        'a': NoteMark(rev: 1, mark: mark(sent)),
        'b': const NoteMark(rev: 1, mark: 'before'),
        'c': const NoteMark(rev: 1, mark: 'before'),
        'd': NoteMark(rev: 2, mark: mark(fresh)),
      }));
      marks.failed('c', 'That note is too big.');
      marks.sent('d');
    }

    Finder markOf(String id, NoteSyncLook look) => find.descendant(of: find.byKey(ValueKey('note-sync:$id')), matching: find.byKey(ValueKey('note-sync-mark:${look.name}')));

    void expectMarks(WidgetTester tester) {
      expect(find.byKey(const ValueKey('note-sync:a')), findsNothing, reason: 'synced: nothing');
      expect(markOf('b', NoteSyncLook.waiting), findsOneWidget, reason: 'waits to go: the arrow');
      expect(markOf('c', NoteSyncLook.failed), findsOneWidget, reason: 'refused: red');
      expect(markOf('d', NoteSyncLook.sent), findsOneWidget, reason: 'just gone: the tick');
      final t = tokensAt(tester, find.byKey(const ValueKey('note-sync:b')));
      Color? colourOf(String id) => tester.widget<AppIcon>(find.descendant(of: find.byKey(ValueKey('note-sync:$id')), matching: find.byType(AppIcon))).color;
      expect(colourOf('b'), jobColour(t, JobLook.sync));
      expect(colourOf('c'), jobColour(t, JobLook.needsYou));
    }

    for (final window in [phone, mac]) {
      stillTest('in the cards: an arrow, a tick, red, and nothing for a synced one; the tick goes after a moment (${window.name})', (tester) async {
        state();
        await pumpApp(
          tester,
          size: window.size,
          home: SingleChildScrollView(
            child: Column(children: [
              for (final (i, note) in [sent, changed, refused, fresh].indexed) SizedBox(width: 300, child: NoteCard(key: ValueKey(note.id), note: note, index: i, onOpen: (_) {}, now: 1)),
            ]),
          ),
        );
        expectMarks(tester);
        now = now.add(marks.tickFor);
        await tester.pump(marks.tickFor);
        await tester.pump();
        expect(find.byKey(const ValueKey('note-sync:d')), findsNothing, reason: 'the tick has had its moment');
        expect(markOf('b', NoteSyncLook.waiting), findsOneWidget);
      });

      stillTest('in the sidebar\'s rows (${window.name})', (tester) async {
        state();
        await pumpApp(
          tester,
          size: window.size,
          home: BackScope(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: NoteTree(notes: [sent, changed, refused, fresh], activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: WorkspaceStore(), stored: MemoryStored())))),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expectMarks(tester);
      });

      stillTest('in the icon view (${window.name})', (tester) async {
        state();
        await pumpApp(
          tester,
          size: window.size,
          home: BackScope(child: SingleChildScrollView(child: IconBrowser(folders: const [], notes: [sent, changed, refused, fresh], onFolder: (_) {}, onOpen: (_) {}, now: 1, store: WorkspaceStore()))),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expectMarks(tester);
      });
    }

    stillTest('red says why on hover, and on a long press', (tester) async {
      state();
      await pumpApp(tester, size: mac.size, home: Align(alignment: Alignment.topLeft, child: SizedBox(width: 300, child: NoteCard(note: refused, index: 0, onOpen: (_) {}, now: 1))));
      expect(tester.widget<Semantics>(find.descendant(of: find.byKey(const ValueKey('note-sync:c')), matching: find.byType(Semantics)).first).properties.label, 'Not synced: That note is too big.');
      expect(find.byKey(const ValueKey('note-sync-reason')), findsNothing);
      await tester.longPress(find.byKey(const ValueKey('note-sync:c')));
      await tester.pump();
      expect(find.text('Not synced: That note is too big.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('note-sync-reason')), findsNothing, reason: 'gone after a while');
    });

    stillTest('nothing signed out, nor where the note looks as it did', (tester) async {
      marks.syncing = () => false;
      state();
      await pumpApp(tester, size: phone.size, home: Column(children: [for (final (i, note) in [sent, changed].indexed) SizedBox(width: 300, child: NoteCard(note: note, index: i, onOpen: (_) {}, now: 1))]));
      expect(find.byType(NoteSyncMarkView), findsNothing);
    });

    stillTest('Calm draws the arrow in ink', (tester) async {
      state();
      await pumpApp(tester, size: phone.size, prefs: const AppPreferences(theme: 'dark', calm: true), home: Align(alignment: Alignment.topLeft, child: SizedBox(width: 300, child: NoteCard(note: changed, index: 0, onOpen: (_) {}, now: 1))));
      final t = tokensAt(tester, find.byKey(const ValueKey('note-sync:b')));
      expect(tester.widget<AppIcon>(find.descendant(of: find.byKey(const ValueKey('note-sync:b')), matching: find.byType(AppIcon))).color, t.color('app-ink'));
    });
  });

  group('a note\'s sync in the tabs and in simple mode', () {
    /// Every note of the library as the account had it, but Groceries, changed here since.
    void synced() => marks.account(SyncState(notes: {for (final note in library) note.id: NoteMark(rev: 1, mark: note.id == 'groceries' ? 'before' : mark(note))}));

    for (final (name, size, mobile) in [('phone', phone.size, true), ('mac', mac.size, false)]) {
      stillTest('the open note\'s tab wears its arrow, the others nothing ($name)', (tester) async {
        synced();
        final sheet = await appSheet(tester);
        await pumpApp(
          tester,
          size: size,
          home: AppShell(sheet: sheet, notes: library, workspaces: spaces, openNotes: const ['weekend', 'groceries'], mobile: mobile, finePointer: !mobile, onDeleteNote: (_) {}),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final tab = find.ancestor(of: find.byKey(const ValueKey('note-sync:groceries')), matching: find.byType(NoteTab));
        expect(tab, findsOneWidget);
        expect(find.descendant(of: tab, matching: find.byKey(const ValueKey('note-sync-mark:waiting'))), findsOneWidget);
        expect(find.byKey(const ValueKey('note-sync:weekend')), findsNothing);
        // Sent: a tick for a moment, then nothing.
        marks.account(SyncState(notes: {for (final note in library) note.id: NoteMark(rev: 2, mark: mark(note))}));
        marks.sent('groceries');
        await tester.pump();
        expect(find.descendant(of: find.byType(NoteTab), matching: find.byKey(const ValueKey('note-sync-mark:sent'))), findsOneWidget);
        now = now.add(marks.tickFor);
        await tester.pump(marks.tickFor);
        await tester.pump();
        expect(find.byKey(const ValueKey('note-sync:groceries')), findsNothing);
      });
    }

    stillTest('simple mode shows them as advanced does', (tester) async {
      synced();
      await pumpApp(
        tester,
        size: phone.size,
        prefs: const AppPreferences(theme: 'light', experience: 'simple', experienceChosen: true),
        home: BackScope(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: NoteTree(notes: library.take(6).toList(), activeId: null, simple: true, onOpen: (_) {}, onNew: () {}, workspaces: WorkspaceStore(), stored: MemoryStored())))),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.descendant(of: find.byKey(const ValueKey('note-sync:groceries')), matching: find.byKey(const ValueKey('note-sync-mark:waiting'))), findsOneWidget);
    });
  });

  group('a file going', () {
    for (final window in [phone, mac]) {
      stillTest('a picture in a note has a thin bar along its foot while it goes (${window.name})', (tester) async {
        final store = MemoryPictureStore({'p1.png': (await tester.runAsync(png))!});
        await pumpApp(tester, size: window.size, home: Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: KeptPicture(name: 'p1.png', store: store))));
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump();
        }
        expect(find.byType(JobBar), findsNothing);
        final gone = marks.sending(FileKind.image, 'p1.png');
        await tester.pump();
        final bar = tester.getRect(find.byKey(const ValueKey('file-sending:image/p1.png')));
        final picture = tester.getRect(find.byType(KeptPicture));
        expect(bar.bottom, closeTo(picture.bottom, 0.5), reason: 'along its foot');
        expect(bar.width, closeTo(picture.width, 0.5));
        final t = tokensAt(tester, find.byType(JobBar));
        expect(tester.widget<JobBar>(find.byType(JobBar)).colour, kindColour(t, JobKind.images));
        gone();
        await tester.pump();
        expect(find.byType(JobBar), findsNothing);
      });
    }
  });
}

