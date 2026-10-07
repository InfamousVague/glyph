import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/notes/when.dart';

/// A card's timestamp, read rather than parsed (lib/notes/when.dart): the cases of the web's `notes/when.test.ts`,
/// then every seeded note's as the web page says it in American English.
void main() {
  const minute = 60000;
  const hour = 60 * minute;
  const day = 24 * hour;
  // A Friday at noon, local time.
  final now = DateTime(2026, 9, 25, 12).millisecondsSinceEpoch;

  test('counts minutes and hours while they are few', () {
    expect(when(now - 30000, now), 'Just now');
    expect(when(now - 5 * minute, now), '5 min ago');
    expect(when(now - 59 * minute, now), '59 min ago');
    expect(when(now - 3 * hour, now), '3 hr ago');
  });

  test('says yesterday, then the day of the week, then the date', () {
    expect(when(now - 30 * hour, now), 'Yesterday');
    expect(when(now - 3 * day, now), 'Tuesday');
    expect(when(now - 30 * day, now), 'August 26');
  });

  test('says each seeded note’s as the web page does', () {
    final web = jsonDecode(File('test/core/fixtures/web_library.json').readAsStringSync()) as Map<String, dynamic>;
    for (final note in seedLibrary()) {
      expect(when(note.updatedAt, seedNow), web['read'][note.id]['when'], reason: note.id);
    }
  });
}
