import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/svg_path.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/link_marks.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/sheet/kit.dart' show StrokeMark;
import 'package:glacier/glacier.dart';

import '../settings/support.dart';
import 'support.dart';

/// What a note is linked to, worn on the note (lib/plugins/link_marks.dart): the cases of
/// `src/app/plugins/LinkMarks.test.tsx` and of `src/app/plugins/hooks.test.tsx`, then the row held to the rects the
/// web page measured.
///
/// What differs from the web's cases:
/// - The page's two cases about the workspace ("leaves the workspace to the tab…", "says nothing on a note in no
///   workspace…") file a note in a workspace first, to show no pill is drawn for it. Nothing here reads the
///   workspaces at all, so both are held as what is left of them: a note with no links draws nothing.
/// - hooks.test.tsx used the real Notion plugin's `linkBoard`; the plugin here is a stand-in that keeps what a note
///   is linked to in its own storage through its host, which is the same path (Notion's is its worker's).
/// - `usePlugins()` has no widget of its own (the registry is a `Listenable`): its case is a `ListenableBuilder`.
///
/// The measurements are `test/plugins/fixtures/link-marks-390.json`: the web app's note screen in Chromium at
/// 390 x 844, two device pixels to one, light, 2026-10-08, over a note linked to a Notion board called Roadmap and
/// the repo InfamousVague/AttackFM. The row is held from its own corner, to half a pixel.

/// The page's own marks (plugins/notion/marks.tsx, plugins/github/marks.tsx), a path each.
Widget notionMark(BuildContext context, double size) => StrokeMark(path: svgPath('M5 4h10l4 4v12H5zM9 16V9l6 7V9'), size: size);
Widget repoMark(BuildContext context, double size) => StrokeMark(path: svgPath('M6 3v12M18 3a3 3 0 1 0 0 6a3 3 0 1 0 0-6M6 15a3 3 0 1 0 0 6a3 3 0 1 0 0-6M18 9a9 9 0 0 1-9 9'), size: size);

/// Two plugins that link notes, each keeping what a note is linked to in its own storage, through its host.
class Linking {
  Linking() {
    boards = createHost(manifestOf('notion', name: 'Notion', storage: ['glyph-test-boards']), ground: on.ground);
    repos = createHost(manifestOf('github', name: 'GitHub', storage: ['glyph-test-repos']), ground: on.ground);
    String? Function(String) read(PluginHost host, String key) => (noteId) => host.storage.get<Map<String, Object?>>(key, const {})[noteId] as String?;
    registry = createRegistry(
      [
        GlyphPlugin(manifest: boards.manifest, icon: 'square-kanban', noteLinks: [linkOf('notion-board', 'Notion board', read(boards, 'glyph-test-boards'), icon: notionMark)]),
        GlyphPlugin(manifest: repos.manifest, icon: 'git-branch', noteLinks: [linkOf('github-repo', 'GitHub repo', read(repos, 'glyph-test-repos'), icon: repoMark)]),
      ],
      store: MemorySwitches(),
    );
  }

  final TestGround on = TestGround();
  late final PluginHost boards;
  late final PluginHost repos;
  late final Registry registry;

  void _link(PluginHost host, String key, String noteId, String? name) {
    // A copy: what a read answers is shared with every other read of it.
    final links = {...host.storage.get<Map<String, Object?>>(key, const {})};
    if (name == null) {
      links.remove(noteId);
    } else {
      links[noteId] = name;
    }
    host.storage.set(key, links);
  }

  void linkBoard(String noteId, String? title) => _link(boards, 'glyph-test-boards', noteId, title);
  void linkRepo(String noteId, String? name) => _link(repos, 'glyph-test-repos', noteId, name);
}

/// A note's links as words: each link's id and what it names (`Links` of hooks.test.tsx).
Widget linksAsWords(String noteId, {Registry? registry}) => Directionality(
      textDirection: TextDirection.ltr,
      child: NoteLinksBuilder(noteId: noteId, registry: registry, builder: (context, links) => Text(links.map((l) => '${l.link.id}: ${l.name}').join(', '), key: const ValueKey('links'))),
    );

String wordsShown(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('links'))).data!;

