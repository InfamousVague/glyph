// What the index tests share: a scripted AI (no real one is ever asked) and a folder of notes.
import 'dart:convert';

import 'package:ghost_md/ai/indexes/index_ai.dart';
import 'package:ghost_md/core/note.dart';

/// An AI that answers every note it is sent about with its own title, and records what it was sent.
class ScriptedAi implements IndexAi {
  ScriptedAi({this.onDevice = false, this.name = 'Claude', this.extra = const []});

  @override
  final bool onDevice;
  @override
  final String name;

  /// More items to put in each answer: a made-up number, a link, a bad date.
  final List<Map<String, Object?>> extra;
  final List<String> prompts = [];
  bool cancelled = false;

  @override
  Future<String> ask({required String system, required String prompt, required int maxTokens}) async {
    prompts.add(prompt);
    if (system == overviewSystem) return 'A folder about **the launch**: plans, meetings and [[Secret]] decisions.';
    final titles = [for (final m in RegExp(r'^### Note (\d+): (.*) \(\d{4}-\d{2}-\d{2}\)$', multiLine: true).allMatches(prompt)) m.group(2)!];
    return jsonEncode([
      for (var i = 0; i < titles.length; i += 1)
        {
          'n': i + 1,
          'about': 'About ${titles[i]}',
          'theme': titles[i].startsWith('Standup') ? 'Meetings' : 'Planning',
          'decisions': [
            if (titles[i] == 'Sync rewrite') {'date': '2026-10-28', 'what': 'Move sync to the new server'},
          ],
        },
      ...extra,
    ]);
  }

  /// The note titles each batch was sent.
  List<String> get sent => [for (final p in prompts) ...RegExp(r'^### Note \d+: (.*) \(', multiLine: true).allMatches(p).map((m) => m.group(1)!)];

  @override
  void cancel() => cancelled = true;
}

Note note(String id, String path, String body, {int at = 1000}) => Note(id: id, body: body, createdAt: at, updatedAt: at, path: path);

final DateTime t0 = DateTime.utc(2026, 11, 2, 10);
int ms(DateTime at) => at.millisecondsSinceEpoch;

List<Note> launchNotes({int at = 0}) => [
      note('a', 'workspaces/Launch/Roadmap.md', '---\nauthors: alice\n---\n# Roadmap\nThe three bets.', at: at == 0 ? ms(t0) - 5000 : at),
      note('b', 'workspaces/Launch/Sync rewrite.md', '---\nowner: bob\n---\n# Sync rewrite\nWe decided to move sync.', at: at == 0 ? ms(t0) - 4000 : at),
      note('c', 'workspaces/Launch/Meetings/Standup 2026-11-01.md', '---\nassignee: "@alice"\n---\n# Standup 2026-11-01\nThe sync bug.', at: at == 0 ? ms(t0) - 3000 : at),
    ];

