// Ports, from src/app/editor/wispArrivals.test.ts (tauri/), the cases about what wispMotion.ts decides, in its
// order and under its names, onto lib/editor/marks/wisp_motion.dart: `commonEnds`, what a heard, rewritten, typed,
// deleted, tapped or revealed transaction sets in motion, the `typing` switch, the user events that are not typing
// (`input.board`, `input.plus`, `input.toggle`), the pace, and `settle`.
//
// What is read differently (the Dart file's header, "What differs"):
// - `wispArrivals()` and `wispArrivals({ typing: true })` are `wispDepartures(typing_: false)` and
//   `wispDepartures()`: the field, the switch and the ghosts.
// - `setPreferences({ motionSpeed })` is the facet `wispPace` (relaxed 1.6, brisk 0.6, as the web's own bounds say).
// - The clock is `wispNow`, held still here, so the waits between words are exact.
//
// Of the web's drawing cases two are kept for the part of them that is a decision, each said in its comment:
// - 'settles every word of a paragraph heard at once, past as many as the pool holds': that every word, past the
//   pool's 32, is let go once it is said to have settled (`settle`). The frame loop that says so is not ported.
// - 'is read where the text stood when the same change adds lines above it, as a fill that signs the note does':
//   where the ghost stands and what it says, in a view, without a throw. The ghost's classes are the drawing's.
//
// Left out, as drawing: the `--glacier-duration-normal` the speed case reads off the page; 'draws each moving word
// through a filter of its own, and no more at once than the pool holds'; 'takes its filters away with the editor';
// 'is drawn in the look the text had, where it stood'.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/wisp_motion.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

EditorState state([String doc = '', List<Extension> more = const <Extension>[]]) => EditorState.create(doc: doc, extensions: Extension.list(<Extension>[wispDepartures(typing_: false), ...more]));

EditorState typingState([String doc = '']) => EditorState.create(doc: doc, extensions: wispDepartures());

EditorState heard(EditorState from, ChangeSpec changes, [WispKind kind = WispKind.heard]) => from.update(TransactionSpec(changes: changes, annotations: wisp.of(kind))).state;

EditorState user(EditorState from, ChangeSpec changes, String event) => from.update(TransactionSpec(changes: changes, userEvent: event)).state;

