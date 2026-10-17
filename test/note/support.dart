import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/place_tags.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/core_library.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/untouched.dart';
import 'package:ghost_md/core/versions_record.dart';
import 'package:ghost_md/core/versions_store.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/note/note_settings.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/page_dock.dart' show PageDockSeam;
import 'package:ghost_md/shell/screen.dart';
import 'package:ghost_md/shell/top_bar.dart';

import '../library/support.dart';
import '../notes/bar_support.dart' show appSheet;
import '../support/render.dart';

export '../library/support.dart' show FakeCore;
export '../notes/bar_support.dart' show notch;

/// What the web page measured (test/note/reference/note_reference.mjs), by the window's width.
Map<String, dynamic> webNote(int width) => jsonDecode(File('test/note/reference/note_$width.json').readAsStringSync()) as Map<String, dynamic>;

/// A rectangle the page measured, moved [down] by the test phone's notch.
Rect webRect(Object? rect, {double down = 0}) {
  final r = (rect! as Map).cast<String, dynamic>();
  return Rect.fromLTWH((r['x'] as num).toDouble(), (r['y'] as num).toDouble() + down, (r['w'] as num).toDouble(), (r['h'] as num).toDouble());
}

/// What a note's screen was opened over, and what it asked of the app.
class NoteWorld {
  NoteWorld({FakeCore? core, MemoryStored? device}) : device = device ?? MemoryStored() {
    final it = libraryOver(core);
    this.core = it.core;
    library = it.library;
    prefs = PreferencesStore()..startWithoutStorage();
    untouched = UntouchedNotes(kept: this.device);
    versions = VersionsRecord(store: VersionsStore(null, kept: this.device), preferences: prefs, workspaces: workspaces);
  }

  late final FakeCore core;
  late final CoreLibrary library;
  final MemoryStored device;
  late final PreferencesStore prefs;
  late final UntouchedNotes untouched;
  late final VersionsRecord versions;
  final WorkspaceStore workspaces = WorkspaceStore(storage: MemoryWorkspaceStorage());

  /// What the screen asked for, in order: `back`, `delete x`, `pin x true`, `archive x`, and what it said.
  final List<String> asked = [];
}

/// The seams as the web page had them filled when it was measured: every row of the More sheet there.
NoteSeams measuredSeams(List<String> asked) => NoteSeams(
      onShare: () => asked.add('share'),
      onFind: (view, initial) => asked.add('find "$initial"'),
      onComment: (view) => asked.add('comment'),
      bookmark: (view, page) => (marked: false, onPress: () => asked.add('bookmark')),
      onAi: (view, kind, [instruction]) => asked.add('ai $kind${instruction == null ? '' : ' $instruction'}'),
      sharing: (context) => const [
        SheetRow(icon: AppIcon(Lucide.share2, size: 18), label: 'Share a read-only link', hint: 'Sign in under Settings › Account first: a share is kept with your account.'),
      ],
      linked: (context) => [
        SheetRow(icon: const AppIcon(Lucide.share2, size: 18), label: 'Notion board', hint: 'Works in the Ghost.md app on your phone.', onPress: () {}, disabled: true),
        SheetRow(icon: const AppIcon(Lucide.share2, size: 18), label: 'GitHub repo', hint: 'A repo for this note: its list items can go there as issues, and the AI reads it for context.', onPress: () {}),
      ],
      cheatSheet: (context) => const SheetNote('The cheat sheet.'),
      location: (tag) => NoteLocation(tag: tag, onAdd: () => asked.add('locate'), onRemove: () => asked.add('unlocate')),
    );

/// A note's screen as the app draws it: [note] open in its tab in the app's shell on a window of [size], or, with
/// [bar] false, the screen alone with no bar over it. [dock] gives it the dock (lib/shell/page_dock.dart).
Future<NoteScreenState> pumpNote(
  WidgetTester tester,
  NoteWorld world,
  Note note, {
  Size size = const Size(390, 844),
  String theme = 'light',
  bool? mobile,
  bool? fine,
  String? at,
  Caret? caret,
  NoteSeams? seams,
  bool readOnly = false,
  PlaceTags? tags,
  bool speak = false,
  bool bar = true,
  Set<String> taken = const {},
  DateTime Function()? clock,
  Duration settle = const Duration(milliseconds: 500),
  PageDockSeam? dock,
}) async {
  final sheet = await appSheet(tester);
  Widget screen(Note open, {String? at, Caret? caret}) => NoteScreen(
        note: open,
        library: world.library,
        workspaces: world.workspaces,
        versions: world.versions,
        preferences: world.prefs,
        device: world.device,
        untouched: world.untouched,
        onBack: () => world.asked.add('back'),
        onDelete: (id) => world.asked.add('delete $id'),
        onPin: (pinned) => world.asked.add('pin ${pinned.id} ${pinned.starred}'),
        onArchive: (archived) => world.asked.add('archive ${archived.id}'),
        onSpeak: speak ? (id) => world.asked.add('speak $id') : null,
        at: at,
        caret: caret,
        readOnly: readOnly,
        tags: tags,
        takenTitles: taken,
        clock: clock,
        seams: seams ?? const NoteSeams(),
        say: (message) => world.asked.add('say $message'),
        lifecycle: false,
        dock: dock,
      );
  await pumpApp(
    tester,
    size: size,
    prefs: Preferences(theme: theme),
    home: bar
        ? AppShell(
            sheet: sheet,
            notes: [note],
            workspaces: world.workspaces.value,
            topBar: TopBarStyle.classic,
            openNotes: [note.id],
            mobile: mobile ?? size.width < 600,
            finePointer: fine ?? size.width >= 600,
            initialScreen: Screen.note(note, at: at, caret: caret),
            // A wide window has the side panel's toggle at the bar's end, as the page measured has (its history).
            asideBuilder: size.width >= 600 ? (context, shell) => const SizedBox.shrink() : null,
            noteBuilder: (context, shell, open) => screen(open.note, at: open.at, caret: open.caret),
          )
        : screen(note, at: at, caret: caret),
  );
  await tester.pump();
  await tester.pump(settle);
  return tester.state<NoteScreenState>(find.byType(NoteScreen));
}

/// A note the library holds, with [body]. Call it inside `tester.runAsync`.
Future<Note> seedNote(NoteWorld world, String id, String body) => world.library.createNote(body, id: id);

/// The screen taken down, so its saving's last words are written and its timers are done.
Future<void> closeNote(WidgetTester tester) async {
  // Out of the note first: taken down in one go with the shell, the screen's tools are handed back to a bar that is
  // already gone (shell/top_bar_tools.dart clears a frame after the screen goes).
  final shell = find.byType(AppShell);
  if (shell.evaluate().isNotEmpty) {
    tester.state<AppShellState>(shell).backToList();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  // [pumpApp] turned the shadows on, and the binding checks its switch as a test ends.
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
