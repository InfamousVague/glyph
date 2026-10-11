/// The extended markdown Ghost.md draws. Ports `src/app/editor/extended.ts`.
///
/// The language already parses more than plain markdown (GFM plus subscript, superscript and emoji). What is drawn
/// here, all of it ordinary markdown elsewhere (docs/MARKDOWN.md in tauri/):
///
///     x^2^  H~2~O            raised and lowered runs
///     > [!NOTE]              a callout, GitHub's own spelling
///     Term / : the meaning   a definition list; the colon hidden off the caret's line
///     ---\ntitle: …\n---     front matter, which read as a horizontal rule before
///     $x^2$  $$ … $$         maths, set as code
///     :tada:                 a shortcode, drawn as its emoji (core/emoji.dart)
///
/// The front matter is drawn folded as well ([frontMatterFolded]): one quiet line naming its keys while the editor
/// is not focused with the caret in the block; a block that holds only `look` folds to nothing. A block decoration
/// cannot come from a view plugin, so the fold is a state field, told of the editor's focus through
/// `focusChangeEffect`. Only where the words can be edited: a read-only page shows the lines as they are.
///
/// What differs:
/// - The theme is a [LookSheet] ([_theme]) with each rule of the web's `EditorView.baseTheme` cited beside it.
///   `border-inline-start` on `.cm-callout` is kept as written though a quote's own rule (three classes to its
///   two) sets it back to none, exactly as on the page.
/// - `.cm-frontFold > span` is the fold widget's own drawing; `cursor: pointer` and `user-select: none` have no
///   counterpart. The fold's tap puts the caret on the first key and asks the view for focus, as there.
/// - A shortcode's `title` (its name on hover) is not drawn.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/emoji.dart';
import '../../core/front_matter.dart';
import '../../core/maths.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../state/rangeset.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/text.dart';
import 'blocks.dart';
import 'decoration.dart';
import 'editor_view.dart';
import 'plugin.dart';
import 'syntax_tree.dart';
import 'widget.dart';

/// The words of a raised or lowered run, by node name: the highlighter gives both the same tag.
const Map<String, String> _scripts = <String, String>{'Superscript': 'cm-sup', 'Subscript': 'cm-sub'};

/// A definition's line: `: the meaning`, under the term it belongs to.
final RegExp _definition = RegExp(r'^(\s{0,3}:)(\s+\S.*)$');

/// Which lines the note's front matter covers, as line numbers, or null: what core/front_matter.dart counts as
/// front matter. Only the lines the rule can reach are read, and only when the first is a fence.
({int from, int to})? frontMatter(Doc doc) => _front.of(doc).lines;

class _Front {
  const _Front(this.lines);
  final ({int from, int to})? lines;
}

/// Read once for each document: the fold, the marks and the + all ask, on every letter and every move of the caret.
final DocMemo<_Front> _front = DocMemo<_Front>((doc) {
  if (!frontMatterFence.hasMatch(doc.line(1).text)) return const _Front(null);
  final most = doc.lines < frontMatterLines ? doc.lines : frontMatterLines;
  final head = <String>[for (var n = 1; n <= most; n++) doc.line(n).text];
  final end = frontMatterEnd(head);
  return _Front(end > 0 ? (from: 1, to: end) : null);
});

/// A callout's kind, as GitHub writes it: `> [!NOTE]` on the quote's first line.
final RegExp _callout = RegExp(r'^\s*>\s*\[!(note|tip|important|warning|caution)\]\s*(.*)$', caseSensitive: false);

/// The kind of callout a blockquote is, or null for an ordinary quote.
String? calloutKind(String firstLine) => _callout.firstMatch(firstLine)?.group(1)?.toLowerCase();

/// A shortcode, drawn as its emoji. The words come back the moment the caret is on the line.
class EmojiWidget extends EditorWidget {
  const EmojiWidget(this.emoji, this.name);

  final String emoji;
  final String name;