/// The row on a phone's width, at the top of the screen.
Future<void> pumpMarks(WidgetTester tester, Registry registry, String noteId, {VoidCallback? onPress, String theme = 'light', Size size = phone, double top = 0}) => pumpSettings(
      tester,
      Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [LinkMarks(noteId: noteId, onPress: onPress, registry: registry)]),
      ),
      size: size,
      prefs: Preferences(theme: theme),
      settle: false,
    );

List<String> namesShown(WidgetTester tester) => [for (final mark in tester.widgetList<LinkMark>(find.byType(LinkMark))) mark.linked.name];

void main() {
  setUpAll(loadAppFonts);

  group('the workspace on the note', () {
    testWidgets('leaves the workspace to the tab, which wears it: a note filed with no links says nothing here', (tester) async {
      final linking = Linking()..linkBoard('n4', 'Roadmap');
      await pumpMarks(tester, linking.registry, 'n1', onPress: () {});
      expect(find.byType(LinkMark), findsNothing);
      expect(find.byType(GlacierPressable), findsNothing);
      expect(tester.getSize(find.byType(LinkMarks)), Size.zero);
      await endSettings(tester);
    });

    testWidgets('says nothing on a note in no workspace with no links', (tester) async {
      await pumpMarks(tester, Linking().registry, 'n2', onPress: () {});
      expect(find.byType(LinkMark), findsNothing);
      expect(tester.getSize(find.byType(LinkMarks)), Size.zero);
      await endSettings(tester);
    });
  });

  group('the links on the note', () {
    testWidgets('wears a mark for each, named, with no workspace pill, and says them all to a screen reader', (tester) async {
      final linking = Linking()
        ..linkBoard('n4', 'Roadmap')
        ..linkRepo('n4', 'InfamousVague/AttackFM');
      var pressed = 0;
      final handle = tester.ensureSemantics();
      await pumpMarks(tester, linking.registry, 'n4', onPress: () => pressed++);
      expect(namesShown(tester), ['Roadmap', 'InfamousVague/AttackFM']);
      expect(find.byKey(LinkMark.ringKey), findsNWidgets(2));
      expect(find.byType(StrokeMark), findsNWidgets(2));
      const said = 'Linked to Notion board Roadmap and GitHub repo InfamousVague/AttackFM. Change in this note’s settings.';
      expect(LinkMarks.said(linking.registry.linksOf('n4')), said);
      expect(tester.getSemantics(find.bySemanticsLabel(said)), isSemantics(label: said, isButton: true, hasTapAction: true, hasEnabledState: true, isEnabled: true, isFocusable: true));
      // One thing to a screen reader: the marks are not read again inside it.
      expect(find.bySemanticsLabel('Notion board: Roadmap'), findsNothing);
      await tester.tap(find.byType(LinkMarks));
      expect(pressed, 1);
      handle.dispose();
      await endSettings(tester);
    });

    testWidgets('is a plain row with nothing to press when there is nowhere to open', (tester) async {
      final linking = Linking()
        ..linkBoard('n4', 'Roadmap')
        ..linkRepo('n4', 'InfamousVague/AttackFM');
      final handle = tester.ensureSemantics();
      await pumpMarks(tester, linking.registry, 'n4');
      expect(find.descendant(of: find.byType(LinkMarks), matching: find.byType(GlacierPressable)), findsNothing);
      expect(namesShown(tester), ['Roadmap', 'InfamousVague/AttackFM']);
      // The page's `title` on each mark.
      expect(find.bySemanticsLabel('Notion board: Roadmap'), findsOneWidget);
      expect(find.bySemanticsLabel('GitHub repo: InfamousVague/AttackFM'), findsOneWidget);
      // With nothing to press it is not set in from the edges: it stands where it is put.
      expect(tester.getTopLeft(find.byType(LinkMark).first), Offset.zero);
      handle.dispose();
      await endSettings(tester);
    });

    testWidgets('cuts a long name short on one line, and wraps to a second line of marks where one will not hold them', (tester) async {
      final linking = Linking()
        ..linkBoard('n4', 'A board with a name far longer than any mark has room for on a phone')
        ..linkRepo('n4', 'InfamousVague/AttackFM-and-the-rest-of-it');
      await pumpMarks(tester, linking.registry, 'n4', onPress: () {});
      final t = tokensAt(tester, find.byType(LinkMarks));
      final first = tester.getRect(find.byType(LinkMark).at(0));
      final second = tester.getRect(find.byType(LinkMark).at(1));
      // `.name { max-inline-size: 14rem }`, after the ring and its gap.
      expect(first.width, closeTo(1.5 * 0.85 * t.fontSize('sm') + 0.4 * t.fontSize('sm') + t.lenOf('14rem'), 0.01));
      expect(first.height, closeTo(1.4 * t.fontSize('sm'), 0.5));
      expect(second.top - first.bottom, closeTo(t.space(2), 0.01), reason: '`gap: var(--glacier-space-2)` between lines');
      expect(second.left, first.left);
      await endSettings(tester);
    });

    testWidgets('is the quiet ink, and the page’s ink while it is pressed', (tester) async {
      final linking = Linking()..linkBoard('n4', 'Roadmap');
      await pumpMarks(tester, linking.registry, 'n4', onPress: () {});
      Color ink() => tester.widget<Text>(find.text('Roadmap')).style!.color!;
      final ring = tester.widget<Container>(find.byKey(LinkMark.ringKey)).decoration! as BoxDecoration;
      expect(ink(), sameColor(cssColor(tester, 'var(--app-ink-3)')));
      expect((ring.border! as Border).top.color, ink());
      final press = await tester.startGesture(tester.getCenter(find.text('Roadmap')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(ink(), sameColor(cssColor(tester, 'var(--app-ink)')));
      await press.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ink(), sameColor(cssColor(tester, 'var(--app-ink-3)')));
      await endSettings(tester);
    });
  });

  group('useNoteLinks', () {
    testWidgets('reads again when a plugin writes what the note is linked to', (tester) async {
      final linking = Linking();
      await tester.pumpWidget(linksAsWords('n1', registry: linking.registry));
      expect(wordsShown(tester), '');
      linking.linkBoard('n1', 'Jobs');
      await tester.pump();
      expect(wordsShown(tester), 'notion-board: Jobs');
      linking.linkBoard('n1', null);
      await tester.pump();
      expect(wordsShown(tester), '');
    });

    testWidgets('drops a plugin’s links while it is switched off, and brings them back when it is on', (tester) async {
      final linking = Linking()..linkBoard('n1', 'Jobs');
      await tester.pumpWidget(linksAsWords('n1', registry: linking.registry));
      expect(wordsShown(tester), 'notion-board: Jobs');
      linking.registry.setEnabled('notion', false);
      await tester.pump();
      expect(wordsShown(tester), '');
      linking.registry.setEnabled('notion', true);
      await tester.pump();
      expect(wordsShown(tester), 'notion-board: Jobs');
    });

    testWidgets('follows the note it is given', (tester) async {
      final linking = Linking()..linkBoard('n1', 'Jobs');
      await tester.pumpWidget(linksAsWords('n1', registry: linking.registry));
      await tester.pumpWidget(linksAsWords('n2', registry: linking.registry));
      expect(wordsShown(tester), '');
      await tester.pumpWidget(linksAsWords('n1', registry: linking.registry));
      expect(wordsShown(tester), 'notion-board: Jobs');
    });

    testWidgets('reads the app’s registry when it is given none, and the one put in place after it was drawn', (tester) async {
      final before = plugins;
      addTearDown(() => usePlugins(before));
      usePlugins(createRegistry(const [], store: MemorySwitches()));
      final linking = Linking()..linkBoard('n1', 'Jobs');
      await tester.pumpWidget(linksAsWords('n1'));
      expect(wordsShown(tester), '');
      // The built-in plugins arrive (lib/plugins/built_in.dart): the next draw reads them, and their switches after.
      usePlugins(linking.registry);
      await tester.pumpWidget(linksAsWords('n1'));
      expect(wordsShown(tester), 'notion-board: Jobs');
      linking.registry.setEnabled('notion', false);
      await tester.pump();
      expect(wordsShown(tester), '');
    });

    testWidgets('stops listening once it is off the screen', (tester) async {
      final linking = Linking()..linkBoard('n1', 'Jobs');
      await tester.pumpWidget(linksAsWords('n1', registry: linking.registry));
      await tester.pumpWidget(const SizedBox.shrink());
      // Neither a write nor a switch reaches a builder that is gone (it would throw, setting state after dispose).
      linking.linkBoard('n1', 'Other');
      linking.registry.setEnabled('notion', false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('usePlugins', () {
    testWidgets('lists every plugin, and redraws with the ones on as a switch moves', (tester) async {
      final registry = Linking().registry;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListenableBuilder(listenable: registry, builder: (context, _) => Text('${registry.all().length}: ${registry.enabled().map((p) => p.manifest.id).join(' ')}', key: const ValueKey('links'))),
        ),
      );
      expect(wordsShown(tester), '2: notion github');
      registry.setEnabled('github', false);
      await tester.pump();
      expect(wordsShown(tester), '2: notion');
      registry.setEnabled('github', true);
      await tester.pump();
      expect(wordsShown(tester), '2: notion github');
    });
  });

  group('the row, against the web’s', () {
    testWidgets('two marks under a note’s head: the rings, the marks in them and the names, rect for rect', (tester) async {
      final web = (jsonDecode(File('test/plugins/fixtures/link-marks-390.json').readAsStringSync()) as Map).cast<String, dynamic>();
      Map thing(String name, int i) => (web[name] as List)[i] as Map;
      final row = thing('row', 0);
      final linking = Linking()
        ..linkBoard('n1', 'Roadmap')
        ..linkRepo('n1', 'InfamousVague/AttackFM');
      await pumpMarks(tester, linking.registry, 'n1', onPress: () {});
      expect(LinkMarks.said(linking.registry.linksOf('n1')), web['said']);
      expect([for (final l in linking.registry.linksOf('n1')) '${l.link.label}: ${l.name}'], web['titles']);

      // From the row's own corner: the page has it under the note's head, here it is at the top of the screen.
      final origin = tester.getTopLeft(find.byType(LinkMarks));
      void near(String what, Finder finder, Map want) {
        final got = tester.getRect(finder).shift(-origin);
        final x = (want['x'] as num) - (row['x'] as num), y = (want['y'] as num) - (row['y'] as num);
        expect(got, rectNear(x.toDouble(), y.toDouble(), (want['w'] as num).toDouble(), (want['h'] as num).toDouble()), reason: '$what: $got against x$x y$y w${want['w']} h${want['h']}');
      }

      expect(tester.getSize(find.byType(LinkMarks)).height, closeTo(row['h'] as num, 0.5));
      for (var i = 0; i < 2; i++) {
        final mark = find.byType(LinkMark).at(i);
        near('mark $i', mark, thing('marks', i));
        near('ring $i', find.descendant(of: mark, matching: find.byKey(LinkMark.ringKey)), thing('rings', i));
        near('icon $i', find.descendant(of: mark, matching: find.byType(StrokeMark)), thing('icons', i));
        near('name $i', find.descendant(of: mark, matching: find.byType(Text)), thing('names', i));
        expect(tester.widget<Text>(find.descendant(of: mark, matching: find.byType(Text))).data, thing('names', i)['text']);
      }
      // The ring's line and the ink, as the page computed them.
      final ring = tester.widget<Container>(find.byKey(LinkMark.ringKey).first).decoration! as BoxDecoration;
      expect('${(ring.border! as Border).top.width.toStringAsFixed(0)}px', (web['ring'] as Map)['border']);
      expect((ring.border! as Border).top.color, sameColor(cssColor(tester, (web['ring'] as Map)['color'] as String)));
      expect(tester.widget<Text>(find.text('Roadmap')).style!.color, sameColor(cssColor(tester, thing('names', 0)['color'] as String)));
      expect(tester.widget<Text>(find.text('Roadmap')).style!.fontSize, closeTo(double.parse((thing('names', 0)['size'] as String).replaceAll('px', '')), 0.01));
      await endSettings(tester);
    });
  });

  group('pictures', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('the marks of a linked note, $theme', (tester) async {
        final linking = Linking()
          ..linkBoard('n1', 'Roadmap')
          ..linkRepo('n1', 'InfamousVague/AttackFM');
        // The size of the strip cut from the page's picture (fixtures/web/link-marks-<theme>.png): the row and 8px
        // above and below it.
        await pumpMarks(tester, linking.registry, 'n1', onPress: () {}, theme: theme, size: const Size(390, 44), top: 8);
        await shot(tester, 'link-marks-$theme');
      });
    }
  });
}
