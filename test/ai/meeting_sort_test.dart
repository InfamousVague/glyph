// Meetings sorted into workspaces by the AI (lib/ai/meeting_sort.dart): the question the AI is asked, how its answer
// is read back to a workspace, which meetings are the sorting's to file, and the filing itself, into the chosen
// workspace's Meetings folder, an organization's included. The AI is a function that answers what the case says.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/meeting_sort.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/workspaces.dart';

const body = '# Tidepool Series A planning\n\n## Summary\nThe round, the deck and who to call.\n\n- [ ] Send the deck to Ana.\n\n'
    '## Transcript\n\n**Ana Ruiz:** Where is the deck?\n\n**Matt:** Friday.\n\n**Ana Ruiz:** Good.';

Note note(String id, String text) => Note(id: id, body: text, createdAt: 0, updatedAt: 0, revision: 1);

void main() {
  const candidates = [
    SortCandidate(id: 'w-ghost1', label: 'Ghost.md', titles: ['Roadmap']),
    SortCandidate(id: 'org-o1', label: 'HelloTrade'),
    SortCandidate(id: 'w-clien1', label: 'HelloTrade › Clients'),
  ];

  group('the question', () {
    test('names the meeting, who spoke, its summary, and every workspace with its id and notes', () {
      final message = meetingSortMessage(title: 'Tidepool Series A planning', attendees: attendeesOf(body), summary: 'The round.', candidates: candidates);
      expect(message, contains('Title: Tidepool Series A planning'));
      expect(message, contains('Attendees: Ana Ruiz, Matt'));
      expect(message, contains('Summary:\nThe round.'));
      expect(message, contains('- id: w-ghost1\n  name: Ghost.md\n  notes: "Roadmap"'));
      expect(message, contains('- id: w-clien1\n  name: HelloTrade › Clients'));
      expect(meetingSortPrompt, contains('{"workspace":"none"}'));
    });

    test('reads who spoke from the transcript, else from the kept captions', () {
      expect(attendeesOf(body), ['Ana Ruiz', 'Matt']);
      expect(attendeesOf('# Call\n\n## Captions\n\n**Sam (0:01):** Hello.\n\n**Lee (0:04):** Hi.'), ['Sam', 'Lee']);
      expect(attendeesOf('# Nothing'), isEmpty);
    });

    test('offers the top workspaces and the folders directly inside them, never a Meetings folder', () {
      final store = WorkspaceStore();
      final ghost = store.addWorkspace('Ghost.md')!;
      final org = store.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'HelloTrade'));
      final clients = store.addWorkspace('Clients', 'ink', org.id)!;
      store.addWorkspace('Acme', 'ink', clients.id);
      store.addWorkspace('Meetings', 'ink', ghost.id);
      store.fileNote('n9', ghost.id);
      final offered = sortCandidates(store.value.list, titlesIn: (id) => id == ghost.id ? ['Roadmap', '', 'Launch', 'Pricing', 'More'] : const []);
      expect([for (final c in offered) c.label], ['Ghost.md', 'HelloTrade', 'HelloTrade › Clients']);
      expect(offered.first.titles, ['Roadmap', 'Launch', 'Pricing']);
    });
  });

  group('the answer', () {
    test('an exact id', () => expect(readMeetingSort('{"workspace":"w-ghost1","confident":true}', candidates), 'w-ghost1'));
    test('in a fence, after thinking', () => expect(readMeetingSort('<think>hm</think>```json\n{"workspace": "org-o1"}\n```', candidates), 'org-o1'));
    test('a name, or a path, in any case', () {
      expect(readMeetingSort('{"workspace":"ghost.md"}', candidates), 'w-ghost1');
      expect(readMeetingSort('{"workspace":"HelloTrade › Clients"}', candidates), 'w-clien1');
      expect(readMeetingSort('{"workspace":"Clients"}', candidates), 'w-clien1');
    });
    test('a bare id with no JSON', () => expect(readMeetingSort('w-ghost1', candidates), 'w-ghost1'));
    test('none', () {
      expect(readMeetingSort('{"workspace":"none"}', candidates), isNull);
      expect(readMeetingSort('none', candidates), isNull);
    });
    test('not sure', () => expect(readMeetingSort('{"workspace":"w-ghost1","confident":false}', candidates), isNull));
    test('an id that was not offered', () => expect(readMeetingSort('{"workspace":"w-zzzzzz"}', candidates), isNull));
    test('rubbish', () {
      expect(readMeetingSort('I think it might be about fundraising.', candidates), isNull);
      expect(readMeetingSort('{"workspace": 3}', candidates), isNull);
      expect(readMeetingSort('', candidates), isNull);
    });
  });

  group('which meetings are sorted', () {
    const space = Workspace(id: 'w-ghost1', name: 'Ghost.md');
    test('an unfiled one, once, and only with the switch on', () {
      final prefs = Preferences.defaults;
      expect(sortsMeetings(prefs), isTrue);
      expect(sortable(prefs, 'n1', null), isTrue);
      expect(sortable(withSorted(prefs, 'n1', null), 'n1', null), isFalse);
      expect(sortable(withSortMeetings(prefs, false), 'n1', null), isFalse);
    });

    test('one the app filed, while it stays there; never one the person filed', () {
      final prefs = Preferences.defaults;
      expect(sortable(prefs, 'n1', space), isFalse);
      final app = withAppFiled(prefs, 'n1', space.id);
      expect(sortable(app, 'n1', space), isTrue);
      expect(sortable(app, 'n1', const Workspace(id: 'w-other1', name: 'Other')), isFalse);
      // Sorted, the app's mark is not put back.
      expect(withAppFiled(withSorted(prefs, 'n1', null), 'n1', space.id).more[meetingSortsKey], {'n1': {'sorted': ''}});
    });
  });

  group('the filing', () {
    late WorkspaceStore store;
    late Preferences prefs;
    late Map<String, Note> notes;
    late List<String> asked;
    late String answer;
    late List<(String, String)> said;

    MeetingSorter sorter() => MeetingSorter(
          workspaces: store,
          preferences: () => prefs,
          setPreferences: (change) => prefs = change(prefs),
          getNote: (id) async => notes[id],
          ask: (system, prompt) async {
            asked.add(prompt);
            return answer;
          },
          filed: (title, where) => said.add((title, where)),
        );

    setUp(() {
      store = WorkspaceStore();
      prefs = Preferences.defaults;
      notes = {'n1': note('n1', body)};
      asked = [];
      said = [];
    });

    test('files an unfiled meeting in its workspace’s Meetings folder, made for it, and says so', () async {
      final ghost = store.addWorkspace('Ghost.md')!;
      answer = '{"workspace":"${ghost.id}","confident":true}';
      final folder = await sorter().meetingSummarized('n1', body);
      expect(folder?.name, 'Meetings');
      expect(folder?.parent, ghost.id);
      expect(store.workspaceOf('n1')?.id, folder?.id);
      expect(said, [('Tidepool Series A planning', 'Ghost.md › Meetings')]);
      expect(asked.single, contains('The round, the deck and who to call.'));
      expect(prefs.more[meetingSortsKey], {'n1': {'sorted': folder?.id}});
    });

    test('uses the Meetings folder already there', () async {
      final ghost = store.addWorkspace('Ghost.md')!;
      final meetings = store.addWorkspace('meetings', 'sea', ghost.id)!;
      answer = '{"workspace":"${ghost.id}"}';
      expect((await sorter().meetingSummarized('n1', body))?.id, meetings.id);
      expect(store.value.list.where((w) => w.parent == ghost.id), hasLength(1));
    });

    test('an organization’s workspace gets an org-<id> › Meetings folder', () async {
      final org = store.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'HelloTrade'));
      answer = '{"workspace":"org-o1"}';
      final folder = await sorter().meetingSummarized('n1', body);
      expect(folder?.parent, org.id);
      expect(orgOfWorkspace(store.value.list, folder!.id), 'o1');
      expect(store.workspaceOf('n1')?.id, folder.id);
    });

    test('moves one the app filed, but never one the person filed', () async {
      final ghost = store.addWorkspace('Ghost.md')!;
      final home = store.addWorkspace('Home')!;
      answer = '{"workspace":"${ghost.id}"}';
      store.fileNote('n1', home.id);
      expect(await sorter().meetingSummarized('n1', body), isNull);
      expect(store.workspaceOf('n1')?.id, home.id);
      expect(asked, isEmpty);
      prefs = withAppFiled(prefs, 'n1', home.id);
      expect((await sorter().meetingSummarized('n1', body))?.parent, ghost.id);
    });

    test('runs once: a second summary asks nothing, though the person moved it back', () async {
      final ghost = store.addWorkspace('Ghost.md')!;
      answer = '{"workspace":"${ghost.id}"}';
      final s = sorter();
      await s.meetingSummarized('n1', body);
      store.fileNote('n1', null);
      expect(await s.meetingSummarized('n1', body), isNull);
      expect(asked, hasLength(1));
      expect(store.workspaceOf('n1'), isNull);
    });

    test('leaves it, remembered, when the AI is not sure or says none', () async {
      store.addWorkspace('Ghost.md');
      answer = '{"workspace":"none"}';
      expect(await sorter().meetingSummarized('n1', body), isNull);
      expect(store.workspaceOf('n1'), isNull);
      expect(prefs.more[meetingSortsKey], {'n1': {'sorted': ''}});
      expect(store.value.list.map((w) => w.name), ['Ghost.md']);
    });

    test('does nothing with the switch off', () async {
      final ghost = store.addWorkspace('Ghost.md')!;
      answer = '{"workspace":"${ghost.id}"}';
      prefs = withSortMeetings(prefs, false);
      expect(await sorter().meetingSummarized('n1', body), isNull);
      expect(asked, isEmpty);
      expect(store.workspaceOf('n1'), isNull);
    });

    test('an AI that cannot answer leaves it unremembered, to ask again', () async {
      store.addWorkspace('Ghost.md');
      final s = MeetingSorter(workspaces: store, preferences: () => prefs, setPreferences: (change) => prefs = change(prefs), getNote: (id) async => notes[id], ask: (_, _) async => null);
      expect(await s.meetingSummarized('n1', body), isNull);
      expect(prefs.more[meetingSortsKey], isNull);
    });

    test('filed by the person while the AI thought, it stays', () async {
      final ghost = store.addWorkspace('Ghost.md')!;
      final home = store.addWorkspace('Home')!;
      final s = MeetingSorter(
        workspaces: store,
        preferences: () => prefs,
        setPreferences: (change) => prefs = change(prefs),
        getNote: (id) async => notes[id],
        ask: (_, _) async {
          store.fileNote('n1', home.id);
          return '{"workspace":"${ghost.id}"}';
        },
      );
      expect(await s.meetingSummarized('n1', body), isNull);
      expect(store.workspaceOf('n1')?.id, home.id);
    });
  });
}
