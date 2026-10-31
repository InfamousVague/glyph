// Pictures of the app for the website's home page, ghostmarkdown.com (Matt, 2026-10-31: "make all the screenshots
// light mode not dark mode"): the whole app on a phone, 390 by 844 at 2x as landing/shots/ are, and on a wide window,
// 960 by 600 at 2x for the two laptops, in the light theme, over the app put together (lib/root/ghost_root.dart) on
// the seeded library the store's pictures use, with three notes of the test's own. Written only by
// `FEATURE_SHOTS=1 flutter test --update-goldens test/site/home_site_shots_test.dart`, into
// build/feature-shots/home-site/<name>.png (not committed); cwebp makes each into landing/shots/<name>.webp at 780 by
// 1688 (the laptops at 1920 by 1200), quality 86, as scripts/lovart-site-shots.sh makes the Lovart ones.
//
// - `home`: the home page, pinned notes first, then recent notes as cards.
// - `desk`: the same on a wide window.
// - `journal`: a journal, its entries by day.
// - `board`: Launch week, to-dos as cards in columns.
// - `canvas`: the cabin weekend, laid out.
// - `fields`: to-dos with a person, a priority, a tag and a due day as chips, a choice, and a sum.
// - `ticket`: PRD-11, its fields in a panel over its words.
// - `table`: the open tickets as a table, their estimates added up.
// - `query`: This sprint on a wide window, its query drawn as a board.
// - `calendar`: a note drawing a month of the to-dos with a day.
// - `plugins`: the Market.
//
// Claude's chat and Claude typing are not here: they need a Claude run scripted through the root's wiring, which has
// no hook for one, and the meeting's note is test/root/meeting_transcript_shots_test.dart's.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/registry.dart' show MemorySwitches, createRegistry, usePlugins;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../plugins/support.dart';
import '../support/render.dart';

const String out = 'build/feature-shots/home-site';

/// The to-dos' fields as Obsidian Tasks writes them, each a chip; a choice; and a sum worked out.
const String fieldsBody = '# Renewals\n'
    '\n'
    'What is due this month, and who has it.\n'
    '\n'
    '- [ ] Renew the insurance @matt ⏫ 📅 2026-10-02 #home\n'
    '- [ ] Book the dentist @sam 🔼 📅 2026-10-09\n'
    '- [ ] Return the library books 📅 2026-10-04 #errands\n'
    '- [x] Pay the water bill 📅 2026-09-25\n'
    '\n'
    '## Which plan\n'
    '\n'
    '- ( ) Monthly\n'
    '- (x) Yearly\n'
    '\n'
    '= \$45 + \$18 * 2\n';

/// A month of the to-dos with a day, drawn from a query.
const String calendarBody = '# This week\n'
    '\n'
    'The to-dos with a day, on the calendar.\n'
    '\n'
    '```query\n'
    'from: tasks\n'
    'where: due >= 2026-09-01\n'
    'show: calendar\n'
    '```\n';

/// A journal entry as New entry writes it: named by the minute, dated, its heading the day.
Note entry(String id, DateTime at, String words) {
  String two(int n) => n.toString().padLeft(2, '0');
  final day = '${at.year}-${two(at.month)}-${two(at.day)}';
  final time = '${two(at.hour)}:${two(at.minute)}';
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final body = '---\ntitle: "$day ${two(at.hour)}.${two(at.minute)}"\ndate: ${day}T$time\n---\n# ${weekdays[at.weekday - 1]}, ${months[at.month - 1]} ${at.day}\n\n**$time** $words\n';
  return Note(id: id, body: body, createdAt: at.millisecondsSinceEpoch, updatedAt: at.millisecondsSinceEpoch);
}

/// The journal and its entries, the newest first in its list.
List<Note> journal() {
  final today = DateTime.fromMillisecondsSinceEpoch(seedNow);
  final entries = [
    entry('site-entry-1', DateTime(today.year, today.month, today.day, 8, 12), 'Up early. The bakery was open, so the day started well.'),
    entry('site-entry-2', DateTime(today.year, today.month, today.day - 1, 21, 40), 'Finished The Peregrine. Ana was right about the lamp book, it is next.'),
    entry('site-entry-3', DateTime(today.year, today.month, today.day - 3, 7, 55), 'First swim of the autumn. Cold, and worth it.'),
    entry('site-entry-4', DateTime(today.year, today.month, today.day - 9, 18, 30), 'Sam is in for the cabin weekend. Booking it Friday.'),
  ];
  final list = entries.map((e) => '- [[${RegExp(r'title: "([^"]+)"').firstMatch(e.body)!.group(1)}]]').join('\n');
  final book = Note(
    id: 'site-journal',
    body: '---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: "# {{date}}\\n\\n**{{time}}** "\n---\n# Diary\n\n$list\n',
    createdAt: seedNow - 20 * 86400000,
    updatedAt: seedNow - 600000,
  );
  return [book, ...entries];
}

