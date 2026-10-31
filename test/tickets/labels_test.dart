import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/tickets/labels.dart';

import 'support.dart';

/// Labels and components (lib/tickets/labels.dart): the colour each label wears, from the notebook's
/// `label-colours:` or its default; a ticket's labels written back; and the query engine filtering and grouping by
/// them.
void main() {
  group('a label’s colour', () {
    test('is the notebook’s where it names one, else a well-known label’s, else one from its letters', () {
      final colours = labelColoursOf(notes.first.body);
      expect(colours, {'bug': 'amber', 'signup': 'teal'});
      expect(labelHue('bug', colours), 'amber');
      expect(labelHue('Bug'), 'red');
      expect(labelHue('#docs'), 'teal');
      expect(labelHue('Tech debt'), 'amber');
      final made = labelHue('waffle');
      expect(labelHues, contains(made));
      expect(made, isNot('gray'));
      expect(labelHue('waffle'), made);
    });

    test('is read from a map, a list or plain pairs, and a hue the app has not got is left out', () {
      String book(String said) => '---\nbook: true\nlabel-colours: $said\n---\n# B\n';
      expect(labelColoursOf(book('{bug: red, "needs design": purple}')), {'bug': 'red', 'needs-design': 'purple'});
      expect(labelColoursOf(book('[bug=red, ui: blue]')), {'bug': 'red', 'ui': 'blue'});
      expect(labelColoursOf(book('bug: red, ui: chartreuse')), {'bug': 'red'});
      expect(labelColoursOf('---\nlabel-colors: {ui: teal}\n---\n'), {'ui': 'teal'});
      expect(labelColoursOf(null), isEmpty);
    });

    test('is written into the notebook as one map, and taken off for the default', () {
      const book = '---\nbook: true\nkey: WAIT\n---\n# Waitlist\n';
      final one = withLabelColour(book, 'Bug', 'red');
      expect(one, '---\nbook: true\nkey: WAIT\nlabel-colours: {bug: red}\n---\n# Waitlist\n');
      final two = withLabelColour(one, 'needs design', 'purple');
      expect(two, contains('label-colours: {bug: red, needs-design: purple}'));
      expect(labelColoursOf(two), {'bug': 'red', 'needs-design': 'purple'});
      expect(withLabelColour(withLabelColour(two, 'bug', null), 'needs design', null), book);
      expect(withLabelColour(book, 'bug', 'chartreuse'), book);
    });
  });

  group('a ticket’s labels', () {
    const body = '---\ntype: ticket\nlabels: [bug, "#ui"]\n---\n# T\n';

    test('are read cleaned and once, and written back across', () {
      expect(labelsOf(body), ['bug', 'ui']);
      expect(labelsOf('---\nlabels: Bug, bug, ui\n---\n'), ['Bug', 'ui']);
      expect(withLabels(body, ['bug', 'ui', 'Needs design']), '---\ntype: ticket\nlabels: [bug, ui, Needs design]\n---\n# T\n');
      expect(withLabels(body, []), '---\ntype: ticket\n---\n# T\n');
    });

    test('are toggled and changed many at once, whatever their case', () {
      expect(labelsOf(withLabelToggled(body, 'UI')), ['bug']);
      expect(labelsOf(withLabelToggled(body, 'email')), ['bug', 'ui', 'email']);
      expect(labelsOf(withLabelsChanged(body, add: ['email', 'BUG'], remove: ['ui'])), ['bug', 'email']);
    });

    test('and its component are named across the library, the most used first', () {
      final bodies = [for (final each in notes) each.body];
      expect(labelsIn(bodies), ['bug', 'ui', 'backend', 'email']);
      expect(componentsIn(bodies), ['Waitlist', 'Webhooks']);
      expect(componentOf(notes[3].body), 'Waitlist');
    });
  });

  group('the query engine', () {
    final library = libraryOf(notes);
    List<String?> keys(String lines) => [for (final group in runQuery(readQuery(lines).query!, library, today).groups) for (final row in group.rows) row.id];

    test('filters by a label and by a component', () {
      expect(keys('from: tickets\nwhere: labels has bug\nsort: id'), ['PAY-1', 'WAIT-1']);
      expect(keys('from: tickets\nwhere: labels has UI and labels not has bug\nsort: id'), ['PAY-2', 'WAIT-2']);
      expect(keys('from: tickets\nwhere: component = waitlist'), ['WAIT-1']);
    });

    test('groups a board by label, a ticket in each of its labels’ lanes, and by component', () {
      final byLabel = runQuery(readQuery('from: tickets\nwhere: labels is not empty\ngroup: labels\nshow: board\nsort: id').query!, library, today);
      expect({for (final group in byLabel.groups) group.label: [for (final row in group.rows) row.id]}, {
        'backend': ['PAY-1'],
        'bug': ['PAY-1', 'WAIT-1'],
        'email': ['WAIT-1'],
        'ui': ['PAY-2', 'WAIT-2'],
      });
      final byComponent = runQuery(readQuery('from: tickets\nwhere: component is not empty\ngroup: component\nshow: board').query!, library, today);
      expect([for (final group in byComponent.groups) group.label], ['Waitlist', 'Webhooks']);
    });
  });
}
