// Cleanup's page and its review (lib/plugins/cleanup/cleanup_pane.dart, review.dart; docs/CLEANUP.md, "The page" and
// "The review"): the folder, the AI, the passes and what is sent; the review grouped by pass with a tick on each item,
// a diff for an edit, before → after for a move and a title; Apply applying only the ticked, Apply all its own quieter
// row; Undo on what was applied; Simple's More; Local only's one AI; and Clean up with AI… in a folder's menu. Pictures
// into build/feature-shots/cleanup/ under --update-goldens.
import 'package:flutter/gestures.dart' show kSecondaryMouseButton, PointerDeviceKind;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/notes/folder_menu.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/cleanup/cleanup.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:glacier/glacier.dart';

import '../../support/feature_shot.dart';
import '../../support/render.dart';
import 'support.dart';

/// The scripted AI's answer for Work: a new Meetings folder for the standup, the untitled call to Clients with a title
/// and a link, Plan to tidy, tags for the invoices, the empty idea to the Archive; and Tidy's answer for Plan.
String richAnswer(String system, String prompt) {
  if (system.startsWith('You fix the Markdown')) return '# Plan\n\n### Steps\n\n- one\n- two\n\n## Done\n\nAll good.';
  final n = noteRefs(prompt), f = folderRefs(prompt);
  return answerJson({
    'folders': [
      {'ref': 'new1', 'name': 'Meetings', 'parent': 'f0', 'why': 'Standups and calls'},
    ],
    'moves': [
      {'note': n['Standup'], 'to': 'new1', 'why': 'A standup'},
      {'note': n['Untitled'], 'to': f['Work › Clients'], 'why': 'A call with a client'},
    ],
    'titles': [
      {'note': n['Untitled'], 'title': 'Kiln spring menu call', 'why': 'It had no title'},
    ],
    'tidy': [
      {'note': n['Plan'], 'why': 'A stray # and mixed list markers'},
    ],
    'tags': [
      {'note': n['October invoices'], 'tags': ['admin', 'billing'], 'why': 'Money to chase'},
    ],
    'links': [
      {'note': n['Untitled'], 'to': [n['Kiln brief']], 'why': 'The same client'},
    ],
    'stale': [
      {'note': n['Idea'], 'why': 'Empty since July'},
    ],
  });
}

