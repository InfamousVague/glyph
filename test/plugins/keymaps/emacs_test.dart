// The Keyboard modes plugin's Emacs (lib/plugins/keymaps/emacs.dart), on plain strings: the motions, the kills
// gathered into one and yanked back, the mark and its region, transposing, opening a line, undo, the incremental
// search both ways, and C-x C-s.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/keymaps/emacs.dart';
import 'package:ghost_md/plugins/keymaps/text.dart';

/// Emacs over [text] with the caret at the first `|` in it, which is taken out.
(EmacsEngine, StringKeyText) emacsOn(String text) {
  final caret = text.indexOf('|');
  final target = StringKeyText(text.replaceFirst('|', ''), caret: caret < 0 ? 0 : caret);
  return (EmacsEngine(target), target);
}

/// Keys by Emacs's names, a space between: what Emacs does not take is typed, as the editor would (`SPC` a space).
void press(EmacsEngine emacs, StringKeyText target, String keys) {
  for (final key in keys.split(' ')) {
    final name = key == 'SPC' ? ' ' : key;
    if (emacs.handle(name)) continue;
    if (name == 'DEL') {
      final from = target.anchor < target.head ? target.anchor : target.head, to = target.anchor < target.head ? target.head : target.anchor;
      if (to > from) {
        target.change([(from: from, to: to, insert: '')], from);
      } else if (from > 0) {
        target.change([(from: from - 1, to: from, insert: '')], from - 1);
      }
      emacs.moved(target.anchor, target.head, docChanged: true);
    } else if (name.runes.length == 1) {
      target.type(name);
      emacs.moved(target.anchor, target.head, docChanged: true);
    }
  }
}

String shown(StringKeyText t) => '${t.text.substring(0, t.head)}|${t.text.substring(t.head)}';

