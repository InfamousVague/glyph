// editor/clips.test.ts, case for case. The page's `<audio>` is the seam `ClipPlayer` here: a player that says what it
// was told, as the page's test said what its media elements were told. "Stops at its end" is the player's own, and is
// asked of it (it is told the clip, whose end it is).
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/clip_refs.dart';
import 'package:ghost_md/editor/media/clips.dart';
import 'package:ghost_md/editor/media/inline_box.dart';

import '../../support/render.dart';
import 'support.dart';

const String memo = '![voice 0:12](tape:12000-24000@k3f9x2)';
final String doc = <String>['Before the memo', '- $memo', 'and one said mid-sentence ![voice 0:03](tape:30000-33000@k3f9x2) here'].join('\n');
const Tape tape = Tape(src: 'rec://note.wav', id: 'k3f9x2');

class Player extends ChangeNotifier implements ClipPlayer {
  final List<(String, Clip)> played = <(String, Clip)>[];
  bool refuse = false;

  @override
  ({String src, Clip clip})? playing;

  @override
  Future<void> play(String src, Clip clip) async {
    if (refuse) throw StateError('NotAllowedError');
    played.add((src, clip));
    playing = (src: src, clip: clip);
    notifyListeners();
  }

  @override
  void stop() {
    playing = null;
    notifyListeners();
  }

  /// The recording reached the clip's end.
  void end() => stop();
}

const Key clip = ValueKey<String>('cm-clip'), quiet = ValueKey<String>('cm-clipQuiet'), length = ValueKey<String>('cm-clipLength');

int lineStart(int n) => doc.split('\n').take(n - 1).join('\n').length + (n > 1 ? 1 : 0);

void main() {
  setUpAll(loadAppFonts);

  Future<Player> open(WidgetTester tester, {Tape of = tape, int caret = 0}) async {
    final player = Player();
    final view = await pumpNote(tester, doc, more: <Extension>[clips(), tapeSource.of(of), clipPlayer.of(player)]);
    if (caret != 0) {
      view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
      await tester.pump();
    }
    return player;
  }

  group('a voice memo in a note', () {
    testWidgets('is a player in place of its mark, on a line of its own or in the middle of a sentence', (tester) async {
      await open(tester);
      expect(find.bySemanticsLabel('Play this voice memo, 0:12'), findsOneWidget);
      expect(find.bySemanticsLabel('Play this voice memo, 0:03'), findsOneWidget);
      expect(shownOf(tester, 1), isNot(contains('![voice')));
      expect(shownOf(tester, 2), 'and one said mid-sentence  here');
      expect(tester.widgetList<InlineWords>(find.byKey(length)).map((w) => w.text), <String>['0:12', '0:03']);
    });

    testWidgets('shows its mark as written on the caret’s line, the player beside it, so it can be edited', (tester) async {
      await open(tester, caret: lineStart(2));
      expect(shownOf(tester, 1), contains(memo));
      expect(find.byKey(clip), findsNWidgets(2));
      expect(shownOf(tester, 2), isNot(contains('![voice')));
    });

    testWidgets('is a quiet mark with nothing to press where the note has no recording, or another one', (tester) async {
      for (final of in const <Tape>[Tape.none, Tape(src: 'rec://other.wav', id: 'zz9')]) {
        final player = await open(tester, of: of);
        expect(find.byKey(clip), findsNothing);
        expect(tester.widgetList<InlineWords>(find.byKey(const ValueKey<String>('cm-clipQuiet-words'))).map((w) => w.text), <String>['voice 0:12', 'voice 0:03']);
        await tester.tap(find.byKey(quiet).first, warnIfMissed: false);
        expect(player.played, isEmpty);
      }
    });

    testWidgets('plays its stretch of the recording, and stops at its end', (tester) async {
      final player = await open(tester);
      await tester.tap(find.byKey(clip).first);
      await tester.pump();
      expect(player.played, <(String, Clip)>[('rec://note.wav', const Clip(startMs: 12000, endMs: 24000, tape: 'k3f9x2'))]);
      expect(find.bySemanticsLabel('Stop this voice memo, 0:12'), findsOneWidget);
      player.end();
      await tester.pump();
      expect(find.bySemanticsLabel('Play this voice memo, 0:12'), findsOneWidget);
    });

    testWidgets('plays one at a time: a second memo stops the first, and a second press stops its own', (tester) async {
      final player = await open(tester);
      await tester.tap(find.byKey(clip).first);
      await tester.pump();
      await tester.tap(find.byKey(clip).last);
      await tester.pump();
      expect(find.bySemanticsLabel('Play this voice memo, 0:12'), findsOneWidget);
      expect(find.bySemanticsLabel('Stop this voice memo, 0:03'), findsOneWidget);
      await tester.tap(find.byKey(clip).last);
      await tester.pump();
      expect(find.bySemanticsLabel('Play this voice memo, 0:03'), findsOneWidget);
      expect(player.playing, isNull);
    });

    testWidgets('says so when the recording will not play', (tester) async {
      final player = await open(tester);
      player.refuse = true;
      await tester.tap(find.byKey(clip).first);
      await tester.pump();
      await tester.pump();
      final said = tester.getSemantics(find.bySemanticsLabel('Play this voice memo, 0:12'));
      expect(said.hint, 'This voice memo couldn’t be played.');
    });

    testWidgets('is one thing to the caret: its hidden mark is an atomic range', (tester) async {
      final player = Player();
      final view = await pumpNote(tester, doc, more: <Extension>[clips(), tapeSource.of(tape), clipPlayer.of(player)]);
      final ranges = <(int, int)>[];
      for (final set in view.atomicRanges) {
        set.between(0, view.state.doc.length, (from, to, _) {
          ranges.add((from, to));
          return null;
        });
      }
      expect(ranges, contains((lineStart(2) + 2, lineStart(2) + 2 + memo.length)));
    });
  });
}
