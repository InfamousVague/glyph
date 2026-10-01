import { describe, expect, it } from 'vitest';
import { markOf } from './itemLinks.ts';
import { anchorSpan, lineWords, withoutLead, wordsEnd } from './itemSyntax.ts';
import {
  DATE_KEYS,
  FIELD_EMOJI,
  NO_PRIORITY_RANK,
  PRIORITIES,
  TASKS_ORDER,
  fieldKey,
  fieldsIn,
  fieldsOf,
  isDateKey,
  isTasksKey,
  personHandle,
  personKey,
  priorityOf,
  priorityRank,
  samePerson,
  withAssignee,
  withField,
  withoutFields,
} from './taskFields.ts';

/*
 * "One grammar per syntax, tested line by line" (core/itemSyntax.ts). The fields are read by the chips, the voice, a
 * board's cards, a title sent away and a query's table, and written by a picker and a spoken "due Friday": these are
 * the lines every one of them must agree about, and the ones Obsidian Tasks must still read after the app has written.
 */

/** What each field in `text` is, as `kind key=value`, in order. */
const said = (text: string) => fieldsIn(text).map((span) => `${span.kind} ${span.key}=${span.value}`);
/** What each field in `text` covers, as written. */
const written = (text: string) => fieldsIn(text).map((span) => text.slice(span.from, span.to));

/**
 * How Obsidian Tasks reads a line's due date: its fields from the end of the line, a block link and tags aside, up to
 * the first thing that is not one of them. A due date anywhere else is words to it.
 */