  @override
  bool eq(EmojiWidget other) => other.emoji == emoji;

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.maybeOf(context);
    final body = (view is EditorView ? view.look?.env.body : null) ?? DefaultTextStyle.of(context).style.fontSize ?? 16;
    // '.cm-emoji': { fontSize: '1.05em', lineHeight: '1' }
    return Text(emoji, style: TextStyle(fontSize: body * 1.05, height: 1, leadingDistribution: TextLeadingDistribution.even), textScaler: TextScaler.noScaling);
  }
}

/// Keys the folded line never names, since the note's own drawing says them: its look.
const Set<String> _unsaid = <String>{'look'};

final RegExp _key = RegExp(r'^\s*([\w.-]+)\s*:');

/// The names of the keys a front matter block holds, in order, less the unsaid ones: what the folded line says.
List<String> _keyNames(EditorState state, ({int from, int to}) front) {
  final names = <String>[];
  for (var n = front.from + 1; n < front.to; n += 1) {
    final found = _key.firstMatch(state.doc.line(n).text);
    if (found != null && !_unsaid.contains(found.group(1)!.toLowerCase())) names.add(found.group(1)!);
  }
  return names;
}

/// Whether the block holds keys and every one of them is unsaid: it folds to nothing, not to a line.
bool _onlyUnsaid(EditorState state, ({int from, int to}) front) {
  var any = false;
  for (var n = front.from + 1; n < front.to; n += 1) {
    final found = _key.firstMatch(state.doc.line(n).text);
    if (found == null) continue;
    if (!_unsaid.contains(found.group(1)!.toLowerCase())) return false;
    any = true;
  }
  return any;
}

/// Whether a selection head sits on one of the block's lines.
bool _caretIn(EditorState state, ({int from, int to}) front) => state.selection.ranges.any((range) {
  final n = state.doc.lineAt(range.head).number;
  return n >= front.from && n <= front.to;
});

/// The front matter folded to one line: its keys' names. A tap opens it, by putting the caret on its first key.
class FrontWidget extends EditorWidget implements ClassedBlockWidget {
  const FrontWidget(this.keys, this.at);

  final List<String> keys;

  /// Where the caret goes on a tap: the first key's line.
  final int at;

  @override
  String get className => 'cm-frontFold';

