// The Keyboard modes plugin's Vim (lib/plugins/keymaps/vim.dart), on plain strings: the motions and their counts,
// the operators with motions and text objects, Insert and its ways out, Visual by character and by line, the
// register, undo and redo, `.`, search, and the command line.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/keymaps/text.dart';
import 'package:ghost_md/plugins/keymaps/vim.dart';

import 'support.dart';

/// Vim over [text] with the caret at the first `|` in it, which is taken out.
(VimEngine, StringKeyText) vimOn(String text, {VimMode start = VimMode.normal, bool jk = false, DateTime Function()? now}) {
  final caret = text.indexOf('|');
  final target = StringKeyText(text.replaceFirst('|', ''), caret: caret < 0 ? 0 : caret);
  return (VimEngine(target, start: start, jk: () => jk, now: now), target);
}

/// Keys typed: what Vim does not take is typed into the text, as the editor would.
void press(VimEngine vim, StringKeyText target, String keys) {
  for (final key in keyNames(keys)) {
    if (vim.handle(key)) continue;
    if (key == vimEnter) {
      target.type('\n');
    } else if (key == vimBackspace) {
      if (target.head > 0) target.change([(from: target.head - 1, to: target.head, insert: '')], target.head - 1);
    } else if (!key.startsWith('<') || key.length == 1) {
      target.type(key);
    }
  }
}

/// The text with a `|` where the caret is.
String shown(StringKeyText t) => '${t.text.substring(0, t.head)}|${t.text.substring(t.head)}';