void main() {
  test('C-f C-b C-n C-p, M-f M-b, C-a C-e, M-< M->', () {
    final (emacs, t) = emacsOn('|one two-three\nfour');
    press(emacs, t, 'C-f C-f');
    expect(t.head, 2);
    press(emacs, t, 'C-b');
    expect(t.head, 1);
    press(emacs, t, 'M-f');
    expect(t.head, 3);
    press(emacs, t, 'M-f M-f');
    expect(t.head, 13);
    press(emacs, t, 'M-b');
    expect(t.head, 8);
    press(emacs, t, 'C-e');
    expect(t.head, 13);
    press(emacs, t, 'C-a');
    expect(t.head, 0);
    press(emacs, t, 'C-n');
    expect(t.head, 14);
    press(emacs, t, 'C-p');
    expect(t.head, 0);
    press(emacs, t, 'M->');
    expect(t.head, t.text.length);
    press(emacs, t, 'M-<');
    expect(t.head, 0);
  });

  test('C-k kills the line\'s rest, then its break, and kills in a row are one kill to yank', () {
    final (emacs, t) = emacsOn('|first line\nsecond\nthird');
    press(emacs, t, 'C-k');
    expect(t.text, '\nsecond\nthird');
    press(emacs, t, 'C-k C-k');
    expect(t.text, '\nthird');
    expect(emacs.kills, ['first line\nsecond']);
    press(emacs, t, 'M-> C-y');
    expect(shown(t), '\nthirdfirst line\nsecond|');
    // Anything between ends the run: the next kill is a kill of its own.
    press(emacs, t, 'M-< C-k C-f C-k');
    expect(emacs.kills, hasLength(3));
    expect(emacs.kills.last, 'hirdfirst line');
  });

  test('M-d and M-DEL kill words, the backward ones gathered before', () {
    final (emacs, t) = emacsOn('one two |three four');
    press(emacs, t, 'M-d M-d');
    expect(t.text, 'one two ');
    expect(emacs.kills.single, 'three four');
    final (back, t2) = emacsOn('one two three|');
    press(back, t2, 'M-DEL M-DEL');
    expect(t2.text, 'one ');
    expect(back.kills.single, 'two three');
  });

  test('C-d, C-h and the editor\'s own Backspace, which ends a run of kills', () {
    final (emacs, t) = emacsOn('ab|cd');
    press(emacs, t, 'C-d');
    expect(shown(t), 'ab|d');
    press(emacs, t, 'C-h');
    expect(shown(t), 'a|d');
    expect(emacs.handle('DEL'), isFalse);
  });

  test('C-SPC sets the mark, the motions select from it, C-g lets it go', () {
    final (emacs, t) = emacsOn('|hello world');
    press(emacs, t, 'C-SPC');
    expect(emacs.marking, isTrue);
    expect(emacs.badge, 'MARK');
    press(emacs, t, 'M-f');
    expect(t.selected, 'hello');
    press(emacs, t, 'C-f C-f');
    expect(t.selected, 'hello w');
    press(emacs, t, 'C-g');
    expect(emacs.marking, isFalse);
    expect(emacs.badge, isNull);
    expect(t.anchor, t.head);
  });

  test('C-w kills the region and M-w copies it, both to be yanked', () {
    final (emacs, t) = emacsOn('|alpha beta gamma');
    press(emacs, t, 'C-SPC M-f C-w');
    expect(t.text, ' beta gamma');
    expect(emacs.kills.last, 'alpha');
    press(emacs, t, 'M-f C-SPC M-f M-w');
    expect(t.text, ' beta gamma');
    expect(emacs.kills.last, ' gamma');
    expect(emacs.marking, isFalse);
    press(emacs, t, 'M-< C-y');
    expect(t.text, ' gamma beta gamma');
    final (none, t2) = emacsOn('|words');
    press(none, t2, 'C-w');
    expect(t2.text, 'words');
    expect(none.message, 'The mark is not set now');
  });

  test('C-t transposes, at a line\'s end the two before; C-o opens a line', () {
    final (emacs, t) = emacsOn('ab|cd');
    press(emacs, t, 'C-t');
    expect(shown(t), 'acb|d');
    press(emacs, t, 'C-e C-t');
    expect(shown(t), 'acdb|');
    press(emacs, t, 'C-a C-t');
    expect(t.text, 'acdb');
    press(emacs, t, 'C-f C-o');
    expect(shown(t), 'a|\ncdb');
  });

  test('C-/ and C-_ undo through the text\'s own undo', () {
    final (emacs, t) = emacsOn('|one two');
    press(emacs, t, 'M-d C-d');
    expect(t.text, 'two');
    press(emacs, t, 'C-/');
    expect(t.text, ' two');
    press(emacs, t, 'C-_');
    expect(t.text, 'one two');
  });

  test('C-s searches as it is typed, again with C-s, failing then round; RET stays, C-g goes back', () {
    final (emacs, t) = emacsOn('|cat dog cot dog');
    press(emacs, t, 'C-s d');
    expect(t.selected, 'd');
    expect(emacs.badge, 'I-search: d');
    press(emacs, t, 'o g');
    expect((t.anchor, t.head), (4, 7));
    press(emacs, t, 'C-s');
    expect((t.anchor, t.head), (12, 15));
    press(emacs, t, 'C-s');
    expect(emacs.badge, 'Failing I-search: dog');
    press(emacs, t, 'C-s');
    expect((t.anchor, t.head), (4, 7));
    press(emacs, t, 'RET');
    expect(emacs.badge, isNull);
    expect(t.head, 7);
    // C-g puts the caret back where the search began.
    press(emacs, t, 'C-s c o t C-g');
    expect(t.head, 7);
    // C-s twice searches for the last again.
    press(emacs, t, 'C-s C-s');
    expect((t.anchor, t.head), (12, 15));
    // Backspace takes the query back a letter.
    press(emacs, t, 'DEL DEL');
    expect(emacs.badge, 'I-search: d');
  });

  test('C-r searches backward, and a key it does not take ends the search and is itself', () {
    final (emacs, t) = emacsOn('one two one two|');
    press(emacs, t, 'C-r o n e');
    expect(t.selected, 'one');
    expect(t.head, 8);
    press(emacs, t, 'C-r');
    expect(t.head, 0);
    expect(emacs.badge, 'I-search backward: one');
    press(emacs, t, 'C-e');
    expect(emacs.badge, isNull);
    expect(t.head, t.text.length);
  });

  test('C-x C-s saves; C-x with anything else is undefined', () {
    final (emacs, t) = emacsOn('|text');
    press(emacs, t, 'C-x');
    expect(emacs.badge, 'C-x-');
    press(emacs, t, 'C-s');
    expect(t.saves, 1);
    expect(emacs.message, 'Saved');
    press(emacs, t, 'C-x C-q');
    expect(emacs.message, 'C-x C-q is undefined');
    expect(t.saves, 1);
  });

  test('a key Emacs does not name is the editor\'s, and a click puts the mark down', () {
    final (emacs, t) = emacsOn('|text');
    expect(emacs.handle('C-v'), isFalse);
    expect(emacs.handle('x'), isFalse);
    press(emacs, t, 'C-SPC C-f');
    t.select(3, 3);
    emacs.moved(3, 3);
    expect(emacs.marking, isFalse);
  });
}
