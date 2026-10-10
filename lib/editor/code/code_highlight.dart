/// Code coloured by its language, and HTML's tags with it: what `markdown({codeLanguages, htmlTagLanguage})` and
/// `syntaxHighlighting(glyphHighlight)` do between them in `src/app/editor/Editor.tsx` (language.ts,
/// glyphHighlight.ts). The audit's Missing 1.
///
/// On the web the Markdown parser hands a fenced block's words to the grammar its info string names
/// (`languages.dart`), and an HTML block, an HTML tag in a line and a comment block to HTML's
/// (@lezer/markdown `parseCode`); the inner tree is laid over the outer one, and the highlighter reads it there
/// with the same list of tags and classes as the note's own. So a keyword in a block is `codeKeyword`, a tag's
/// name in a line of prose is `codeType`, and what each looks like is the code theme's (`looks/code_themes.dart`,
/// already ported: the seven palettes and the classes' rules in `looks/markdown_look.dart`).
///
/// Here the note's tree has no inner trees (`syntax/tree.dart`), so a plugin stands beside the note's
/// highlighter: it finds the fences and the HTML on screen, has each read by its language, and marks the runs
/// with the same classes. The note's highlighter is told which nodes' own words are another language's
/// ([codeDraws], through its `nestedLanguage`), since on the web those words carry no class of the note's: a
/// block with a language is in the code's ink, not the one colour of a block without (`CodeText`'s `code`).
///
/// What a block costs, which the web gets from Lezer's incremental parse and this gets another way:
/// - A block is read when its own words change, and at no other time. A block is known by the piece of the
///   note's tree it is, which a reparse keeps for every block a change did not touch: a letter typed elsewhere
///   finds each block on screen by that piece and reads nothing. A caret's move, a focus, anything that changes
///   neither the tree nor what is on screen, is not looked at.
/// - A block that did change is taken up from where its words changed (`CodeLanguage.resume`), not from its
///   first line.
/// - A long block is read as far as the screen shows, within [CodeWorkBudget.apply] once it is past
///   [CodeWorkBudget.always], and the rest in slices between frames; CodeMirror gives a change twenty
///   milliseconds and then works in idle slices to a hundred thousand characters past the screen
///   (@codemirror/language `Work`). Code not read yet is in the code's ink.
library;

import 'dart:async';

import '../editor.dart';
import '../syntax/tree.dart' show SyntaxNode;
import '../view/glyph_highlight.dart' show nestedLanguage;
import '../view/syntax_tree.dart';
import 'languages.dart';
import 'work.dart';

/// How long the highlighter may read for, as CodeMirror's `Work` says it for the web. `null` is no limit, for a
/// test that wants every block read at once.
abstract final class CodeWorkBudget {
  /// Microseconds of reading as a change or a scroll is drawn (`Work.Apply` is 20 ms on the web, where a frame
  /// is not what is being held to).
  static int? apply = 3000;

  /// The characters of a block that are read as it is drawn whatever the clock says, so that a block of an
  /// ordinary length is never drawn half coloured, on a slow phone or under a test on a busy machine: a clock
  /// alone would make what is on screen a matter of chance.
  static int always = 8000;

  /// Microseconds of reading in each slice after (`Work.Slice`, at most 100 ms on the web).
  static int? slice = 4000;

  /// The pause between slices (`Work.MinPause`).
  static Duration pause = const Duration(milliseconds: 32);

  /// How far past the screen a block is read on (`Work.MaxParseAhead`).
  static int ahead = 100000;
}

const Set<String> _html = <String>{'HTMLBlock', 'HTMLTag', 'CommentBlock'};

/// The blocks that hold other blocks: a fence or an HTML block may be inside one.
const Set<String> _containers = <String>{'Document', 'Blockquote', 'BulletList', 'OrderedList', 'ListItem'};

/// The lines a fence can open on, and the lines HTML can be on: read from each line's words alone and kept with
/// the document's tree (`LineFact`), so that a note with neither is not walked at all, and in a note with some
/// only the blocks that have them are gone into. Most notes have neither, and most paragraphs no `<`.
final LineFact<bool> _fenceLines = LineFact<bool>((text) => text.contains('```') || text.contains('~~~') ? true : null);
final LineFact<bool> _angleLines = LineFact<bool>((text) => text.contains('<') ? true : null);