void main() {
  group('motions', () {
    test('h j k l, with counts, held to the line and to its last character', () {
      final (vim, t) = vimOn('|one two\nthree\nx');
      press(vim, t, 'l');
      expect(t.head, 1);
      press(vim, t, '9l');
      expect(t.head, 6);
      press(vim, t, 'j');
      expect(t.head, 8 + 4);
      press(vim, t, 'j');
      expect(shown(t), 'one two\nthree\n|x');
      // The column is kept through a short line.
      press(vim, t, 'kk');
      expect(t.head, 6);
      press(vim, t, '3h');
      expect(t.head, 3);
      press(vim, t, '5j');
      expect(shown(t), 'one two\nthree\n|x');
    });

    test('w b e and their WORD twins, ge, over punctuation and lines', () {
      final (vim, t) = vimOn('|foo.bar baz\n\nqux');
      press(vim, t, 'w');
      expect(t.head, 3);
      press(vim, t, 'w');
      expect(t.head, 4);
      press(vim, t, 'w');
      expect(t.head, 8);
      // An empty line is a word.
      press(vim, t, 'w');
      expect(t.head, 12);
      press(vim, t, 'w');
      expect(t.head, 13);
      press(vim, t, 'b');
      expect(t.head, 12);
      press(vim, t, '2b');
      expect(t.head, 4);
      press(vim, t, 'gg');
      press(vim, t, 'W');
      expect(t.head, 8);
      press(vim, t, 'B');
      expect(t.head, 0);
      press(vim, t, 'e');
      expect(t.head, 2);
      press(vim, t, 'E');
      expect(t.head, 6);
      press(vim, t, 'ge');
      expect(t.head, 3);
      press(vim, t, '3w');
      expect(t.head, 12);
    });

    test('0 ^ \$ and g_, gg and G with and without a count', () {
      final (vim, t) = vimOn('  one two  \nsecond\n  third');
      press(vim, t, r'$');
      expect(t.head, 10);
      press(vim, t, '0');
      expect(t.head, 0);
      press(vim, t, '^');
      expect(t.head, 2);
      press(vim, t, 'g_');
      expect(t.head, 8);
      press(vim, t, 'G');
      expect(t.head, 21);
      press(vim, t, 'gg');
      expect(t.head, 2);
      press(vim, t, '2G');
      expect(t.head, 12);
      // `$` then `j` keeps to each line's end.
      press(vim, t, r'gg$j');
      expect(t.head, 17);
    });

    test('f t F T with ; and , and %', () {
      final (vim, t) = vimOn('|a(b, c), d(e)');
      press(vim, t, 'f,');
      expect(t.head, 3);
      press(vim, t, ';');
      expect(t.head, 7);
      press(vim, t, ',');
      expect(t.head, 3);
      press(vim, t, '0t)');
      expect(t.head, 5);
      press(vim, t, ';');
      expect(t.head, 11);
      press(vim, t, 'F(');
      expect(t.head, 10);
      press(vim, t, 'T,');
      expect(t.head, 8);
      press(vim, t, '0%');
      expect(t.head, 6);
      press(vim, t, '%');
      expect(t.head, 1);
    });

    test('{ and } by paragraphs', () {
      final (vim, t) = vimOn('|one\ntwo\n\nthree\n\nfour');
      press(vim, t, '}');
      expect(t.head, 8);
      press(vim, t, '}');
      expect(t.head, 15);
      press(vim, t, '{');
      expect(t.head, 8);
    });
  });

  group('operators', () {
    test('x X dd with counts, and p P putting what they took', () {
      final (vim, t) = vimOn('|abcdef\nline two\nline three');
      press(vim, t, '2x');
      expect(shown(t), '|cdef\nline two\nline three');
      expect(vim.register?.text, 'ab');
      press(vim, t, 'p');
      expect(shown(t), 'ca|bdef\nline two\nline three');
      press(vim, t, 'X');
      expect(t.text, 'cbdef\nline two\nline three');
      press(vim, t, 'j2dd');
      expect(shown(t), '|cbdef');
      expect(vim.register?.linewise, isTrue);
      press(vim, t, 'P');
      expect(shown(t), '|line two\nline three\ncbdef');
      press(vim, t, 'Gp');
      expect(t.text, 'line two\nline three\ncbdef\nline two\nline three');
    });

    test('dw cw d\$ ciw diw daw, and dw keeps to its line', () {
      var (vim, t) = vimOn('|one two three');
      press(vim, t, 'dw');
      expect(shown(t), '|two three');
      press(vim, t, 'cwTWO<Esc>');
      expect(shown(t), 'TW|O three');
      press(vim, t, r'd$');
      expect(shown(t), 'T|W');

      (vim, t) = vimOn('alpha be|ta gamma');
      press(vim, t, 'ciwB<Esc>');
      expect(shown(t), 'alpha | gamma'.replaceFirst('| ', '|B '));
      press(vim, t, 'wdiw');
      expect(t.text, 'alpha B ');
      press(vim, t, '0daw');
      expect(t.text, 'B ');

      (vim, t) = vimOn('|last\nnext');
      press(vim, t, 'dw');
      expect(t.text, '\nnext');
    });

    test('quotes and brackets: ci" di( da[ yi{', () {
      final (vim, t) = vimOn('say "hi |there" (a (b) c) [x] {y}');
      press(vim, t, 'ci"yo<Esc>');
      expect(t.text, 'say "yo" (a (b) c) [x] {y}');
      press(vim, t, 'f(ldi(');
      expect(t.text, 'say "yo" () [x] {y}');
      press(vim, t, 'f[da[');
      expect(t.text, 'say "yo" ()  {y}');
      press(vim, t, r'$yi{');
      expect(vim.register?.text, 'y');
    });

    test('a block in braces over lines: di{ takes the lines between', () {
      final (vim, t) = vimOn('f() {\n  a|\n  b\n}');
      press(vim, t, 'di{');
      expect(t.text, 'f() {\n}');
    });

    test('ip and ap take a paragraph, by lines', () {
      final (vim, t) = vimOn('one\n|two\n\nthree');
      press(vim, t, 'yip');
      expect(vim.register?.text, 'one\ntwo');
      expect(vim.register?.linewise, isTrue);
      press(vim, t, 'dap');
      expect(t.text, 'three');
    });

    test('yy p, cc keeping the indent, >> and <<, J', () {
      final (vim, t) = vimOn('|  first\nsecond');
      press(vim, t, 'yyjp');
      expect(t.text, '  first\nsecond\n  first');
      press(vim, t, 'ccnew<Esc>');
      expect(t.text, '  first\nsecond\n  new');
      press(vim, t, 'k>>');
      expect(t.text, '  first\n  second\n  new');
      press(vim, t, '<<');
      expect(t.text, '  first\nsecond\n  new');
      press(vim, t, 'ggJ');
      expect(shown(t), '  first| second\n  new');
    });

    test('r ~ D C s S', () {
      final (vim, t) = vimOn('|abc def');
      press(vim, t, '2rx');
      expect(shown(t), 'x|xc def');
      press(vim, t, '0~~');
      expect(t.text, 'XXc def');
      press(vim, t, 'wD');
      expect(t.text, 'XXc ');
      press(vim, t, '0sy<Esc>');
      expect(t.text, 'yXc ');
      press(vim, t, 'Sall<Esc>');
      expect(t.text, 'all');
      press(vim, t, '0lCz<Esc>');
      expect(t.text, 'az');
    });

    test('a count before an operator and before its motion multiply', () {
      final (vim, t) = vimOn('|a b c d e f g');
      press(vim, t, '2d2w');
      expect(t.text, 'e f g');
    });
  });

  group('insert', () {
    test('i a I A o O put the caret where Vim does, and Esc steps back one', () {
      final (vim, t) = vimOn('  ab|c\nend');
      press(vim, t, 'iX<Esc>');
      expect(shown(t), '  ab|Xc\nend');
      press(vim, t, 'aY<Esc>');
      expect(shown(t), '  abX|Yc\nend');
      press(vim, t, 'I-<Esc>');
      expect(shown(t), '  |-abXYc\nend');
      press(vim, t, 'A!<Esc>');
      expect(t.text, '  -abXYc!\nend');
      press(vim, t, 'onext<Esc>');
      expect(t.text, '  -abXYc!\n  next\nend');
      press(vim, t, 'Oabove<Esc>');
      expect(t.text, '  -abXYc!\n  above\n  next\nend');
      expect(vim.mode, VimMode.normal);
    });

    test('Insert leaves every other key to the editor', () {
      final (vim, t) = vimOn('|', start: VimMode.insert);
      expect(vim.handle('d'), isFalse);
      expect(vim.handle(vimEnter), isFalse);
      expect(vim.handle(vimRedo), isFalse);
      expect(vim.handle(vimEscape), isTrue);
      expect(t.text, '');
    });

    test('jk leaves Insert where it is switched on, inside the wait, and takes the j back out', () {
      var clock = DateTime(2026, 10, 29);
      var (vim, t) = vimOn('|', start: VimMode.insert, jk: true, now: () => clock);
      press(vim, t, 'hijk');
      expect(t.text, 'hi');
      expect(vim.mode, VimMode.normal);
      press(vim, t, 'Aj');
      clock = clock.add(const Duration(seconds: 2));
      press(vim, t, 'k');
      expect(t.text, 'hijk');
      expect(vim.mode, VimMode.insert);

      (vim, t) = vimOn('|', start: VimMode.insert);
      press(vim, t, 'jk');
      expect(t.text, 'jk');
      expect(vim.mode, VimMode.insert);
    });
  });

  group('visual', () {
    test('v with motions, o, then d y c and the case keys', () {
      final (vim, t) = vimOn('|hello world again');
      press(vim, t, 've');
      expect(vim.mode, VimMode.visual);
      expect(t.selected, 'hello');
      press(vim, t, 'y');
      expect(vim.register?.text, 'hello');
      expect(vim.mode, VimMode.normal);
      press(vim, t, 'wvlld');
      expect(t.text, 'hello ld again');
      press(vim, t, 'veU');
      expect(t.text, 'hello LD again');
      press(vim, t, 'wviwcAGAIN<Esc>');
      expect(t.text, 'hello LD AGAIN');
      press(vim, t, '0vlloh');
      expect(t.selected, 'hel');
    });

    test('V by lines, with > and d, and an object in Visual', () {
      final (vim, t) = vimOn('|one\ntwo\nthree');
      press(vim, t, 'Vj');
      expect(vim.mode, VimMode.visualLine);
      expect(t.selected, 'one\ntwo\n');
      press(vim, t, '>');
      expect(t.text, '  one\n  two\nthree');
      press(vim, t, 'Vjd');
      expect(t.text, 'three');
      press(vim, t, 'viw');
      expect(t.selected, 'three');
      press(vim, t, '<Esc>');
      expect(vim.mode, VimMode.normal);
    });

    test('p over a selection puts the register there and keeps what was there', () {
      final (vim, t) = vimOn('|one two');
      press(vim, t, 'yiwwviwp');
      expect(t.text, 'one one');
      expect(vim.register?.text, 'two');
    });

    test('a range selected some other way is taken up as Visual, and a caret ends it', () {
      final (vim, t) = vimOn('|one two');
      t.select(4, 7);
      vim.moved(4, 7);
      expect(vim.mode, VimMode.visual);
      press(vim, t, 'd');
      expect(t.text, 'one ');
      t.select(1, 1);
      vim.moved(1, 1);
      expect(vim.mode, VimMode.normal);
    });
  });

  group('undo, redo and repeat', () {
    test('u and Ctrl-r go through the text\'s own undo, with a count', () {
      final (vim, t) = vimOn('|a b c');
      press(vim, t, 'xxx');
      expect(t.text, ' c');
      press(vim, t, '2u');
      expect(t.text, ' b c');
      press(vim, t, '<C-r>');
      expect(t.text, 'b c');
      press(vim, t, 'uuuu');
      expect(t.text, 'a b c');
      expect(vim.message, 'Already at oldest change');
    });

    test('. does the last change again, with what was typed, and a new count', () {
      final (vim, t) = vimOn('|one two three four');
      press(vim, t, 'cwONE<Esc>w.');
      expect(t.text, 'ONE ONE three four');
      press(vim, t, 'wdw.');
      expect(t.text, 'ONE ONE ');
      final (vim2, t2) = vimOn('|abcdef');
      press(vim2, t2, 'x3.');
      expect(t2.text, 'ef');
      press(vim2, t2, 'Ax<Esc>.');
      expect(t2.text, 'efxx');
    });
  });

  group('search and the command line', () {
    test('/ and ? with n and N, going round, smartcase', () {
      final (vim, t) = vimOn('|cat dog Cat dog cat');
      press(vim, t, '/dog<CR>');
      expect(t.head, 4);
      expect(vim.commandLine, isNull);
      press(vim, t, 'n');
      expect(t.head, 12);
      press(vim, t, 'n');
      expect(t.head, 4);
      expect(vim.message, contains('top'));
      press(vim, t, 'N');
      expect(t.head, 12);
      press(vim, t, '0/cat<CR>');
      expect(t.head, 8);
      press(vim, t, '/Cat<CR>');
      expect(t.head, 8);
      press(vim, t, '?dog<CR>');
      expect(t.head, 4);
      press(vim, t, '/zebra<CR>');
      expect(vim.message, 'Pattern not found: zebra');
    });

    test('* and # find the word under the cursor, whole', () {
      final (vim, t) = vimOn('|go gone go');
      press(vim, t, '*');
      expect(t.head, 8);
      press(vim, t, '#');
      expect(t.head, 0);
    });

    test('the line is typed, mended with Backspace and put away with Esc', () {
      final (vim, t) = vimOn('|a\nb\nc');
      press(vim, t, ':wx');
      expect(vim.commandLine, ':wx');
      press(vim, t, '<BS>');
      expect(vim.commandLine, ':w');
      press(vim, t, '<Esc>');
      expect(vim.commandLine, isNull);
      expect(t.saves, 0);
      press(vim, t, ':3<CR>');
      expect(t.head, 4);
    });

    test(':w saves, :q closes, :wq and ZZ do both', () {
      final (vim, t) = vimOn('|text');
      press(vim, t, ':w<CR>');
      expect((t.saves, t.closes), (1, 0));
      expect(vim.message, 'Saved');
      press(vim, t, ':q<CR>');
      expect((t.saves, t.closes), (1, 1));
      press(vim, t, ':wq<CR>');
      expect((t.saves, t.closes), (2, 2));
      press(vim, t, 'ZZ');
      expect((t.saves, t.closes), (3, 3));
      press(vim, t, ':frobnicate<CR>');
      expect(vim.message, 'Not an editor command: frobnicate');
    });
  });

  test('a note that can\'t be changed is moved through and left as it was', () {
    final (vim, t) = vimOn('|one two');
    t.readOnly = true;
    press(vim, t, 'wdwx');
    expect(t.text, 'one two');
    expect(t.head, 4);
    press(vim, t, 'i');
    expect(vim.mode, VimMode.normal);
    expect(vim.message, 'This note can’t be changed');
  });
}
