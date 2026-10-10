/// Asks the spell checker about the words near the caret, a moment after the person stops, and marks what it finds
/// (spell_marks.dart). The part of spell-check a WebView does by itself for the page's editor.
///
/// WHAT IS ASKED, AND WHEN. Only the lines round the caret ([spellLinesEitherSide] each way, [spellMostChars] at
/// most), only in an editor that is typed in, has the keyboard's focus and has the keyboard's aids on
/// (`spellcheck`, Settings' switch: the page's `PROSE_ATTRS`), and only [spellWait] after the last change or move
/// of the caret: never at each letter, and never the whole note. One question is out at a time; what changes
/// while it is out is asked about once it is back. An answer about words that changed while it was out is thrown
/// away. Nothing is asked while the keyboard is composing.
///
/// WHAT IS LEFT OUT of what is asked: code (a fence, a block, a span), addresses and a link's target, HTML, a
/// `[[link]]`, a `#tag`, an `@name`, a blank (`{?…}`), and the front matter. Each is handed over as spaces, so
/// every answer's place is still the note's.
///
/// THE WORD BEING TYPED is not marked: an answer that touches the caret is left out, and comes with the next look,
/// once the caret has left the word. The page's marker waits for the end of the word too.
library;

import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import '../editor.dart';
import '../view/syntax_tree.dart';
import 'spell_check.dart';
import 'spell_marks.dart';

/// How long after the last change or move the checker is asked.
const Duration spellWait = Duration(milliseconds: 600);

/// How many lines above and below the caret's are asked about with it.
const int spellLinesEitherSide = 4;

/// The most that is handed to the checker at once, in characters: the caret's line is always whole within it.
const int spellMostChars = 2000;

/// What the checker is never asked about, by the parser's names.
const Set<String> _code = <String>{'FencedCode', 'CodeBlock', 'InlineCode', 'CodeText', 'URL', 'Autolink', 'HTMLBlock', 'HTMLTag', 'CommentBlock', 'Comment', 'ProcessingInstruction', 'ProcessingInstructionBlock', 'LinkReference'};

/// And by their shape, where the parser has no name for them or the note's own marks are not in its tree.
final List<RegExp> _shapes = <RegExp>[
  RegExp(r'\[\[[^\]\n]*\]\]'),
  RegExp(r'(?:https?://|www\.)\S+'),
  RegExp(r'\S+@\S+\.\S+'),
  RegExp(r'(^|\s)[#@][\w/-]+', multiLine: true),
  RegExp(r'\{\?[^}\n]*\}'),
  RegExp(r'\]\([^)\n]*\)'),
  RegExp(r'^\s*[\w-]+::', multiLine: true),
];

/// The stretch of [state] round its caret that is asked about: whole lines, [spellLinesEitherSide] either side of
/// the caret's, fewer when they are long.
({int from, int to}) spellStretch(EditorState state) {
  final doc = state.doc;
  final at = doc.lineAt(state.selection.main.head);
  var first = at.number, last = at.number;
  var from = at.from, to = at.to;
  for (var step = 1; step <= spellLinesEitherSide; step++) {
    if (at.number + step <= doc.lines) {
      final line = doc.line(at.number + step);
      if (line.to - from > spellMostChars) break;
      last = line.number;
      to = line.to;
    }
    if (at.number - step >= 1) {
      final line = doc.line(at.number - step);
      if (to - line.from > spellMostChars) break;
      first = line.number;
      from = line.from;
    }
  }
  assert(first <= last);
  return (from: from, to: to);
}