/// Whether one of `lines` (in order) is between `from` and `to`.
bool _anyLine(List<FactLine<bool>> lines, int from, int to) {
  var low = 0, high = lines.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (lines[mid].to < from) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low < lines.length && lines[low].from <= to;
}

/// What of a node another language reads: the stretches of it, counted from its start, a start and an end for
/// each; and for a fence, the pack's name for the language its info string asks for.
class _Shape {
  _Shape(this.ranges, this.language, this.known);

  final List<int> ranges;

  /// Who reads it: null for a fence with no language, one the pack does not know, or one nothing here reads.
  final CodeLanguage? language;

  /// Whether the pack knows the language, read here or not.
  final bool known;
}

final Expando<_Shape> _shapes = Expando<_Shape>('code shape');

_Shape _shapeOf(EditorState state, SyntaxNode node) {
  final tree = node.tree;
  final kept = _shapes[tree];
  if (kept != null) return kept;
  final ranges = <int>[];
  final _Shape shape;
  if (tree.type.name == 'FencedCode') {
    String? info;
    for (var i = 0; i < tree.children.length; i++) {
      final child = tree.children[i], at = tree.positions[i];
      if (child.type.name == 'CodeText') {
        // `addCodeText` joins one piece to the piece before it; a line's indentation in a list is between two.
        if (ranges.isNotEmpty && ranges.last == at) {
          ranges.last = at + child.length;
        } else {
          ranges
            ..add(at)
            ..add(at + child.length);
        }
      } else if (child.type.name == 'CodeInfo') {
        info = state.doc.sliceString(node.from + at, node.from + at + child.length);
      }
    }
    final name = info == null ? null : languageNameOf(info);
    shape = _Shape(ranges, name == null ? null : languageNamed(name), name != null);
  } else {
    // `leftOverSpace`: the node, less the nodes inside it (a quote's marks down the side of an HTML block).
    var pos = 0;
    for (var i = 0; i < tree.children.length; i++) {
      final at = tree.positions[i];
      if (at > pos) {
        ranges
          ..add(pos)
          ..add(at);
      }
      pos = at + tree.children[i].length;
    }
    if (tree.length > pos) {
      ranges
        ..add(pos)
        ..add(tree.length);
    }
    shape = _Shape(ranges, htmlInMarkdown, true);
  }
  return _shapes[tree] = shape;
}

/// Whether a node's own words are another language's, so that the note's highlighter gives them no class of its
/// own: a fenced block's code when the pack knows its language, and HTML wherever it stands. What
/// `view/glyph_highlight.dart` asks through `nestedLanguage`.
bool codeDraws(EditorState state, SyntaxNode node) {
  final name = node.name;
  if (name == 'CodeText') {
    final fence = node.parent;
    return fence != null && fence.name == 'FencedCode' && _shapeOf(state, fence).known;
  }
  return _html.contains(name);
}

/// One fence or one stretch of HTML, read.
class _Block {
  _Block(this.shape, this.code, this.work);

  final _Shape shape;
  final String code;
  CodeWork work;

  // The runs last worked out: of which stretch of the code, how much was read then, and the runs.
  int _from = -1, _to = -1, _readAt = -1;
  bool _doneAt = false;

  /// Whether the runs last worked out were short of what is on screen: not all of it was read.
  bool _short = false;
  final List<int> _runFrom = <int>[], _runTo = <int>[];
  final List<Decoration> _runMark = <Decoration>[];
}

final Expando<_Block> _blocks = Expando<_Block>('code block');

/// The HTML read lately, by its words: a tag in a line is a few letters, and the same few in line after line.
final Map<String, CodeWork> _htmlRead = <String, CodeWork>{};

/// One decoration for each class, as the note's highlighter keeps them.
final Map<String, Decoration> _marks = <String, Decoration>{};

final StateEffectType<void> _moreRead = StateEffect.define<void>();

class _CodeHighlighter extends PluginValue {
  _CodeHighlighter(this.view) {
    decorations = _build(null);
  }

  final EditorViewLike view;
  late DecorationSet decorations;

  /// The blocks on screen as last drawn: where each started, and what was read of it.
  List<(int from, _Block block)> _shown = const <(int, _Block)>[];

