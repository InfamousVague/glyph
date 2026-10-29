import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/plugins/github/github.dart';
import 'package:ghost_md/plugins/github/plain_field.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/sheet/kit.dart';

import 'support.dart';

/// The GitHub page of Settings and the repo picker, held to the web page by measurement.
///
/// `fixtures/*.json` are what Chromium measured (`getBoundingClientRect`, 390 x 844, two device pixels to one) for
/// `GitHubPane` and `ProjectPicker` drawn alone on the web app's dev server, from its own modules and stylesheets:
/// the pane inside a `.settingsScreen__pane` with the plugin's hue at the screen's top, the picker inside the
/// note sheet's `.sheet`. `fixtures/web/*.png` are the pictures of those pages, light and dark, to lay beside
/// `shots/`. The script that made them is not in the repository (it was run from a scratch folder, 2026-10-08).
///
/// A box is held on all four sides, to half a pixel. A line of words is held by where it starts and how tall it is,
/// since its box on the page is as wide as its column and here as wide as its words. Two differences that are the
/// kits' own, not these pages', are allowed for and no more:
/// - **Settings' small text is 20 px a line here and 20.08 on the page** (lib/settings/kit: a line height given as a
///   multiple rounds to a whole pixel, README "Kit gaps"). A card's description is three such lines, so each card
///   starts a quarter of a pixel higher than the one before it did, and the page's foot is 0.74 px up. So a card is
///   held to where the page has it to one pixel, and everything in a card to half a pixel of its place in the card.
/// - **A sheet's field is half a pixel taller here** (lib/sheet/kit.dart draws `--app-line` at its 1.5 px, where
///   the measuring browser drew it at 1; test/sheet/kit_test.dart has the same note). What is under a field is that
///   half pixel lower.
void main() {
  setUpAll(loadAppFonts);

  late TestGround ground;

  final project = {
    'id': 'infamousvague/attackfm',
    'owner': 'InfamousVague',
    'repo': 'AttackFM',
    'url': 'https://github.com/InfamousVague/AttackFM',
    'branch': 'main',
    'description': '',
    'files': ['README.md'],
    'pack': 'A radio.',
    'packModel': null,
    'packedAt': DateTime.utc(2026, 9, 20, 12).millisecondsSinceEpoch,
  };

  void seed(String name) {
    ground = useGround();
    if (name == 'pane-repo') ground.kept.setItem('glyph-github-projects', jsonEncode([project]));
    if (name == 'picker-linked') {
      ground.kept.setItem('glyph-github-projects', jsonEncode([project, {...project, 'id': 'o/r', 'owner': 'o', 'repo': 'r', 'packModel': 'qwen3.5-4b'}]));
      ground.kept.setItem('glyph-project-links', jsonEncode({'n1': 'infamousvague/attackfm'}));
    }
  }

  Finder chipOf(Finder icon) => find.ancestor(of: icon, matching: find.byType(Container)).first;

  group('the GitHub page, against the web page', () {
    for (final name in ['pane-empty', 'pane-repo']) {
      testWidgets('$name is where the page draws it', (tester) async {
        seed(name);
        final web = webRects('test/plugins/github/fixtures/$name.json');
        await pumpPane(tester, const GitHubPane(withSetup: false));

        final sections = find.byType(PaneSection);
        expect(sections, findsNWidgets(web['sections']!.length));

        /// How much higher the card a thing is in starts here than on the page: the kit's small text, see above.
        double lift(Finder inCard) {
          for (final (i, one) in web['sections']!.indexed) {
            if (find.descendant(of: sections.at(i), matching: inCard).evaluate().isNotEmpty) return tester.getRect(sections.at(i)).top - (one['y']! as num);
          }
          return 0;
        }

        void inCard(Finder found, Map<String, Object?> one, {String parts = 'xywh', required String what}) => held(tester.getRect(found), one, parts: parts, what: what, dy: lift(found));

        for (final (i, one) in web['sections']!.indexed) {
          held(tester.getRect(sections.at(i)), one, what: 'section $i', by: 1);
          inCard(find.descendant(of: sections.at(i), matching: find.byType(ClipRRect)).first, web['cards']![i], what: 'card $i');
        }
        for (final (i, title) in ['REPOS', 'TOKEN'].indexed) {
          inCard(find.text(title), web['titles']![i], parts: 'yh', what: 'title $title');
          expect(tester.getRect(find.text(title)).left, closeTo((web['titles']![i]['x']! as num) + 8.93, 0.5));
        }
        final descs = [
          'Repos the model on your phone has read. A note linked to one is formatted knowing its names and terms, and its list items can go there as issues.',
          'A token lets Ghost.md read private repos and make and close issues from your notes. It stays on your devices.',
        ];
        for (final (i, words) in descs.indexed) {
          inCard(find.text(words), web['descs']![i], parts: 'yh', what: 'description $i');
        }

        final rows = find.byType(SettingRow);
        expect(rows, findsNWidgets(web['rows']!.length));
        for (final (i, one) in web['rows']!.indexed) {
          inCard(rows.at(i), one, what: 'row $i');
          final row = tester.widget<SettingRow>(rows.at(i));
          inCard(find.descendant(of: rows.at(i), matching: find.text(row.label)), web['labels']![i], parts: 'xyh', what: 'label ${row.label}');
          inCard(find.descendant(of: rows.at(i), matching: find.text((row.hint! as Text).data!)), web['hints']![i], parts: 'xyh', what: 'hint of ${row.label}');
        }
        for (final (i, one) in web['icons']!.indexed) {
          inCard(chipOf(find.descendant(of: rows.at(i), matching: find.byType(AppIcon))), one, what: 'icon chip $i');
        }
        final actions = find.byType(RowAction);
        expect(actions, findsNWidgets(web['actions']!.length));
        for (final (i, one) in web['actions']!.indexed) {
          inCard(actions.at(i), one, what: 'action ${one['text']}');
        }
        inCard(find.byType(PlainField), web['inputs']!.single, what: 'the token field');
        if (web['empty']!.isNotEmpty) {
          inCard(find.byType(SettingsEmpty), web['empty']!.single, what: 'the empty card');
          inCard(chipOf(find.descendant(of: find.byType(SettingsEmpty), matching: find.byType(AppIcon))), web['emptyIcon']!.single, what: 'the empty card’s icon');
          inCard(find.text('No repos yet.'), web['emptyTitle']!.single, what: 'the empty card’s title');
          inCard(find.text('Open a note, tap More, and choose GitHub repo to link one.'), web['emptyBody']!.single, parts: 'yh', what: 'the empty card’s words');
        }
        held(tester.getRect(find.byType(SettingsFootnote)), web['footnote']!.single, what: 'the footnote', by: 1);
        await away(tester);
      });
    }

    for (final theme in ['light', 'dark']) {
      for (final name in ['pane-empty', 'pane-repo']) {
        testWidgets('a picture of $name, $theme', (tester) async {
          seed(name);
          await pumpPane(tester, const GitHubPane(withSetup: false), theme: theme);
          await shot(tester, 'github-$name-$theme');
        });
      }
    }
  });

  group('the repo picker, against the web page', () {
    for (final name in ['picker-empty', 'picker-linked']) {
      testWidgets('$name is where the page draws it', (tester) async {
        seed(name);
        final web = webRects('test/plugins/github/fixtures/$name.json');
        await pumpSheetPage(tester, ProjectPicker(noteId: 'n1', onDone: () {}));

        // The field's line is half a pixel thicker here (see above): the field and its card are that much taller,
        // and what is under the line that much lower.
        final line = (web['inputs']!.single['y']! as num) + (web['inputs']!.single['h']! as num);
        double under(Map<String, Object?> one) => (one['y']! as num) >= line - 1 ? 0.5 : 0;
        double over(Map<String, Object?> one) => (one['y']! as num) < line && (one['y']! as num) + (one['h']! as num) >= line ? 0.5 : 0;
        void at(Finder found, Map<String, Object?> one, {String parts = 'xywh', required String what}) => held(tester.getRect(found), one, parts: parts, what: what, dy: under(one), dh: over(one));

        at(find.byType(SheetTitle), web['title']!.single, what: 'the title');
        final notes = find.byType(SheetNote);
        expect(notes, findsNWidgets(web['notes']!.length));
        for (final (i, one) in web['notes']!.indexed) {
          at(notes.at(i), one, what: 'note $i');
        }
        at(find.byType(SheetHeading), web['headings']!.single, what: 'the heading');
        final groups = find.byType(SheetGroup);
        expect(groups, findsNWidgets(web['groups']!.length));
        for (final (i, one) in web['groups']!.indexed) {
          at(groups.at(i), one, what: 'group $i');
        }
        final rows = find.byType(SheetRow);
        expect(rows, findsNWidgets(web['rows']!.length));
        for (final (i, one) in web['rows']!.indexed) {
          at(rows.at(i), one, what: 'row ${one['text']}');
        }
        final icons = find.byType(SheetIcon);
        expect(icons, findsNWidgets(web['icons']!.length));
        for (final (i, one) in web['icons']!.indexed) {
          at(icons.at(i), one, what: 'icon $i');
        }
        // A row's words: its hint under its label, and a label alone where the page's `.label` box is only that.
        final said = ['Kept from its README.', 'Read by qwen3.5-4b.', 'Add a GitHub token that can read it. It stays on this phone.'];
        final hints = [for (final words in said) if (find.text(words).evaluate().isNotEmpty) words];
        expect(hints, hasLength(web['hints']!.length));
        for (final (i, one) in web['hints']!.indexed) {
          at(find.text(hints[i]), one, parts: 'xyh', what: 'hint ${hints[i]}');
        }
        for (final label in ['Read and link', 'Don’t link a project']) {
          if (find.text(label).evaluate().isEmpty) continue;
          at(find.text(label), web['labels']!.firstWhere((one) => one['text'] == label), what: 'label $label');
        }
        at(find.byType(SheetField), web['fields']!.single, what: 'the link’s field');
        at(find.text('LINK'), web['fieldLabels']!.single, parts: 'xyh', what: 'the field’s label');
        at(find.ancestor(of: find.byType(EditableText), matching: find.byType(DecoratedBox)).first, web['inputs']!.single, what: 'the line typed on');
        await away(tester);
      });
    }

    for (final theme in ['light', 'dark']) {
      for (final name in ['picker-empty', 'picker-linked']) {
        testWidgets('a picture of $name, $theme', (tester) async {
          seed(name);
          await pumpSheetPage(tester, ProjectPicker(noteId: 'n1', onDone: () {}), theme: theme);
          await shot(tester, 'github-$name-$theme');
        });
      }
    }
  });
}
