// What Wrapped's tests share (docs/WRAPPED.md): an invented library of a year's notes in a few folders and an
// organization's, and a scripted AI that answers by the refs it is shown, never a real one. Nobody in it is real.
import 'dart:convert';

import 'package:ghost_md/core/library_config.dart' show MemoryConfigFile;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/plugins/cleanup/cleanup.dart' show CleanupAi;
import 'package:ghost_md/plugins/wrapped/wrapped.dart';

import '../cleanup/support.dart' show Asked, scriptedAi;

export '../cleanup/support.dart' show Asked, scriptedAi;

/// 2026-11-05, 12:00 local.
final DateTime wrappedNow = DateTime(2026, 11, 5, 12);

int at(int year, int month, int day, [int hour = 9]) => DateTime(year, month, day, hour).millisecondsSinceEpoch;

Note wrappedNote(String id, String body, {required int written, int? edited, int? archivedAt, NoteSource source = NoteSource.editor, int revision = 1}) =>
    Note(id: id, body: body, createdAt: written, updatedAt: edited ?? written, archivedAt: archivedAt, source: source, revision: revision);

/// The notes: a March streak of three days, a busy Tuesday morning in May, a meeting, a recording, a note linked by
/// two others, tags, to-dos done and open, last year's long forgotten recipe, a stale empty draft, an exact copy, and
/// the organization's note.
List<Note> wrappedNotes() => [
      wrappedNote('trip', '# Coast trip\n\nPacking for the coast. See [[Packing list]].\n\n- [ ] Book the ferry\n- [x] Ask Sam for the tent #travel', written: at(2026, 3, 2), edited: at(2026, 3, 3)),
      wrappedNote('packing', '# Packing list\n\n- [ ] Boots\n- [ ] Rain coat\n- [x] Map', written: at(2026, 3, 3, 10)),
      wrappedNote('menu', '# Spring menu\n\nCall with the Kiln shop about prices. #work\n\n- [ ] Send the draft menu', written: at(2026, 3, 4), edited: at(2026, 3, 4)),
      wrappedNote('standup', '# Standup\n\nShipped the reading view, then the map and the sync fixes for the release.\n\n- [x] Fix sync', written: at(2026, 5, 5, 9)),
      wrappedNote('standup-copy', '# Standup (copy)\n\nShipped the reading view, then the map and the sync fixes for the release.\n\n- [x] Fix sync', written: at(2026, 5, 5, 9)),
      wrappedNote('meeting', '---\nmeeting: weekly\n---\n# Weekly sync\n\nWe agreed the release is on Monday. See [[Packing list]].', written: at(2026, 5, 12, 9)),
      wrappedNote('voice', '# A thought on the walk\n\nThe garden needs a path along the fence.', written: at(2026, 6, 1, 18), source: NoteSource.capture),
      wrappedNote('draft', '# Draft\n', written: at(2025, 1, 10), edited: at(2025, 1, 10)),
      wrappedNote(
        'recipe',
        '# Grandma’s soup\n\n${List.filled(14, 'Slow cooked onions with thyme, then the stock, then the beans, simmered for an hour.').join(' ')}',
        written: at(2024, 10, 1),
        edited: at(2024, 10, 2),
      ),
      wrappedNote('team', '# Team goals\n\n- [ ] Hire a designer', written: at(2026, 4, 1)),
    ];

const OrgLike wrappedOrg = OrgLike(id: 'o1', name: 'Ghost.md', hue: 'sea');

/// The library, the folders and the Trash: Travel and Work, and the organization's workspace with its note.
class WrappedWorld {
  WrappedWorld({List<Note>? notes}) : library = SampleLibrary(notes ?? wrappedNotes(), clock: () => wrappedNow.millisecondsSinceEpoch) {
    workspaces.ensureOrgWorkspace(wrappedOrg);
    workspaces.fileNote('trip', 'travel');
    workspaces.fileNote('menu', 'work');
    workspaces.fileNote('standup', 'work');
    workspaces.fileNote('team', 'org-o1');
  }

  final SampleLibrary library;
  final MemoryTrash trash = MemoryTrash();
  late final WorkspaceStore workspaces = WorkspaceStore(
    storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [
      Workspace(id: 'travel', name: 'Travel'),
      Workspace(id: 'work', name: 'Work'),
    ])),
    trash: trash,
  );
  final MemoryConfigFile file = MemoryConfigFile();

  WrappedService service({List<CleanupAi>? ais, WrappedPacing pacing = testPacing, bool Function()? busy, List<Duration>? waited, bool on = true, WrappedStore? store}) => WrappedService(
        library: library,
        workspaces: workspaces,
        trash: trash,
        store: store ?? WrappedStore(file: file),
        on: () => on,
        ais: () async => ais ?? const [],
        clock: () => wrappedNow,
        busy: busy ?? () => false,
        pacing: pacing,
        wait: (d) async => waited?.add(d),
        contradictions: () => null,
      );
}

/// Two notes an ask, a second between, so a test counts the asks.
const WrappedPacing testPacing = WrappedPacing(notesPerAsk: 2, charsPerNote: 300, gap: Duration(seconds: 1), busyCheck: Duration(seconds: 5));

/// The refs a read prompt gives its notes, by title: `“Standup” → n1`.
Map<String, String> readRefs(String prompt) => {
      for (final m in RegExp(r'^\[(n\d+)\] (?:“(.*)”|\(no title\)) ·', multiLine: true).allMatches(prompt)) m.group(2) ?? '(no title)': m.group(1)!,
    };

/// The refs the library prompt gives its folders, by path.
Map<String, String> folderRefsOf(String prompt) => {
      for (final m in RegExp(r'^- (f\d+): (.+)$', multiLine: true).allMatches(prompt)) m.group(2)!: m.group(1)!,
    };

/// A scripted AI: each note's gist is "About <title>", Draft is stale, the soup a gem; the library's answer puts the
/// menu's sync note into Work, the walk into a new Garden folder, and links the trip to the meeting.
CleanupAi fakeAi({List<Asked>? asked, String id = 'claude', String name = 'Claude'}) => scriptedAi((system, prompt) {
      final refs = readRefs(prompt);
      if (system.startsWith('You read')) {
        return jsonEncode({
          'notes': [
            for (final MapEntry(key: title, value: ref) in refs.entries)
              {'ref': ref, 'gist': 'About $title', 'themes': [title.contains('Standup') ? 'work' : 'life'], 'stale': title == 'Draft', 'why': title == 'Draft' ? 'An empty draft' : '', 'gem': title == 'Grandma’s soup'},
          ],
        });
      }
      final f = folderRefsOf(prompt);
      return jsonEncode({
        'themes': ['Travel plans', 'Work releases', 'Home'],
        'moves': [
          {'note': refs['Weekly sync'], 'to': f['Work'], 'why': 'A work meeting'},
        ],
        'folders': [
          {'name': 'Garden', 'parent': null, 'notes': [refs['A thought on the walk']], 'why': 'Garden ideas'},
        ],
        'links': [
          {'from': refs['Coast trip'], 'to': refs['Weekly sync'], 'why': 'Both about Monday'},
        ],
        'gems': [refs['Grandma’s soup']],
      });
    }, id: id, name: name, asked: asked);
