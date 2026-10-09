import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/day_order.dart';
import 'package:ghost_md/core/note_names.dart';
import 'package:ghost_md/core/template.dart';

/// A long date is in the phone's order, as the page's `Intl.DateTimeFormat(undefined, …)` writes it
/// (core/day_order.dart).
void main() {
  tearDown(() => monthFirst = false);
  final day = DateTime(2026, 10, 9);

  test('the day comes first until the phone says otherwise, and for British English', () {
    expect(longDate(day), 'Friday, 9 October 2026');
    expect(longDay(day), 'Friday 9 October');
    useDayOrderOf(const Locale('en', 'GB'));
    expect(longDate(day), 'Friday, 9 October 2026');
  });

  test('American English puts the month first, with its commas', () {
    useDayOrderOf(const Locale('en', 'US'));
    expect(longDate(day), 'Friday, October 9, 2026');
    expect(longDay(day), 'Friday, October 9');
  });

  test('another language keeps the day first: the words are English either way', () {
    useDayOrderOf(const Locale('de', 'DE'));
    expect(monthFirst, isFalse);
  });
}
