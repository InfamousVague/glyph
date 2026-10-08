import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/item_links.dart' show markOf;
import 'package:ghost_md/core/item_syntax.dart';
import 'package:ghost_md/core/task_fields.dart';

/// The fields on a list item's words (lib/core/task_fields.dart), case for case with the web's
/// `core/taskFields.test.ts`.
///
/// "One grammar per syntax, tested line by line" (core/itemSyntax.ts). The fields are read by the chips, the voice,
/// a board's cards, a title sent away and a query's table, and written by a picker and a spoken "due Friday": these
/// are the lines every one of them must agree about, and the ones Obsidian Tasks must still read after the app has
/// written.
///
/// What differs: JavaScript's `undefined` has no twin, so the two checks of it are the checks of null beside them;
/// `toMatchObject` on the fields' record is the whole record compared ([record]).

/// What each field in [text] is, as `kind key=value`, in order.
List<String> said(String text) => [for (final span in fieldsIn(text)) '${span.kind.name} ${span.key}=${span.value}'];

/// What each field in [text] covers, as written.
List<String> written(String text) => [for (final span in fieldsIn(text)) text.substring(span.from, span.to)];

/// What an item's fields say, as the web's object literal: every name and what is under it.
Map<String, Object?> record(TaskFields fields) => {
  'due': fields.due,
  'start': fields.start,
  'scheduled': fields.scheduled,
  'done': fields.done,
  'created': fields.created,
  'cancelled': fields.cancelled,
  'recurs': fields.recurs,
  'priority': fields.priority,
  'assignees': fields.assignees,
  'id': fields.id,
  'dependsOn': fields.dependsOn,
  'onCompletion': fields.onCompletion,
  'fields': fields.fields,
};

const String _vs = '\uFE0F';
final RegExp _blockLink = RegExp(r'\s+\^[A-Za-z0-9-]+\s*$');
final RegExp _trailingSpace = RegExp(r'\s+$');
final RegExp _dueLast = RegExp('\\s*📅$_vs?\\s*(\\d{4}-\\d{2}-\\d{2})\$', unicode: true);
final RegExp _priorityLast = RegExp('\\s*(?:🔺|⏫|🔼|🔽|⏬)$_vs?\$', unicode: true);
final RegExp _dateLast = RegExp('\\s*(?:🛫|⏳|✅|➕|❌)$_vs?\\s*\\d{4}-\\d{2}-\\d{2}\$', unicode: true);
final RegExp _ruleLast = RegExp('\\s*🔁$_vs?\\s*[a-zA-Z0-9, !]+\$', unicode: true);
final RegExp _tagLast = RegExp(r'\s+#[^\s#]+$', unicode: true);

/// How Obsidian Tasks reads a line's due date: its fields from the end of the line, a block link and tags aside, up
/// to the first thing that is not one of them. A due date anywhere else is words to it.
String? tasksDue(String line) {
  var rest = withoutLead(line).replaceFirst(_blockLink, '').replaceFirst(_trailingSpace, '');
  String? due;
  for (;;) {
    final before = rest;
    rest = rest
        .replaceFirstMapped(_dueLast, (m) {
          due ??= m.group(1);
          return '';
        })
        .replaceFirst(_priorityLast, '')
        .replaceFirst(_dateLast, '')
        .replaceFirst(_ruleLast, '')
        .replaceFirst(_tagLast, '');
    if (rest == before) return due;
  }
}

