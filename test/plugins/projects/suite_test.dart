// The project tools' switches and where each answers (docs/PM_PLUGINS.md; Matt, 2026-11-01): what a note's words use,
// the dependency on Tickets, an organization's list against the person's own, and the person's switches travelling.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/page_tree.dart' show TeamspaceSettings, teamspaceHomeBody, withProjectPlugins;
import 'package:ghost_md/plugins/projects/suite.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/sync/connections.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;

/// A suite over its own registry, with organizations whose home pages are [homes] (organization id to body) and notes
/// filed by [orgOf].
({ProjectSuite suite, Registry registry, Map<String, String> homes}) world({Map<String, String>? homes, Map<String, String> orgOf = const {}, Map<String, Set<String>> used = const {}}) {
  final registry = createRegistry(projectPlugins, store: MemorySwitches());
  final kept = {...?homes};
  late final ProjectSuite suite;
  suite = ProjectSuite(
    registry: () => registry,
    orgOfNote: (id) => orgOf[id],
    listOf: (org) => kept[org] == null ? null : TeamspaceSettings.of(kept[org]).plugins,
    orgIds: () => kept.keys,
    orgName: (org) => {'ht': 'HelloTrade', 'hq': 'Hello HQ'}[org],
    usedIn: (org) => used[org] ?? const {},
    writeOrg: (org, tools) async {
      kept[org] = withProjectPlugins(kept[org] ?? teamspaceHomeBody(org), tools);
      return true;
    },
    stored: MemoryStored(),
  );
  return (suite: suite, registry: registry, homes: kept);
}