/// The words of [from]..[to] as the checker is handed them: the note's own, with everything that is not prose
/// (see the header) as spaces, so a place in this text is that place in the note, less [from].
String spellText(EditorState state, int from, int to) {
  final text = state.doc.sliceString(from, to);
  if (text.isEmpty) return text;
  final units = text.codeUnits.toList();
  void blank(int a, int b) {
    for (var i = a < 0 ? 0 : a; i < b && i < units.length; i++) {
      if (units[i] != 0x0a) units[i] = 0x20;
    }
  }

  syntaxTree(state).iterate(
    from: from,
    to: to,
    enter: (node) {
      if (!_code.contains(node.name)) return null;
      blank(node.from - from, node.to - from);
      return false;
    },
  );
  // The front matter: from a first line of three dashes to the next.
  if (from == 0 && text.startsWith('---\n')) {
    final end = text.indexOf('\n---', 3);
    blank(0, end < 0 ? text.length : end + 4);
  } else if (from > 0) {
    final head = state.doc.sliceString(0, from > 4 ? 4 : from);
    if (head == '---\n') {
      final whole = state.doc.sliceString(0, to);
      final end = whole.indexOf('\n---', 3);
      if (end < 0 || end + 4 > from) blank(0, (end < 0 ? to : end + 4) - from);
    }
  }
  final masked = String.fromCharCodes(units);
  for (final shape in _shapes) {
    for (final match in shape.allMatches(masked)) {
      blank(match.start, match.end);
    }
  }
  return String.fromCharCodes(units);
}

class _Watch extends PluginValue {
  _Watch(this.view, this.checker, this.wait, this.locale);

  final EditorViewLike view;
  final SpellChecker checker;
  final Duration wait;
  final Locale Function() locale;

  Timer? _soon;
  bool _asking = false;
  bool _again = false;
  bool _gone = false;

  bool get _on => !view.state.readOnly && (view.state.facet(EditorViewLike.contentAttributes).spellcheck ?? false);

  @override
  void update(ViewUpdate update) {
    final was = update.startState.facet(EditorViewLike.contentAttributes).spellcheck ?? false;
    final now = update.state.facet(EditorViewLike.contentAttributes).spellcheck ?? false;
    if (was && !now) {
      // The aids turned off: the marks go with them, after this update (a plugin may not dispatch inside one).
      _soon?.cancel();
      _soon = null;
      scheduleMicrotask(() {
        if (!_gone && !_on && misspellingsOf(view.state).isNotEmpty) view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[clearMisspellings.of(null)]));
      });
      return;
    }
    if (!now) return;
    if (update.docChanged || update.selectionSet || update.focusChanged || (!was && now)) _later();
  }

  void _later() {
    if (_gone) return;
    _soon?.cancel();
    _soon = Timer(wait, _look);
  }

  Future<void> _look() async {
    _soon = null;
    if (_gone || !_on || !view.hasFocus) return;
    // An underlined run the keyboard is still writing is not a word yet.
    if (view.composing) return _later();
    if (_asking) {
      _again = true;
      return;
    }
    final state = view.state;
    final stretch = spellStretch(state);
    final asked = spellText(state, stretch.from, stretch.to);
    _asking = true;
    List<Misspelling>? found;
    try {
      found = await checker.check(asked, locale: locale());
    } catch (_) {
      found = null;
    } finally {
      _asking = false;
    }
    if (_gone) return;
    final now = view.state;
    // Asked about words that are not there any more: the answer is for nothing, and the change asked again.
    final same = identical(now.doc, state.doc) || (stretch.to <= now.doc.length && spellText(now, stretch.from, stretch.to) == asked);
    if (found != null && same && _on) {
      final head = now.selection.main.head;
      final typed = now.selection.main.empty;
      view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[
        setMisspellings.of((
          from: stretch.from,
          to: stretch.to,
          found: <Misspelling>[
            for (final each in found)
              // The word the caret is in or at the end of is still being written.
              if (!(typed && stretch.from + each.from <= head && head <= stretch.from + each.to)) Misspelling(stretch.from + each.from, stretch.from + each.to, each.suggestions),
          ],
        )),
      ]));
    }
    if (_again || !same) {
      _again = false;
      _later();
    }
  }

  @override
  void destroy() {
    _gone = true;
    _soon?.cancel();
  }
}

Locale _phoneLocale() => PlatformDispatcher.instance.locale;

/// Spell-check for an editor that is typed in: the marks (spell_marks.dart) and the watcher that asks [checker],
/// the phone's own unless given. [wait] and [locale] are a test's to change.
Extension spellCheck({SpellChecker? checker, Duration wait = spellWait, Locale Function()? locale}) => Extension.list(<Extension>[
      spellMarks,
      ViewPlugin.define<_Watch>((view) => _Watch(view, checker ?? const PhoneSpellChecker(), wait, locale ?? _phoneLocale)),
    ]);
