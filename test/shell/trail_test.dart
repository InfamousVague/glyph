import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/shell/trail.dart';
import 'package:ghost_md/shell/visited.dart';

/// `notes/visited.test.ts` and `shell/useTrail.test.tsx`, case for case.
void main() {
  bool all(Place place) => true;

  group('the trail', () {
    test('starts on the list with nowhere to go', () {
      expect(Trail.first.canGoBack(all), isFalse);
      expect(Trail.first.canGoOn(all), isFalse);
    });

    test('remembers where you have been, in order', () {
      final trail = Trail.first.went(notePlace('a')).went(notePlace('b'));
      expect(trail.places, ['list', 'note:a', 'note:b']);
      expect(trail.at, 2);
    });

    test('does not record arriving where you already are', () {
      final once = Trail.first.went(notePlace('a'));
      expect(identical(once.went(notePlace('a')), once), isTrue);
    });

    test('goes back and forward over the same places', () {
      final trail = Trail.first.went(notePlace('a')).went(notePlace('b'));
      final back = trail.backFrom(all)!;
      expect(back.place, 'note:a');
      expect(back.onFrom(all)!.place, 'note:b');
    });

    test('forgets what was ahead once you go somewhere new from back there', () {
      final back = Trail.first.went(notePlace('a')).went(notePlace('b')).backFrom(all)!;
      final elsewhere = back.went(notePlace('c'));
      expect(elsewhere.places, ['list', 'note:a', 'note:c']);
      expect(elsewhere.canGoOn(all), isFalse);
    });

    test('steps over a note that has been deleted', () {
      final trail = Trail.first.went(notePlace('a')).went(notePlace('gone')).went(notePlace('b'));
      expect(trail.backFrom((place) => noteIdOf(place) != 'gone')!.place, 'note:a');
    });

    test('says there is nowhere to go when everything behind is deleted', () {
      expect(Trail.first.went(notePlace('gone')).canGoBack((place) => noteIdOf(place) != null), isFalse);
    });

    test('keeps the last places and no more', () {
      var trail = Trail.first;
      for (var i = 0; i < mostPlaces + 10; i++) {
        trail = trail.went(notePlace('n$i'));
      }
      expect(trail.places, hasLength(mostPlaces));
      expect(trail.place, notePlace('n${mostPlaces + 9}'));
      expect(trail.places, isNot(contains('list')));
    });

    test('names a note’s place, and reads the note back out of it', () {
      expect(notePlace('a'), 'note:a');
      expect(noteIdOf('note:a'), 'a');
      expect(noteIdOf(homePlace), isNull);
      expect(noteIdOf(allNotesPlace), isNull);
    });
  });

  group('the trail, as the shell walks it', () {
    test('records each arrival, and steps back and forward through them', () {
      final walk = TrailController(live: {'a', 'b'})..arrive('list');
      expect(walk.canBack, isFalse);
      walk
        ..arrive(notePlace('a'))
        ..arrive(allNotesPlace);
      expect(walk.trail.places, ['list', 'note:a', 'notes']);
      expect(walk.back(), 'note:a');
      // The shell goes where it was told, and the arrival is the step's, not somewhere new.
      walk.arrive(notePlace('a'));
      expect(walk.trail.places, ['list', 'note:a', 'notes']);
      expect(walk.canOn, isTrue);
      expect(walk.on(), 'notes');
    });

    test('leaves out a place whose note can no longer be seen, and answers null with nowhere to go', () {
      final walk = TrailController(live: {'a', 'b'})
        ..arrive('list')
        ..arrive(notePlace('a'))
        ..arrive(notePlace('b'));
      walk.live = {'b'};
      expect(walk.back(), 'list');
      walk.arrive('list');
      expect(walk.canBack, isFalse);
      expect(walk.back(), isNull);
    });

    test('records the next arrival after a step that landed where the page already was', () {
      final walk = TrailController(live: {'a', 'b'})
        ..arrive('list')
        ..arrive(notePlace('a'))
        ..arrive('list');
      // The note between the two visits home is gone: back steps over it, to home, where the page already is.
      walk.live = {'b'};
      expect(walk.back(), 'list');
      walk.arrive(notePlace('b'));
      expect(walk.canBack, isTrue);
      expect(walk.back(), 'list');
    });

    test('does not count a capture or the Academy as a place', () {
      final walk = TrailController()
        ..arrive('list')
        ..arrive(null)
        ..arrive('list');
      expect(walk.trail.places, ['list']);
    });

    test('tells whoever draws the arrows when their answers may have changed, and not otherwise', () {
      var told = 0;
      final walk = TrailController(live: {'a'})..addListener(() => told += 1);
      walk.arrive('list');
      expect(told, 0);
      walk.arrive(notePlace('a'));
      expect(told, 1);
      walk.live = {'a'};
      expect(told, 1);
      walk.live = {};
      expect(told, 2);
      walk.back();
      expect(told, 3);
      // Nowhere to go: nothing moved.
      expect(walk.back(), isNull);
      expect(told, 3);
    });
  });
}
