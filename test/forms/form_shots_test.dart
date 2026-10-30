import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/forms/form_def.dart';
import 'package:ghost_md/forms/form_inbox.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/fake_crypto.dart';
import '../support/render.dart';
import '../support/sync_device.dart' show DeviceFiles, DeviceNotes;

/// Pictures of a ticket filed from an answer to a form (docs/FORMS.md; Matt, 2026-10-30, the ninth of "add all 12"):
/// the ticket as the app opens it - its key, its status, the answers in its front matter and under their labels, the
/// line saying it came by the form - and the notebook's index with it listed beside the form. On a phone and the
/// Mac's window, light and dark. The ticket is filed as the sync step files one (lib/forms/form_inbox.dart
/// `fileAnswer`). Written only by `flutter test --update-goldens test/forms/form_shots_test.dart`, into
/// build/feature-shots/forms/*.png (not committed), to be looked at, not held as goldens.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const bookBody = '---\nbook: true\nkey: BUG\nstatuses: [Triage, To do, Doing, Done]\n---\n# Bug reports\n\nWhat goes wrong, from inside the team and out.\n\n1. [[Report a bug]]\n';
  const formBody = '''# Report a bug

Something not working in Ghost.md? Tell us what happened and we'll turn it into a ticket.

```form
to: [[Bug reports]]
ticket: Bug: {Summary}
template: Bug report
thanks: Thanks, we'll look into it.
- Summary: short, required
- What happened: long, required
- How bad is it: choice (Annoying | Blocking my work | I lost something)
- Your email: email, optional
```
''';

  Future<void> snap(WidgetTester tester, String name) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/feature-shots/forms/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The ticket and the notebook as the forms step leaves them, from one answer.
  Future<List<Note>> filed() async {
    final notes = DeviceNotes();
    notes.held['bug-book'] = Note(id: 'bug-book', body: bookBody, createdAt: seedNow - 86400000, updatedAt: seedNow - 86400000);
    notes.held['bug-form'] = Note(id: 'bug-form', body: formBody, createdAt: seedNow - 86400000, updatedAt: seedNow - 86400000);
    final ctx = FormPassContext(
      token: 't',
      api: Api(base: 'http://none.test/api', fetcher: (_) async => FetchResponse.json(404, {'error': noSuchRoute})),
      crypto: FakeCrypto(),
      pair: () => throw StateError('not asked'),
      notes: notes,
      files: DeviceFiles(),
      now: () => seedNow - 600000,
      prefs: () => const Preferences(),
      kept: MemoryStored(),
    );
    const answer = FormAnswer(answers: [
      ('Summary', 'Sync stops after the Mac wakes from sleep'),
      ('What happened', 'I closed the lid for lunch. When I opened it again, notes from the phone stopped arriving until I quit and reopened the app.'),
      ('How bad is it', 'Blocking my work'),
      ('Your email', 'ana@example.com'),
    ]);
    await fileAnswer(ctx, id: 'bug-ticket', answerId: 'answer-1', formNote: notes.held['bug-form'], answer: answer, notes: notes.held.values.toList(), at: seedNow - 900000);
    return notes.held.values.toList();
  }

  for (final (size, ratio, where, mac) in [(const Size(390, 844), 3.0, 'phone', false), (const Size(1280, 800), 2.0, 'mac', true)]) {
    for (final theme in ['light', 'dark']) {
      testWidgets('a ticket filed from a form, and its notebook, $where, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        useStored(MemoryStored());
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final library = SampleLibrary.seeded();
        final notes = (await tester.runAsync(filed))!;
        for (final note in notes) {
          await tester.runAsync(() => library.apply(note));
        }
        await pumpApp(
          tester,
          size: size,
          ratio: ratio,
          prefs: Preferences(theme: theme),
          home: GhostRoot(launch: false, library: library, stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
        );
        if (mac) {
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
        }
        await tester.pump(const Duration(milliseconds: 300));
        tester.state<AppShellState>(find.byType(AppShell)).openNote('bug-ticket');
        await settle(tester);
        await snap(tester, 'ticket-$where-$theme');
        tester.state<AppShellState>(find.byType(AppShell)).openNote('bug-book');
        await settle(tester);
        await snap(tester, 'notebook-$where-$theme');
        tester.state<AppShellState>(find.byType(AppShell)).backToList();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 500));
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  test('the pictures’ ticket is the forms step’s own', () async {
    final notes = await filed();
    final ticket = notes.firstWhere((n) => n.id == 'bug-ticket');
    expect(ticket.body, contains('id: BUG-1'));
    expect(ticket.body, contains('via: form'));
    expect(formOf(formBody)!.to, 'Bug reports');
  });
}
