// A voice memo played where it sits (lib/tapes/clip_player.dart): a stretch of the note's recording on the app's
// one player, with the player this folder's tests share (fake_player.dart).
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/media/clip_refs.dart';
import 'package:ghost_md/tapes/clip_player.dart';

import 'fake_player.dart';

void main() {
  const memo = Clip(startMs: 2000, endMs: 2500);

  test('plays the note\'s recording from the clip\'s start and stops at its end', () {
    fakeAsync((clock) {
      final player = FakeTapePlayer(lengths: const {'n1': 10000});
      final clips = TapeClipPlayer(player);
      var told = 0;
      clips.addListener(() => told += 1);
      clips.play('n1', memo);
      clock.flushMicrotasks();
      expect(player.calls, ['load n1', 'seek 2000', 'play']);
      expect(clips.playing, (src: 'n1', clip: memo));
      clock.elapse(const Duration(milliseconds: 400));
      expect(clips.playing, isNotNull);
      clock.elapse(const Duration(milliseconds: 200));
      expect(clips.playing, isNull);
      expect(player.calls.last, 'pause');
      expect(player.playing.value, isFalse);
      expect(told, 2);
      clips.dispose();
    });
  });

  test('has one voice: a second memo takes the player from the first, and a press on the one sounding stops it', () {
    fakeAsync((clock) {
      final player = FakeTapePlayer(lengths: const {'n1': 10000});
      final clips = TapeClipPlayer(player);
      const other = Clip(startMs: 6000, endMs: 9000);
      clips.play('n1', memo);
      clock.flushMicrotasks();
      clips.play('n1', other);
      clock.flushMicrotasks();
      expect(clips.playing?.clip, other);
      clock.elapse(const Duration(milliseconds: 300));
      expect(clips.playing?.clip, other, reason: 'the first memo\'s end is not this one\'s');
      clips.stop();
      expect(clips.playing, isNull);
      expect(player.calls.last, 'pause');
      clips.dispose();
    });
  });

  test('a recording that is not here fails the press, and nothing is left sounding', () {
    fakeAsync((clock) {
      final player = FakeTapePlayer(lengths: const {});
      final clips = TapeClipPlayer(player);
      Object? failed;
      clips.play('gone', memo).catchError((Object failure) => failed = failure);
      clock.flushMicrotasks();
      expect(failed, isNotNull);
      expect(clips.playing, isNull);
      clips.dispose();
    });
  });

  test('the tape paused by its own button, or broken, is the memo over', () {
    fakeAsync((clock) {
      final player = FakeTapePlayer(lengths: const {'n1': 10000});
      final clips = TapeClipPlayer(player);
      clips.play('n1', memo);
      clock.flushMicrotasks();
      player.pause();
      expect(clips.playing, isNull);
      clips.play('n1', memo);
      clock.flushMicrotasks();
      player.fail();
      expect(clips.playing, isNull);
      clips.dispose();
    });
  });
}
