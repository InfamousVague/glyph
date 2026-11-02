// The notes the Ask tests read (docs/ASK_THE_ORG.md): two standups of HelloTrade's that disagree about the launch
// day, a personal note that says something else again, a note in another organization, and a folder inside
// HelloTrade's workspace. And a scripted model, which answers what it is told to and never reaches a network.
import 'dart:async';

import 'package:ghost_md/ask/ask_model.dart';
import 'package:ghost_md/ask/ask_retrieve.dart';
import 'package:ghost_md/ask/ask_scope.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/workspaces.dart';

const int day = 24 * 3600 * 1000;
final int oct27 = DateTime(2026, 10, 27, 9).millisecondsSinceEpoch;
final int oct29 = DateTime(2026, 10, 29, 9).millisecondsSinceEpoch;
final int nov2 = DateTime(2026, 11, 2, 12).millisecondsSinceEpoch;

Note note(String id, String body, {int? at, String? path, int? archivedAt}) => Note(id: id, body: body, createdAt: at ?? oct27, updatedAt: at ?? oct27, path: path, archivedAt: archivedAt);

final Note standup27 = note('s27', '''---
tags: [standup]
---
# Standup Oct 27

## Launch
- We ship on Thursday, after the store review.
- Ana owns the release notes.

## Hiring
- Two interviews this week.
''', at: oct27);

final Note standup29 = note('s29', '''# Standup Oct 29

## Launch
- The store review slipped, so the launch is now Monday.
- See [[Standup Oct 27]] for the old plan.
''', at: oct29);

final Note clientMeeting = note('m1', '''# Acme kickoff

Acme wants the dashboard by December.
Their contact is Priya.
''', at: oct29);

final Note mine = note('p1', '''# Groceries

- Eggs, milk, the launch party cake for Thursday.
''', at: oct29);

final Note otherOrg = note('x1', '''# Other team standup

## Launch
- Our launch is Friday.
''', at: oct29);

final Note archived = note('a1', '''# Old launch

The launch is in March.
''', at: oct27, archivedAt: oct29);

const Workspace helloTrade = Workspace(id: 'org-o1', name: 'HelloTrade');
const Workspace meetings = Workspace(id: 'w-meet', name: 'Meetings', parent: 'org-o1');
const Workspace otherTeam = Workspace(id: 'org-o2', name: 'Other');
const Workspace home = Workspace(id: 'w-home', name: 'Home');

final Workspaces workspaces = Workspaces(
  list: const [helloTrade, meetings, otherTeam, home],
  of: const {'s27': 'org-o1', 's29': 'org-o1', 'm1': 'w-meet', 'x1': 'org-o2', 'p1': 'w-home', 'a1': 'org-o1'},
);

final List<Note> library = [standup27, standup29, clientMeeting, mine, otherOrg, archived];
final AskWorld world = AskWorld.of(workspaces);
const AskScope helloScope = AskScope.org('o1', 'HelloTrade');

/// A model that answers [said] (or what [answer] makes of the prompt), and remembers what it was sent.
class ScriptedModel implements AskModel {
  ScriptedModel(this.said, {this.onDevice = false, this.name = 'Claude', this.answer});

  String said;
  final String Function(String prompt)? answer;
  @override
  final bool onDevice;
  @override
  final String name;
  final List<String> prompts = [];
  final List<String> systems = [];
  Completer<String>? held;

  @override
  AskBudget get budget => onDevice ? AskBudget.device : AskBudget.cloud;

  @override
  AskCall complete({required String system, required String prompt}) {
    systems.add(system);
    prompts.add(prompt);
    final held = this.held;
    return (done: held != null ? held.future : Future.value(answer?.call(prompt) ?? said), cancel: () {});
  }
}

/// The disagreement the standups hold, as a good model would answer it.
const String launchAnswer = '''```json
{"notFound": false,
 "sentences": [{"text": "Ana owns the release notes.", "citations": [{"noteId": "s27", "fromLine": 8, "toLine": 8, "quote": "Ana owns the release notes"}]}],
 "conflicts": [{"about": "The launch day", "sides": [
   {"text": "Thursday", "citation": {"noteId": "s27", "fromLine": 7, "toLine": 7, "quote": "We ship on Thursday"}},
   {"text": "Monday", "citation": {"noteId": "s29", "fromLine": 4, "toLine": 4, "quote": "the launch is now Monday"}}
 ]}]}
```''';
