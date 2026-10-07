import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/settings/section_steps.dart';

/// The web app's src/app/settings/sectionSteps.test.ts on the Dart port: Settings' two depths (docs/DESIGN.md §138),
/// the panes on the list and the sub-pages that are not, each stepping back to the page it was opened from.
class _Place implements SectionPlace {
  const _Place(this.id, this.label, this.group, {this.listed = true, this.parent});
  @override
  final String id;
  @override
  final String label;
  @override
  final int group;
  @override
  final bool listed;
  @override
  final String? parent;
}

const _sections = [
  _Place('account', 'Account', 0),
  _Place('theme', 'Appearance', 1),
  _Place('recording', 'Recording', 1),
  _Place('plugins', 'Plugins', 1),
  _Place('plugin:notion', 'Notion', 1, listed: false, parent: 'plugins'),
  _Place('about', 'About', 2),
  _Place('cheatsheet', 'Cheat sheet', 2, listed: false, parent: 'about'),
  _Place('examples', 'Examples', 2, listed: false, parent: 'about'),
  _Place('developer', 'Developer', 3),
  _Place('test-results', 'Test results', 3),
];

List<String> _ids(List<_Place> list) => [for (final s in list) s.id];
_Place _at(String id) => _sections.firstWhere((s) => s.id == id);
Object? _to(BackStep step) => step is BackTo ? step.id : 'close';

void main() {
  group('the list', () {
    test('has the panes and not the sub-pages', () {
      expect(_ids(listedOf(_sections)), ['account', 'theme', 'recording', 'plugins', 'about', 'developer', 'test-results']);
    });

    test('clusters the rows by group, a sub-page between two rows of one group not splitting their card', () {
      expect(clustersOf(_sections).map(_ids), [
        ['account'],
        ['theme', 'recording', 'plugins'],
        ['about'],
        ['developer', 'test-results'],
      ]);
    });
  });

  group('back', () {
    test('steps a sub-page to its parent, a pane to the list, and closes from the list', () {
      expect(_to(stepBack(_sections, 'plugin:notion')), 'plugins');
      expect(_to(stepBack(_sections, 'examples')), 'about');
      expect(_to(stepBack(_sections, 'plugins')), isNull);
      expect(stepBack(_sections, null), isA<BackCloses>());
    });

    test('steps a sub-page whose parent is not there to the list, not to nothing', () {
      expect(_to(stepBack(const [_Place('orphan', 'Orphan', 0, listed: false, parent: 'gone')], 'orphan')), isNull);
    });

    test('names where it goes in the head', () {
      expect(backWord(_sections, _at('plugin:notion')), 'Plugins');
      expect(backWord(_sections, _at('cheatsheet')), 'About');
      expect(backWord(_sections, _at('theme')), 'Settings');
      expect(backWord(_sections, null), 'Settings');
    });

    test('names the screen itself as the root over a pane, when it is not Settings: an organization’s own screen', () {
      expect(backWord(_sections, _at('theme'), 'Ghost'), 'Ghost');
      expect(backWord(_sections, null, 'Ghost'), 'Ghost');
      // A sub-page still steps to its parent, whatever the screen is called.
      expect(backWord(_sections, _at('plugin:notion'), 'Ghost'), 'Plugins');
    });
  });

  group('forward', () {
    test('re-enters the page back just left, from where back landed', () {
      // A pane left for the list comes back from the list.
      expect(stepForward(_sections, null, 'theme'), 'theme');
      // A sub-page left for its parent comes back from the parent, not from the list or another page.
      expect(stepForward(_sections, 'plugins', 'plugin:notion'), 'plugin:notion');
      expect(stepForward(_sections, null, 'plugin:notion'), isNull);
      expect(stepForward(_sections, 'about', 'plugin:notion'), isNull);
    });

    test('stays put with nothing left behind, or with what was left gone from the sections', () {
      expect(stepForward(_sections, null, null), isNull);
      expect(stepForward(_sections, null, 'developer-gone'), isNull);
    });
  });

  group('the split view', () {
    test('keeps the parent’s row current while a sub-page shows', () {
      expect(currentRow(_sections, _at('examples')), 'about');
      expect(currentRow(_sections, _at('recording')), 'recording');
      expect(currentRow<_Place>(_sections, null), isNull);
    });
  });
}
