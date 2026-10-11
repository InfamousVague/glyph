import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/notes/tabs/tab_parts.dart';
import 'package:ghost_md/notes/tabs/tab_row.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/app_tab_bar.dart';
import 'package:ghost_md/shell/placeholders.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../notes/bar_support.dart';
import '../support/render.dart';

/// A note with no words yet (lib/core/core_library.dart `isDraft`) is its own screen's alone, as on the page, whose
/// list never holds one: seen beside the Tauri app on a phone, a new note has no tab and its page starts a row of
/// tabs higher until its first words are kept.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('a draft is shown on its own screen with no tab, in no list, and takes its tab with its first words', (tester) async {
    final sheet = await appSheet(tester);
    final notes = <Note>[makeNote('fresh', body: ''), ...library];
    final drafts = ValueNotifier<Set<String>>({'fresh'});
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: ValueListenableBuilder<Set<String>>(
        valueListenable: drafts,
        builder: (context, now, _) => AppShell(sheet: sheet, notes: notes, drafts: now, workspaces: spaces, backStack: BackStack()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final app = tester.state<AppShellState>(find.byType(AppShell));
    String? stamp() => tester.element(find.byType(AppTabBar)).tokens.attrs['tabs'];

    expect(ids(app.notes), isNot(contains('fresh')), reason: 'no list holds it');
    app.openNote('fresh');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.screen.noteOnScreen, 'fresh');
    expect(find.byType(NotePlaceholder), findsOneWidget);
    // Open, and remembered as open, with nothing drawn for it: the bar is one line tall.
    expect(app.tabs.open, ['fresh']);
    expect(find.byType(NoteTab), findsNothing);
    expect(find.byType(TabRow), findsNothing);
    expect(stamp(), 'on');

    // Its first words are kept: it is a note like any other.
    drafts.value = const {};
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(NoteTab), findsOneWidget);
    expect(stamp(), 'rows');
    expect(ids(app.notes), contains('fresh'));
    await away(tester);
    drafts.dispose();
  });
}
