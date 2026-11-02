// Self-maintaining indexes (docs/AI_INDEXES.md; Matt, 2026-11-02: "the AI keeps an index note (what's here, the key
// decisions, who owns what) and updates it as notes change"). No real AI is asked: a scripted one answers.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/indexes/index_ai.dart';
import 'package:ghost_md/ai/indexes/index_build.dart';
import 'package:ghost_md/ai/indexes/index_keeper.dart';
import 'package:ghost_md/ai/indexes/index_scope.dart';
import 'package:ghost_md/ai/indexes/index_section.dart';
import 'package:ghost_md/core/background_jobs.dart';
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

void main() {
  group('the section', () {
    test('only the fenced section is rewritten; the person’s words before and after stay byte for byte', () {
      const before = '---\nindex: on\n---\n# Launch\n\nRead me first.  \nTrailing spaces kept.\n\n';
      const after = '\n\n## My own notes\n- keep this\n';
      final page = '$before<!-- ghost:index updated=2026-11-01T00:00:00Z by=Claude -->\nold words\n<!-- /ghost:index -->$after';
      final next = withSection(page, renderSection(const IndexContent(overview: 'New.'), updated: t0, by: 'Claude'))!;
      expect(next.startsWith(before), isTrue);
      expect(next.endsWith(after), isTrue);
      expect(next, isNot(contains('old words')));
      expect(next, contains('New.'));
      expect(readSection(next).span!.updated, t0);
    });

    test('a page with no section gets it after its words; a page whose end marker is gone is left alone', () {
      final added = withSection('# Plan\n\nMine.\n', renderSection(const IndexContent(), updated: t0, by: 'Claude'))!;
      expect(added, startsWith('# Plan\n\nMine.\n\n<!-- ghost:index'));
      expect(withSection('# Plan\n<!-- ghost:index updated=x -->\nhalf deleted', 'x'), isNull);
    });

    test('rendered and read back, the AI’s parts are the same', () {
      const content = IndexContent(
        overview: 'What it is.',
        entries: [IndexEntry(title: 'Roadmap', theme: 'Planning', about: 'The bets'), IndexEntry(title: 'Standup', theme: 'Meetings', about: '')],
        decisions: [IndexDecision(date: '2026-10-28', what: 'Move sync', title: 'Sync rewrite')],
        owners: {'alice': ['Roadmap']},
        recent: [('Roadmap', '2026-11-01')],
      );
      final inner = readSection(renderSection(content, updated: t0, by: 'On this device')).span!;
      expect(inner.by, 'On this device');
      final back = parseSection(inner.inner);
      expect(back.overview, 'What it is.');
      expect([for (final e in back.entries) (e.title, e.theme, e.about)], [('Roadmap', 'Planning', 'The bets'), ('Standup', 'Meetings', '')]);
      expect([for (final d in back.decisions) (d.date, d.what, d.title)], [('2026-10-28', 'Move sync', 'Sync rewrite')]);
    });

    test('the settings are the page’s front matter', () {
      final body = const IndexSettings(on: true, every: IndexEvery.nightly, by: 'dev1', byName: 'Mac').writeInto('# Launch\n');
      final read = IndexSettings.of(body);
      expect((read.on, read.every, read.by, read.byName), (true, IndexEvery.nightly, 'dev1', 'Mac'));
      expect(IndexSettings.of(const IndexSettings().writeInto(body)).on, isFalse);
    });
  });

  group('the answers', () {
    test('an item about a number not sent, with no one-liner or a bad date is dropped; links and markers are taken out', () {
      final facts = readNoteFacts(
          'Sure! [{"n":1,"about":"See [[Secret plan]] <!-- x -->","theme":"## Plans","decisions":[{"date":"Oct 3","what":"x"},{"date":"2026-10-03","what":"Ship it"}]},'
          '{"n":7,"about":"made up","theme":"x"},{"n":2,"about":"","theme":"x"},{"n":1,"about":"twice","theme":"x"}]',
          2);
      expect(facts, hasLength(1));
      expect(facts.single.about, 'See Secret plan x');
      expect(facts.single.theme, 'Plans');
      expect(facts.single.decisions, [('2026-10-03', 'Ship it')]);
      expect(readNoteFacts('no json here', 3), isEmpty);
    });
  });

  group('a build', () {
    test('every link points at a real note; what the AI made up is not a link', () async {
      final ai = ScriptedAi(extra: [
        {'n': 9, 'about': 'A note that does not exist', 'theme': 'Ghosts'},
      ]);
      final notes = notesIn('workspaces/Launch', launchNotes(), pageId: 'page');
      final built = await buildIndex(folderTitle: 'Launch', pageBody: '# Launch\n', notes: notes, ai: ai, now: t0);
      final links = {for (final m in RegExp(r'\[\[([^\]]+)\]\]').allMatches(built.body)) m.group(1)!};
      expect(links, {'Roadmap', 'Sync rewrite', 'Standup 2026-11-01'});
      expect(built.body, isNot(contains('[[Secret')));
      expect(built.body, isNot(contains('Ghosts')));
      expect(built.body, contains('- 2026-10-28 · Move sync to the new server — [[Sync rewrite]]'));
      expect(built.body, contains('- **alice** — [[Standup 2026-11-01]], [[Roadmap]]'));
      expect(built.body, contains('- **bob** — [[Sync rewrite]]'));
      expect(built.body, contains('### Meetings\n- [[Standup 2026-11-01]] — About Standup 2026-11-01'));
    });

    test('a refresh reads again only the notes changed since, and keeps what it said of the rest', () async {
      final first = ScriptedAi();
      var notes = notesIn('workspaces/Launch', launchNotes(), pageId: 'page');
      final built = await buildIndex(folderTitle: 'Launch', pageBody: '# Launch\n', notes: notes, ai: first, now: t0);
      expect(first.sent, hasLength(3));

      // One note edited after the index was written, one new, one gone.
      notes = [
        note('a', 'workspaces/Launch/Roadmap.md', '# Roadmap\nFour bets now.', at: ms(t0) + 60000),
        notes.firstWhere((n) => n.id == 'b'),
        note('d', 'workspaces/Launch/Hiring.md', '# Hiring\nTwo engineers.', at: ms(t0) - 1),
      ];
      expect(indexDirty(built.body, notes), isTrue);
      final second = ScriptedAi();
      final again = await buildIndex(folderTitle: 'Launch', pageBody: built.body, notes: notes, ai: second, now: t0.add(const Duration(hours: 1)));
      expect(second.sent..sort(), ['Hiring', 'Roadmap']);
      expect(again.read..sort(), ['a', 'd']);
      expect(again.body, contains('[[Sync rewrite]] — About Sync rewrite'));
      expect(again.body, isNot(contains('Standup')));
      expect(indexDirty(again.body, notes), isFalse);

      // A full rebuild reads them all.
      final third = ScriptedAi();
      await buildIndex(folderTitle: 'Launch', pageBody: again.body, notes: notes, ai: third, now: t0, full: true);
      expect(third.sent, hasLength(3));
    });
  });

  group('who writes it', () {
    final device = ScriptedAi(onDevice: true, name: 'On this device');
    final cloud = ScriptedAi();

    test('Local only: the device’s model alone, never a cloud provider', () {
      var askedCloud = false;
      final pick = pickIndexAi(localOnly: true, cloud: () {
        askedCloud = true;
        return cloud;
      }, device: () => device);
      expect(pick.ai, same(device));
      expect(askedCloud, isFalse);
      expect(pickIndexAi(localOnly: true, cloud: () => cloud, device: () => null).ai, isNull);
    });

    test('otherwise whatever is connected, then the device, then nobody with a reason', () {
      expect(pickIndexAi(localOnly: false, cloud: () => cloud, device: () => device).ai, same(cloud));
      expect(pickIndexAi(localOnly: false, cloud: () => null, device: () => device).ai, same(device));
      final none = pickIndexAi(localOnly: false, cloud: () => null, device: () => null);
      expect(none.ai, isNull);
      expect(none.why, contains('Settings › AI'));
    });
  });

  group('the keeper', () {
    late ValueNotifier<List<Note>> library;
    late DateTime now;
    late ScriptedAi ai;

    IndexKeeper keeper(String id) => IndexKeeper(
          notes: library,
          get: (id) async => library.value.where((n) => n.id == id).firstOrNull,
          write: (id, change) async {
            library.value = [for (final n in library.value) n.id == id ? n.copyWith(body: change(n.body), updatedAt: ms(now)) : n];
          },
          makePage: (folder, title) async {
            final page = note('page', '$folder/index.md', '# $title\n', at: ms(now));
            library.value = [...library.value, page];
            return page;
          },
          pick: () => IndexAiPick(ai),
          deviceId: id,
          deviceName: id == 'mac' ? 'Mac' : 'phone',
          clock: () => now,
          record: Activity(clock: () => now),
        );

    setUp(() {
      now = t0;
      ai = ScriptedAi();
      library = ValueNotifier(launchNotes());
    });

    test('turning on makes the folder’s page, and the refresh writes only its section', () async {
      final mac = keeper('mac');
      await mac.turnOn('workspaces/Launch', title: 'Launch');
      final page = library.value.firstWhere((n) => n.id == 'page');
      expect(IndexSettings.of(page.body).by, 'mac');
      expect(mac.status('workspaces/Launch').on, isTrue);
      expect(await mac.refresh('workspaces/Launch', title: 'Launch'), isNull);
      final written = library.value.firstWhere((n) => n.id == 'page').body;
      expect(written, startsWith('---\nindex: on\nindex-every: hourly\nindex-by: mac\nindex-by-name: Mac\n---\n# Launch\n\n<!-- ghost:index'));
      expect(mac.status('workspaces/Launch').count, 3);
      expect(mac.lastRead, hasLength(3));
      mac.dispose();
    });

    test('an organization’s index is written by the one device that turned it on; Take over moves it', () async {
      library.value = [...launchNotes(), note('home', 'orgs/Acme/Home.md', '# Acme\n\nOur team.\n')];
      final mac = keeper('mac'), phone = keeper('phone');
      expect(IndexKeeper.pageOf('orgs/Acme', library.value)!.id, 'home');
      await mac.turnOn('orgs/Acme', title: 'Acme');
      expect(phone.status('orgs/Acme').mine, isFalse);
      expect(phone.status('orgs/Acme').byName, 'Mac');
      final refused = await phone.refresh('orgs/Acme', title: 'Acme');
      expect(refused, contains('kept by Mac'));
      expect(ai.prompts, isEmpty);
      // The phone's tick passes it by, dirty or not.
      await phone.tick();
      expect(ai.prompts, isEmpty);
      await phone.takeOver('orgs/Acme', title: 'Acme');
      expect(mac.status('orgs/Acme').mine, isFalse);
      expect(await phone.refresh('orgs/Acme', title: 'Acme'), isNull);
      expect(library.value.firstWhere((n) => n.id == 'home').body, contains('Our team.\n\n<!-- ghost:index'));
      mac.dispose();
      phone.dispose();
    });

    test('a tick refreshes a dirty index once it is due, reading only what changed', () async {
      final mac = keeper('mac');
      await mac.turnOn('workspaces/Launch', title: 'Launch', every: IndexEvery.quarter);
      await mac.refresh('workspaces/Launch', title: 'Launch');
      ai.prompts.clear();
      now = t0.add(const Duration(minutes: 5));
      library.value = [for (final n in library.value) n.id == 'b' ? n.copyWith(body: '# Sync rewrite\nDone.', updatedAt: ms(now)) : n];
      expect(mac.status('workspaces/Launch').dirty, isTrue);
      await mac.tick();
      expect(ai.prompts, isEmpty, reason: 'not due for 15 minutes');
      now = t0.add(const Duration(minutes: 16));
      await mac.tick();
      expect(ai.sent, ['Sync rewrite']);
      expect(mac.lastRead, ['b']);
      expect(mac.status('workspaces/Launch').dirty, isFalse);
      mac.dispose();
    });

    test('Stop leaves the page as it was', () async {
      final mac = keeper('mac');
      await mac.turnOn('workspaces/Launch', title: 'Launch');
      final before = library.value.firstWhere((n) => n.id == 'page').body;
      final going = mac.refresh('workspaces/Launch', title: 'Launch');
      mac.stop('workspaces/Launch');
      expect(await going, isNull);
      expect(ai.cancelled, isTrue);
      expect(library.value.firstWhere((n) => n.id == 'page').body, before);
      mac.dispose();
    });
  });
}
