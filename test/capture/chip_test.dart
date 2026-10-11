import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/chip.dart';
import 'package:ghost_md/capture/live_route.dart' show liveTiming;
import 'package:ghost_md/capture/take_host.dart';

/// The recorder's chip (lib/capture/chip.dart): which of its three looks it takes, and how long a settled one stays.
/// Case for case with the web's `capture/chip.test.ts`.

void main() {
  group('the chip’s look', () {
    test('is hearing while a name or a command is under way', () {
      expect(chipPhase(const RouteViewHearing(name: 'work')), 'hearing');
      expect(chipPhase(const RouteViewCommand(words: 'add eggs')), 'hearing');
    });

    test('is landed once something has, and missed when nothing could', () {
      expect(chipPhase(const RouteViewDone(text: 'Added to the note you named')), 'moved');
      expect(chipPhase(const RouteViewSaid(text: 'Not done.')), 'missed');
      expect(chipPhase(const RouteViewMissed(title: 'Oven')), 'missed');
      expect(chipPhase(const RouteViewMoved(title: 'Work')), 'moved');
    });

    test('has its own look for the last thing said, taken back', () {
      expect(chipPhase(const RouteViewTookBack(said: 'Call Sam', outcome: TookBackGone(), undo: 3)), 'tookBack');
    });
  });

  group('how long a chip stays', () {
    test('lets a sentence or the items that landed be read, and a tick go sooner', () {
      expect(lingerMs(const RouteViewSaid(text: 'Not done.')), 3200);
      expect(lingerMs(const RouteViewAdded(title: 'Work', body: '- Call Sam', added: ['- Call Sam'])), 3200);
      expect(lingerMs(const RouteViewDone(text: 'Added to the note you named')), 2200);
      expect(lingerMs(const RouteViewMoved(title: 'Work')), 2200);
      expect(lingerMs(const RouteViewMissed(title: 'Oven')), 2200);
    });

    test('keeps a take-back and its Undo for four seconds, inside the reader’s own window for it', () {
      const chip = RouteViewTookBack(said: 'Call Sam', outcome: TookBackGone(), undo: 3);
      expect(lingerMs(chip), 4000);
      expect(lingerMs(chip)!, lessThan(liveTiming.takeBackMs));
    });

    test('keeps one still under way until the recorder says more', () {
      expect(lingerMs(null), isNull);
      expect(lingerMs(const RouteViewHearing(name: 'work')), isNull);
      expect(lingerMs(const RouteViewCommand(words: '')), isNull);
      expect(lingerMs(const RouteViewWaiting(title: 'Work')), isNull);
    });
  });

  group('a command still being said', () {
    test('shows without its keyword', () {
      expect(partialCommand('Hey Ghost, add eggs to '), 'add eggs to');
      expect(partialCommand(' add eggs '), 'add eggs');
    });
  });
}