function tasksDue(line: string): string | null {
  let rest = withoutLead(line)
    .replace(/\s+\^[A-Za-z0-9-]+\s*$/, '')
    .trimEnd();
  let due: string | null = null;
  for (;;) {
    const before = rest;
    rest = rest
      .replace(/\s*📅️?\s*(\d{4}-\d{2}-\d{2})$/u, (_all, day: string) => {
        due ??= day;
        return '';
      })
      .replace(/\s*(?:🔺|⏫|🔼|🔽|⏬)️?$/u, '')
      .replace(/\s*(?:🛫|⏳|✅|➕|❌)️?\s*\d{4}-\d{2}-\d{2}$/u, '')
      .replace(/\s*🔁️?\s*[a-zA-Z0-9, !]+$/u, '')
      .replace(/\s+#[^\s#]+$/u, '');
    if (rest === before) return due;
  }
}

describe('priorities', () => {
  it('are Tasks’ five, the most urgent first, each with its emoji and its rank', () => {
    expect(PRIORITIES.map((p) => `${p.emoji} ${p.name} ${p.label} ${p.rank}`)).toEqual([
      '🔺 highest Highest 0',
      '⏫ high High 1',
      '🔼 medium Medium 2',
      '🔽 low Low 4',
      '⏬ lowest Lowest 5',
    ]);
  });

  it('are read from a name in any case, or from the emoji with or without its variation selector', () => {
    expect(priorityOf('high')?.name).toBe('high');
    expect(priorityOf(' Highest ')?.name).toBe('highest');
    expect(priorityOf('LOW')?.emoji).toBe('🔽');
    expect(priorityOf('⏫')?.name).toBe('high');
    expect(priorityOf('⏫️')?.name).toBe('high');
    expect(priorityOf('🔺')?.name).toBe('highest');
    expect(priorityOf('⏬')?.name).toBe('lowest');
  });

  it('are nothing for anything else, normal and none included', () => {
    for (const word of ['', 'normal', 'none', 'urgent', 'p1', 'hi', 'high!', '⬆️']) expect(priorityOf(word), word).toBeNull();
    expect(priorityOf(null)).toBeNull();
    expect(priorityOf(undefined)).toBeNull();
  });

  it('sort an item with none between medium and low, as Tasks does', () => {
    expect(NO_PRIORITY_RANK).toBe(3);
    expect(priorityRank(null)).toBe(3);
    expect(priorityRank(undefined)).toBe(3);
    const sorted = (['low', null, 'highest', 'medium', 'lowest', 'high'] as const).slice().sort((a, b) => priorityRank(a) - priorityRank(b));
    expect(sorted).toEqual(['highest', 'high', 'medium', null, 'low', 'lowest']);
  });
});

describe('the fields’ names', () => {
  it('keep Tasks’ order, the dates last, done the last of all', () => {
    expect(TASKS_ORDER).toEqual(['id', 'dependsOn', 'priority', 'recurs', 'onCompletion', 'created', 'start', 'scheduled', 'due', 'cancelled', 'done']);
    expect(DATE_KEYS).toEqual(['created', 'start', 'scheduled', 'due', 'cancelled', 'done']);
    expect(FIELD_EMOJI).toMatchObject({ due: '📅', start: '🛫', scheduled: '⏳', done: '✅', created: '➕', cancelled: '❌', recurs: '🔁', id: '🆔', dependsOn: '⛔', onCompletion: '🏁' });
  });

  it('say which are dates and which are Tasks’', () => {
    expect(isDateKey('due')).toBe(true);
    expect(isDateKey('priority')).toBe(false);
    expect(isTasksKey('priority')).toBe(true);
    expect(isTasksKey('recurs')).toBe(true);
    expect(isTasksKey('effort')).toBe(false);
    expect(isTasksKey('assignee')).toBe(false);
  });

  it('compare a named field as Dataview does: lower case, a dash for each run of spaces', () => {
    expect(fieldKey('Due Date')).toBe('due-date');
    expect(fieldKey('  Effort ')).toBe('effort');
    expect(fieldKey('story  points')).toBe('story-points');
    expect(fieldKey('due-date')).toBe('due-date');
  });
});

describe('people', () => {
  it('are written as a handle: the at sign off, spaces a dash, what a handle cannot hold dropped', () => {
    expect(personHandle('Sam')).toBe('Sam');
    expect(personHandle('@sam')).toBe('sam');
    expect(personHandle('  Sam Ortiz ')).toBe('Sam-Ortiz');
    expect(personHandle('@@sam.')).toBe('sam');
    expect(personHandle("O'Brien")).toBe('OBrien');
    expect(personHandle('Zoë')).toBe('Zoë');
    expect(personHandle('sam.jones')).toBe('sam.jones');
    expect(personHandle('2pac')).toBe('pac');
  });

  it('have no handle where nothing of the name can be one', () => {
    for (const name of ['', '   ', '@', '123', '...', '@-']) expect(personHandle(name), name).toBeNull();
  });

  it('are one person however they are mentioned', () => {
    expect(personKey('@Sam')).toBe('sam');
    expect(personKey('Sam Ortiz')).toBe('sam-ortiz');
    expect(samePerson('@sam', 'Sam')).toBe(true);
    expect(samePerson('sam-ortiz', 'Sam Ortiz')).toBe(true);
    expect(samePerson('sam', 'samuel')).toBe(false);
    expect(samePerson('', '')).toBe(false);
  });
});

describe('the fields in a text', () => {
  it('reads Matt’s line: a date, a priority and a person, and leaves the tag and the anchor', () => {
    const line = '- [ ] Fix the login loop 📅 2026-10-03 ⏫ @sam #bug ^login-loop';
    expect(fieldsIn(line)).toEqual([
      { kind: 'date', key: 'due', value: '2026-10-03', from: 25, to: 38 },
      { kind: 'priority', key: 'priority', value: 'high', from: 39, to: 40 },
      { kind: 'person', key: 'assignee', value: 'sam', from: 41, to: 45 },
    ]);
    expect(written(line)).toEqual(['📅 2026-10-03', '⏫', '@sam']);
  });

  it('reads every date by its sign, and the other signs Tasks reads for due and scheduled', () => {
    expect(said('📅 2026-10-03 🛫 2026-10-01 ⏳ 2026-10-02 ✅ 2026-10-04 ➕ 2026-09-30 ❌ 2026-10-05')).toEqual([
      'date due=2026-10-03',
      'date start=2026-10-01',
      'date scheduled=2026-10-02',
      'date done=2026-10-04',
      'date created=2026-09-30',
      'date cancelled=2026-10-05',
    ]);
    expect(said('📆 2026-10-03 🗓 2026-10-04 🗓️ 2026-10-05 ⌛ 2026-10-06')).toEqual(['date due=2026-10-03', 'date due=2026-10-04', 'date due=2026-10-05', 'date scheduled=2026-10-06']);
  });

  it('takes a date with the variation selector, no space, or several', () => {
    expect(written('📅️ 2026-10-03')).toEqual(['📅️ 2026-10-03']);
    expect(said('📅2026-10-03')).toEqual(['date due=2026-10-03']);
    expect(written('a 📅   2026-10-03 b')).toEqual(['📅   2026-10-03']);
    expect(said('📅\t2026-10-03')).toEqual(['date due=2026-10-03']);
  });

  it('keeps a date as written, even one the calendar has not got: the note says what it says', () => {
    expect(said('📅 2026-02-30')).toEqual(['date due=2026-02-30']);
  });

  it('is no date without a day after the sign in ISO’s form', () => {
    for (const text of ['📅', '📅 tomorrow', '📅 2026-10-3', '📅 20261003', '📅 03-10-2026', '📅 2026-10-031', '📅\n2026-10-03']) expect(said(text), text).toEqual([]);
  });

  it('reads each priority, with or without its selector, anywhere in the words', () => {
    expect(said('🔺 ⏫ 🔼 🔽 ⏬')).toEqual(['priority priority=highest', 'priority priority=high', 'priority priority=medium', 'priority priority=low', 'priority priority=lowest']);
    expect(written('Fix⏫️ now')).toEqual(['⏫️']);
  });

  it('reads a recurrence’s rule to the next field, a tag, a person or the tail, and not its trailing commas', () => {
    expect(said('🔁 every week on Monday 📅 2026-10-03')).toEqual(['recurs recurs=every week on Monday', 'date due=2026-10-03']);
    expect(said('🔁 every day when done')).toEqual(['recurs recurs=every day when done']);
    expect(written('🔁 every 2 weeks, 📅 2026-10-03')).toEqual(['🔁 every 2 weeks', '📅 2026-10-03']);
    expect(written('🔁 every week ^chores')).toEqual(['🔁 every week']);
    expect(written('🔁 every week #home')).toEqual(['🔁 every week']);
    expect(written('🔁 every week @sam')).toEqual(['🔁 every week', '@sam']);
    expect(written('🔁 every month [3/8]')).toEqual(['🔁 every month']);
    expect(written('🔁 every month!')).toEqual(['🔁 every month!']);
  });

  it('is no recurrence without words after the sign', () => {
    expect(said('🔁')).toEqual([]);
    expect(said('🔁 #home')).toEqual([]);
  });

  it('reads Tasks’ id, what it waits on and what to do when it is done, as they are', () => {
    expect(said('🆔 abc123 ⛔ def456,ghi789 🏁 delete')).toEqual(['tasks id=abc123', 'tasks dependsOn=def456,ghi789', 'tasks onCompletion=delete']);
    expect(said('⛔ a1, b2')).toEqual(['tasks dependsOn=a1, b2']);
  });

  it('reads a person after the start, a space or an opening bracket', () => {
    expect(said('@sam')).toEqual(['person assignee=sam']);
    expect(written('Ask (@sam) and [@ana] and {@lee}')).toEqual(['@sam', '@ana', '@lee']);
    expect(said('cc @Sam.Jones and @sam_o and @ana-b')).toEqual(['person assignee=Sam.Jones', 'person assignee=sam_o', 'person assignee=ana-b']);
    expect(said('@Zoë and @李')).toEqual(['person assignee=Zoë', 'person assignee=李']);
  });

  it('leaves a trailing full stop or dash to the sentence', () => {
    expect(written('Ask @sam.')).toEqual(['@sam']);
    expect(written('Ask @sam-- then')).toEqual(['@sam']);
    expect(said('Ask @sam...')).toEqual(['person assignee=sam']);
  });

  it('is no person in an address, a redaction, a time, a lone at sign or a word', () => {
    for (const text of ['sam@example.com', 'mail sam@example.com', '@@Sam Ortiz@@', 'meet @ 2pm', 'meet @2pm', '@', 'a @ b', 'x@sam', '"@sam"', '@sam@mastodon.social', 'https://medium.com/@sam', '@_sam']) {
      expect(said(text), text).toEqual([]);
    }
  });

  it('is no field inside a redaction', () => {
    expect(said('@@ask @dave about 📅 2026-10-03@@ and @sam')).toEqual(['person assignee=sam']);
  });

  it('reads a named field, Dataview’s, its key as Dataview compares it and its value trimmed', () => {
    expect(fieldsIn('Fix [effort:: 3] now')).toEqual([{ kind: 'inline', key: 'effort', value: '3', from: 4, to: 16 }]);
    expect(said('[Due Date:: 2026-10-03]')).toEqual(['inline due-date=2026-10-03']);
    expect(said('[key ::  spaced out  ]')).toEqual(['inline key=spaced out']);
    expect(said('[empty::]')).toEqual(['inline empty=']);
    expect(said('[blocked:: [[GHO-9]]]')).toEqual(['inline blocked=[[GHO-9]]']);
    expect(said('[blocked:: [[GHO-9]], [[GHO-10|the loop]]]')).toEqual(['inline blocked=[[GHO-9]], [[GHO-10|the loop]]']);
    expect(said('[size.cm:: 30] [a/b:: c] [x_y:: z]')).toEqual(['inline size.cm=30', 'inline a/b=c', 'inline x_y=z']);
  });

  it('is no named field in a link, a note link, a picture, one colon, or with no key', () => {
    for (const text of ['[key:: v](https://x.y)', '[[key:: v]]', '![key:: v]', '[key: v]', '[:: v]', '[ key:: v]', '[key:: a [b] c]']) expect(said(text), text).toEqual([]);
  });

  it('takes the field that starts first where two would overlap: a person in a named field is its value', () => {
    expect(said('[owner:: @sam] and @ana')).toEqual(['inline owner=@sam', 'person assignee=ana']);
    expect(said('[when:: 📅 2026-10-03]')).toEqual(['inline when=📅 2026-10-03']);
  });

  it('finds nothing in quiet words: code, an address, a note link’s title, maths, HTML', () => {
    expect(said('Explain `📅 2026-10-03` and ``@sam``')).toEqual([]);
    expect(said('[the doc](https://x.com/@sam/📅 2026-10-03)')).toEqual([]);
    expect(said('see [[@sam notes]] and [[Plan ⏫]]')).toEqual([]);
    expect(said('$a @b$')).toEqual([]);
    expect(said('<span title="@sam">x</span>')).toEqual([]);
  });

  it('finds nothing in fenced code or front matter, and counts positions across lines', () => {
    const note = '---\nowner: "@sam"\n---\n- [ ] Ship @ana\n```\n- [ ] Not @lee\n```\n- [ ] Due 📅 2026-10-03';
    expect(written(note)).toEqual(['@ana', '📅 2026-10-03']);
    expect(fieldsIn(note)[0]!.from).toBe(note.indexOf('@ana'));
  });

  it('counts positions from the offset given', () => {
    expect(fieldsIn('a @b', 10)).toEqual([{ kind: 'person', key: 'assignee', value: 'b', from: 12, to: 14 }]);
    expect(fieldsIn('', 10)).toEqual([]);
  });

  it('leaves the item’s own signs alone: the box, a counter, the mark, the anchor, the bookmark, a tag', () => {
    expect(said('- [x] Ship it #web §§ [notion](https://n.so/a) [3/8] ^ship')).toEqual([]);
  });
});

describe('what the fields say', () => {
  it('reads Matt’s line into one record', () => {
    expect(fieldsOf('- [ ] Fix the login loop 📅 2026-10-03 ⏫ @sam #bug ^login-loop')).toEqual({
      due: '2026-10-03',
      start: null,
      scheduled: null,
      done: null,
      created: null,
      cancelled: null,
      recurs: null,
      priority: 'high',
      assignees: ['sam'],
      id: null,
      dependsOn: [],
      onCompletion: null,
      fields: {},
    });
  });

  it('reads every kind at once', () => {
    const fields = fieldsOf('Pay rent @sam @Ana 🔺 🔁 every month 🆔 rent ⛔ pay,bank 🏁 keep ➕ 2026-09-01 🛫 2026-09-28 ⏳ 2026-09-30 📅 2026-10-01 ❌ 2026-10-02 ✅ 2026-10-03 [effort:: 2]');
    expect(fields).toMatchObject({
      due: '2026-10-01',
      start: '2026-09-28',
      scheduled: '2026-09-30',
      done: '2026-10-03',
      created: '2026-09-01',
      cancelled: '2026-10-02',
      recurs: 'every month',
      priority: 'highest',
      assignees: ['sam', 'Ana'],
      id: 'rent',
      dependsOn: ['pay', 'bank'],
      onCompletion: 'keep',
    });
    expect(fields.fields).toEqual({ effort: '2' });
  });

  it('takes the first of a repeated field, and each person once', () => {
    const fields = fieldsOf('📅 2026-10-03 📅 2026-11-01 🔽 ⏫ @sam @Sam @SAM. @ana [a:: 1] [A:: 2] ⛔ x,y ⛔ y,z');
    expect(fields.due).toBe('2026-10-03');
    expect(fields.priority).toBe('low');
    expect(fields.assignees).toEqual(['sam', 'ana']);
    expect(fields.fields).toEqual({ a: '1' });
    expect(fields.dependsOn).toEqual(['x', 'y', 'z']);
  });

  it('is empty for words with no fields, and its named fields have no inherited keys', () => {
    const fields = fieldsOf('Just words #tag');
    expect(fields.assignees).toEqual([]);
    expect(fields.due).toBeNull();
    expect(fields.fields).toEqual({});
    expect(fields.fields['constructor']).toBeUndefined();
    expect(fieldsOf('').priority).toBeNull();
  });

  it('reads Dataview’s own names for a task’s dates, and a priority by name, where there is no emoji for them', () => {
    const fields = fieldsOf('Pay [due:: 2026-10-03] [start:: 2026-10-01] [scheduled:: 2026-10-02] [created:: 2026-09-01] [completion:: 2026-10-04] [cancelled:: 2026-10-05] [priority:: High]');
    expect(fields).toMatchObject({ due: '2026-10-03', start: '2026-10-01', scheduled: '2026-10-02', created: '2026-09-01', done: '2026-10-04', cancelled: '2026-10-05', priority: 'high' });
    expect(fields.fields.due).toBe('2026-10-03');
  });

  it('lets the emoji win over Dataview’s name, and a named date that is not a day stay a named field', () => {
    expect(fieldsOf('[due:: 2026-10-01] 📅 2026-10-03').due).toBe('2026-10-03');
    expect(fieldsOf('[priority:: low] ⏫').priority).toBe('high');
    const fields = fieldsOf('[due:: Friday] [priority:: soon]');
    expect(fields.due).toBeNull();
    expect(fields.priority).toBeNull();
    expect(fields.fields).toEqual({ due: 'Friday', priority: 'soon' });
  });
});

describe('the words without their fields', () => {
  it('are what the item says, a tag kept as words', () => {
    expect(withoutFields('Fix the login loop @sam #bug ⏫ 📅 2026-10-03')).toBe('Fix the login loop #bug');
    expect(withoutFields('Fix the login loop 📅 2026-10-03 ⏫ @sam #bug')).toBe('Fix the login loop #bug');
  });

  it('take a field from the start, the middle or the end, and tidy the spaces it leaves', () => {
    expect(withoutFields('@sam fix it')).toBe('fix it');
    expect(withoutFields('Call [phone:: 555 0100] tomorrow')).toBe('Call tomorrow');
    expect(withoutFields('  Pay   rent 🔁 every month  ')).toBe('Pay rent');
    expect(withoutFields('⏫')).toBe('');
  });

  it('leave words with no fields, and fields in code, as they are', () => {
    expect(withoutFields('Buy milk')).toBe('Buy milk');
    expect(withoutFields('Explain `📅 2026-10-03` to sam@example.com')).toBe('Explain `📅 2026-10-03` to sam@example.com');
  });

  it('are what a card or a title says when read through the item’s grammar', () => {
    expect(withoutFields(lineWords('- [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03 ^login-loop'))).toBe('Fix the login loop #bug');
  });
});

describe('a field written', () => {
  const DAY = '2026-10-03';

  it('goes at the end of the words of a to-do, a bullet, a number, or a line that is not an item', () => {
    expect(withField('- [ ] Fix it', 'due', DAY)).toBe('- [ ] Fix it 📅 2026-10-03');
    expect(withField('* Fix it', 'due', DAY)).toBe('* Fix it 📅 2026-10-03');
    expect(withField('  3. Fix it', 'due', DAY)).toBe('  3. Fix it 📅 2026-10-03');
    expect(withField('Fix it', 'due', DAY)).toBe('Fix it 📅 2026-10-03');
    expect(withField('', 'due', DAY)).toBe('📅 2026-10-03');
  });

  it('goes after the box of an empty to-do, with one space', () => {
    expect(withField('- [ ] ', 'due', DAY)).toBe('- [ ] 📅 2026-10-03');
    expect(withField('- [ ]', 'due', DAY)).toBe('- [ ] 📅 2026-10-03');
    expect(withField('- [ ] ^fix', 'priority', 'high')).toBe('- [ ] ⏫ ^fix');
  });

  it('goes before the tail - the bookmark, the mark, a counter, the anchor - which still reads as the tail', () => {
    const line = withField('- [ ] Ship it §§ [notion](https://n.so/a) [3/8] ^ship', 'due', DAY);
    expect(line).toBe('- [ ] Ship it 📅 2026-10-03 §§ [notion](https://n.so/a) [3/8] ^ship');
    expect(line.slice(0, wordsEnd(line))).toBe('- [ ] Ship it 📅 2026-10-03');
    expect(anchorSpan(line)?.id).toBe('ship');
    expect(withField('- [ ] Ship it [notion](https://n.so/a) ^ship', 'priority', 'high')).toBe('- [ ] Ship it ⏫ [notion](https://n.so/a) ^ship');
    expect(markOf(withField('- [ ] Ship it [notion](https://n.so/a) ^ship', 'priority', 'high'))?.name).toBe('notion');
    expect(withField('- Water [3/8]', 'due', DAY)).toBe('- Water 📅 2026-10-03 [3/8]');
    expect(withField('- [ ] Read §§', 'due', DAY)).toBe('- [ ] Read 📅 2026-10-03 §§');
  });

  it('keeps Tasks’ order however the fields are added', () => {
    let line = '- [ ] Pay rent ^rent';
    line = withField(line, 'due', '2026-10-01');
    line = withField(line, 'priority', 'high');
    line = withField(line, 'done', '2026-10-02');
    line = withField(line, 'start', '2026-09-28');
    line = withField(line, 'recurs', 'every month');
    line = withField(line, 'created', '2026-09-01');
    line = withField(line, 'scheduled', '2026-09-30');
    line = withField(line, 'cancelled', '2026-10-05');
    expect(line).toBe('- [ ] Pay rent ⏫ 🔁 every month ➕ 2026-09-01 🛫 2026-09-28 ⏳ 2026-09-30 📅 2026-10-01 ❌ 2026-10-05 ✅ 2026-10-02 ^rent');
  });

  it('goes into the run of Tasks’ fields with the tags among them, never after words', () => {
    expect(withField('- [ ] Fix ⏫ #bug ^fix', 'due', DAY)).toBe('- [ ] Fix ⏫ 📅 2026-10-03 #bug ^fix');
    expect(withField('- [ ] Fix #bug 📅 2026-10-03', 'priority', 'high')).toBe('- [ ] Fix #bug ⏫ 📅 2026-10-03');
    expect(withField('- [ ] Fix #bug', 'due', DAY)).toBe('- [ ] Fix #bug 📅 2026-10-03');
    // A field in the middle of the words is not the run's: the new one goes at the end, where Tasks will read it.
    expect(withField('- [ ] Pay ⏫ the rent', 'due', DAY)).toBe('- [ ] Pay ⏫ the rent 📅 2026-10-03');
  });

  it('is changed where it is, in the sign it is written in, and a second of it taken off', () => {
    expect(withField('- [ ] Pay 📅 2026-10-01 the rent', 'due', DAY)).toBe('- [ ] Pay 📅 2026-10-03 the rent');
    expect(withField('- [ ] Pay 📆 2026-10-01 ^rent', 'due', DAY)).toBe('- [ ] Pay 📅 2026-10-03 ^rent');
    expect(withField('- [ ] Pay 📅 2026-10-01 📅 2026-10-02 ^rent', 'due', DAY)).toBe('- [ ] Pay 📅 2026-10-03 ^rent');
    expect(withField('- [ ] Pay 🔽 ^rent', 'priority', 'highest')).toBe('- [ ] Pay 🔺 ^rent');
    expect(withField('- [ ] Pay 🔁 every week', 'recurs', 'every 2 weeks')).toBe('- [ ] Pay 🔁 every 2 weeks');
  });

  it('is taken off with the space before it, or after it where it opens the words', () => {
    expect(withField('- [ ] Fix it 📅 2026-10-03 ^fix', 'due', null)).toBe('- [ ] Fix it ^fix');
    expect(withField('- [ ] 📅 2026-10-03 Fix it', 'due', null)).toBe('- [ ] Fix it');
    expect(withField('- [ ] 📅 2026-10-03', 'due', null)).toBe('- [ ] ');
    expect(withField('📅 2026-10-03 Fix it', 'due', null)).toBe('Fix it');
    expect(withField('- [ ] Fix ⏫ 📆 2026-10-01 📅 2026-10-02', 'due', null)).toBe('- [ ] Fix ⏫');
    expect(withField('- [ ] Fix it', 'due', null)).toBe('- [ ] Fix it');
  });

  it('takes a priority by its emoji, and writes the emoji without its selector', () => {
    expect(withField('- [ ] Fix', 'priority', '⏫️')).toBe('- [ ] Fix ⏫');
    expect(withField('- [ ] Fix', 'priority', 'Lowest')).toBe('- [ ] Fix ⏬');
  });

  it('leaves the line as it was for a value the field cannot hold', () => {
    const line = '- [ ] Fix it 📅 2026-10-01';
    for (const [key, value] of [
      ['due', 'Friday'],
      ['due', '2026-02-30'],
      ['start', '3 Oct'],
      ['priority', 'urgent'],
      ['priority', 'normal'],
      ['recurs', 'every week; Monday'],
      ['recurs', ''],
      ['id', 'two words'],
      ['dependsOn', 'a,,b'],
      ['onCompletion', 'delete it'],
    ] as const) {
      expect(withField(line, key, value), `${key}=${value}`).toBe(line);
    }
  });

  it('writes Tasks’ others in their own signs', () => {
    expect(withField('- [ ] Fix', 'id', 'fix1')).toBe('- [ ] Fix 🆔 fix1');
    expect(withField('- [ ] Fix', 'dependsOn', 'a1, b2')).toBe('- [ ] Fix ⛔ a1,b2');
    expect(withField('- [ ] Fix 📅 2026-10-03', 'onCompletion', 'delete')).toBe('- [ ] Fix 🏁 delete 📅 2026-10-03');
  });

  it('never reaches into code for a field to change', () => {
    expect(withField('- [ ] Explain `📅 2026-10-01`', 'due', DAY)).toBe('- [ ] Explain `📅 2026-10-01` 📅 2026-10-03');
  });

  it('leaves the line where Obsidian Tasks still reads its due date', () => {
    let line = '- [ ] Fix the login loop #bug ^login-loop';
    line = withField(line, 'due', DAY);
    expect(tasksDue(line)).toBe(DAY);
    line = withAssignee(line, 'sam');
    line = withField(line, 'effort', '3');
    line = withField(line, 'priority', 'high');
    line = withField(line, 'recurs', 'every week');
    expect(line).toBe('- [ ] Fix the login loop #bug @sam [effort:: 3] ⏫ 🔁 every week 📅 2026-10-03 ^login-loop');
    expect(tasksDue(line)).toBe(DAY);
    // Matt's own order, a person among the fields, is read here, and is words to Tasks.
    expect(tasksDue('- [ ] Fix the login loop 📅 2026-10-03 ⏫ @sam #bug ^login-loop')).toBeNull();
  });
});

describe('a named field written', () => {
  it('goes before the run of Tasks’ fields, as Dataview writes it', () => {
    expect(withField('- [ ] Fix', 'effort', '3')).toBe('- [ ] Fix [effort:: 3]');
    expect(withField('- [ ] Fix ⏫ 📅 2026-10-03 ^fix', 'effort', '3')).toBe('- [ ] Fix [effort:: 3] ⏫ 📅 2026-10-03 ^fix');
    expect(withField('- [ ] Fix', 'blocked by', '[[GHO-9]]')).toBe('- [ ] Fix [blocked by:: [[GHO-9]]]');
  });

  it('is changed where it is, its key as the person wrote it, and taken off', () => {
    expect(withField('- [ ] Fix [Effort:: 3] now', 'effort', '5')).toBe('- [ ] Fix [Effort:: 5] now');
    expect(withField('- [ ] Fix [Story Points:: 3]', 'story-points', '8')).toBe('- [ ] Fix [Story Points:: 8]');
    expect(withField('- [ ] Fix [effort:: 3] now', 'Effort', null)).toBe('- [ ] Fix now');
  });

  it('keeps Dataview’s form for a date or a priority written that way', () => {
    expect(withField('- [ ] Pay [due:: 2026-10-01]', 'due', '2026-10-03')).toBe('- [ ] Pay [due:: 2026-10-03]');
    expect(withField('- [ ] Pay [priority:: low]', 'priority', '⏫')).toBe('- [ ] Pay [priority:: high]');
    expect(withField('- [ ] Pay [due:: 2026-10-01] 📅 2026-10-02', 'due', null)).toBe('- [ ] Pay');
    expect(withField('- [ ] Pay [due:: 2026-10-01]', 'due', 'Friday')).toBe('- [ ] Pay [due:: 2026-10-01]');
  });

  it('leaves the line as it was for a key or a value it cannot hold', () => {
    const line = '- [ ] Fix';
    for (const [key, value] of [
      ['', '3'],
      ['a:b', '3'],
      ['a]b', '3'],
      ['[effort', '3'],
      ['effort', 'a]b'],
      ['effort', 'a [b] c'],
    ] as const) {
      expect(withField(line, key, value), `${key}=${value}`).toBe(line);
    }
  });
});

describe('a person written', () => {
  it('goes before the run of Tasks’ fields, as a handle', () => {
    expect(withAssignee('- [ ] Fix it', 'Sam')).toBe('- [ ] Fix it @Sam');
    expect(withAssignee('- [ ] Fix it ⏫ 📅 2026-10-03 ^fix', 'sam')).toBe('- [ ] Fix it @sam ⏫ 📅 2026-10-03 ^fix');
    expect(withAssignee('- [ ] Fix it', 'Sam Ortiz')).toBe('- [ ] Fix it @Sam-Ortiz');
    expect(withAssignee('- [ ] ', '@ana')).toBe('- [ ] @ana');
  });

  it('goes after the people already there, and is not added twice', () => {
    expect(withAssignee('- [ ] Fix it @sam 📅 2026-10-03', 'ana')).toBe('- [ ] Fix it @sam @ana 📅 2026-10-03');
    expect(withAssignee('- [ ] Fix it @sam', 'Sam')).toBe('- [ ] Fix it @sam');
    expect(withAssignee('- [ ] Ask @Sam-Ortiz', 'sam ortiz')).toBe('- [ ] Ask @Sam-Ortiz');
  });

  it('is taken off wherever they are mentioned, and only them', () => {
    expect(withAssignee('- [ ] Fix it @sam @ana', 'Sam', false)).toBe('- [ ] Fix it @ana');
    expect(withAssignee('- [ ] @sam fix it', 'sam', false)).toBe('- [ ] fix it');
    expect(withAssignee('- [ ] Fix it @ana', 'sam', false)).toBe('- [ ] Fix it @ana');
  });

  it('leaves the line alone for a name with nothing to make a handle of', () => {
    expect(withAssignee('- [ ] Fix it', '123')).toBe('- [ ] Fix it');
    expect(withAssignee('- [ ] Fix it', '  ')).toBe('- [ ] Fix it');
  });

  it('is never found in a redaction to take off', () => {
    expect(withAssignee('- [ ] Ask @@@sam@@', 'sam', false)).toBe('- [ ] Ask @@@sam@@');
  });
});