List<String> texts(EditorState s) => [for (final m in moving(s)) s.doc.sliceString(m.from, m.to)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final clock = wispNow;
  setUp(() => wispNow = () => 50000);
  tearDown(() => wispNow = clock);

  group('text arriving from smoke in the editor', () {
    test('moves at the chosen speed: a relaxed arc is longer and a brisk one shorter, and so is the wait between words', () {
      ({double dur, double gap}) measure(double? pace) {
        final letters = moving(heard(state('', [if (pace != null) wispPace.of(pace)]), const ChangeSpec(from: 0, insert: 'buy milk')));
        return (dur: letters.map((m) => m.dur).reduce((a, b) => a < b ? a : b), gap: letters[1].at - letters[0].at);
      }

      final normal = measure(1);
      final relaxed = measure(1.6);
      final brisk = measure(0.6);
      // The arc carries up to 100 ms of jitter, so compare against its bounds rather than one draw.
      expect(relaxed.dur, greaterThanOrEqualTo(350 * 1.6));
      expect(brisk.dur, lessThanOrEqualTo(450 * 0.6));
      expect(normal.dur, greaterThanOrEqualTo(350));
      expect(relaxed.gap, closeTo(normal.gap * 1.6, 1e-5));
      expect(brisk.gap, closeTo(normal.gap * 0.6, 1e-5));
      // No pace said is the usual one.
      expect(measure(null).gap, normal.gap);
      expect(normal.gap, greaterThan(0));
    });

    test('finds what a rewrite really changed', () {
      expect(commonEnds('buy mil', 'buy milk'), (prefix: 7, suffix: 0));
      expect(commonEnds('buy milk', 'buy oat milk'), (prefix: 4, suffix: 4));
      expect(commonEnds('same', 'same'), (prefix: 4, suffix: 0));
      expect(commonEnds('abc', 'xyz'), (prefix: 0, suffix: 0));
    });

    test('sets every word of a heard phrase moving, one after another, spaces aside', () {
      final next = heard(state(), const ChangeSpec(from: 0, insert: 'buy milk'));
      final letters = moving(next);
      expect(texts(next), ['buy', 'milk']);
      expect(letters.every((m) => m.gone == ''), isTrue);
      final at = [for (final m in letters) m.at];
      expect(at, [...at]..sort());
      expect(at[1] - at[0], greaterThan(0));
    });

    test('moves only the letters a rewrite changed, and shows what it took away', () {
      final first = state('buy mil');
      final firmed = heard(first, const ChangeSpec(from: 0, to: 7, insert: 'buy milk'), WispKind.rewrite);
      expect(texts(firmed), ['k']);

      final swapped = heard(state('buy milk'), const ChangeSpec(from: 0, to: 8, insert: 'buy oat milk'), WispKind.rewrite);
      expect(texts(swapped).join(), 'oat');

      final cut = heard(state('buy milk'), const ChangeSpec(from: 0, to: 8, insert: 'by milk'), WispKind.rewrite);
      final ghosts = [for (final m in moving(cut)) if (m.gone.isNotEmpty) m];
      expect([for (final m in ghosts) m.gone], ['u']);
      expect(ghosts.first.from, 1);
    });

    test('with typing on, shows typed and pasted text at once, and smokes away what is taken out', () {
      final typed = typingState();
      expect(typed.facet(typing), isTrue);
      expect(state().facet(typing), isFalse);
      // A typed letter is there at once: nothing arrives through smoke under the finger that typed it.
      final one = user(typed, const ChangeSpec(from: 0, insert: 'h'), 'input.type');
      expect(moving(one), isEmpty);
      // A letter backspaced by hand goes at once: no smoke to stutter under the fingers.
      final gone = user(one, const ChangeSpec(from: 0, to: 1, insert: ''), 'delete.backward');
      expect(moving(gone).where((m) => m.gone.isNotEmpty), isEmpty);
      // A word taken out at once still smokes.
      final word = user(typingState('buy milk'), const ChangeSpec(from: 4, to: 8, insert: ''), 'delete.selection');
      expect([for (final m in moving(word)) m.gone], ['milk']);
      // A paste is there at once too.
      final pasted = user(typed, ChangeSpec(from: 0, insert: 'x' * 100), 'input.paste');
      expect(moving(pasted), isEmpty);
      // Typing over a selection: the new letters are simply there, and only the words they replaced smoke away.
      final over = user(typingState('buy milk'), const ChangeSpec(from: 4, to: 8, insert: 'e'), 'input.type');
      expect([for (final m in moving(over)) m.gone], ['milk']);
      final programmatic = typed.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'set'))).state;
      expect(moving(programmatic), isEmpty);
      // A tapped box smokes its letter away where it stood; a board's own edits (a card moved, a divider dragged) do not.
      final box = typingState('- [x] milk');
      final tapped = moving(user(box, const ChangeSpec(from: 3, to: 4, insert: ' '), 'input.toggle'));
      expect([for (final m in tapped) (m.gone, m.from)], [('x', 3)]);
      // The one letter between two brackets that stay put dissolves where it stands: no throw across the box, no rise into it.
      expect(tapped.first.box, isTrue);
      // And ticked, the mark dissolves in where it stands: a tap is not typing.
      final ticked = moving(user(typingState('- [ ] milk'), const ChangeSpec(from: 3, to: 4, insert: 'x'), 'input.toggle'));
      expect([for (final m in ticked) (m.gone, m.from, m.to, m.box)], [('', 3, 4, true)]);
      final byHand = moving(user(box, const ChangeSpec(from: 3, to: 4, insert: 'y'), 'input.type'));
      expect(byHand.every((m) => !m.box && m.gone.isNotEmpty), isTrue);
      expect(moving(user(box, const ChangeSpec(from: 3, to: 4, insert: ' '), 'input.board')), isEmpty);
      expect(moving(user(box, const ChangeSpec(from: 3, to: 4, insert: ' '), 'input.board')), isEmpty);
    });

    test('sets nothing from the + beside the line in motion: what it adds is there at once, and the lead it replaces just goes', () {
      final item = typingState('Lunch\n- [ ] ');
      const replace = ChangeSpec(from: 6, to: 12, insert: '![](image/x.jpg)\n');
      // The same change typed would smoke the box away; the + drawing a picture over an empty to-do does not.
      expect([for (final m in moving(user(item, replace, 'input.type'))) m.gone], ['- [ ] ']);
      expect(moving(user(item, replace, 'input.plus.drawn')), isEmpty);
      expect(moving(user(item, const ChangeSpec(from: 12, insert: '28 Sep 2026, 14:05'), 'input.plus')), isEmpty);
    });

    test('reveals a note already there a few words at a time, in order, blank lines aside', () {
      final opened = typingState('# Title\n\n  - a list item  \na paragraph long enough to break into more than one piece');
      final revealed = opened.update(TransactionSpec(effects: revealWisp.of((from: 0, to: opened.doc.length)))).state;
      final pieces = texts(revealed);
      expect(pieces.take(2), ['# Title', '- a list item']);
      expect(pieces.length, greaterThan(3));
      expect(pieces.every((p) => p.length <= 24 || !p.contains(' ')), isTrue);
      final at = [for (final m in moving(revealed)) m.at];
      expect(at, [...at]..sort());
    });

    test('ignores changes without the annotation, and follows later edits', () {
      final plain = state().update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'typed'))).state;
      expect(moving(plain), isEmpty);
      final withHeard = heard(state(), const ChangeSpec(from: 0, insert: 'milk'));
      final shifted = withHeard.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'oat '))).state;
      expect(texts(shifted).join(), 'milk');
      expect(moving(shifted).first.from, 4);
      final deleted = shifted.update(const TransactionSpec(changes: ChangeSpec(from: 4, to: 8, insert: ''))).state;
      expect(moving(deleted), isEmpty);
    });
  });

  group('words drawn arriving', () {
    test('settles every word of a paragraph heard at once, past as many as the pool holds', () {
      // The decision's half of the web case: 90 words heard at once are all in motion, more than the pool of 32
      // draws together, and each is let go when the drawing says it has settled, in whatever lots it says so.
      final words = [for (var n = 0; n < 90; n++) 'w$n'].join(' ');
      var on = heard(state(), ChangeSpec(from: 0, insert: words));
      expect(moving(on), hasLength(90));
      expect({for (final m in moving(on)) m.id}, hasLength(90));
      // The first lot settles: the rest stay, where they were.
      final firstLot = [for (final m in moving(on).take(32)) m.id];
      on = on.update(TransactionSpec(effects: settle.of(firstLot))).state;
      expect(moving(on), hasLength(58));
      expect(texts(on).first, 'w32');
      expect(moving(on).any((m) => firstLot.contains(m.id)), isFalse);
      on = on.update(TransactionSpec(effects: settle.of([for (final m in moving(on)) m.id]))).state;
      expect(moving(on), isEmpty);
    });
  });

  group('the smoke of text that went', () {
    test('is read where the text stood when the same change adds lines above it, as a fill that signs the note does', () {
      // The decision's half of the web case: one change adds lines above and replaces the blank. The ghost says what
      // the blank said and stands where the answer now is, 22 characters on, and a view takes the change whole.
      const doc = '# Tokyo trip\n\nCheapest on {?what day}';
      final at = doc.indexOf('{?');
      const above = '---\nauthors: Ghost\n---\n';
      final view = EditorView(wholeDocument: true, state: state(doc));
      addTearDown(view.destroy);
      view.dispatch(
        TransactionSpec(
          changes: <ChangeSpec>[
            const ChangeSpec(from: 0, insert: above),
            ChangeSpec(from: at, to: doc.length, insert: 'Tuesday'),
          ],
          annotations: wisp.of(WispKind.rewrite),
        ),
      );
      expect(view.state.doc.toString(), '$above# Tokyo trip\n\nCheapest on Tuesday');
      final ghosts = [for (final m in moving(view.state)) if (m.gone.isNotEmpty) m];
      expect([for (final m in ghosts) m.gone], ['{?what day}']);
      expect((ghosts.single.from, ghosts.single.to), (at + above.length, at + above.length));
      // And it is drawn there: one widget, at that point.
      final drawn = <int>[];
      for (final set in view.decorations) {
        set.between(0, view.state.doc.length, (from, to, value) {
          if (value.widget != null) drawn.add(from);
          return null;
        });
      }
      expect(drawn, [at + above.length]);
    });
  });
}
