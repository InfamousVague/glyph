import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/plugins/github/plain_field.dart';
import 'package:ghost_md/plugins/slack/slack.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';

import 'support.dart';

/// The Slack page of Settings, held to the web page by measurement.
///
/// `fixtures/pane-empty.json` and `pane-one.json` are what Chromium measured (`getBoundingClientRect`, 390 x 844,
/// two device pixels to one) for `SlackPane` drawn alone on the web app's dev server, from its own modules and
/// stylesheets, inside a `.settingsScreen__pane` with the plugin's hue at the screen's top. The page only draws in
/// the app, so the binary was stood in for on that page: `window.__TAURI_INTERNALS__` with an `invoke` that answers
/// `ota_status` (native generation 27) and `slack_channels` (the ids with a webhook), and refuses everything else.
/// `fixtures/pane-browser.json` is the page with no binary ("Slack works in the app."), which this port never
/// draws; it is kept for the record and held to nothing. `fixtures/web/*.png` are the pictures of those pages,
/// light and dark, to lay beside `shots/`.
///
/// What is held, and the one allowance (Settings' small text is 20 px a line here and 20.08 on the page, the
/// kit's own), are as test/plugins/github/measured_test.dart says.
void main() {
  setUpAll(loadAppFonts);

  const hook = 'https://hooks.slack.com/services/T0/B0/abc';

  void seed(String name) {
    final slack = FakeSlack();
    if (name == 'pane-one') {
      slack.ground.kept.setItem('glyph-slack-channels', jsonEncode([{'id': 'a1', 'name': '#launch'}]));
      slack.ground.secrets.held['glyph-slack-webhook:a1'] = hook;
    }
  }

  Finder chipOf(Finder icon) => find.ancestor(of: icon, matching: find.byType(Container)).first;

  group('Slack’s page, against the web page', () {
    for (final name in ['pane-empty', 'pane-one']) {
      testWidgets('$name is where the page draws it', (tester) async {
        seed(name);
        final web = webRects('test/plugins/slack/fixtures/$name.json');
        await pumpPane(tester, const SlackPane());

        final sections = find.byType(PaneSection);
        expect(sections, findsNWidgets(web['sections']!.length));

        /// How much higher the card a thing is in starts here than on the page: the kit's small text.
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
        for (final (i, title) in ['CHANNELS', 'ADD A CHANNEL'].indexed) {
          inCard(find.text(title), web['titles']![i], parts: 'yh', what: 'title $title');
        }
        final descs = [
          'Each is a Slack channel’s incoming webhook, under a name you give it. Kept on each of your devices, and once kept no page can read the webhook back.',
          'In Slack, add an incoming webhook to the channel (Apps › Incoming WebHooks, or a workflow’s webhook), copy its URL, and paste it here.',
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
        final fields = find.byType(PlainField);
        expect(fields, findsNWidgets(web['inputs']!.length));
        for (final (i, one) in web['inputs']!.indexed) {
          inCard(fields.at(i), one, what: 'field $i');
        }
        held(tester.getRect(find.byType(SettingsFootnote)), web['footnote']!.single, what: 'the footnote', by: 1);
        await away(tester);
      });
    }

    for (final theme in ['light', 'dark']) {
      for (final name in ['pane-empty', 'pane-one']) {
        testWidgets('a picture of $name, $theme', (tester) async {
          seed(name);
          await pumpPane(tester, const SlackPane(), theme: theme);
          await shot(tester, 'slack-$name-$theme');
        });
      }
    }
  });
}
