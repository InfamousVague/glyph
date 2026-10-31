import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/page_tree.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/note/doc_page.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/note/note_settings.dart';

import '../support/header_bar.dart';
import '../support/render.dart';
import 'support.dart';

/// The doc page (lib/note/doc_page.dart; docs/TEAMSPACES.md, Matt, 2026-10-31: "the doc page UI"): the crumbs and
/// their fold on a phone, the icon, the outline beside the words on a wide window only, read or edit by the space's
/// `docs:`, the pages either side, the pages under a folder page, the edited line, and what simple mode keeps.
void main() {
  setUpAll(loadAppFonts);

  const acme = Workspace(id: 'org-acme', name: 'Acme');
  const beta = Workspace(id: 'org-beta', name: 'Beta');
  const work = Workspace(id: 'w-work', name: 'Work');

  const bodies = <String, String>{
    'home': '---\ntitle: Home\ntype: teamspace\ndocs: read\nicon: 🏠\n---\n# Home\n',
    'eng': '# Engineering\n\nHow we build.\n',
    'plan': '---\nicon: 🚀\nowner: "[[Bo]]"\n---\n# Plan\n\nThe plan for the quarter.\n\n## Goals\n\nShip.\n\n## Risks\n\nNone.\n',
    'step1': '# Step one\n\nFirst we draw.\n',
    'step2': '# Step two\n\nThen we build.\n',
    'bhome': '---\ntitle: Home\ntype: teamspace\ndocs: edit\n---\n# Home\n',
    'bdoc': '# Notes\n\nBeta notes.\n',
    'mine': '# Garden\n\nMy garden.\n',
    'bed': '# Bed one\n\nTomatoes.\n',
    'quick': '# Quick\n\nA thought.\n',
  };
  const paths = <String, String>{
    'home': 'orgs/Acme/Home.md',
    'eng': 'orgs/Acme/Engineering/Engineering.md',
    'plan': 'orgs/Acme/Engineering/Plan/Plan.md',
    'step1': 'orgs/Acme/Engineering/Plan/Step one.md',
    'step2': 'orgs/Acme/Engineering/Plan/Step two.md',
    'bhome': 'orgs/Beta/Home.md',
    'bdoc': 'orgs/Beta/Notes.md',
    'mine': 'workspaces/Work/Garden/Garden.md',
    'bed': 'workspaces/Work/Garden/Bed one.md',
    'quick': 'Inbox/Quick.md',
  };
  PageTree tree() => PageTree.build(
        [for (final id in bodies.keys) Note(id: id, body: bodies[id]!, createdAt: 0, updatedAt: 1000, path: paths[id])],
        workspaces: const [work, acme, beta],
      );

  // A new world for each screen: the saving keeps a note's last writes by its id.
  Future<NoteScreenState> pump(WidgetTester tester, String id, {Size size = const Size(840, 900), bool simple = false, List<String>? opened}) async {
    final world = NoteWorld();
    final note = (await tester.runAsync(() => seedNote(world, id, bodies[id]!)))!;
    if (simple) world.prefs.value = world.prefs.value.copyWith(experience: 'simple', experienceChosen: true);
    final log = opened ?? <String>[];
    final screen = await pumpNote(
      tester,
      world,
      note,
      size: size,
      pageTree: ValueNotifier<PageTree>(tree()),
      seams: NoteSeams(openNote: log.add, pickCover: () async => 'cover.png'),
    );
    // The editor's view arrives a frame after the screen, and the rail and the edited line with it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return screen;
  }

  Finder inCrumbs(String text) => find.descendant(of: find.byKey(const ValueKey('doc-crumbs')), matching: find.text(text));

  group('the model', () {
    test("a note's place: crumbs from the space down, read first by the home's docs:, Inbox no doc", () {
      final t = tree();
      final step = DocPlace.of(t, 'step1')!;
      expect([for (final c in step.crumbs) c.title], ['Acme', 'Engineering', 'Plan', 'Step one']);
      expect(step.crumbs.first.noteId, 'home', reason: "the space's crumb opens its home");
      expect(step.crumbs.first.icon?.emoji, '🏠');
      expect(step.crumbs.last.here, isTrue);
      expect(step.readFirst, isTrue);
      expect((step.previous?.title, step.next?.title), ('Plan', 'Step two'));
      expect([for (final p in DocPlace.of(t, 'plan')!.pages) p.title], ['Step one', 'Step two']);
      expect(DocPlace.of(t, 'bdoc')!.readFirst, isFalse, reason: 'docs: edit');
      expect(DocPlace.of(t, 'quick'), isNull, reason: 'a note in Inbox is no doc');
      expect(DocPlace.of(t, 'bed')!.readFirst, isFalse, reason: 'Personal is always edit');
      expect([for (final c in DocPlace.of(t, 'bed')!.crumbs) c.title], ['Personal', 'Work', 'Garden', 'Bed one']);
      expect(DocPlace.of(t, 'home')!.crumbs.length, 1, reason: 'the home has no space above it');
    });

    test('the crumbs fold on a phone past three: the first, …, the last two', () {
      final crumbs = DocPlace.of(tree(), 'step1')!.crumbs;
      expect([for (final c in foldedCrumbs(crumbs, compact: true)) c?.title], ['Acme', null, 'Plan', 'Step one']);
      expect(foldedCrumbs(crumbs, compact: false), crumbs);
      expect(foldedCrumbs(crumbs.sublist(1), compact: true), crumbs.sublist(1));
    });

    test('the edited line: when, who, the owner', () {
      const now = 10 * 3600 * 1000;
      expect(editedWords(at: now - 2 * 3600 * 1000, by: 'ana', now: now), 'Edited 2 hr ago by ana');
      expect(editedWords(at: now, by: 'me', now: now), 'Edited just now by you');
      expect(editedWords(at: now, by: 'matt', self: 'matt', now: now, owner: 'Bo'), 'Edited just now by you · Owner: Bo');
      expect(editedWords(at: now - 60000 * 5, now: now), 'Edited 5 min ago');
      expect(ownerOf(bodies['plan']!), 'Bo');
      expect(ownerOf(bodies['step1']!), isNull);
    });
  });

  group('the page', () {
    testWidgets('a nested team page wears its crumbs, and one opens its page', (tester) async {
      final opened = <String>[];
      await pump(tester, 'step1', opened: opened);
      expect(find.byKey(const ValueKey('doc-crumbs')), findsOneWidget);
      for (final title in ['Acme', 'Engineering', 'Plan', 'Step one']) {
        expect(inCrumbs(title), findsOneWidget, reason: title);
      }
      await tester.tap(inCrumbs('Engineering'));
      await tester.pump();
      expect(opened, ['eng']);
      await tester.tap(inCrumbs('Step one'));
      await tester.pump();
      expect(opened, ['eng'], reason: 'this page is no way anywhere');
      await closeNote(tester);
    });

    testWidgets('on a phone the middle crumbs fold into …, which opens them out', (tester) async {
      await pump(tester, 'step1', size: const Size(390, 844));
      expect(find.byKey(const ValueKey('doc-crumbs-fold')), findsOneWidget);
      expect(inCrumbs('Engineering'), findsNothing);
      expect(inCrumbs('Acme'), findsOneWidget);
      expect(inCrumbs('Plan'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doc-crumbs-fold')));
      await tester.pump();
      expect(inCrumbs('Engineering'), findsOneWidget);
      await closeNote(tester);
    });

    testWidgets('a page with an icon wears it over its title', (tester) async {
      await pump(tester, 'plan');
      expect(find.byKey(const ValueKey('doc-icon')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('doc-icon')), matching: find.text('🚀')), findsOneWidget);
      await closeNote(tester);
    });

    testWidgets('the icon chooser writes icon: into the front matter', (tester) async {
      final screen = await pump(tester, 'step1');
      // Read first: Edit, then the chooser from the icon's own row of the More sheet.
      await tester.tap(find.byKey(const ValueKey('doc-edit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await pressInBar(tester, 'more', label: 'More for this note');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('THIS PAGE'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('page:doc-icon')));
      await tester.tap(find.byKey(const ValueKey('page:doc-icon')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('doc-icon-choice:🎯')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(screen.view!.state.doc.toString(), startsWith('---\nicon: 🎯\n---\n# Step one'));
      expect(find.byKey(const ValueKey('doc-icon')), findsOneWidget);
      await closeNote(tester);
    });

    testWidgets('the outline stands beside the words on a wide window only', (tester) async {
      await pump(tester, 'plan', size: const Size(1280, 900));
      expect(find.byKey(const ValueKey('doc-outline')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('doc-outline')), matching: find.text('Goals')), findsOneWidget);
      await closeNote(tester);

      await pump(tester, 'plan', size: const Size(390, 844));
      expect(find.byKey(const ValueKey('doc-outline')), findsNothing);
      await closeNote(tester);
    });

    testWidgets('a space that reads first opens its pages to be read, and Edit writes; Read reads again', (tester) async {
      final screen = await pump(tester, 'step1');
      expect(screen.reading, isTrue);
      expect(screen.view!.state.readOnly, isTrue);
      expect(find.byKey(const ValueKey('doc-edit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doc-edit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(screen.reading, isFalse);
      expect(screen.view!.state.readOnly, isFalse);
      expect(find.byKey(const ValueKey('doc-read')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doc-read')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(screen.view!.state.readOnly, isTrue);
      await closeNote(tester);
    });

    testWidgets("docs: edit and Personal open straight into editing, with no Edit", (tester) async {
      for (final id in ['bdoc', 'bed']) {
        final screen = await pump(tester, id);
        expect(screen.reading, isFalse, reason: id);
        expect(screen.view!.state.readOnly, isFalse, reason: id);
        expect(find.byKey(const ValueKey('doc-edit')), findsNothing, reason: id);
        await closeNote(tester);
      }
    });

    testWidgets('a note in Inbox is drawn as it was: no crumbs, no steps', (tester) async {
      await pump(tester, 'quick');
      expect(find.byKey(const ValueKey('doc-crumbs')), findsNothing);
      expect(find.byKey(const ValueKey('doc-steps'), skipOffstage: false), findsNothing);
      expect(find.byKey(const ValueKey('doc-edited'), skipOffstage: false), findsNothing);
      await closeNote(tester);
    });

    testWidgets('the pages either side are at the foot, and one opens', (tester) async {
      final opened = <String>[];
      await pump(tester, 'step1', opened: opened);
      final prev = find.byKey(const ValueKey('doc-prev'), skipOffstage: false);
      final next = find.byKey(const ValueKey('doc-next'), skipOffstage: false);
      expect(prev, findsOneWidget);
      expect(find.descendant(of: prev, matching: find.text('Plan', skipOffstage: false)), findsOneWidget);
      expect(find.descendant(of: next, matching: find.text('Step two', skipOffstage: false)), findsOneWidget);
      await tester.ensureVisible(next);
      await tester.pump();
      await tester.tap(next);
      await tester.pump();
      expect(opened, ['step2']);
      await closeNote(tester);
    });

    testWidgets("a folder page's sub-pages are cards: one a row on a phone, side by side wide", (tester) async {
      final opened = <String>[];
      await pump(tester, 'plan', opened: opened, size: const Size(390, 844));
      final one = find.byKey(const ValueKey('doc-page:step1'), skipOffstage: false);
      final two = find.byKey(const ValueKey('doc-page:step2'), skipOffstage: false);
      expect(find.byKey(const ValueKey('doc-pages'), skipOffstage: false), findsOneWidget);
      expect(find.descendant(of: one, matching: find.text('First we draw.', skipOffstage: false)), findsOneWidget, reason: 'its peek');
      expect(tester.getTopLeft(two).dy, greaterThan(tester.getTopLeft(one).dy), reason: 'one card a row');
      await tester.ensureVisible(two);
      await tester.pump();
      await tester.tap(two);
      await tester.pump();
      expect(opened, ['step2']);
      await closeNote(tester);

      await pump(tester, 'plan', size: const Size(1280, 900));
      expect(tester.getTopLeft(find.byKey(const ValueKey('doc-page:step2'), skipOffstage: false)).dy, tester.getTopLeft(find.byKey(const ValueKey('doc-page:step1'), skipOffstage: false)).dy, reason: 'a grid');
      await closeNote(tester);
    });

    testWidgets('the edited line sits under the title, with the owner', (tester) async {
      await pump(tester, 'plan');
      final line = find.byKey(const ValueKey('doc-edited'));
      expect(line, findsOneWidget);
      expect((tester.widget<Text>(line).data ?? ''), allOf(startsWith('Edited '), endsWith(' · Owner: Bo')));
      await closeNote(tester);
    });

    testWidgets('simple mode keeps the crumbs and the steps; the outline, the affordances and the edited line are behind More…', (tester) async {
      final screen = await pump(tester, 'plan', size: const Size(1280, 900), simple: true);
      expect(find.byKey(const ValueKey('doc-crumbs')), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-steps'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-pages'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-icon')), findsOneWidget, reason: 'the icon itself is the page’s');
      expect(find.byKey(const ValueKey('doc-outline')), findsNothing);
      expect(find.byKey(const ValueKey('doc-edited')), findsNothing);
      expect(find.byKey(const ValueKey('doc-affordances')), findsNothing);
      expect(screen.reading, isTrue, reason: 'read first in simple mode too');
      await tester.tap(find.byKey(const ValueKey('doc-edit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await pressInBar(tester, 'more', label: 'More for this note');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(NoteSettings), findsOneWidget);
      expect(find.text('THIS PAGE', skipOffstage: false), findsNothing, reason: 'behind More…');
      await tester.ensureVisible(find.text('More…'));
      await tester.tap(find.text('More…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('THIS PAGE', skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('page:doc-info'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('page:doc-cover'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('page:doc-outline'), skipOffstage: false), findsOneWidget);
      await closeNote(tester);
    });

    testWidgets('on a desktop, Add icon and Add cover wait for the pointer over the head', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final screen = await pump(tester, 'bdoc');
        expect(find.byKey(const ValueKey('doc-affordances')), findsOneWidget);
        expect(find.byKey(const ValueKey('doc-add-icon')), findsOneWidget);
        expect(find.byKey(const ValueKey('doc-add-cover')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('doc-add-cover')), warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(screen.view!.state.doc.toString(), startsWith('---\nbanner: "![](image/cover.png)"\n---\n'));
        await closeNote(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('writing the settings', () {
    test("withDocsMode writes docs: into a home's front matter, and the settings read it back", () {
      final home = teamspaceHomeBody('Acme');
      final read = withDocsMode(home, DocsMode.read);
      expect(TeamspaceSettings.of(read).docs, DocsMode.read);
      expect(read.split('\n').where((line) => line.startsWith('docs:')).toList(), ['docs: read'], reason: 'replaced, not added twice');
      expect(withDocsMode(read, DocsMode.edit), home);
      expect(TeamspaceSettings.of(withDocsMode('# Home\n', DocsMode.read)).docs, DocsMode.read, reason: 'front matter made where there was none');
    });

    test('withPageIcon writes icon: as PageIcon reads it, and takes it off', () {
      expect(PageIcon.of(frontMatterIcon(withPageIcon('# Plan\n', '🚀')))?.emoji, '🚀');
      expect(PageIcon.of(frontMatterIcon(withPageIcon('# Plan\n', ':rocket:')))?.emoji, '🚀');
      expect(PageIcon.of(frontMatterIcon(withPageIcon('# Plan\n', 'book-open')))?.name, 'book-open');
      expect(withPageIcon(withPageIcon('# Plan\n', '🚀'), null), '# Plan\n');
      expect(withPageIcon('# Plan\n', '  '), '# Plan\n');
    });
  });
}

String? frontMatterIcon(String body) => TeamspaceSettings.of(body).icon?.written;