/// The device's core, asked for nothing: every command is unanswered, as a test without the native library has it.
Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async => null;

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    usePluginGround(TestGround().ground);
    final registry = createRegistry(builtIn, store: MemorySwitches());
    for (final id in ['claude', 'calendar', 'github', 'webhooks', 'notion', 'lovart']) {
      registry.setEnabled(id, true);
    }
    usePlugins(registry);
  });

  tearDown(() {
    usePluginGround(PluginGround());
    usePlugins(createRegistry(const []));
    debugDefaultTargetPlatformOverride = null;
  });

  /// Time for the page to draw and settle: the machine's clock, then the test's.
  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The app over the seeded library and the test's own notes, on a phone or, [wide], a Mac's window.
  Future<AppShellState> open(WidgetTester tester, {bool wide = false}) async {
    if (wide) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final library = SampleLibrary.seeded();
    await tester.runAsync(() async {
      // Days old, so the home page's Recent cards stay the seed's own.
      await library.apply(Note(id: 'site-fields', body: fieldsBody, createdAt: seedNow - 5 * 86400000, updatedAt: seedNow - 4 * 86400000));
      await library.apply(Note(id: 'site-calendar', body: calendarBody, createdAt: seedNow - 5 * 86400000, updatedAt: seedNow - 4 * 86400000));
      for (final note in journal()) {
        await library.apply(note);
      }
    });
    await pumpApp(
      tester,
      size: wide ? const Size(960, 600) : const Size(390, 844),
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        core: core,
        library: library,
        stored: MemoryStored(),
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
      ),
    );
    // The site's shots have no phone's status bar over them, only a step above the app's bar; a window has none.
    final top = wide ? 0.0 : 20.0;
    tester.view.padding = FakeViewPadding(top: top);
    tester.view.viewPadding = FakeViewPadding(top: top);
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    return tester.state<AppShellState>(find.byType(AppShell));
  }

  Future<void> snap(WidgetTester tester, String name) async {
    Directory(out).createSync(recursive: true);
    await expectLater(find.byType(GhostApp), matchesGoldenFile('../../$out/$name.png'));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    // Put back before the test ends: the binding checks the foundation's switches then, ahead of any tearDown.
    debugDefaultTargetPlatformOverride = null;
  }

  /// The note [id] opened, and the page settled on it.
  Future<void> openNote(WidgetTester tester, AppShellState shell, String id) async {
    shell.openNote(id);
    await settle(tester, 10);
  }

  testWidgets('home', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await open(tester);
    await snap(tester, 'home');
  });

  testWidgets('desk', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await open(tester, wide: true);
    await snap(tester, 'desk');
  });

  for (final (name, id) in [('journal', 'site-journal'), ('board', 'launch'), ('fields', 'site-fields'), ('ticket', 'prd11'), ('table', 'open-tickets'), ('calendar', 'site-calendar')]) {
    testWidgets(name, (tester) async {
      if (!autoUpdateGoldenFiles) return;
      final shell = await open(tester);
      await openNote(tester, shell, id);
      await snap(tester, name);
    });
  }

  testWidgets('canvas', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    final shell = await open(tester);
    await openNote(tester, shell, 'cabin-canvas');
    // The whole canvas on the screen, as Shift+1 puts it, rather than at the camera's resting zoom.
    await tester.tap(find.bySemanticsLabel('Fit the whole canvas on the screen').first);
    await settle(tester, 8);
    await snap(tester, 'canvas');
  });

  testWidgets('query', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    final shell = await open(tester, wide: true);
    await openNote(tester, shell, 'sprint');
    await snap(tester, 'query');
  });

  testWidgets('plugins', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    final shell = await open(tester);
    shell.showMarket();
    await settle(tester, 10);
    await snap(tester, 'plugins');
  });
}
