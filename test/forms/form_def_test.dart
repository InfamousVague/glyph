// A form's fence (lib/forms/form_def.dart, docs/FORMS.md), read as the reader page reads it (tauri/src/read/form.ts,
// whose form.test.ts has the same cases): its fields, their kinds and whether each must be filled, the owner's lines
// left out of what is shared, a new form's words, and a ticket's title and words made from an answer.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/forms/form_def.dart';

const String bug = '''# Report a bug

Tell us what went wrong. We read every one.

```form
to: [[Bug reports]]
ticket: Bug: {Summary}
template: Bug report
thanks: Thanks, we'll look into it.
button: Send report
- Summary: short, required
- What happened: long, required
- How bad: choice (Annoying | Blocking | Lost work)
- Your email: email, optional
- Screenshot: file
- Time: 10:30 or so
- Summary: long
```

Thank you.''';

void main() {
  group('the fence', () {
    test('reads its fields, their kinds and whether each is needed, and the owner’s lines', () {
      final def = formOf(bug)!;
      expect((def.to, def.ticket, def.template, def.thanks, def.button), ('Bug reports', 'Bug: {Summary}', 'Bug report', "Thanks, we'll look into it.", 'Send report'));
      expect(def.fields, const [
        FormField(label: 'Summary', kind: FormFieldKind.short, required: true),
        FormField(label: 'What happened', kind: FormFieldKind.long, required: true),
        FormField(label: 'How bad', kind: FormFieldKind.choice, options: ['Annoying', 'Blocking', 'Lost work']),
        FormField(label: 'Your email', kind: FormFieldKind.email),
        FormField(label: 'Screenshot', kind: FormFieldKind.file),
        // A colon that starts no kind is the label's own; a second field of one label is the first.
        FormField(label: 'Time: 10:30 or so', kind: FormFieldKind.short),
      ]);
      expect(def.takesFile, isTrue);
      expect(isFormBody(bug), isTrue);
    });

    test('is none for a note without one, and takes the plainer spellings', () {
      expect(formOf('# Notes\n\n```js\nform\n```'), isNull);
      expect(isFormBody('# A note about forms'), isFalse);
      final def = formOf('~~~ form\n- Name*\n- Size: select (S, M, L), required\n- Notes: paragraph\n- Pick: choice\n~~~')!;
      expect(def.fields, const [
        FormField(label: 'Name', kind: FormFieldKind.short, required: true),
        FormField(label: 'Size', kind: FormFieldKind.choice, required: true, options: ['S', 'M', 'L']),
        FormField(label: 'Notes', kind: FormFieldKind.long),
        // A choice with nothing to choose is a line to type.
        FormField(label: 'Pick', kind: FormFieldKind.short),
      ]);
      expect(def.takesFile, isFalse);
      expect(def.to, isNull);
    });

    test('shares its introduction and its fields, never where its answers go', () {
      final shared = publicFormBody('---\nform-of: x\n---\n$bug');
      expect(frontMatterOffset(shared), 0, reason: 'no front matter');
      expect(shared, isNot(contains('Bug reports')));
      expect(shared, isNot(contains('ticket:')));
      expect(shared, isNot(contains('template:')));
      expect(shared, contains("thanks: Thanks, we'll look into it."));
      expect(shared, contains('- Summary: short, required'));
      expect(shared, contains('Tell us what went wrong.'));
      expect(formOf(shared)!.fields, formOf(bug)!.fields, reason: 'the same form for the visitor');
    });

    test('a new form starts as one a bug report or a request fits, filing into its notebook', () {
      final def = formOf(newFormWords(notebook: 'Requests'))!;
      expect(def.to, 'Requests');
      expect(def.ticket, '{Summary}');
      expect(def.fields.map((f) => (f.label, f.kind, f.required)), [('Summary', FormFieldKind.short, true), ('Details', FormFieldKind.long, true), ('Your email', FormFieldKind.email, false)]);
    });
  });

  group('a ticket from an answer', () {
    const answer = FormAnswer(answers: [('Summary', 'Crash on launch'), ('What happened', 'It closes at once.\nEvery time.'), ('How bad', 'Blocking'), ('Your email', 'ana@example.com')]);

    test('is titled by the form’s pattern, else by the first answer, on one line', () {
      final def = formOf(bug)!;
      expect(ticketTitleOf(def, answer), 'Bug: Crash on launch');
      expect(ticketTitleOf(formOf('```form\n- Summary\n```'), answer), 'Crash on launch');
      expect(ticketTitleOf(formOf('```form\nticket: Bug: {Missing}\n- A\n```'), answer), 'Crash on launch', reason: 'a pattern that leaves nothing');
      expect(ticketTitleOf(null, const FormAnswer(answers: [('Q', 'Line one\nline two [[x]]')])), 'Line one');
      expect(ticketTitleOf(null, const FormAnswer(answers: [])), 'Form answer');
      expect(ticketTitleOf(null, FormAnswer(answers: [('Q', 'a' * 300)])).length, 120);
    });

    test('carries the answers in its front matter and its body, and says it came by the form and when', () {
      final def = formOf(bug)!;
      final body = withAnswer('---\ntype: ticket\nid: BUG-3\nstatus: To do\n---\n# Bug: Crash on launch\n', def, answer, formTitle: 'Report a bug', at: DateTime.utc(2026, 10, 30, 14, 5));
      expect(frontMatterValue(body, 'via'), 'form');
      expect(frontMatterValue(body, 'form'), '[[Report a bug]]');
      expect(frontMatterValue(body, 'answered'), '2026-10-30T14:05:00.000Z');
      expect(frontMatterValue(body, 'email'), 'ana@example.com');
      expect(frontMatterValue(body, 'how-bad'), 'Blocking');
      expect(frontMatterValue(body, 'summary'), 'Crash on launch');
      expect(frontMatterValue(body, 'what-happened'), isNull, reason: 'a long answer is in the body only');
      expect(frontMatterValue(body, 'id'), 'BUG-3');
      expect(body, contains('## What happened\n\nIt closes at once.\nEvery time.\n'));
      expect(body, endsWith('_Via the form [[Report a bug]], 2026-10-30 14:05 UTC._\n'));
    });

    test('a field named as a ticket’s own key does not take it over', () {
      final body = withAnswer('---\ntype: ticket\nstatus: To do\n---\n# T\n', formOf('```form\n- Status\n- Priority\n```'), const FormAnswer(answers: [('Status', 'Urgent!'), ('Priority', 'high')]), formTitle: 'F', at: DateTime.utc(2026));
      expect(frontMatterValue(body, 'status'), 'To do');
      expect(frontMatterValue(body, 'priority'), isNull);
      expect(body, contains('## Status\n\nUrgent!'));
    });
  });
}
