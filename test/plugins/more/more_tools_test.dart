// The more tools' switches (docs/PM_PLUGINS.md §10; Matt, 2026-11-01: "think about other things that can be plugins
// that might be overwhelming for a new user as well"): what a note's words use, the one-time adoption that turns a
// tool on exactly where it was in use and never for a fresh library, the switches travelling, what Google Meet and
// Zoom stand on, and the Market's shelf.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_facts.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/editor/plus/add_rows.dart';
import 'package:ghost_md/meet/meet_kinds.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/meetings/meetings.dart' show googleMeetPlugin, zoomPlugin;
import 'package:ghost_md/plugins/more/more_tools.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/sync/connections.dart';

void main() {
  setUp(() => MoreTools.debugAllOn = false);
  tearDown(() => MoreTools.debugAllOn = true);

  Registry registryOf([Map<String, bool>? switches]) => createRegistry([...morePlugins, googleMeetPlugin, zoomPlugin], store: MemorySwitches(switches));

  group('what a note uses', () {
    test('Diagrams and math: a mermaid fence, a fence in a language, a formula, inline maths', () {
      expect(moreToolsUsedIn('# Plain\n\nNothing here, and it costs \$5 or \$6 with tax.\n'), isEmpty);
      expect(moreToolsUsedIn('# D\n\n```mermaid\nflowchart LR\n  A --> B\n```\n'), {diagramsTool});
      expect(moreToolsUsedIn('# Code\n\n```dart\nvoid main() {}\n```\n'), {diagramsTool});
      expect(moreToolsUsedIn('# Code\n\n~~~ python\nprint(1)\n~~~\n'), {diagramsTool});
      expect(moreToolsUsedIn('# F\n\n\$\$\na^2 + b^2 = c^2\n\$\$\n'), {diagramsTool});
      expect(moreToolsUsedIn('# F\n\nWhere \$x^2\$ is the area.\n'), {diagramsTool});
      // A plain block, and the app's own fences, are no language.
      expect(moreToolsUsedIn('# Code\n\n```\nplain\n```\n'), isEmpty);
      expect(moreToolsUsedIn('# Q\n\n```query\nfrom: notes\n```\n\n```board\nTodo:\n```\n\n```text\nwords\n```\n'), isEmpty);
    });

    test('Places, Email to a note and Meetings, from the front matter and the words', () {
      expect(moreToolsUsedIn('---\nlocation: 52.37,4.89\nplace: "Amsterdam"\n---\n# Here\n'), {placesTool});
      expect(moreToolsUsedIn('---\nentry-place: true\n---\n# Today\n'), {placesTool});
      expect(moreToolsUsedIn('# Lunch\n\n[Café Winkel](geo:52.37,4.88)\n'), {placesTool});
      expect(moreToolsUsedIn('---\nfrom: "Ada <ada@example.com>"\n---\n# Your order\n'), {emailTool});
      expect(moreToolsUsedIn('---\nfrom: the shop\n---\n# Not mail\n'), isEmpty, reason: 'a from: with no address is no mail’s');
      expect(moreToolsUsedIn('---\nmeeting: {start: 2026-10-31T10:00:00.000Z, kind: meet}\n---\n# Standup\n'), {meetingsTool});
    });

    test('a note’s facts keep them, a canvas as Canvas', () {
      const canvas = '---\ncanvas: true\n---\n{"nodes":[],"edges":[]}\n';
      final facts = NoteFacts.of(Note(id: 'c', body: canvas, createdAt: 0, updatedAt: 0));
      expect(facts.isCanvas, isTrue);
      expect(facts.more, contains(canvasTool));
      expect(NoteFacts.of(Note(id: 'd', body: '# D\n\n```js\n1\n```\n', createdAt: 0, updatedAt: 0)).more, {diagramsTool});
    });
  });

  group('the switches', () {
    test('ship off, and are the person’s alone', () {
      final registry = registryOf();
      for (final id in moreTools) {
        expect(registry.byId(id)?.manifest.standard, isFalse, reason: id);
        expect(moreToolOn(id, registry), isFalse, reason: id);
      }
      // Every one of the six is in the app's list once.
      expect([for (final plugin in builtIn) plugin.manifest.id].where(isMoreTool).toList(), moreTools);
    });

    test('travel between the person’s devices', () {
      for (final id in moreTools) {
        expect(syncedSwitches, contains(id));
      }
      final registry = registryOf({canvasTool: true});
      final items = {for (final item in connectionItems(const {}, registry: () => registry, platform: TargetPlatform.android)) item.name: item};
      expect(items[switchItemName(canvasTool)]?.peek?.call(), 'on');
      expect(items[switchItemName(diagramsTool)]?.peek?.call(), isNull, reason: 'a switch never moved sends nothing');
    });

    test('Google Meet and Zoom stand on Meetings: off, Ghost joins nothing and the service is told', () {
      final off = registryOf();
      expect(off.isEnabled('google-meet'), isTrue, reason: 'their own switches ship on');
      expect(moreNeedsMet('google-meet', off), isFalse);
      expect(meetKindOn('meet', registry: off), isFalse);
      expect(meetKindOn('zoom', registry: off), isFalse);
      expect(meetKindsWanted(registry: off), {'meet': false, 'zoom': false});
      final on = registryOf({meetingsTool: true});
      expect(meetKindOn('meet', registry: on), isTrue);
      expect(meetKindsWanted(registry: on), {'meet': true, 'zoom': true});
      expect(withMoreNeeds('zoom'), [meetingsTool, 'zoom']);
      expect(moreDependentsOf(meetingsTool, on), ['google-meet', 'zoom']);
    });

    test('the + offers A diagram and A formula only with Diagrams and math; a block of code always', () {
      List<String> ids(bool diagrams) => [
            for (final row in allRows(readGates(picture: false, video: false, place: false, note: false, canvas: false, diagrams: diagrams), DateTime(2026, 11, 1))) row.id,
          ];
      expect(ids(false), isNot(contains('chart')));
      expect(ids(false), isNot(contains('formula')));
      expect(ids(false), contains('code'));
      expect(ids(true), containsAll(['chart', 'formula', 'code']));
    });
  });

  group('adopting', () {
    Map<String, (String, bool Function())> checks(Set<String> used) => {for (final id in moreTools) id: (id, () => used.contains(id))};

    test('turns on exactly the tools in use, once, and nothing for a fresh library', () {
      final fresh = registryOf();
      final kept = MemoryStored();
      expect(adoptMoreTools(fresh, checks(const {}), store: kept), isEmpty);
      for (final id in moreTools) {
        expect(fresh.isEnabled(id), isFalse, reason: id);
        expect(fresh.hasSwitch(id), isFalse, reason: 'no switch is written for a tool not in use: $id');
        expect(moreToolChecked(id, store: kept), isTrue);
      }
      // Next week the person writes a ```dart block: the check was made, and Diagrams stays off, for the chip.
      expect(adoptMoreTools(fresh, checks({diagramsTool}), store: kept), isEmpty);
      expect(fresh.isEnabled(diagramsTool), isFalse);

      final used = registryOf();
      final usedKept = MemoryStored();
      expect(adoptMoreTools(used, checks({canvasTool, placesTool}), store: usedKept), [canvasTool, placesTool]);
      expect(used.isEnabled(canvasTool), isTrue);
      expect(used.isEnabled(placesTool), isTrue);
      expect(used.isEnabled(diagramsTool), isFalse);
      expect(used.isEnabled(meetingsTool), isFalse);
    });

    test('leaves a switch the person moved as it was, and asks a check’s question only while it is unmade', () {
      final registry = registryOf({canvasTool: false});
      var asked = 0;
      adoptMoreTools(registry, {canvasTool: (canvasTool, () => ++asked > 0)}, store: MemoryStored());
      expect(registry.isEnabled(canvasTool), isFalse, reason: 'switched off by hand before');
      final kept = MemoryStored();
      adoptMoreTools(registry, {emailAddressCheck: (emailTool, () => ++asked > 0)}, store: kept);
      adoptMoreTools(registry, {emailAddressCheck: (emailTool, () => ++asked > 0)}, store: kept);
      expect(asked, 2, reason: 'once for Canvas, once for the address: never again');
      expect(registry.isEnabled(emailTool), isTrue);
    });

    test('does nothing while every test’s switches are on', () {
      MoreTools.debugAllOn = true;
      final registry = registryOf();
      expect(adoptMoreTools(registry, checks(moreTools.toSet()), store: MemoryStored()), isEmpty);
      expect(registry.hasSwitch(canvasTool), isFalse);
    });
  });
}