  /// Blocks on screen with more to read: how far each is wanted.
  final List<(_Block block, int wanted)> _waiting = <(_Block, int)>[];
  Timer? _timer;

  @override
  void update(ViewUpdate update) {
    final more = update.transactions.any((tr) => tr.effects.any((effect) => effect.isOf(_moreRead)));
    final treeMoved = !identical(syntaxTreeOrNull(update.state), syntaxTreeOrNull(update.startState));
    if (!treeMoved && !update.viewportChanged && !more) return;
    decorations = _build(update.docChanged ? update.changes : null);
  }

  @override
  void destroy() {
    _timer?.cancel();
    _timer = null;
  }

  DecorationSet _build(ChangeDesc? changes) {
    final state = view.state, tree = syntaxTreeOrNull(state);
    _waiting.clear();
    if (tree == null) {
      _shown = const <(int, _Block)>[];
      return Decoration.none;
    }
    // A note with no fence and no `<` in it has nothing here, and is not walked.
    final doc = state.doc;
    final noAngles = _angleLines.nowhere(doc);
    if (noAngles && _fenceLines.nowhere(doc)) {
      _shown = const <(int, _Block)>[];
      _timer?.cancel();
      _timer = null;
      return Decoration.none;
    }
    final builder = RangeSetBuilder<Decoration>();
    final budget = Budget(CodeWorkBudget.apply);
    final shown = <(int, _Block)>[];
    for (final range in view.visibleRanges) {
      final from = range.from, to = range.to;
      // The lines on screen with a `<` on them: asked of the leaves the screen's lines are in, not of the note.
      final angles = noAngles ? const <FactLine<bool>>[] : _angleLines.between(doc, doc.lineAt(from).number, doc.lineAt(to).number);
      tree.iterate(
        from: from,
        to: to,
        enter: (SyntaxNode node) {
          final name = node.name;
          if (name != 'FencedCode' && !_html.contains(name)) {
            // Into the blocks that hold blocks; into a paragraph, a heading, a table, only where a line of it
            // has a `<` on it, which is where a tag can be.
            if (_containers.contains(name)) return null;
            return angles.isNotEmpty && _anyLine(angles, node.from, node.to) ? null : false;
          }
          if (node.to <= from || node.from >= to) return false;
          final block = _blockFor(state, node, changes);
          if (block != null) {
            if (shown.isEmpty || !identical(shown.last.$2, block)) shown.add((node.from, block));
            _draw(block, node.from, from, to, budget, builder);
          }
          return false;
        },
      );
    }
    _shown = shown;
    if (_waiting.isNotEmpty) {
      _timer ??= Timer(CodeWorkBudget.pause, _slice);
    } else {
      _timer?.cancel();
      _timer = null;
    }
    return builder.finish();
  }

  /// What is read of the fence or the HTML at `node`, reading it if it is new; null where no language reads it.
  _Block? _blockFor(EditorState state, SyntaxNode node, ChangeDesc? changes) {
    final kept = _blocks[node.tree];
    if (kept != null) return kept;
    final shape = _shapeOf(state, node);
    final language = shape.language;
    if (language == null || shape.ranges.isEmpty) return null;
    final ranges = shape.ranges;
    final String code;
    if (ranges.length == 2) {
      code = state.doc.sliceString(node.from + ranges[0], node.from + ranges[1]);
    } else {
      final buffer = StringBuffer();
      for (var i = 0; i < ranges.length; i += 2) {
        buffer.write(state.doc.sliceString(node.from + ranges[i], node.from + ranges[i + 1]));
      }
      code = buffer.toString();
    }
    CodeWork? work;
    if (identical(language, htmlInMarkdown) && code.length <= 256) {
      work = _htmlRead[code];
      if (work == null) {
        if (_htmlRead.length > 400) _htmlRead.clear();
        work = _htmlRead[code] = language.start(code);
      }
    } else {
      // The block as it was before the change, if this is one that changed: the one that started where this does.
      for (final (was, block) in _shown) {
        if ((changes == null ? was : changes.mapPos(was)) == node.from && identical(block.work.language, language)) {
          work = language.resume(block.work, code);
          break;
        }
      }
      work ??= language.start(code);
    }
    return _blocks[node.tree] = _Block(shape, code, work);
  }

