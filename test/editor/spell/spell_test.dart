// Spell-check in the note's editor (lib/editor/spell; docs/PARITY.md, Missing 11): the phone's checker asked about
// the words near the caret a moment after the person stops, never at each letter and never the whole note, and a
// red wave under each word it would have otherwise. The page had it from its WebView (`spellcheck="true"` while the
// keyboard's aids are on); nothing was here. The checker is a stand-in, and the phone's own is tried over the
// engine's channel, in its own words.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/editor_widget.dart';
import 'package:ghost_md/editor/spell/spell.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import '../input/support.dart';

/// A checker that knows a few wrong words, and counts what it is asked.
class FakeChecker implements SpellChecker {
  FakeChecker([this.wrong = const {'teh': ['the', 'tea'], 'recieve': ['receive'], 'wrnog': ['wrong']}]);

  final Map<String, List<String>> wrong;
  final List<String> asked = [];
  final List<Locale> locales = [];

  /// Set, an answer waits until the test lets it go.
  Completer<void>? hold;

  /// Set, the phone answers nothing (a question already out, or no checker).
  bool refuses = false;

  @override
  Future<List<Misspelling>?> check(String text, {required Locale locale}) async {
    asked.add(text);
    locales.add(locale);
    await hold?.future;
    if (refuses) return null;
    return [
      for (final word in RegExp(r"[A-Za-z']+").allMatches(text))
        if (wrong[word[0]!.toLowerCase()] case final offered?) Misspelling(word.start, word.end, offered),
    ];
  }
}

EditorState stateOf(String doc, {int? caret, List<Extension> more = const []}) =>
    EditorState.create(doc: doc, selection: caret == null ? null : EditorSelection.single(caret), extensions: noteExtensions(more: [spellMarks, ...more]));

List<String> marked(EditorState state) => [for (final word in misspellingsOf(state)) state.doc.sliceString(word.from, word.to)];

const wait = Duration(milliseconds: 600);

/// The same colour, to the step a canvas keeps one at.
bool sameInk(Color a, Color b) => (a.r - b.r).abs() < 0.01 && (a.g - b.g).abs() < 0.01 && (a.b - b.b).abs() < 0.01 && (a.a - b.a).abs() < 0.01;