void main() {
  setUpAll(loadAppFonts);

  late CleanupWorld world;
  setUp(() => world = CleanupWorld());
  tearDown(() => preferences.update((p) => p.copyWith(experience: 'advanced')));

  Future<void> pumpPage(WidgetTester tester, CleanupService service, {String theme = 'light', Size size = const Size(430, 900)}) async {
    await pumpApp(
      tester,
      size: size,
      prefs: AppPreferences(theme: theme),
      home: Builder(
        builder: (context) {
          final t = context.tokens;
          return Material(
            type: MaterialType.transparency,
            child: ColoredBox(
              color: t.color('glacier-bg'),
              child: Align(
                alignment: Alignment.topLeft,
                child: GlacierScope(
                  attrs: const {'hue': 'lime'},
                  child: SettingsPaneScope(
                    finder: SettingsFinder(),
                    child: SingleChildScrollView(padding: EdgeInsets.only(left: t.len('app-gutter-start'), right: t.len('app-gutter-end'), top: 16, bottom: 40), child: CleanupPane(service: service)),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Finder word(String text, [Finder? within]) {
    final found = find.widgetWithText(RowAction, text);
    return within == null ? found : find.descendant(of: within, matching: found);
  }

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  CleanupService serviceOf({bool localOnly = false, List<CleanupAi>? ais}) {
    final service = world.service(ais: ais ?? [scriptedAi(richAnswer, id: 'claude', name: 'Claude')], localOnly: localOnly);
    for (final pass in CleanupPass.values) {
      service.setPass(pass, true);
    }
    service.choose('work');
    return service;
  }

  testWidgets('the page before a run: the folder, the AI, what to do, and exactly what is sent', (tester) async {
    final service = serviceOf();
    await pumpPage(tester, service);
    await settle(tester);
    expect(find.text('Work'), findsOneWidget);
    // The archived note is not counted: it is not read either.
    expect(find.textContaining('8 notes, the folders inside it included'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    for (final pass in CleanupPass.values) {
      expect(find.byKey(ValueKey('cleanup-pass-switch-${pass.name}')), findsOneWidget, reason: pass.name);
    }
    expect(find.textContaining('first 600 characters go to Claude, with your key, through its plugin, 40 notes at a time'), findsOneWidget);
    expect(tester.widget<RowAction>(word('Look')).disabled, isFalse);
    await featureShot(tester, 'cleanup', 'page-light');
    await away(tester);
  });

  testWidgets('the review: grouped by pass, every item ticked, a diff for an edit, before → after for a move and a title', (tester) async {
    final service = serviceOf();
    await pumpPage(tester, service, size: const Size(430, 3600));
    await tester.runAsync(() => service.look());
    await settle(tester);
    expect(service.stage, CleanupStage.review);
    expect(find.byKey(const ValueKey('cleanup-review')), findsOneWidget);
    expect(find.textContaining('9 suggestions for Work from Claude. Nothing changes until you apply.'), findsOneWidget);
    for (final title in ['Sort · 3', 'Titles · 1', 'Duplicates · 1', 'Tidy · 1', 'Tags and links · 2', 'Stale · 1']) {
      expect(find.text(title.toUpperCase()).evaluate().isNotEmpty || find.text(title).evaluate().isNotEmpty, isTrue, reason: title);
    }
    expect(find.text('New folder: Meetings'), findsOneWidget);
    // The arrows are drawn as a glyph (the faces have none): read back as →.
    Finder arrowed(String words) => find.byWidgetPredicate((w) => w is Text && w.textSpan != null && w.textSpan!.toPlainText().replaceAll('\uFFFC', '→').replaceAll(RegExp(r'\s*→\s*'), ' → ').trim() == words);
    expect(arrowed('Work → Work › Meetings (new)'), findsOneWidget);
    expect(arrowed('Work → Work › Clients'), findsOneWidget);
    expect(arrowed('→ Kiln spring menu call'), findsOneWidget);
    expect(find.text('Keep Standup'), findsOneWidget);
    expect(find.textContaining('Standup (shared) goes to the Trash'), findsOneWidget);
    expect(find.byKey(const ValueKey('cleanup-diff')), findsNWidgets(4), reason: 'the tidy, two tag-and-link edits, and the lines a merge brings');
    expect(diffRows('# A\n\n* one\n\n\nB', '# A\n\n- one\n\nB').map((r) => '${r.kind.name} ${r.text}'), ['kept # A', 'removed * one', 'added - one', 'kept B']);
    expect(find.text('Apply 9 changes'), findsOneWidget);
    expect(find.text('Apply all 9'), findsOneWidget);
    await featureShot(tester, 'cleanup', 'review-light');

    // A tick taken off the new folder takes its move with it; the note's own row puts both back.
    await tap(tester, find.byKey(const ValueKey('cleanup-item-folder:work/meetings')));
    expect(service.ticked, isNot(contains('move:standup')));
    expect(find.text('Apply 7 changes'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('cleanup-item-move:standup')));
    expect(service.ticked, containsAll(['move:standup', 'folder:work/meetings']));
    // The stale note and the tidy unticked: Apply applies only what is ticked.
    await tap(tester, find.byKey(const ValueKey('cleanup-item-stale:idea')));
    await tap(tester, find.byKey(const ValueKey('cleanup-item-tidy:messy')));
    expect(find.text('Apply 7 changes'), findsOneWidget);
    await tester.ensureVisible(word('Apply'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(word('Apply'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    expect(service.stage, CleanupStage.applied);
    expect(world.library.noteOf('idea')!.archivedAt, isNull);
    expect(world.library.noteOf('messy')!.body, startsWith('# Plan\n\n#\n'));
    expect(world.workspaces.workspaceOf('kiln-call')?.id, 'clients');
    expect(world.trash.isTrashed('standup-copy'), isTrue);
    expect(find.text('1 new folder · 2 moved · 3 edited · 1 to the Trash'), findsOneWidget);
    await featureShot(tester, 'cleanup', 'applied-light');

    // Undo takes the whole run back.
    await tester.ensureVisible(find.byKey(const ValueKey('cleanup-undo')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('cleanup-undo')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    expect(world.workspaces.workspaceOf('kiln-call')?.id, 'work');
    expect(world.trash.isTrashed('standup-copy'), isFalse);
    expect(world.library.noteOf('kiln-call')!.body, cleanupNotes().firstWhere((n) => n.id == 'kiln-call').body);
    expect(find.textContaining('Taken back: 7 changes'), findsOneWidget);
    await away(tester);
  });

  testWidgets('the review in the dark, and on a phone', (tester) async {
    final service = serviceOf();
    await pumpPage(tester, service, theme: 'dark', size: const Size(430, 3600));
    await tester.runAsync(() => service.look());
    await settle(tester);
    await featureShot(tester, 'cleanup', 'review-dark');
    await away(tester);
    final phone = serviceOf();
    await pumpPage(tester, phone, size: const Size(390, 844));
    await tester.runAsync(() => phone.look());
    await settle(tester);
    await featureShot(tester, 'cleanup', 'review-phone');
    expect(find.byKey(const ValueKey('cleanup-review')), findsOneWidget);
    await away(tester);
  });

  testWidgets('Simple keeps the basic three, the rest behind More, which opens in place', (tester) async {
    final service = serviceOf();
    await pumpPage(tester, service);
    preferences.update((p) => p.copyWith(experience: 'simple', experienceChosen: true));
    await settle(tester);
    expect(find.byKey(const ValueKey('cleanup-pass-switch-sort')), findsOneWidget);
    expect(find.byKey(const ValueKey('cleanup-pass-switch-tidy')), findsNothing);
    expect(find.byKey(const ValueKey('cleanup-rewrite')), findsNothing);
    await tap(tester, word('Show'));
    expect(find.byKey(const ValueKey('cleanup-pass-switch-tidy')), findsOneWidget);
    expect(find.byKey(const ValueKey('cleanup-rewrite')), findsOneWidget);
    await away(tester);
  });

  testWidgets('Local only: the page says so, and only the model on this device is offered', (tester) async {
    final service = serviceOf(localOnly: true, ais: [scriptedAi(richAnswer, id: 'device', name: 'On this device', local: true)]);
    await pumpPage(tester, service);
    await settle(tester);
    expect(find.text('Local only is on, so only the model on this device is used.'), findsOneWidget);
    expect(find.text('On this device'), findsOneWidget);
    expect(find.textContaining('to the model on this device, and nothing leaves it, 12 notes at a time'), findsOneWidget);
    await featureShot(tester, 'cleanup', 'page-local-only');
    await away(tester);
  });

  testWidgets('a folder’s menu has Clean up with AI… while the plugin is on, and it opens the page at that folder', (tester) async {
    final before = plugins;
    addTearDown(() => usePlugins(before));
    final store = world.workspaces;
    final cleaned = <String>[];
    Future<void> menuOf(bool on) async {
      usePlugins(createRegistry(builtIn, store: MemorySwitches({'cleanup': on})));
      await pumpApp(
        tester,
        home: BackScope(
          child: FolderMenuScope(
            store: store,
            onRename: (_) {},
            onDelete: (_) {},
            onCleanup: (folder) => cleaned.add(folder.id),
            child: FolderMenuArea(folderId: 'clients', child: Container(key: const ValueKey('tile'), width: 200, height: 100, color: const Color(0xFFEEEEEE))),
          ),
        ),
      );
      final mouse = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('tile'))), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await menuOf(false);
    expect(find.byKey(const ValueKey('folder-menu-cleanup')), findsNothing);
    await away(tester);
    await menuOf(true);
    expect(find.text('Clean up with AI…'), findsOneWidget);
    await featureShot(tester, 'cleanup', 'folder-menu');
    await tester.tap(find.byKey(const ValueKey('folder-menu-cleanup')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(cleaned, ['clients']);
    await away(tester);
  });
}