void main() {
  group('priorities', () {
    test('are Tasks’ five, the most urgent first, each with its emoji and its rank', () {
      expect([for (final p in priorities) '${p.emoji} ${p.name} ${p.label} ${p.rank}'], [
        '🔺 highest Highest 0',
        '⏫ high High 1',
        '🔼 medium Medium 2',
        '🔽 low Low 4',
        '⏬ lowest Lowest 5',
      ]);
    });

    test('are read from a name in any case, or from the emoji with or without its variation selector', () {
      expect(priorityOf('high')?.name, 'high');
      expect(priorityOf(' Highest ')?.name, 'highest');
      expect(priorityOf('LOW')?.emoji, '🔽');
      expect(priorityOf('⏫')?.name, 'high');
      expect(priorityOf('⏫️')?.name, 'high');
      expect(priorityOf('🔺')?.name, 'highest');
      expect(priorityOf('⏬')?.name, 'lowest');
    });

    test('are nothing for anything else, normal and none included', () {
      for (final word in ['', 'normal', 'none', 'urgent', 'p1', 'hi', 'high!', '⬆️']) {
        expect(priorityOf(word), isNull, reason: word);
      }
      expect(priorityOf(null), isNull);
    });

    test('sort an item with none between medium and low, as Tasks does', () {
      expect(noPriorityRank, 3);
      expect(priorityRank(null), 3);
      final sorted = <String?>['low', null, 'highest', 'medium', 'lowest', 'high']..sort((a, b) => priorityRank(a) - priorityRank(b));
      expect(sorted, ['highest', 'high', 'medium', null, 'low', 'lowest']);
    });
  });

  group('the fields’ names', () {
    test('keep Tasks’ order, the dates last, done the last of all', () {
      expect(tasksOrder, ['id', 'dependsOn', 'priority', 'recurs', 'onCompletion', 'created', 'start', 'scheduled', 'due', 'cancelled', 'done']);
      expect(dateKeys, ['created', 'start', 'scheduled', 'due', 'cancelled', 'done']);
      expect(fieldEmoji, {'due': '📅', 'start': '🛫', 'scheduled': '⏳', 'done': '✅', 'created': '➕', 'cancelled': '❌', 'recurs': '🔁', 'id': '🆔', 'dependsOn': '⛔', 'onCompletion': '🏁'});
    });

    test('say which are dates and which are Tasks’', () {
      expect(isDateKey('due'), isTrue);
      expect(isDateKey('priority'), isFalse);
      expect(isTasksKey('priority'), isTrue);
      expect(isTasksKey('recurs'), isTrue);
      expect(isTasksKey('effort'), isFalse);
      expect(isTasksKey('assignee'), isFalse);
    });

    test('compare a named field as Dataview does: lower case, a dash for each run of spaces', () {
      expect(fieldKey('Due Date'), 'due-date');
      expect(fieldKey('  Effort '), 'effort');
      expect(fieldKey('story  points'), 'story-points');
      expect(fieldKey('due-date'), 'due-date');
    });
  });

  group('people', () {
    test('are written as a handle: the at sign off, spaces a dash, what a handle cannot hold dropped', () {
      expect(personHandle('Sam'), 'Sam');
      expect(personHandle('@sam'), 'sam');
      expect(personHandle('  Sam Ortiz '), 'Sam-Ortiz');
      expect(personHandle('@@sam.'), 'sam');
      expect(personHandle("O'Brien"), 'OBrien');
      expect(personHandle('Zoë'), 'Zoë');
      expect(personHandle('sam.jones'), 'sam.jones');
      expect(personHandle('2pac'), 'pac');
    });

    test('have no handle where nothing of the name can be one', () {
      for (final name in ['', '   ', '@', '123', '...', '@-']) {
        expect(personHandle(name), isNull, reason: name);
      }
    });

    test('are one person however they are mentioned', () {
      expect(personKey('@Sam'), 'sam');
      expect(personKey('Sam Ortiz'), 'sam-ortiz');
      expect(samePerson('@sam', 'Sam'), isTrue);
      expect(samePerson('sam-ortiz', 'Sam Ortiz'), isTrue);
      expect(samePerson('sam', 'samuel'), isFalse);
      expect(samePerson('', ''), isFalse);
    });
  });

  group('the fields in a text', () {
    test('reads Matt’s line: a date, a priority and a person, and leaves the tag and the anchor', () {
      const line = '- [ ] Fix the login loop 📅 2026-10-03 ⏫ @sam #bug ^login-loop';
      expect(fieldsIn(line), [
        const FieldSpan(kind: FieldKind.date, key: 'due', value: '2026-10-03', from: 25, to: 38),
        const FieldSpan(kind: FieldKind.priority, key: 'priority', value: 'high', from: 39, to: 40),
        const FieldSpan(kind: FieldKind.person, key: 'assignee', value: 'sam', from: 41, to: 45),
      ]);
      expect(written(line), ['📅 2026-10-03', '⏫', '@sam']);
    });

    test('reads every date by its sign, and the other signs Tasks reads for due and scheduled', () {
      expect(said('📅 2026-10-03 🛫 2026-10-01 ⏳ 2026-10-02 ✅ 2026-10-04 ➕ 2026-09-30 ❌ 2026-10-05'), [
        'date due=2026-10-03',
        'date start=2026-10-01',
        'date scheduled=2026-10-02',
        'date done=2026-10-04',
        'date created=2026-09-30',
        'date cancelled=2026-10-05',
      ]);
      expect(said('📆 2026-10-03 🗓 2026-10-04 🗓️ 2026-10-05 ⌛ 2026-10-06'), ['date due=2026-10-03', 'date due=2026-10-04', 'date due=2026-10-05', 'date scheduled=2026-10-06']);
    });

    test('takes a date with the variation selector, no space, or several', () {
      expect(written('📅️ 2026-10-03'), ['📅️ 2026-10-03']);
      expect(said('📅2026-10-03'), ['date due=2026-10-03']);
      expect(written('a 📅   2026-10-03 b'), ['📅   2026-10-03']);
      expect(said('📅\t2026-10-03'), ['date due=2026-10-03']);
    });

    test('keeps a date as written, even one the calendar has not got: the note says what it says', () {
      expect(said('📅 2026-02-30'), ['date due=2026-02-30']);
    });

    test('is no date without a day after the sign in ISO’s form', () {
      for (final text in ['📅', '📅 tomorrow', '📅 2026-10-3', '📅 20261003', '📅 03-10-2026', '📅 2026-10-031', '📅\n2026-10-03']) {
        expect(said(text), isEmpty, reason: text);
      }
    });

    test('reads each priority, with or without its selector, anywhere in the words', () {
      expect(said('🔺 ⏫ 🔼 🔽 ⏬'), ['priority priority=highest', 'priority priority=high', 'priority priority=medium', 'priority priority=low', 'priority priority=lowest']);
      expect(written('Fix⏫️ now'), ['⏫️']);
    });

    test('reads a recurrence’s rule to the next field, a tag, a person or the tail, and not its trailing commas', () {
      expect(said('🔁 every week on Monday 📅 2026-10-03'), ['recurs recurs=every week on Monday', 'date due=2026-10-03']);
      expect(said('🔁 every day when done'), ['recurs recurs=every day when done']);
      expect(written('🔁 every 2 weeks, 📅 2026-10-03'), ['🔁 every 2 weeks', '📅 2026-10-03']);
      expect(written('🔁 every week ^chores'), ['🔁 every week']);
      expect(written('🔁 every week #home'), ['🔁 every week']);
      expect(written('🔁 every week @sam'), ['🔁 every week', '@sam']);
      expect(written('🔁 every month [3/8]'), ['🔁 every month']);
      expect(written('🔁 every month!'), ['🔁 every month!']);
    });

    test('is no recurrence without words after the sign', () {
      expect(said('🔁'), isEmpty);
      expect(said('🔁 #home'), isEmpty);
    });

    test('reads Tasks’ id, what it waits on and what to do when it is done, as they are', () {
      expect(said('🆔 abc123 ⛔ def456,ghi789 🏁 delete'), ['tasks id=abc123', 'tasks dependsOn=def456,ghi789', 'tasks onCompletion=delete']);
      expect(said('⛔ a1, b2'), ['tasks dependsOn=a1, b2']);
    });

    test('reads a person after the start, a space or an opening bracket', () {
      expect(said('@sam'), ['person assignee=sam']);
      expect(written('Ask (@sam) and [@ana] and {@lee}'), ['@sam', '@ana', '@lee']);
      expect(said('cc @Sam.Jones and @sam_o and @ana-b'), ['person assignee=Sam.Jones', 'person assignee=sam_o', 'person assignee=ana-b']);
      expect(said('@Zoë and @李'), ['person assignee=Zoë', 'person assignee=李']);
    });

    test('leaves a trailing full stop or dash to the sentence', () {
      expect(written('Ask @sam.'), ['@sam']);
      expect(written('Ask @sam-- then'), ['@sam']);
      expect(said('Ask @sam...'), ['person assignee=sam']);
    });

    test('is no person in an address, a redaction, a time, a lone at sign or a word', () {
      for (final text in ['sam@example.com', 'mail sam@example.com', '@@Sam Ortiz@@', 'meet @ 2pm', 'meet @2pm', '@', 'a @ b', 'x@sam', '"@sam"', '@sam@mastodon.social', 'https://medium.com/@sam', '@_sam']) {
        expect(said(text), isEmpty, reason: text);
      }
    });

    test('is no field inside a redaction', () {
      expect(said('@@ask @dave about 📅 2026-10-03@@ and @sam'), ['person assignee=sam']);
    });

    test('reads a named field, Dataview’s, its key as Dataview compares it and its value trimmed', () {
      expect(fieldsIn('Fix [effort:: 3] now'), [const FieldSpan(kind: FieldKind.inline, key: 'effort', value: '3', from: 4, to: 16)]);
      expect(said('[Due Date:: 2026-10-03]'), ['inline due-date=2026-10-03']);
      expect(said('[key ::  spaced out  ]'), ['inline key=spaced out']);
      expect(said('[empty::]'), ['inline empty=']);
      expect(said('[blocked:: [[GHO-9]]]'), ['inline blocked=[[GHO-9]]']);
      expect(said('[blocked:: [[GHO-9]], [[GHO-10|the loop]]]'), ['inline blocked=[[GHO-9]], [[GHO-10|the loop]]']);
      expect(said('[size.cm:: 30] [a/b:: c] [x_y:: z]'), ['inline size.cm=30', 'inline a/b=c', 'inline x_y=z']);
    });

    test('is no named field in a link, a note link, a picture, one colon, or with no key', () {
      for (final text in ['[key:: v](https://x.y)', '[[key:: v]]', '![key:: v]', '[key: v]', '[:: v]', '[ key:: v]', '[key:: a [b] c]']) {
        expect(said(text), isEmpty, reason: text);
      }
    });

    test('takes the field that starts first where two would overlap: a person in a named field is its value', () {
      expect(said('[owner:: @sam] and @ana'), ['inline owner=@sam', 'person assignee=ana']);
      expect(said('[when:: 📅 2026-10-03]'), ['inline when=📅 2026-10-03']);
    });

    test('finds nothing in quiet words: code, an address, a note link’s title, maths, HTML', () {
      expect(said('Explain `📅 2026-10-03` and ``@sam``'), isEmpty);
      expect(said('[the doc](https://x.com/@sam/📅 2026-10-03)'), isEmpty);
      expect(said('see [[@sam notes]] and [[Plan ⏫]]'), isEmpty);
      expect(said(r'$a @b$'), isEmpty);
      expect(said('<span title="@sam">x</span>'), isEmpty);
    });

    test('finds nothing in fenced code or front matter, and counts positions across lines', () {
      const note = '---\nowner: "@sam"\n---\n- [ ] Ship @ana\n```\n- [ ] Not @lee\n```\n- [ ] Due 📅 2026-10-03';
      expect(written(note), ['@ana', '📅 2026-10-03']);
      expect(fieldsIn(note).first.from, note.indexOf('@ana'));
    });

    test('counts positions from the offset given', () {
      expect(fieldsIn('a @b', 10), [const FieldSpan(kind: FieldKind.person, key: 'assignee', value: 'b', from: 12, to: 14)]);
      expect(fieldsIn('', 10), isEmpty);
    });

    test('leaves the item’s own signs alone: the box, a counter, the mark, the anchor, the bookmark, a tag', () {
      expect(said('- [x] Ship it #web §§ [notion](https://n.so/a) [3/8] ^ship'), isEmpty);
    });
  });

  group('what the fields say', () {
    test('reads Matt’s line into one record', () {
      expect(record(fieldsOf('- [ ] Fix the login loop 📅 2026-10-03 ⏫ @sam #bug ^login-loop')), {
        'due': '2026-10-03',
        'start': null,
        'scheduled': null,
        'done': null,
        'created': null,
        'cancelled': null,
        'recurs': null,
        'priority': 'high',
        'assignees': ['sam'],
        'id': null,
        'dependsOn': <String>[],
        'onCompletion': null,
        'fields': <String, String>{},
      });
    });

    test('reads every kind at once', () {
      final fields = fieldsOf('Pay rent @sam @Ana 🔺 🔁 every month 🆔 rent ⛔ pay,bank 🏁 keep ➕ 2026-09-01 🛫 2026-09-28 ⏳ 2026-09-30 📅 2026-10-01 ❌ 2026-10-02 ✅ 2026-10-03 [effort:: 2]');
      expect(record(fields), {
        'due': '2026-10-01',
        'start': '2026-09-28',
        'scheduled': '2026-09-30',
        'done': '2026-10-03',
        'created': '2026-09-01',
        'cancelled': '2026-10-02',
        'recurs': 'every month',
        'priority': 'highest',
        'assignees': ['sam', 'Ana'],
        'id': 'rent',
        'dependsOn': ['pay', 'bank'],
        'onCompletion': 'keep',
        'fields': {'effort': '2'},
      });
      expect(fields.fields, {'effort': '2'});
    });

    test('takes the first of a repeated field, and each person once', () {
      final fields = fieldsOf('📅 2026-10-03 📅 2026-11-01 🔽 ⏫ @sam @Sam @SAM. @ana [a:: 1] [A:: 2] ⛔ x,y ⛔ y,z');
      expect(fields.due, '2026-10-03');
      expect(fields.priority, 'low');
      expect(fields.assignees, ['sam', 'ana']);
      expect(fields.fields, {'a': '1'});
      expect(fields.dependsOn, ['x', 'y', 'z']);
    });

    test('is empty for words with no fields, and its named fields have no inherited keys', () {
      final fields = fieldsOf('Just words #tag');
      expect(fields.assignees, isEmpty);
      expect(fields.due, isNull);
      expect(fields.fields, isEmpty);
      expect(fields.fields['constructor'], isNull);
      expect(fieldsOf('').priority, isNull);
    });

    test('reads Dataview’s own names for a task’s dates, and a priority by name, where there is no emoji for them', () {
      final fields = fieldsOf('Pay [due:: 2026-10-03] [start:: 2026-10-01] [scheduled:: 2026-10-02] [created:: 2026-09-01] [completion:: 2026-10-04] [cancelled:: 2026-10-05] [priority:: High]');
      expect([fields.due, fields.start, fields.scheduled, fields.created, fields.done, fields.cancelled, fields.priority], ['2026-10-03', '2026-10-01', '2026-10-02', '2026-09-01', '2026-10-04', '2026-10-05', 'high']);
      expect([for (final key in dateKeys) fields.date(key)], ['2026-09-01', '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-05', '2026-10-04']);
      expect(fields.fields['due'], '2026-10-03');
    });

    test('lets the emoji win over Dataview’s name, and a named date that is not a day stay a named field', () {
      expect(fieldsOf('[due:: 2026-10-01] 📅 2026-10-03').due, '2026-10-03');
      expect(fieldsOf('[priority:: low] ⏫').priority, 'high');
      final fields = fieldsOf('[due:: Friday] [priority:: soon]');
      expect(fields.due, isNull);
      expect(fields.priority, isNull);
      expect(fields.fields, {'due': 'Friday', 'priority': 'soon'});
    });
  });

  group('the words without their fields', () {
    test('are what the item says, a tag kept as words', () {
      expect(withoutFields('Fix the login loop @sam #bug ⏫ 📅 2026-10-03'), 'Fix the login loop #bug');
      expect(withoutFields('Fix the login loop 📅 2026-10-03 ⏫ @sam #bug'), 'Fix the login loop #bug');
    });

    test('take a field from the start, the middle or the end, and tidy the spaces it leaves', () {
      expect(withoutFields('@sam fix it'), 'fix it');
      expect(withoutFields('Call [phone:: 555 0100] tomorrow'), 'Call tomorrow');
      expect(withoutFields('  Pay   rent 🔁 every month  '), 'Pay rent');
      expect(withoutFields('⏫'), '');
    });

    test('leave words with no fields, and fields in code, as they are', () {
      expect(withoutFields('Buy milk'), 'Buy milk');
      expect(withoutFields('Explain `📅 2026-10-03` to sam@example.com'), 'Explain `📅 2026-10-03` to sam@example.com');
    });

    test('are what a card or a title says when read through the item’s grammar', () {
      expect(withoutFields(lineWords('- [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03 ^login-loop')), 'Fix the login loop #bug');
    });
  });

  group('a field written', () {
    const day = '2026-10-03';

    test('goes at the end of the words of a to-do, a bullet, a number, or a line that is not an item', () {
      expect(withField('- [ ] Fix it', 'due', day), '- [ ] Fix it 📅 2026-10-03');
      expect(withField('* Fix it', 'due', day), '* Fix it 📅 2026-10-03');
      expect(withField('  3. Fix it', 'due', day), '  3. Fix it 📅 2026-10-03');
      expect(withField('Fix it', 'due', day), 'Fix it 📅 2026-10-03');
      expect(withField('', 'due', day), '📅 2026-10-03');
    });

    test('goes after the box of an empty to-do, with one space', () {
      expect(withField('- [ ] ', 'due', day), '- [ ] 📅 2026-10-03');
      expect(withField('- [ ]', 'due', day), '- [ ] 📅 2026-10-03');
      expect(withField('- [ ] ^fix', 'priority', 'high'), '- [ ] ⏫ ^fix');
    });

    test('goes before the tail - the bookmark, the mark, a counter, the anchor - which still reads as the tail', () {
      final line = withField('- [ ] Ship it §§ [notion](https://n.so/a) [3/8] ^ship', 'due', day);
      expect(line, '- [ ] Ship it 📅 2026-10-03 §§ [notion](https://n.so/a) [3/8] ^ship');
      expect(line.substring(0, wordsEnd(line)), '- [ ] Ship it 📅 2026-10-03');
      expect(anchorSpan(line)?.id, 'ship');
      expect(withField('- [ ] Ship it [notion](https://n.so/a) ^ship', 'priority', 'high'), '- [ ] Ship it ⏫ [notion](https://n.so/a) ^ship');
      expect(markOf(withField('- [ ] Ship it [notion](https://n.so/a) ^ship', 'priority', 'high'))?.name, 'notion');
      expect(withField('- Water [3/8]', 'due', day), '- Water 📅 2026-10-03 [3/8]');
      expect(withField('- [ ] Read §§', 'due', day), '- [ ] Read 📅 2026-10-03 §§');
    });

    test('keeps Tasks’ order however the fields are added', () {
      var line = '- [ ] Pay rent ^rent';
      line = withField(line, 'due', '2026-10-01');
      line = withField(line, 'priority', 'high');
      line = withField(line, 'done', '2026-10-02');
      line = withField(line, 'start', '2026-09-28');
      line = withField(line, 'recurs', 'every month');
      line = withField(line, 'created', '2026-09-01');
      line = withField(line, 'scheduled', '2026-09-30');
      line = withField(line, 'cancelled', '2026-10-05');
      expect(line, '- [ ] Pay rent ⏫ 🔁 every month ➕ 2026-09-01 🛫 2026-09-28 ⏳ 2026-09-30 📅 2026-10-01 ❌ 2026-10-05 ✅ 2026-10-02 ^rent');
    });

    test('goes into the run of Tasks’ fields with the tags among them, never after words', () {
      expect(withField('- [ ] Fix ⏫ #bug ^fix', 'due', day), '- [ ] Fix ⏫ 📅 2026-10-03 #bug ^fix');
      expect(withField('- [ ] Fix #bug 📅 2026-10-03', 'priority', 'high'), '- [ ] Fix #bug ⏫ 📅 2026-10-03');
      expect(withField('- [ ] Fix #bug', 'due', day), '- [ ] Fix #bug 📅 2026-10-03');
      // A field in the middle of the words is not the run's: the new one goes at the end, where Tasks will read it.
      expect(withField('- [ ] Pay ⏫ the rent', 'due', day), '- [ ] Pay ⏫ the rent 📅 2026-10-03');
    });

    test('is changed where it is, in the sign it is written in, and a second of it taken off', () {
      expect(withField('- [ ] Pay 📅 2026-10-01 the rent', 'due', day), '- [ ] Pay 📅 2026-10-03 the rent');
      expect(withField('- [ ] Pay 📆 2026-10-01 ^rent', 'due', day), '- [ ] Pay 📅 2026-10-03 ^rent');
      expect(withField('- [ ] Pay 📅 2026-10-01 📅 2026-10-02 ^rent', 'due', day), '- [ ] Pay 📅 2026-10-03 ^rent');
      expect(withField('- [ ] Pay 🔽 ^rent', 'priority', 'highest'), '- [ ] Pay 🔺 ^rent');
      expect(withField('- [ ] Pay 🔁 every week', 'recurs', 'every 2 weeks'), '- [ ] Pay 🔁 every 2 weeks');
    });

    test('is taken off with the space before it, or after it where it opens the words', () {
      expect(withField('- [ ] Fix it 📅 2026-10-03 ^fix', 'due', null), '- [ ] Fix it ^fix');
      expect(withField('- [ ] 📅 2026-10-03 Fix it', 'due', null), '- [ ] Fix it');
      expect(withField('- [ ] 📅 2026-10-03', 'due', null), '- [ ] ');
      expect(withField('📅 2026-10-03 Fix it', 'due', null), 'Fix it');
      expect(withField('- [ ] Fix ⏫ 📆 2026-10-01 📅 2026-10-02', 'due', null), '- [ ] Fix ⏫');
      expect(withField('- [ ] Fix it', 'due', null), '- [ ] Fix it');
    });

    test('takes a priority by its emoji, and writes the emoji without its selector', () {
      expect(withField('- [ ] Fix', 'priority', '⏫️'), '- [ ] Fix ⏫');
      expect(withField('- [ ] Fix', 'priority', 'Lowest'), '- [ ] Fix ⏬');
    });

    test('leaves the line as it was for a value the field cannot hold', () {
      const line = '- [ ] Fix it 📅 2026-10-01';
      for (final (key, value) in [
        ('due', 'Friday'),
        ('due', '2026-02-30'),
        ('start', '3 Oct'),
        ('priority', 'urgent'),
        ('priority', 'normal'),
        ('recurs', 'every week; Monday'),
        ('recurs', ''),
        ('id', 'two words'),
        ('dependsOn', 'a,,b'),
        ('onCompletion', 'delete it'),
      ]) {
        expect(withField(line, key, value), line, reason: '$key=$value');
      }
    });

    test('writes Tasks’ others in their own signs', () {
      expect(withField('- [ ] Fix', 'id', 'fix1'), '- [ ] Fix 🆔 fix1');
      expect(withField('- [ ] Fix', 'dependsOn', 'a1, b2'), '- [ ] Fix ⛔ a1,b2');
      expect(withField('- [ ] Fix 📅 2026-10-03', 'onCompletion', 'delete'), '- [ ] Fix 🏁 delete 📅 2026-10-03');
    });

    test('never reaches into code for a field to change', () {
      expect(withField('- [ ] Explain `📅 2026-10-01`', 'due', day), '- [ ] Explain `📅 2026-10-01` 📅 2026-10-03');
    });

    test('leaves the line where Obsidian Tasks still reads its due date', () {
      var line = '- [ ] Fix the login loop #bug ^login-loop';
      line = withField(line, 'due', day);
      expect(tasksDue(line), day);
      line = withAssignee(line, 'sam');
      line = withField(line, 'effort', '3');
      line = withField(line, 'priority', 'high');
      line = withField(line, 'recurs', 'every week');
      expect(line, '- [ ] Fix the login loop #bug @sam [effort:: 3] ⏫ 🔁 every week 📅 2026-10-03 ^login-loop');
      expect(tasksDue(line), day);
      // Matt's own order, a person among the fields, is read here, and is words to Tasks.
      expect(tasksDue('- [ ] Fix the login loop 📅 2026-10-03 ⏫ @sam #bug ^login-loop'), isNull);
    });
  });

  group('a named field written', () {
    test('goes before the run of Tasks’ fields, as Dataview writes it', () {
      expect(withField('- [ ] Fix', 'effort', '3'), '- [ ] Fix [effort:: 3]');
      expect(withField('- [ ] Fix ⏫ 📅 2026-10-03 ^fix', 'effort', '3'), '- [ ] Fix [effort:: 3] ⏫ 📅 2026-10-03 ^fix');
      expect(withField('- [ ] Fix', 'blocked by', '[[GHO-9]]'), '- [ ] Fix [blocked by:: [[GHO-9]]]');
    });

    test('is changed where it is, its key as the person wrote it, and taken off', () {
      expect(withField('- [ ] Fix [Effort:: 3] now', 'effort', '5'), '- [ ] Fix [Effort:: 5] now');
      expect(withField('- [ ] Fix [Story Points:: 3]', 'story-points', '8'), '- [ ] Fix [Story Points:: 8]');
      expect(withField('- [ ] Fix [effort:: 3] now', 'Effort', null), '- [ ] Fix now');
    });

    test('keeps Dataview’s form for a date or a priority written that way', () {
      expect(withField('- [ ] Pay [due:: 2026-10-01]', 'due', '2026-10-03'), '- [ ] Pay [due:: 2026-10-03]');
      expect(withField('- [ ] Pay [priority:: low]', 'priority', '⏫'), '- [ ] Pay [priority:: high]');
      expect(withField('- [ ] Pay [due:: 2026-10-01] 📅 2026-10-02', 'due', null), '- [ ] Pay');
      expect(withField('- [ ] Pay [due:: 2026-10-01]', 'due', 'Friday'), '- [ ] Pay [due:: 2026-10-01]');
    });

    test('leaves the line as it was for a key or a value it cannot hold', () {
      const line = '- [ ] Fix';
      for (final (key, value) in [('', '3'), ('a:b', '3'), ('a]b', '3'), ('[effort', '3'), ('effort', 'a]b'), ('effort', 'a [b] c')]) {
        expect(withField(line, key, value), line, reason: '$key=$value');
      }
    });
  });

  group('a person written', () {
    test('goes before the run of Tasks’ fields, as a handle', () {
      expect(withAssignee('- [ ] Fix it', 'Sam'), '- [ ] Fix it @Sam');
      expect(withAssignee('- [ ] Fix it ⏫ 📅 2026-10-03 ^fix', 'sam'), '- [ ] Fix it @sam ⏫ 📅 2026-10-03 ^fix');
      expect(withAssignee('- [ ] Fix it', 'Sam Ortiz'), '- [ ] Fix it @Sam-Ortiz');
      expect(withAssignee('- [ ] ', '@ana'), '- [ ] @ana');
    });

    test('goes after the people already there, and is not added twice', () {
      expect(withAssignee('- [ ] Fix it @sam 📅 2026-10-03', 'ana'), '- [ ] Fix it @sam @ana 📅 2026-10-03');
      expect(withAssignee('- [ ] Fix it @sam', 'Sam'), '- [ ] Fix it @sam');
      expect(withAssignee('- [ ] Ask @Sam-Ortiz', 'sam ortiz'), '- [ ] Ask @Sam-Ortiz');
    });

    test('is taken off wherever they are mentioned, and only them', () {
      expect(withAssignee('- [ ] Fix it @sam @ana', 'Sam', false), '- [ ] Fix it @ana');
      expect(withAssignee('- [ ] @sam fix it', 'sam', false), '- [ ] fix it');
      expect(withAssignee('- [ ] Fix it @ana', 'sam', false), '- [ ] Fix it @ana');
    });

    test('leaves the line alone for a name with nothing to make a handle of', () {
      expect(withAssignee('- [ ] Fix it', '123'), '- [ ] Fix it');
      expect(withAssignee('- [ ] Fix it', '  '), '- [ ] Fix it');
    });

    test('is never found in a redaction to take off', () {
      expect(withAssignee('- [ ] Ask @@@sam@@', 'sam', false), '- [ ] Ask @@@sam@@');
    });
  });
}
