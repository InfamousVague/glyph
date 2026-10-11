import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/kept_trash.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/trash.dart';

import 'support.dart';

/// The trash as a preference ([KeptTrash]): the cases of the web's `core/trash.test.ts`, over a preferences store of
/// the test's own, and what the web's `useTrash` gives a listener.
void main() {
  late PreferencesStore prefs;
  late KeptTrash trash;

  setUp(() {
    prefs = PreferencesStore()..startWithoutStorage();
    trash = KeptTrash(prefs: prefs, clock: () => 500);
    addTearDown(trash.dispose);
  });

  group('the trash', () {
    test('takes a note in and gives it back', () {
      trash.trashNote('a', 10);
      expect(trash.isTrashed('a'), isTrue);
      trash.restoreNote('a');
      expect(trash.isTrashed('a'), isFalse);
      expect(prefs.value.trash, isEmpty);
    });

    test('keeps a trashed note out of everything else, and shows the trash newest first', () {
      trash.trashNote('a', 10);
      trash.trashNote('c', 30);
      final notes = [makeNote('a'), makeNote('b'), makeNote('c')];
      expect(ids(outOfTrash(notes, trash.value)), ['b']);
      expect(ids(inTrash(notes, trash.value)), ['c', 'a']);
    });

    test('forgets notes deleted for good, and leaves the rest', () {
      trash.trashNote('a', 10);
      trash.trashNote('b', 20);
      trash.forget(['a', 'zz']);
      expect(prefs.value.trash, {'b': 20});
    });
  });

  group('the trash, kept as the preference it is', () {
    test('is the web’s stored shape: each note’s id and when it went in', () {
      trash.trashNote('a');
      trash.trashNote('b', 20);
      expect(prefs.value.toJson()['trash'], {'a': 500, 'b': 20});
      // And the next launch, or another device's settings landing, reads it back.
      final again = PreferencesStore()..startWithoutStorage();
      again.value = Preferences.fromJson(prefs.value.toJson());
      final next = KeptTrash(prefs: again);
      addTearDown(next.dispose);
      expect(next.value, {'a': 500, 'b': 20});
    });

    test('tells a listener when the trash changes, here or from another device, and not for any other setting', () {
      var told = 0;
      trash.addListener(() => told += 1);
      trash.trashNote('a', 10);
      expect(told, 1);
      final before = trash.value;
      // Any other setting changing leaves the trash, and whoever watches it, alone.
      prefs.update((now) => now.copyWith(ripples: !now.ripples));
      expect(told, 1);
      expect(trash.value, same(before));
      // Settings from another device land as a preference change.
      prefs.update((now) => now.copyWith(trash: {'a': 10, 'z': 40}));
      expect(told, 2);
      expect(trash.value, {'a': 10, 'z': 40});
      // Forgetting what is not there writes nothing.
      trash.forget(['nobody']);
      expect(told, 2);
    });

    test('reads rubbish in the preference as an empty trash', () {
      prefs.value = Preferences.fromJson({'trash': 'not a trash'});
      expect(trash.value, isEmpty);
      prefs.value = Preferences.fromJson({
        'trash': {'a': 10, 'b': 'yesterday', 'c': 30.0},
      });
      expect(trash.value, {'a': 10, 'c': 30});
    });
  });
}
