import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note_marks.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/icon_browser.dart';
import 'package:ghost_md/orgs/ui/organization_screen.dart';

import '../orgs_ui/support.dart' show Device, ghost;
import '../support/render.dart';
import 'support.dart';

/// Pictures of the folders above the lists and the icon view (GHST-107), at a phone's size (390 x 844) and a wide
/// window's (1200 x 800), in the light and in the dark, written to build/feature-shots/organize/folders-*.png to be
/// looked at (test/organize/support.dart `snap`), not held as goldens.
void main() {
  setUpAll(loadAppFonts);
  setUp(NoteMarks.debugForget);

  const phone = Size(390, 844);
  const wide = Size(1200, 800);

  Future<void> page(WidgetTester tester, Widget child, {required Size size, required String theme}) async {
    await pumpApp(tester, size: size, ratio: 2, prefs: AppPreferences(theme: theme), home: BackScope(child: child));
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }

  WorkspaceStore spaces(String chosen) => WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()))..chooseWorkspace(chosen);

  for (final (size, sized) in [(phone, 'phone'), (wide, 'wide')]) {
    for (final theme in ['light', 'dark']) {
      testWidgets('home with Home chosen: Garden in its hue above the sections, $sized $theme', (tester) async {
        await page(
          tester,
          HomeScreen(notes: organizeNotes(), workspaces: spaces('home'), onOpen: (_) {}, onNew: () {}, onAllNotes: () {}, onSearch: () {}, clock: () => organizeNow, onNewFolder: (_) {}),
          size: size,
          theme: theme,
        );
        expect(find.byKey(const ValueKey('home-folders')), findsOneWidget);
        await snap(tester, 'folders-home-$sized-$theme');
      });

      testWidgets('All notes with Clients chosen: the strip under the order words, and where it is above, $sized $theme', (tester) async {
        await page(
          tester,
          AllNotesScreen(notes: organizeNotes(), workspaces: spaces('clients'), onOpen: (_) {}, onBack: () {}, stored: MemoryStored(), clock: () => organizeNow, wisp: false, onNewFolder: (_) {}),
          size: size,
          theme: theme,
        );
        expect(find.byKey(const ValueKey('folder-strip')), findsOneWidget);
        await snap(tester, 'folders-allnotes-cards-$sized-$theme');
      });

      testWidgets('All notes as icons with Work chosen: Clients first, then its notes, $sized $theme', (tester) async {
        await page(
          tester,
          AllNotesScreen(
            notes: organizeNotes(),
            workspaces: spaces('work'),
            onOpen: (_) {},
            onBack: () {},
            stored: MemoryStored()..writeText(browseViewKey, 'icons'),
            clock: () => organizeNow,
            wisp: false,
            onNewFolder: (_) {},
          ),
          size: size,
          theme: theme,
        );
        expect(find.byKey(const ValueKey('all-notes-icons')), findsOneWidget);
        await snap(tester, 'folders-allnotes-icons-$sized-$theme');
      });

      testWidgets('All notes as icons at All: the workspaces at the top first, then every note, $sized $theme', (tester) async {
        final store = WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()))..ensureOrgWorkspace(const OrgLike(id: 'acme', name: 'Acme', hue: 'violet'));
        store.fileNote('trip', 'org-acme');
        await page(
          tester,
          AllNotesScreen(
            notes: organizeNotes(),
            workspaces: store,
            onOpen: (_) {},
            onBack: () {},
            stored: MemoryStored()..writeText(browseViewKey, 'icons'),
            clock: () => organizeNow,
            wisp: false,
            onNewFolder: (_) {},
          ),
          size: size,
          theme: theme,
        );
        expect(find.byKey(const ValueKey('tile-folder-org-acme')), findsOneWidget);
        await snap(tester, 'folders-allnotes-icons-all-$sized-$theme');
      });

      testWidgets('an organization’s dashboard as icons, $sized $theme', (tester) async {
        final device = await Device.make();
        final id = await ghost(device);
        final notes = [
          device.keep('launch', '# Launch plan\n\nThe week of the 2nd.', at: organizeNow - 3600000),
          device.keep('press', '# Press list\n\n- [ ] The Verge', at: organizeNow - 7200000),
          device.keep('retro', '# Retro notes\n\nWhat went well.', at: organizeNow - 86400000),
        ];
        for (final note in notes) {
          device.workspaces.fileNote(note.id, orgWorkspaceId(id));
        }
        device.kept.writeText(browseViewKey, 'icons');
        await device.pump(
          tester,
          OrganizationScreen(
            services: device.services,
            orgId: id,
            notes: notes,
            wisp: false,
            now: () => organizeNow,
            onBack: () {},
            onOpenNote: (_) {},
            onNew: () {},
            onAllNotes: (_) {},
            onSettings: () {},
            onOpenOrganization: (_) {},
            onLog: () {},
            onAccount: () {},
            onNewFolder: (_) {},
          ),
          size: size,
          scroll: false,
          dark: theme == 'dark',
        );
        expect(find.byKey(const ValueKey('org-notes-icons')), findsOneWidget);
        await snap(tester, 'folders-dashboard-$sized-$theme');
      });
    }
  }
}