void main() {
  setUpAll(loadAppFonts);

  group('what the checker is handed', () {
    test('is the lines round the caret and no more: four either side, fewer when they are long', () {
      final lines = [for (var i = 0; i < 40; i++) 'line $i of the note'];
      final doc = lines.join('\n');
      final state = stateOf(doc, caret: doc.indexOf('line 20'));
      final stretch = spellStretch(state);
      expect(state.doc.sliceString(stretch.from, stretch.to), lines.sublist(16, 25).join('\n'));
      // At the note's top there is nothing above to take.
      final top = spellStretch(stateOf(doc, caret: 3));
      expect(state.doc.sliceString(top.from, top.to), lines.sublist(0, 5).join('\n'));
      // Long paragraphs: the caret's line whole, and neighbours only while they fit.
      final long = [for (var i = 0; i < 9; i++) 'p$i ${'word ' * 180}'.trim()].join('\n');
      final some = spellStretch(stateOf(long, caret: long.indexOf('p4') + 3));
      expect(some.to - some.from, lessThanOrEqualTo(spellMostChars + 905));
      expect(some.to - some.from, lessThan(long.length ~/ 2));
      expect(long.substring(some.from, some.to), contains('p4 word'));
      // One paragraph longer than the most is still asked about whole: a word is never cut.
      final huge = 'x ${'word ' * 900}'.trim();
      final all = spellStretch(stateOf(huge, caret: 10));
      expect((all.from, all.to), (0, huge.length));
    });

    test('has code, addresses, links’ targets, [[links]], #tags, @names, blanks and the front matter as spaces, each place kept', () {
      const doc = '---\ntitle: Teh plan\ntags: wrnog\n---\n'
          'Teh `teh code` and https://teh.example/recieve and [teh link](https://x.test/teh) and [[Teh page]]\n'
          '#teh @teh {?teh blank}\n'
          'status:: teh\n'
          '```\nteh fence\n```\n'
          'plain teh';
      final state = stateOf(doc, caret: doc.length);
      final text = spellText(state, 0, doc.length);
      expect(text.length, doc.length, reason: 'a place in what is asked is that place in the note');
      final seen = [for (final m in RegExp(r'[A-Za-z]+').allMatches(text)) m[0]!];
      expect(seen, ['Teh', 'and', 'and', 'teh', 'link', 'and', 'teh', 'plain', 'teh']);
      // The lines are still lines.
      expect('\n'.allMatches(text).length, '\n'.allMatches(doc).length);
      // A stretch that begins inside the front matter leaves it out too.
      final inside = spellText(state, doc.indexOf('tags:'), doc.indexOf('Teh `teh'));
      expect(inside.trim(), isEmpty);
    });
  });

  group('the marks', () {
    test('are the words a look found, and a look replaces only what it looked at', () {
      const doc = 'teh first line\nrecieve the second\nwrnog on the third';
      var state = stateOf(doc);
      expect(marked(state), isEmpty);
      state = state.update(TransactionSpec(effects: [setMisspellings.of((from: 0, to: 14, found: const [Misspelling(0, 3, ['the'])]))])).state;
      expect(marked(state), ['teh']);
      expect(misspellingsOf(state).single.suggestions, ['the']);
      final third = doc.indexOf('wrnog');
      state = state.update(TransactionSpec(effects: [setMisspellings.of((from: third, to: doc.length, found: [Misspelling(third, third + 5, const ['wrong'])]))])).state;
      expect(marked(state), ['teh', 'wrnog'], reason: 'the first line was not looked at again, and keeps its mark');
      // Looked at again and found right: the mark goes.
      state = state.update(TransactionSpec(effects: [setMisspellings.of((from: 0, to: 14, found: const []))])).state;
      expect(marked(state), ['wrnog']);
      expect(spellDecorations(state).size, 1);
      state = state.update(TransactionSpec(effects: [clearMisspellings.of(null)])).state;
      expect(marked(state), isEmpty);
    });

    test('move with their words, and leave a word that is typed in', () {
      const doc = 'teh first and recieve last';
      var state = stateOf(doc);
      state = state.update(TransactionSpec(effects: [setMisspellings.of((from: 0, to: doc.length, found: const [Misspelling(0, 3), Misspelling(14, 21)]))])).state;
      // Words typed before both: each mark is still on its word.
      state = state.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'So '))).state;
      expect(marked(state), ['teh', 'recieve']);
      // A letter typed into one: it is not known to be wrong any more.
      state = state.update(TransactionSpec(changes: ChangeSpec(from: state.doc.toString().indexOf('teh') + 3, insert: 'n'))).state;
      expect(marked(state), ['recieve']);
      // And one deleted with its mark.
      final at = state.doc.toString().indexOf('recieve');
      state = state.update(TransactionSpec(changes: ChangeSpec(from: at, to: at + 8))).state;
      expect(marked(state), isEmpty);
    });

    test('offer a word’s suggestions where a menu is opened on it, and write the one chosen', () {
      const doc = 'I will recieve it';
      var state = stateOf(doc);
      state = state.update(TransactionSpec(effects: [setMisspellings.of((from: 0, to: doc.length, found: const [Misspelling(7, 14, ['receive', 'relieve'])]))])).state;
      expect(misspellingAt(state, 6), isNull);
      expect(misspellingAt(state, 7)?.suggestions, ['receive', 'relieve']);
      expect(misspellingAt(state, 14)?.suggestions, ['receive', 'relieve'], reason: 'a caret at the word’s end is on it');
      expect(misspellingAt(state, 15), isNull);
      final tr = state.update(replaceMisspelling(misspellingAt(state, 10)!, 'receive'));
      expect(tr.state.doc.toString(), 'I will receive it');
      expect(tr.state.selection.main.head, 14);
      expect(marked(tr.state), isEmpty);
      expect(tr.annotation(Transaction.userEvent), 'input.spell');
    });
  });

  group('the wave', () {
    test('is four pixels to a period and two high, from one end of the word to the other', () {
      final bounds = SpellWave.waveOf(10, 34, 20).getBounds();
      expect((bounds.left, bounds.right), (10, 34));
      expect(bounds.top, greaterThanOrEqualTo(20));
      expect(bounds.bottom, lessThanOrEqualTo(22));
      expect((SpellWave.period, SpellWave.height, SpellWave.stroke), (4, 2, 1));
    });

    testWidgets('is drawn under a marked word, in the kit’s red, and under nothing else', (tester) async {
      final checker = FakeChecker();
      final rig = await pumpEditor(tester, 'I will recieve it today', caret: 23, more: [spellCheck(checker: checker)]);
      final red = tester.element(find.byType(Editor)).tokens.color('glacier-red-9');
      RenderEditorLine line() => tester.renderObjectList<RenderEditorLine>(find.byElementPredicate((element) => element.renderObject is RenderEditorLine)).first;
      // A red stroked path a pixel thick: the wave, and nothing else the line draws is one.
      final wave = paints..something((method, arguments) {
        if (method != #drawPath) return false;
        final paint = arguments[1] as Paint;
        return sameInk(paint.color, red) && paint.style == PaintingStyle.stroke && paint.strokeWidth == SpellWave.stroke;
      });
      expect(line(), isNot(wave));
      await tester.pump(wait);
      await tester.pump();
      expect(marked(rig.view.state), ['recieve']);
      await tester.pump();
      expect(line(), wave);
      // As wide as the word: from where "recieve" starts to where it ends.
      final from = rig.view.coordsAtPos(rig.at('recieve'))!.left, to = rig.view.coordsAtPos(rig.at('recieve', 7), -1)!.right;
      expect(to - from, greaterThan(20));
      expect(
        line(),
        paints..something((method, arguments) {
          if (method != #drawPath || !sameInk((arguments[1] as Paint).color, red)) return false;
          final bounds = (arguments[0] as Path).getBounds();
          final origin = line().localToGlobal(Offset.zero);
          return (bounds.left + origin.dx - from).abs() < 1.5 && (bounds.right + origin.dx - to).abs() < 1.5 && bounds.height <= SpellWave.height + 0.01;
        }),
      );
      await finish(tester);
    });
  });

  group('the asking', () {
    testWidgets('waits for the person to stop: nothing at a letter, once after the last', (tester) async {
      final checker = FakeChecker();
      final rig = await pumpEditor(tester, '', more: [spellCheck(checker: checker)]);
      await tester.pump(wait);
      final before = checker.asked.length;
      await rig.ime.type('I will recieve');
      expect(checker.asked.length, before, reason: 'fourteen letters, and the checker was not asked once');
      await tester.pump(const Duration(milliseconds: 300));
      await rig.ime.type(' it');
      await tester.pump(const Duration(milliseconds: 500));
      expect(checker.asked.length, before, reason: 'still inside the wait, which every letter starts again');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(checker.asked.length, before + 1);
      expect(checker.asked.last, 'I will recieve it');
      expect(marked(rig.view.state), ['recieve']);
      await finish(tester);
    });

    testWidgets('is about the words near the caret, never the whole of a long note', (tester) async {
      final checker = FakeChecker();
      final lines = [for (var i = 0; i < 400; i++) i == 200 ? 'teh line $i' : 'line $i has recieve in it'];
      final doc = lines.join('\n');
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('teh line 200') + 12, more: [spellCheck(checker: checker)]);
      await tester.pump(wait);
      await tester.pump();
      expect(checker.asked, isNotEmpty);
      for (final asked in checker.asked) {
        expect(asked.length, lessThan(400), reason: 'nine lines of a four-hundred-line note');
        expect(asked, contains('teh line 200'));
      }
      expect(marked(rig.view.state).length, 9);
      expect(misspellingsOf(rig.view.state).every((word) => word.from > doc.indexOf('line 195') && word.to < doc.indexOf('line 206')), isTrue);
      await finish(tester);
    });

    testWidgets('leaves the word still being written unmarked, and marks it once the caret has left it', (tester) async {
      final checker = FakeChecker();
      final rig = await pumpEditor(tester, '', more: [spellCheck(checker: checker)]);
      await rig.ime.type('I will recieve');
      await tester.pump(wait);
      await tester.pump();
      expect(marked(rig.view.state), isEmpty, reason: 'the caret is at its end: it may yet be finished');
      await rig.ime.type(' ');
      await tester.pump(wait);
      await tester.pump();
      expect(marked(rig.view.state), ['recieve']);
      await finish(tester);
    });

    testWidgets('throws away an answer about words that changed while it was out, and asks again', (tester) async {
      final checker = FakeChecker()..hold = Completer<void>();
      final rig = await pumpEditor(tester, 'teh cat sat', caret: 11, more: [spellCheck(checker: checker)]);
      await tester.pump(wait);
      expect(checker.asked, ['teh cat sat']);
      // Typed while the phone is thinking.
      rig.view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, to: 3, insert: 'the')));
      await tester.pump();
      checker.hold!.complete();
      checker.hold = null;
      await tester.pump();
      expect(marked(rig.view.state), isEmpty, reason: '"teh" was answered for, and is not there');
      await tester.pump(wait);
      await tester.pump();
      expect(checker.asked.last, 'the cat sat');
      expect(marked(rig.view.state), isEmpty);
      await finish(tester);
    });

    testWidgets('asks one question at a time, and once more for what changed meanwhile', (tester) async {
      final checker = FakeChecker()..hold = Completer<void>();
      final rig = await pumpEditor(tester, 'teh cat', caret: 7, more: [spellCheck(checker: checker)]);
      await tester.pump(wait);
      expect(checker.asked.length, 1);
      await rig.ime.type(' sat');
      await tester.pump(wait);
      expect(checker.asked.length, 1, reason: 'the first is still out');
      checker.hold!.complete();
      checker.hold = null;
      await tester.pump();
      await tester.pump(wait);
      await tester.pump();
      expect(checker.asked, ['teh cat', 'teh cat sat']);
      expect(marked(rig.view.state), ['teh']);
      await finish(tester);
    });

    testWidgets('a phone that answers nothing leaves the note as it was, and is asked again at the next change', (tester) async {
      final checker = FakeChecker()..refuses = true;
      final rig = await pumpEditor(tester, 'teh cat', caret: 7, more: [spellCheck(checker: checker)]);
      await tester.pump(wait);
      await tester.pump();
      expect(marked(rig.view.state), isEmpty);
      final asked = checker.asked.length;
      await tester.pump(const Duration(seconds: 5));
      expect(checker.asked.length, asked, reason: 'not asked over and over while nothing changes');
      checker.refuses = false;
      await rig.ime.type(' ');
      await tester.pump(wait);
      await tester.pump();
      expect(marked(rig.view.state), ['teh']);
      await finish(tester);
    });

    testWidgets('is never made with the keyboard’s aids off, in a note that cannot be typed in, or without the focus', (tester) async {
      final plain = FakeChecker();
      final off = await pumpEditor(tester, 'teh cat', caret: 7, assist: false, more: [spellCheck(checker: plain)]);
      await off.ime.type(' sat');
      await tester.pump(wait);
      expect(plain.asked, isEmpty, reason: 'spellcheck="false"');
      await finish(tester);

      final reading = FakeChecker();
      await pumpEditor(tester, 'teh cat', readOnly: true, more: [spellCheck(checker: reading)]);
      await tester.pump(wait);
      expect(reading.asked, isEmpty);
      await finish(tester);

      final away = FakeChecker();
      final rig = await pumpEditor(tester, 'teh cat', focus: false, more: [spellCheck(checker: away)]);
      rig.view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 7, insert: ' sat')));
      await tester.pump(wait);
      expect(away.asked, isEmpty, reason: 'a note nobody is typing in');
      await finish(tester);
    });

    testWidgets('turning the aids off takes the marks away', (tester) async {
      final checker = FakeChecker();
      final rig = await pumpEditor(tester, 'teh cat sat', caret: 11, more: [spellCheck(checker: checker)]);
      await tester.pump(wait);
      await tester.pump();
      expect(marked(rig.view.state), ['teh']);
      setAssist(rig.view, false);
      await tester.pump();
      await tester.pump();
      expect(marked(rig.view.state), isEmpty);
      await finish(tester);
    });

    testWidgets('is in the phone’s language', (tester) async {
      final checker = FakeChecker();
      await pumpEditor(tester, 'teh cat', caret: 7, more: [spellCheck(checker: checker, locale: () => const Locale('pt', 'BR'))]);
      await tester.pump(wait);
      expect(checker.locales.single, const Locale('pt', 'BR'));
      await finish(tester);
    });
  });

  group('the phone’s checker', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <MethodCall>[];
    Object? answer;
    Object? failure;

    setUp(() {
      calls.clear();
      answer = const <Object?>[];
      failure = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.spellCheck, (call) async {
        calls.add(call);
        if (failure != null) throw failure!;
        return answer;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.spellCheck, null));
    });

    test('is asked through the engine’s own bridge, with the language and the words, and read as the engine answers', () async {
      answer = [
        {'startIndex': 7, 'endIndex': 14, 'suggestions': ['receive', 'relieve']},
        {'startIndex': 0, 'endIndex': 3, 'suggestions': <String>[]},
      ];
      final found = await const PhoneSpellChecker(supported: true).check('teh    recieve it', locale: const Locale('en', 'GB'));
      expect(calls.single.method, 'SpellCheck.initiateSpellCheck');
      expect(calls.single.arguments, ['en-GB', 'teh    recieve it']);
      expect(found, const [Misspelling(0, 3), Misspelling(7, 14, ['receive', 'relieve'])], reason: 'in the order the words stand');
    });

    test('answers nothing when the phone refuses (a question already out, no checker), and leaves out what will not read', () async {
      failure = PlatformException(code: 'error', message: 'Previous spell check request still pending.');
      expect(await const PhoneSpellChecker(supported: true).check('teh', locale: const Locale('en')), isNull);
      failure = null;
      answer = [
        {'startIndex': 2, 'endIndex': 99, 'suggestions': <String>[]},
        {'startIndex': 3, 'endIndex': 3},
        'not a row',
        {'startIndex': 0, 'endIndex': 3},
      ];
      expect(await const PhoneSpellChecker(supported: true).check('teh', locale: const Locale('en')), const [Misspelling(0, 3)]);
      answer = 'not a list';
      expect(await const PhoneSpellChecker(supported: true).check('teh', locale: const Locale('en')), isNull);
    });

    test('is not asked about nothing, nor on a device whose engine has no checker', () async {
      expect(await const PhoneSpellChecker(supported: true).check('   \n ', locale: const Locale('en')), isEmpty);
      expect(await const PhoneSpellChecker(supported: false).check('teh', locale: const Locale('en')), isNull);
      expect(calls, isEmpty);
    });
  });
}