  /// Marks the runs of `block`, which starts at `at` in the note, between `from` and `to`.
  void _draw(_Block block, int at, int from, int to, Budget budget, RangeSetBuilder<Decoration> builder) {
    final ranges = block.shape.ranges;
    // The stretch of the code that is on screen.
    var codeFrom = -1, codeTo = -1, offset = 0;
    for (var i = 0; i < ranges.length; i += 2) {
      final a = at + ranges[i], b = at + ranges[i + 1];
      if (codeFrom < 0 && from < b) codeFrom = offset + (from > a ? from - a : 0);
      if (to > a) codeTo = offset + (to < b ? to - a : b - a);
      offset += b - a;
    }
    if (codeFrom < 0 || codeTo <= codeFrom) return;
    final work = block.work;
    if (!work.done) {
      final always = work.parsedTo + CodeWorkBudget.always;
      if (work.parsedTo < codeTo) work.work(codeTo < always ? codeTo : always, Budget.none());
      if (work.parsedTo < codeTo) work.work(codeTo, budget);
    }
    if (block._from != codeFrom || block._to != codeTo || block._readAt != work.parsedTo || block._doneAt != work.done) {
      block._runFrom.clear();
      block._runTo.clear();
      block._runMark.clear();
      work.spans(codeFrom, codeTo, (a, b, cls) {
        block._runFrom.add(a);
        block._runTo.add(b);
        block._runMark.add(_marks[cls] ??= Decoration.mark(className: cls));
      }, budget: budget);
      block._from = codeFrom;
      block._to = codeTo;
      block._readAt = work.parsedTo;
      block._doneAt = work.done;
      // Short of the screen: the block's own reading, or (the block read to its end) an inner language's.
      block._short = !work.done && (work.parsedTo < codeTo || work.parsedTo >= block.code.length);
    }
    if (!work.done) {
      final wanted = codeTo + CodeWorkBudget.ahead;
      _waiting.add((block, wanted < block.code.length ? wanted : block.code.length));
    }
    // A run is in the code's own numbers: a piece of it for each stretch of the note it crosses.
    final runFrom = block._runFrom, runTo = block._runTo, runMark = block._runMark;
    var piece = 0, pieceStart = 0;
    for (var i = 0; i < runFrom.length; i++) {
      var a = runFrom[i];
      final b = runTo[i];
      while (a < b && piece < ranges.length) {
        final length = ranges[piece + 1] - ranges[piece];
        if (a >= pieceStart + length) {
          pieceStart += length;
          piece += 2;
          continue;
        }
        final end = b < pieceStart + length ? b : pieceStart + length;
        final docFrom = at + ranges[piece] + (a - pieceStart), docTo = at + ranges[piece] + (end - pieceStart);
        if (docTo > docFrom) builder.add(docFrom, docTo, runMark[i]);
        a = end;
      }
    }
  }

  /// Reads on in the blocks on screen that have more, for a slice, and has them drawn if what is on screen has
  /// more colour for it.
  void _slice() {
    _timer = null;
    final budget = Budget(CodeWorkBudget.slice);
    var show = false, more = false;
    for (final (block, wanted) in _waiting) {
      final work = block.work;
      if (work.done) continue;
      final before = work.parsedTo;
      work.work(wanted, budget);
      // What is on screen has more colour for it when the reading was short of it and has gone on.
      if (block._short && (work.parsedTo > before || work.done)) show = true;
      if (!work.done && work.parsedTo <= wanted) more = true;
      if (budget.spent) {
        more = more || !work.done;
        break;
      }
    }
    if (show) {
      view.dispatch(TransactionSpec(effects: _moreRead.of(null)));
    } else if (more) {
      _timer = Timer(CodeWorkBudget.pause, _slice);
    }
  }
}

final Extension _codeHighlight = Extension.list(<Extension>[
  nestedLanguage.of(codeDraws),
  // Beside the note's own highlighter, which CodeMirror's `treeHighlighter` runs at `Prec.high`.
  Prec.high(ViewPlugin.define<_CodeHighlighter>(_CodeHighlighter.new, decorations: (value) => value.decorations)),
]);

/// Fenced code coloured by its language, and HTML's tags, in the code theme's classes.
Extension codeHighlight() => _codeHighlight;