  @override
  bool eq(FrontWidget other) {
    if (other.at != at || other.keys.length != keys.length) return false;
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] != other.keys[i]) return false;
    }
    return true;
  }

  @override
  double get estimatedHeight => 28;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    // The sizes the editor it is in was given (a card's preview sets its own), which the frozen view does not say.
    final env = view is EditorView ? view.look?.env : null;
    final body = env?.body ?? t.len('app-body');
    final gutter = env?.gutter ?? t.len('app-gutter');
    // '.cm-frontFold': { paddingInline: 'var(--app-gutter, 0)', fontFamily: 'var(--glacier-font-mono)',
    //   fontSize: '0.84em', lineHeight: '1.9', color: 'var(--app-ink-3, var(--glacier-text-muted))' }
    final size = body * 0.84;
    final ink = t.color('app-ink-3');
    final style = t.textAt(size, mono: true, color: ink, height: 1.9);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (view == null) return;
        view.dispatch(TransactionSpec(selection: EditorSelection.single(at), effects: _focusEffect.of(true)));
        view.focus();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: SizedBox(
          // One line of 1.9 to the size, to the sixty-fourth as the page keeps it.
          height: layoutUnit(size * 1.9),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            // '.cm-frontFold > span': { display: 'inline-block', maxInlineSize: '100%',
            //   paddingInline: 'var(--glacier-space-2, 8px)', borderRadius: 'var(--glacier-radius-sm, 4px)',
            //   background: 'color-mix(in oklch, currentColor 3%, transparent)' }
            child: DecoratedBox(
              decoration: BoxDecoration(color: t.colorOf('color-mix(in oklch, currentColor 3%, transparent)', current: ink), borderRadius: BorderRadius.circular(t.radius('sm'))),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space(2)),
                child: Text(keys.isNotEmpty ? keys.join(' · ') : 'front matter', style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, textScaler: TextScaler.noScaling),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A block that holds only unsaid keys, folded to nothing: an empty mark in its place, so the stylesheet can set
/// the title under it as a note's first line (markdown.module.css), with no room above it.
class NoFrontWidget extends EditorWidget implements ClassedBlockWidget {
  const NoFrontWidget();

  @override
  String get className => 'cm-frontNone';

  @override
  bool eq(NoFrontWidget other) => true;

  @override
  double get estimatedHeight => 0;

  @override
  bool get isHidden => true;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The editor gained or lost focus: the block is open only while it has it.
final StateEffectType<bool> _focusEffect = StateEffect.define<bool>();

/// Whether another hand draws the front matter, so it is not folded here: a ticket's properties panel, which steps
/// aside for the lines itself.
final Facet<bool Function(EditorState state), List<bool Function(EditorState state)>> frontMatterDrawn = Facet.define();

class _Fold {
  const _Fold(this.focused, this.decorations);
  final bool focused;
  final DecorationSet decorations;
}

DecorationSet _foldOf(EditorState state, bool focused) {
  final front = frontMatter(state.doc);
  if (front == null || !state.facet(EditorViewLike.editable) || (focused && _caretIn(state, front))) return Decoration.none;
  if (state.facet(frontMatterDrawn).any((drawn) => drawn(state))) return Decoration.none;
  final from = state.doc.line(front.from).from;
  final to = state.doc.line(front.to).to;
  final at = state.doc.line(front.from + 1 < front.to ? front.from + 1 : front.to).from;
  if (_onlyUnsaid(state, front)) return Decoration.set(<Range<Decoration>>[Decoration.replace(widget: const NoFrontWidget(), block: true).range(from, to)]);
  return Decoration.set(<Range<Decoration>>[Decoration.replace(widget: FrontWidget(_keyNames(state, front), at), block: true).range(from, to)]);
}

final StateField<_Fold> _frontFold = StateField.define<_Fold>(
  create: (state) => _Fold(false, _foldOf(state, false)),
  update: (value, tr) {
    var focused = value.focused;
    for (final effect in tr.effects) {
      final told = _focusEffect.cast(effect);
      if (told != null) focused = told.value;
    }
    if (!tr.docChanged && tr.selection == null && !tr.reconfigured && focused == value.focused) return value;
    return _Fold(focused, _foldOf(tr.state, focused));
  },
  provide: (field) => EditorViewLike.decorations.from<_Fold>(field, (value) => value.decorations),
);

/// Whether the front matter is folded to its line now, for a test to ask.
bool frontMatterFolded(EditorState state) => state.field(_frontFold).decorations.size > 0;

class _Mark {
  _Mark(this.from, this.to, this.deco);
  final int from;
  final int to;
  final Decoration deco;
}

final Decoration _frontLine = Decoration.line(className: 'cm-front');
final Decoration _definitionLine = Decoration.line(className: 'cm-definition');
final Decoration _termLine = Decoration.line(className: 'cm-term');
final Decoration _mathsMark = Decoration.mark(className: 'cm-maths');
final Decoration _calloutName = Decoration.mark(className: 'cm-calloutName');
final Decoration _hide = Decoration.replace();
final Map<String, Decoration> _scriptMarks = <String, Decoration>{for (final name in _scripts.values) name: Decoration.mark(className: name)};
final Map<String, Decoration> _calloutLines = <String, Decoration>{};

final RegExp _leadSpace = RegExp(r'^\s+');

/// What a line has of a definition, of maths and of shortcodes, each counted from the line's start.
class _Extras {
  const _Extras(this.lead, this.maths, this.codes);

  /// How much of a definition's line is its colon and the space after it, or null for a line that is none.
  final int? lead;
  final List<({int from, int to})> maths;
  final List<({int from, int to, String emoji})> codes;
}

/// Kept for every line of a document (`LineFact`): the lines on screen are not put to three patterns again on
/// every letter and every move of the caret. A definition and a shortcode are written with a colon and maths with
/// a dollar sign, so a line with neither has none of the three.
final LineFact<_Extras> _extras = LineFact<_Extras>((text) {
  final colon = text.contains(':'), dollar = text.contains(r'$');
  if (!colon && !dollar) return null;
  int? lead;
  if (colon) {
    final definition = _definition.firstMatch(text);
    if (definition != null) lead = definition.group(1)!.length + (_leadSpace.firstMatch(definition.group(2)!)?.group(0)!.length ?? 0);
  }
  final maths = dollar ? mathsIn(text) : const <({int from, int to})>[];
  final codes = colon ? shortcodesIn(text) : const <({int from, int to, String emoji})>[];
  if (lead == null && maths.isEmpty && codes.isEmpty) return null;
  return _Extras(lead, maths, codes);
});

/// A line with a raised or lowered run's mark or a quote's in it: the only lines the tree's walk below has
/// anything to find on.
final LineFact<bool> _treeish = LineFact<bool>((text) => text.contains('^') || text.contains('~') || text.contains('>') ? true : null);

DecorationSet _decorate(EditorState state, int from, int to, bool editing) {
  final marks = <_Mark>[];
  final doc = state.doc;
  // The lines the caret is on, whose marks are shown as typed, to edit: none in a view nobody is typing in.
  final caretLines = <int>{if (editing) for (final range in state.selection.ranges) doc.lineAt(range.head).number};

  // The note's own front matter, which the parser reads as a rule and a run of words.
  final front = frontMatter(doc);
  if (front != null) {
    for (var n = front.from; n <= front.to; n += 1) {
      final line = doc.line(n);
      marks.add(_Mark(line.from, line.from, _frontLine));
    }
  }

  final first = doc.lineAt(from).number;
  final last = doc.lineAt(to).number;
  for (final line in _extras.between(doc, first, last)) {
    final n = line.number;
    if (front != null && n >= front.from && n <= front.to) continue;
    final extras = line.fact;

    // A definition under its term: the meaning hangs under the term, which is set apart. Its colon is how it is
    // written, not how it reads, so off the caret's line it goes; on it, it is there to edit.
    final lead = extras.lead;
    if (lead != null) {
      marks.add(_Mark(line.from, line.from, _definitionLine));
      if (!caretLines.contains(n)) marks.add(_Mark(line.from, line.from + lead, _hide));
      final above = n > 1 ? doc.line(n - 1) : null;
      if (above != null && above.text.trim().isNotEmpty && !_definition.hasMatch(above.text)) {
        marks.add(_Mark(above.from, above.from, _termLine));
      }
    }

    // Maths, set as code. Found by Pandoc's rule (core/maths.dart), so a line with two prices on it is prices.
    for (final maths in extras.maths) {
      marks.add(_Mark(line.from + maths.from, line.from + maths.to, _mathsMark));
    }

    // A shortcode becomes its emoji, unless the caret is on that line, where the words are wanted.
    if (!caretLines.contains(n)) {
      for (final code in extras.codes) {
        marks.add(_Mark(line.from + code.from, line.from + code.to, Decoration.replace(widget: EmojiWidget(code.emoji, line.text.substring(code.from, code.to)))));
      }
    }
  }

  // The lines on screen the walk can find something on. A node that starts on screen and holds none of them holds
  // neither a raised run nor a quote, and is passed over whole; one that starts above the screen is always gone
  // into, since a quote's own mark may be up there.
  final marked = _treeish.between(doc, first, last);
  bool holds(int nodeFrom, int nodeTo) {
    var lo = 0, hi = marked.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (marked[mid].to < nodeFrom) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < marked.length && marked[lo].from <= nodeTo;
  }

  syntaxTree(state).iterate(
    from: from,
    to: to,
    enter: (node) {
      final script = _scripts[node.name];
      if (script != null) {
        // The words, the delimiters aside: `^` and `~` are one character each.
        if (node.to - 1 > node.from + 1) marks.add(_Mark(node.from + 1, node.to - 1, _scriptMarks[script]!));
        return false;
      }
      if (node.name != 'Blockquote') return node.from < from || holds(node.from, node.to) ? null : false;
      final firstLine = doc.lineAt(node.from);
      final kind = calloutKind(firstLine.text);
      if (kind == null) return null;
      // `[!NOTE]` is a link label to the parser, and was drawn as one. It is the callout's name, so it is drawn as
      // a name.
      final at = firstLine.text.indexOf('[!');
      final shut = at < 0 ? -1 : firstLine.text.indexOf(']', at);
      if (at >= 0 && shut > at) marks.add(_Mark(firstLine.from + at, firstLine.from + shut + 1, _calloutName));
      final lastLine = doc.lineAt(node.to - 1 > node.from ? node.to - 1 : node.from);
      for (var n = firstLine.number; n <= lastLine.number; n += 1) {
        final line = doc.line(n);
        final top = n == firstLine.number;
        marks.add(
          _Mark(
            line.from,
            line.from,
            _calloutLines['$kind$top'] ??= Decoration.line(className: top ? 'cm-callout cm-calloutTop' : 'cm-callout', attributes: <String, String>{'data-callout': kind}),
          ),
        );
      }
      return null;
    },
  );
  // A line decoration and a mark can start at the same place; the line one must be added first.
  final order = <int>[for (var i = 0; i < marks.length; i++) i]
    ..sort((a, b) {
      final x = marks[a], y = marks[b];
      if (x.from != y.from) return x.from - y.from;
      final byKind = (x.to == x.from ? -1 : 1) - (y.to == y.from ? -1 : 1);
      // A stable sort, as JavaScript's is.
      return byKind != 0 ? byKind : a - b;
    });
  return Decoration.set(<Range<Decoration>>[for (final i in order) marks[i].deco.range(marks[i].from, marks[i].to)], true);
}

Color? Function(Color) _wash(double percent, LookEnv e) =>
    (current) => e.t.colorOf('color-mix(in oklch, currentColor $percent%, transparent)', current: current);

bool _strong(LookElement el, LineContext c) => const <String>{'warning', 'caution'}.contains(el.attrs['data-callout']);

/// `EditorView.baseTheme({...})` of extended.ts. A base theme's selectors carry the theme's own class, so each
/// rule counts one class more than it shows.
final LookSheet _theme = LookSheet('editor/extended.ts', <LookRule>[
  // '.cm-sup': { verticalAlign: 'super', fontSize: '0.75em', lineHeight: '1' }
  LookRule('cm-sup', classes: 2, (p, e) {
    // Blink raises `super` a third of the parent's size and a pixel.
    p
      ..shift = p.parentSize / 3 + 1
      ..sizeEm(0.75)
      ..lineHeight = 1;
  }),
  // '.cm-sub': { verticalAlign: 'sub', fontSize: '0.75em', lineHeight: '1' }
  LookRule('cm-sub', classes: 2, (p, e) {
    // And lowers `sub` a fifth and a pixel.
    p
      ..shift = -(p.parentSize / 5 + 1)
      ..sizeEm(0.75)
      ..lineHeight = 1;
  }),
  // '.cm-callout': { background: 'color-mix(in oklch, currentColor 4%, transparent)',
  //   borderInlineStart: '3px solid color-mix(in oklch, currentColor 35%, transparent)',
  //   paddingInlineStart: '0.6em' }
  LookRule(
    'cm-callout',
    null,
    classes: 2,
    box: (p, e) {
      p
        ..background = _wash(4, e)
        ..borderStart = 3
        ..borderStartColor = _wash(35, e)
        ..paddingStart = p.em(0.6);
    },
  ),
  // '.cm-callout[data-callout="warning"], .cm-callout[data-callout="caution"]': {
  //   background: 'color-mix(in oklch, currentColor 7%, transparent)',
  //   borderInlineStartColor: 'color-mix(in oklch, currentColor 60%, transparent)' }
  LookRule(
    'cm-callout',
    null,
    classes: 3,
    when: _strong,
    box: (p, e) {
      p
        ..background = _wash(7, e)
        ..borderStartColor = _wash(60, e);
    },
  ),
  // '.cm-calloutName, .cm-calloutName *': { textDecoration: 'none',
  //   color: 'var(--app-ink-3, var(--glacier-text-muted))', fontSize: '0.82em', letterSpacing: '0.08em' }
  for (final under in const <bool>[false, true])
    LookRule('cm-calloutName', classes: 2, under: under, (p, e) {
      p
        ..underline = false
        ..lineThrough = false
        ..color = e.t.color('app-ink-3')
        ..sizeEm(0.82)
        ..trackingEm(0.08);
    }),
  // '.cm-calloutTop': { fontWeight: 'var(--glacier-font-weight-semibold, 600)', paddingBlockStart: '0.25em',
  //   borderStartStartRadius: '0.4em' }
  LookRule(
    'cm-calloutTop',
    (p, e) => p.weight = e.t.len('glacier-font-weight-semibold'),
    classes: 2,
    box: (p, e) {
      p
        ..paddingTop = p.em(0.25)
        ..topStart = Radius.circular(p.em(0.4));
    },
  ),
  // '.cm-callout:not(.cm-calloutTop):last-of-type': { paddingBlockEnd: '0.25em' }
  LookRule('cm-callout', null, classes: 4, when: (el, c) => c.last && !el.has('cm-calloutTop'), box: (p, e) => p.paddingBottom = p.em(0.25)),
  // '.cm-front, .cm-front *': { fontFamily: 'var(--glacier-font-mono)', fontSize: '0.84em',
  //   color: 'var(--app-ink-3, var(--glacier-text-muted))', textDecoration: 'none', fontWeight: 'inherit' }
  for (final under in const <bool>[false, true])
    LookRule('cm-front', classes: 2, under: under, (p, e) {
      p
        ..families = e.monoFamilies
        ..sizeEm(0.84)
        ..color = e.t.color('app-ink-3')
        ..underline = false
        ..lineThrough = false
        ..weightInherit();
    }),
  // '.cm-front': { background: 'color-mix(in oklch, currentColor 3%, transparent)' }
  LookRule('cm-front', null, classes: 2, box: (p, e) => p.background = _wash(3, e)),
  // '.cm-term': { fontWeight: 'var(--glacier-font-weight-semibold, 600)' }
  LookRule('cm-term', classes: 2, (p, e) => p.weight = e.t.len('glacier-font-weight-semibold')),
  // '.cm-line.cm-definition': { paddingInlineStart: '1.2em' }
  LookRule('cm-definition', null, classes: 3, box: (p, e) => p.paddingStart = p.em(1.2)),
  // '.cm-maths': { fontFamily: 'var(--glacier-font-mono)', fontSize: '0.92em',
  //   color: 'var(--app-ink-2, var(--glacier-text))' }
  LookRule('cm-maths', classes: 2, (p, e) {
    p
      ..families = e.monoFamilies
      ..sizeEm(0.92)
      ..color = e.t.color('app-ink-2');
  }),
]);

class _Extended extends PluginValue {
  _Extended(EditorViewLike view) {
    _build(view);
  }

  late DecorationSet decorations;

  /// What the marks were last made for, beside the document and the screen: the lines the caret is on while the
  /// view is typed in, and the parse. A caret that moves along its line changes none of it.
  List<int> _carets = const <int>[];
  Object? _tree;

  static List<int> _caretLines(EditorViewLike view) {
    final state = view.state;
    if (!(view.hasFocus && state.facet(EditorViewLike.editable))) return const <int>[];
    return <int>[for (final range in state.selection.ranges) state.doc.lineAt(range.head).number];
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void update(ViewUpdate update) {
    if (update.docChanged || update.viewportChanged || update.focusChanged) {
      _build(update.view);
    } else if (update.selectionSet) {
      // The same lines under the caret, over the same parse: the same marks, and the set that is there is kept.
      if (!_same(_caretLines(update.view), _carets) || !identical(syntaxTree(update.state), _tree)) _build(update.view);
    }
  }

  void _build(EditorViewLike view) {
    final viewport = view.viewport;
    _carets = _caretLines(view);
    _tree = syntaxTree(view.state);
    decorations = _decorate(view.state, viewport.from, viewport.to, view.hasFocus && view.state.facet(EditorViewLike.editable));
  }
}

final ViewPlugin<_Extended> _extended = ViewPlugin.define<_Extended>(_Extended.new, decorations: (value) => value.decorations);
final Extension _themed = baseTheme(_theme);
final Extension _focusTold = EditorViewLike.focusChangeEffect.of((state, focusing) => _focusEffect.of(focusing));

/// The extended markdown drawn as what it is: raised and lowered runs, callouts, definitions, front matter, maths
/// and shortcodes.
Extension extendedMarkdown() => Extension.list(<Extension>[_frontFold, _focusTold, _extended, _themed]);
