import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/settings/settings_search.dart';

/// The web app's src/app/settings/settingsSearch.test.ts on the Dart port. `findSetting`, which read the page for
/// the element naming a setting, is the kit's finder here and is tested with the screen (settings_screen_test.dart).
class _Section implements SearchableSection {
  const _Section(this.id, this.label, {this.summary, this.words, this.settings = const []});
  @override
  final String id;
  @override
  final String label;
  @override
  final String? summary;
  @override
  final String? words;
  @override
  final List<SettingsFindable> settings;
}

// The shape of Settings since docs/DESIGN.md §138, cut down: Appearance holds what were Type's and Animations' rows.
const _sections = [
  _Section(
    'theme',
    'Appearance',
    summary: 'Dark · Maple Mono',
    words: 'theme look feel',
    settings: [SettingsFindable('Type', 'text font'), SettingsFindable('Note font', 'font typeface'), SettingsFindable('Code', 'syntax'), SettingsFindable('Smoke at the edges'), SettingsFindable('Ghostly typing')],
  ),
  _Section('recording', 'Recording', settings: [SettingsFindable("Use Ghost.md's guess")]),
  _Section('examples', 'Examples', settings: [SettingsFindable('Add the “How Ghost.md works” canvas')]),
  _Section('developer', 'Developer', settings: [SettingsFindable('Smoke bench')]),
];

List<String> _found(String query) => [
      for (final hit in searchSettings(_sections, query)) hit.setting != null ? '${hit.section.id}/${hit.setting}' : hit.section.id,
    ];

void main() {
  group('searchSettings', () {
    test('finds nothing for an empty field', () {
      expect(_found(''), isEmpty);
      expect(_found('   '), isEmpty);
    });

    test('finds a section by its name, its state line or its own words', () {
      expect(_found('appear'), ['theme']);
      expect(_found('dark'), ['theme']);
      expect(_found('feel'), ['theme']);
    });

    test('finds a setting inside a section, each on its own page', () {
      expect(_found('smoke'), ['theme/Smoke at the edges', 'developer/Smoke bench']);
      expect(_found('syntax'), ['theme/Code']);
      expect(_found('FONT'), ['theme/Type', 'theme/Note font']);
    });

    test('needs every word, in any order, each at the start of a word', () {
      expect(_found('edges smo'), ['theme/Smoke at the edges']);
      expect(_found('moke'), isEmpty);
      expect(_found('smoke bench edges'), isEmpty);
    });

    test("doesn't list the settings of a section its name already found", () {
      expect(_found('examples'), ['examples']);
    });

    test('reads curly quotes and apostrophes as straight ones', () {
      expect(_found('"how ghost'), ['examples/Add the “How Ghost.md works” canvas']);
      expect(_found("ghost.md's"), ["recording/Use Ghost.md's guess"]);
      expect(fold('Add the “How Ghost.md works” canvas'), 'add the "how ghost.md works" canvas');
    });
  });
}
