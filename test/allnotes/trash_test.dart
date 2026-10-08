import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/trash.dart';

import '../core/make_note.dart';

/// The trash (lib/core/trash.dart), case for case with the web's `core/trash.test.ts`.
void main() {
  test('takes a note in and gives it back', () {
    final trash = MemoryTrash();
    trash.trashNote('a', 10);
    expect(trash.isTrashed('a'), isTrue);
    trash.restoreNote('a');
    expect(trash.isTrashed('a'), isFalse);
    expect(trash.value, isEmpty);
  });

  test('keeps a trashed note out of everything else, and shows the trash newest first', () {
    final trash = MemoryTrash();
    trash.trashNote('a', 10);
    trash.trashNote('c', 30);
    final notes = [makeNote('a'), makeNote('b'), makeNote('c')];
    expect(ids(outOfTrash(notes, trash.value)), ['b']);
    expect(ids(inTrash(notes, trash.value)), ['c', 'a']);
  });

  test('forgets notes deleted for good, and leaves the rest', () {
    final trash = MemoryTrash();
    trash.trashNote('a', 10);
    trash.trashNote('b', 20);
    trash.forget(['a', 'zz']);
    expect(trash.value, {'b': 20});
  });

  test('says so to whoever listens, and only when something changed', () {
    final trash = MemoryTrash(const {}, () => 99);
    var told = 0;
    trash.addListener(() => told += 1);
    trash.trashNote('a');
    expect(trash.value, {'a': 99});
    expect(told, 1);
    trash.forget(['zz']);
    expect(told, 1);
    trash.restoreNote('a');
    expect(told, 2);
  });
}
