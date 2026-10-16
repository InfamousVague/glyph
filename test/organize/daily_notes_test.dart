import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note_facts.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/notes/daily_notes.dart';
import 'package:ghost_md/notes/note_templates.dart';
import 'package:ghost_md/sync/prefs.dart' show syncedPrefs;

import '../core/make_note.dart';

/// Today's note (lib/notes/daily_notes.dart): one note a date, found by its name, made from a template.
void main() {
  final day = DateTime(2026, 10, 16, 9, 30);

  test('a day’s note is named by its date, and found again by it, never in the archive', () {
    expect(dailyTitle(day), '2026-10-16');
    final notes = [
      makeNote('old', body: '# 2026-10-16', createdAt: 1, archivedAt: 5),
      makeNote('later', body: '# 2026-10-16\n\nSecond', createdAt: 9),
      makeNote('first', body: '---\ntitle: "2026-10-16"\n---\n# Standup', createdAt: 3),
      makeNote('other', body: '# 2026-10-15', createdAt: 2),
    ];
    expect(dailyNoteOf(notes, day)?.id, 'first');
    expect(dailyNoteOf(notes, DateTime(2026, 10, 14)), isNull);
  });

  test('made from the built-in day, named by its heading', () {
    final made = dailyNoteBody(dailyTemplate(const DailyNotesSetup(), builtIns), day);
    expect(made.body, startsWith('# 2026-10-16\n\n'));
    expect(made.title, '2026-10-16');
    expect(NoteFacts.read(made.body).title, '2026-10-16');
    expect(made.body.substring(made.caret), '');
  });

  test('a template named in Settings, your own of that name first; one whose heading is no date is titled by it', () {
    const own = NoteTemplate(id: 'p1', name: 'Standup', sentence: 'One of your own.', words: '# Standup {{date}}\n\n- [ ] ');
    final picked = dailyTemplate(const DailyNotesSetup(template: 'standup'), [...builtIns, own]);
    expect(picked.id, 'p1');
    final made = dailyNoteBody(picked, day);
    expect(made.body, startsWith('---\ntitle: "2026-10-16"\n---\n# Standup '));
    expect(NoteFacts.read(made.body).title, '2026-10-16');
    expect(made.body.substring(made.caret), '');
    // A name nobody has: the day's.
    expect(dailyTemplate(const DailyNotesSetup(template: 'Gone'), builtIns).kind, TemplateId.day);
  });

  test('the choices round-trip through the preferences and travel with the account', () {
    final prefs = withDailyNotes(Preferences.defaults, const DailyNotesSetup(folder: '', notebook: 'n-book', template: 'Standup'));
    final again = Preferences.fromJson(jsonDecode(jsonEncode(prefs.toJson())));
    expect(dailyNotesIn(again), const DailyNotesSetup(folder: '', notebook: 'n-book', template: 'Standup'));
    expect(dailyNotesIn(Preferences.defaults), const DailyNotesSetup());
    expect(dailyNotesIn(Preferences.fromJson({dailyNotesKey: 7})), const DailyNotesSetup());
    expect(syncedPrefs, contains(dailyNotesKey));
  });
}
