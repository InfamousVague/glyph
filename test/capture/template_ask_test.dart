import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/route.dart' show Candidate;
import 'package:ghost_md/capture/template_ask.dart';

/// A note from a template, said for a place (lib/capture/template_ask.dart; Matt, 2026-10-30: "new bug in Kiln"): the
/// template's word, the notebook or folder, a name where one is said; and a finished recording's plan carrying them to
/// the root, which makes it there (lib/root/root_templates.dart, lib/notes/place_templates.dart `templateForPlace`).
void main() {
  test('the word, the place and a name are read', () {
    expect(templateAsk('new bug in Kiln'), (template: 'bug', place: 'Kiln', title: null));
    expect(templateAsk('Make a new meeting in Work called Standup.'), (template: 'meeting', place: 'Work', title: 'Standup'));
    expect(templateAsk('create a new feature in the Ghost.md notebook'), (template: 'feature', place: 'Ghost.md', title: null));
    expect(templateAsk('a new bug report for my Kiln folder named Login loops'), (template: 'bug report', place: 'Kiln', title: 'Login loops'));
    expect(templateAsk('new note in Kiln'), (template: 'note', place: 'Kiln', title: null));
  });

  test('what is not one is left to the commands there were', () {
    expect(templateAsk('add milk to the shopping list'), isNull);
    expect(templateAsk('make a new note called groceries for the week'), isNull, reason: 'a name, not a template for a place');
    expect(templateAsk('new list in Kiln'), isNull);
  });

  test('a finished recording that says one is a new note with its template and place', () {
    final plan = planFinalCommand('New bug in Kiln called Login loops', notes: const <Candidate>[]);
    expect(plan, isA<PlanCreateNote<Candidate>>());
    plan as PlanCreateNote<Candidate>;
    expect(plan.template, 'bug');
    expect(plan.place, 'Kiln');
    expect(plan.title, 'Login loops');
    // A note named as before is no template's.
    final named = planFinalCommand('make a new note called stream ideas', notes: const <Candidate>[]) as PlanCreateNote<Candidate>;
    expect(named.template, isNull);
  });
}
