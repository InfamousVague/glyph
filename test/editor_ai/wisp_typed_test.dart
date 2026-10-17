// Claude's words arriving in a note out of the brief, light smoke (WispKind.typed, lib/editor/marks/wisp_motion.dart,
// drawn by lib/editor/ai/wisp_arrivals.dart), as lib/claude/live_typing.dart types them at its pace and as the
// connector's arrive live: each word legible within about 120 ms of going in, none ever waiting unseen on the pool
// of filters, and with reduced motion no smoke at all. Matt (2026-10-17): "when claude enters text we need the wisp
// on entry to be near instant it's very laggy right now and a bunch of text comes in invisible".
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/live_typing.dart';
import 'package:ghost_md/editor/ai/wisp_arrivals.dart';
import 'package:ghost_md/editor/ai/wisp_filters.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/wisp_motion.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../support/render.dart';
import 'wisp_support.dart';

/// About 600 letters: far more than the pool of filters could hold in smoke at once.
final String _words = List<String>.generate(60, (i) => 'Claude wrote word $i,').join(' ');

/// The moment (the held clock) each letter of the note went in: Claude types at the end, so a place stays put.
final List<double> _wentIn = <double>[];

Extension _stamped() => EditorViewLike.updateListener.of((update) {
  for (final tr in update.transactions) {
    tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
      for (var at = fromB; at < toB; at++) {
        if (at < _wentIn.length) {
          _wentIn[at] = clock;
        } else {
          _wentIn.add(clock);
        }
      }
    });
  }
});

/// Every letter drawn through smoke now has been legible (an opacity of at least 0.9) since 50 ms after it went
/// in, and is out of the smoke altogether by 130 ms; and no word waits unseen. Answers how many words wore smoke.
int _legible(EditorView view) {
  expect(waiting(view), isEmpty, reason: 'a word waits unseen at ${clock - 50000} ms');
  final worn = <String?>{};
  for (final mark in wearing(view)) {
    final age = clock - _wentIn[mark.from];
    final smoke = filterNamed(mark.filter)!;
    worn.add(mark.filter);
    expect(age, lessThan(130), reason: '"${mark.text}" at ${mark.from} still in smoke $age ms after it went in');
    if (age >= 50) expect(smoke.slope, greaterThanOrEqualTo(0.9), reason: '"${mark.text}" faint $age ms after it went in');
  }
  return worn.length;
}

void main() {
  setUpAll(loadAppFonts);
  holdClock();
  setUp(_wentIn.clear);

  group('Claude\'s words out of smoke', () {
    testWidgets('are legible within about 120 ms of going in, a word at a time at the pace, and none waits unseen', (tester) async {
      final view = await pumpEditor(tester, '', more: <Extension>[wispArrivals(), claudeTyping, _stamped()]);
      final typer = NoteTyper(view, follow: () => false, smoke: () => true, open: () => true);
      typer.begin(0);
      typer.type(_words);
      var worn = 0, most = 0;
      for (var frame = 0; frame < 220 && view.state.doc.length < _words.length; frame++) {
        await advance(tester, 16, step: 16);
        final now = _legible(view);
        worn += now;
        if (now > most) most = now;
      }
      expect(view.state.doc.toString(), _words);
      // It did smoke, a word or two at a time.
      expect(worn, greaterThan(0));
      expect(most, lessThanOrEqualTo(poolMax));
      await advance(tester, 140, step: 16);
      expect(drawn(view), isEmpty);
      expect(moving(view.state), isEmpty);
      await typer.end();
      await done(tester);
    });

    testWidgets('are there at once on Stop, a page of them, with only the last few in smoke', (tester) async {
      final view = await pumpEditor(tester, '', more: <Extension>[wispArrivals(), claudeTyping, _stamped()]);
      final typer = NoteTyper(view, follow: () => false, smoke: () => true, open: () => true);
      typer.begin(0);
      typer.type(_words);
      await advance(tester, 160, step: 16);
      typer.flush();
      await tester.pump();
      expect(view.state.doc.toString(), _words);
      for (var frame = 0; frame < 10; frame++) {
        _legible(view);
        await advance(tester, 16, step: 16);
      }
      expect(drawn(view), isEmpty);
      await done(tester);
    });

    testWidgets('from the connector, a few words landing together, are legible at once too', (tester) async {
      final view = await pumpEditor(tester, 'Notes\n', more: <Extension>[wispArrivals(), _stamped()]);
      _wentIn.addAll(List<double>.filled(view.state.doc.length, clock));
      for (var chunk = 0; chunk < 12; chunk++) {
        final words = List<String>.generate(6, (i) => 'w${chunk}_$i').join(' ');
        view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: '$words '), annotations: <Annotation<Object?>>[Transaction.remote.of(true), wisp.of(WispKind.typed)]));
        await tester.pump();
        for (var frame = 0; frame < 3; frame++) {
          await advance(tester, 16, step: 16);
          _legible(view);
        }
      }
      await advance(tester, 140, step: 16);
      expect(drawn(view), isEmpty);
      await done(tester);
    });

    testWidgets('are simply there with reduced motion: no smoke at all', (tester) async {
      final view = await pumpEditor(tester, '', more: <Extension>[wispArrivals(), claudeTyping, wispStill.of(true), _stamped()]);
      final typer = NoteTyper(view, follow: () => false, smoke: () => true, open: () => true);
      typer.begin(0);
      typer.type(_words);
      for (var frame = 0; frame < 60; frame++) {
        await advance(tester, 16, step: 16);
        expect(drawn(view), isEmpty);
        expect(moving(view.state), isEmpty);
      }
      expect(view.state.doc.length, greaterThan(0));
      typer.flush();
      await typer.end();
      await done(tester);
    });
  });
}