void main() {
  setUp(() => ProjectSuite.debugAllOn = false);
  tearDown(() => ProjectSuite.debugAllOn = true);

  group('what a note uses', () {
    test('is read from its front matter and the names of its fences', () {
      expect(toolsUsedIn('# Plain\n\nNothing here.\n'), isEmpty);
      expect(toolsUsedIn('---\ntype: ticket\nid: GHST-12\n---\n# Fix it\n'), {'tickets'});
      expect(toolsUsedIn('---\ntype: ticket\ncycle: 2026-C45\nspent: 1h\n---\n# Fix it\n'), {'tickets', 'planning', 'time-tracking'});
      expect(toolsUsedIn('---\nbook: true\nkey: GHST\n---\n# Ghost tasks\n'), {'tickets'});
      expect(toolsUsedIn('---\nbook: true\nstatuses:\n  - Todo\n  - Done\n---\n# Kiln\n'), {'tickets'});
      expect(toolsUsedIn('---\nbook: true\n---\n# A plain notebook\n'), isEmpty);
      expect(toolsUsedIn('# Plan\n\n```gantt\nDesign: 2026-11-02, 3d\n```\n'), {'gantt'});
      expect(toolsUsedIn('# Plan\n\n~~~board height=12\nTodo: ^a\n~~~\n'), {'boards'});
      expect(toolsUsedIn('# Kiln\n\n```rules\nWhen a ticket moves to Done, ping #ship\n```\n'), {'automations'});
      expect(toolsUsedIn('# Bugs\n\n```form\nto: [[Bug reports]]\n- Summary: short\n```\n'), {'forms'});
    });

    test('reads what a query needs, and nothing of one that reads as built in', () {
      String q(String lines) => '# Q\n\n```query\n$lines\n```\n';
      expect(toolsUsedIn(q('from: notes\nshow: list')), isEmpty);
      expect(toolsUsedIn(q('from: tasks\nshow: calendar')), isEmpty);
      expect(toolsUsedIn(q('from: tickets\nshow: table')), {'tickets'});
      expect(toolsUsedIn(q('from: notes\nshow: board')), {'boards'});
      expect(toolsUsedIn(q('from: notes\nshow: timeline')), {'gantt'});
      expect(toolsUsedIn(q('from: tickets\nshow: gantt')), {'tickets', 'gantt'});
      expect(toolsUsedIn(q('from: tickets\nshow: burndown')), {'tickets', 'planning'});
      expect(toolsUsedIn(q('from: notes\nshow: roadmap')), {'tickets', 'planning'}, reason: 'the roadmap is Planning’s, not a timeline');
    });
  });

  group('the dependency on Tickets', () {
    test('a tool that needs it brings it, and a list without it reads the tool off', () {
      expect(withNeeds(['forms']), ['tickets', 'forms']);
      expect(withNeeds(['gantt', 'boards']), ['gantt', 'boards'], reason: 'Gantt and Boards stand alone');
      expect(toolsOn(['planning', 'gantt']), {'gantt'});
      expect(dependentsOf(['tickets', 'planning', 'gantt', 'forms']), ['planning', 'forms']);
    });

    test('turning on Planning turns on Tickets, and Tickets off takes what needs it', () async {
      final (:suite, :registry, homes: _) = world();
      await suite.turnOn(['planning']);
      expect(suite.personal, {'tickets', 'planning'});
      expect((registry.isEnabled('tickets'), registry.isEnabled('planning')), (true, true));
      await suite.turnOn(['gantt', 'time-tracking']);
      await suite.turnOff('tickets');
      expect(suite.personal, {'gantt'});
      expect(registry.isEnabled('time-tracking'), isFalse);
    });
  });

  group('the scope', () {
    test('a note in an organization asks its list, a personal note the person’s switches', () async {
      final (:suite, :registry, :homes) = world(homes: {'ht': teamspaceHomeBody('HelloTrade', plugins: ['tickets', 'boards']), 'hq': teamspaceHomeBody('Hello HQ')}, orgOf: {'deal': 'ht', 'memo': 'hq'});
      registry.setEnabled('gantt', true);
      suite.changed();
      expect(suite.on('tickets', noteId: 'deal'), isTrue);
      expect(suite.on('gantt', noteId: 'deal'), isFalse, reason: 'the person’s Gantt is not HelloTrade’s');
      expect(suite.on('gantt', noteId: 'mine'), isTrue);
      expect(suite.on('tickets', noteId: 'mine'), isFalse);
      expect(suite.onIn(noteId: 'memo'), isEmpty, reason: 'Hello HQ chose none');
      expect(suite.onIn(orgId: 'unknown'), isEmpty, reason: 'an organization whose home page is not here yet has none on');
      expect(suite.anywhere('tickets'), isTrue, reason: 'HelloTrade has it');
      expect(suite.anywhere('forms'), isFalse);
      expect((suite.whereWords(noteId: 'deal'), suite.whereWords(noteId: 'mine')), (' for HelloTrade', ''));
    });

    test('a tool turned on for an organization is written into its home page, with what it needs, and heard', () async {
      final (:suite, registry: _, :homes) = world(homes: {'ht': teamspaceHomeBody('HelloTrade')}, orgOf: {'deal': 'ht'});
      var told = 0;
      suite.addListener(() => told += 1);
      await suite.turnOn(['automations'], noteId: 'deal');
      expect(homes['ht'], contains('plugins: [tickets, automations]\n'));
      expect(suite.onIn(orgId: 'ht'), {'tickets', 'automations'});
      expect(suite.personal, isEmpty, reason: 'the person’s own switches did not move');
      expect(told, greaterThan(0));
    });

    test('the banner asks for what an organization’s notes use and its list lacks, and is put away per list', () {
      final (:suite, registry: _, homes: _) = world(homes: {'ht': teamspaceHomeBody('HelloTrade', plugins: ['gantt'])}, used: {'ht': {'gantt', 'forms', 'boards'}});
      expect(suite.missingIn('ht'), ['tickets', 'boards', 'forms']);
      expect(suite.bannerPutAway('ht', suite.missingIn('ht')), isFalse);
      suite.putAwayBanner('ht', suite.missingIn('ht'));
      expect(suite.bannerPutAway('ht', ['tickets', 'boards', 'forms']), isTrue);
      expect(suite.bannerPutAway('ht', ['tickets', 'boards', 'forms', 'planning']), isFalse, reason: 'a tool newly missing asks again');
    });

    test('with the suite on for the tests that test its features, everything answers on', () {
      final (:suite, registry: _, homes: _) = world();
      ProjectSuite.debugAllOn = true;
      expect(suite.on('forms', noteId: 'anything'), isTrue);
      expect(suite.missingIn('ht'), isEmpty);
    });
  });

  group('the person’s switches', () {
    test('travel with the account, as the other plugins’ do', () async {
      final (:suite, :registry, homes: _) = world();
      for (final id in projectTools) {
        expect(syncedSwitches, contains(id));
      }
      final items = {for (final item in connectionItems(const {}, registry: () => registry)) item.name: item};
      expect(items.keys, containsAll([for (final id in projectTools) switchItemName(id)]));
      // Another device turned Tickets and Gantt on: this one follows.
      await items[switchItemName('tickets')]!.write('on');
      await items[switchItemName('gantt')]!.write('on');
      suite.changed();
      expect(suite.personal, {'tickets', 'gantt'});
      expect(await items[switchItemName('gantt')]!.read(), 'on');
    });
  });
}
