import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/plus/query_templates.dart' as plus;

import 'support.dart';

/// The databases the + offers ready-made (lib/core/query/templates.dart): each reads, runs, and is shown as its row
/// says. Case for case with the web's `core/query/templates.test.ts`.
void main() {
  group('the ready-made databases', () {
    test('each reads without a problem, and is shown the way its row says', () {
      for (final template in queryTemplates) {
        final reading = readQuery(template.lines);
        expect(reading.problem, isNull, reason: template.id);
        final result = runQuery(reading.query!, libraryOf(notes), today);
        expect(result.show, template.show, reason: template.id);
      }
    });

    test('finds something in an ordinary library', () {
      int found(String id) {
        final template = queryTemplates.firstWhere((each) => each.id == id);
        return runQuery(readQuery(template.lines).query!, libraryOf(notes), today).matched;
      }

      expect(found('week'), greaterThan(0));
      expect(found('late'), greaterThan(0));
      expect(found('people'), greaterThan(0));
      expect(found('board'), 3);
      expect(found('tickets'), 2);
      expect(found('count'), 5);
    });

    test('has an id each, and leaves only Write your own to be written over', () {
      expect({for (final template in queryTemplates) template.id}.length, queryTemplates.length);
      expect([for (final template in queryTemplates) if (template.select != null) template.id], ['own']);
      final own = queryTemplates.firstWhere((template) => template.id == 'own');
      expect(own.lines, contains(own.select!));
    });

    test('are the ones the + list has always handed on', () {
      // Not a web case: lib/editor/plus/query_templates.dart held these before the query core was ported.
      expect(plus.queryTemplates, same(queryTemplates));
      expect(plus.queryFence('from: tasks\n'), queryFence('from: tasks\n'));
    });
  });
}
