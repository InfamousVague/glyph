/// The press-and-hold menu's Style page (context_band.dart), not a bar of its own: a port of
/// `src/app/editor/StyleItems.tsx`, with `.style`'s rules from `ContextMenu.module.css`.
///
/// Matt, of the bar of symbols under the top bar: "redo the UI/UX for selecting text styles, it doesn't look good
/// as is, maybe it needs to be something we do by pressing and holding on text". Style turns the menu over to the
/// formatting, in the same hand: the marks that wrap the selection (bold, italic, struck, code, and any a
/// switched-on plugin adds, like Spoiler), the forms a line takes (heading, quote, list, numbered, to-do), and the
/// things put in (link, table, rule), all in one band that scrolls sideways, a little space between the three
/// kinds.
///
/// A pressed style stays on the page, lit while it applies, so a word can be made bold and struck in one go: what
/// is lit is read from the editor's state on every draw, and a press asks for the next one. An insert closes the
/// menu, since it puts something in and there is nothing to keep lit. The arrow goes back. The commands are
/// commands/format.dart.
///
/// Every row has a hint in plain words, one line on what it does to the words ("Someone else's words" under Quote):
/// said to a screen reader and shown on a desktop while the pointer rests on the row, and in simple mode drawn
/// under the word too (Matt, 2026-10-18, GHST-103: "work on making formatting and stuff easier to understand").
/// In simple mode the plugins' decorative marks (Spoiler, Highlight, Haunt and the rest) stand behind a More row
/// at the page's end, which opens them in place: a first note wants Bold, a heading and a list, not twelve looks.
/// Advanced lists them where they were. Simple mode's Format bar (lib/note/format_bar.dart) presses six of these
/// rows from outside the band, through [formatBarTools]: the same edits, not a copy of them.
///
/// What differs:
/// - the web read the switched-on plugins' formattings from the registry itself; here they are handed in
///   ([StyleItems.formats]), each with the icon it is drawn under, by whoever knows which marks are on
///   (lib/editor/marks);
/// - `StyleItems` answered a fragment of rows; this answers them as a list ([styleItems]) for the band to lay out,
///   and [StyleEntrance] above them is the one clock `styleIn` runs on, each row coming in 22ms after the one
///   before it;
/// - the commands answer a transaction (commands/format.dart) and the row dispatches it.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/lucide.g.dart';
import '../commands/format.dart';
import '../editor.dart';
import '../syntax/language.dart' show InlineFormatSyntax;
import 'menu_band.dart';

/// A plugin's formatting on the Style page: its name, the run that wraps the words, and the icon it is drawn under
/// (`InlineFormat` with `format.icon ?? plugin.icon ?? Type` already chosen).
class BandFormat implements InlineFormatSyntax {
  const BandFormat(this.name, this.delimiter, [this.icon = Lucide.type, this.hint]);

  /// A formatting the parser knows (lib/editor/syntax/language.dart), under [icon], with the plugin's own line on
  /// what it is for as its [hint] (`GlyphFormat.about`).
  BandFormat.of(InlineFormatSyntax format, [this.icon = Lucide.type, this.hint]) : name = format.name, delimiter = format.delimiter;

  @override
  final String name;

  @override
  final String delimiter;

  final MenuIcon icon;

  /// One line in plain words on what the mark does; a plugin that says nothing gets [plainHint].
  final String? hint;

  /// The hint for a plugin's mark that says nothing of itself.
  static const String plainHint = 'A look for the words';
}

/// One of the Style page's styles as something outside the band presses it: simple mode's Format bar
/// (lib/note/format_bar.dart). [lit] is read from the editor's state on every draw, as the page's rows are; [run]
/// answers the page's own transaction, or null where there is nothing to do.
class StyleTool {
  const StyleTool({required this.key, required this.icon, required this.label, required this.hint, required this.lit, required this.run});

  /// The page's own key for the row: `mark:bold`, `block:task`, `insert:link`.
  final String key;
  final MenuIcon icon;
  final String label;
  final String hint;
  final bool Function(EditorState state) lit;
  final Transaction? Function(EditorState state, bool hasFocus) run;
}

/// The six the Format bar carries, in its order: Bold, Italic, Heading, List, To-do, Link. Each is the Style page's
/// row of that name, pressed from outside the band (Matt, 2026-10-18: "A small Format bar in the editor" for simple
/// mode).
List<StyleTool> formatBarTools() => <StyleTool>[
  for (final one in _marks)
    if (one.mark == Mark.bold || one.mark == Mark.italic)
      StyleTool(key: 'mark:${one.mark.name}', icon: one.icon, label: one.label, hint: one.hint, lit: (state) => activeMarks(state).contains(one.mark), run: (state, _) => toggleMark(state, one.mark)),
  for (final one in _blocks)
    if (one.block == Block.heading || one.block == Block.bullet || one.block == Block.task)
      StyleTool(key: 'block:${one.block.name}', icon: one.icon, label: one.label, hint: one.hint, lit: (state) => activeBlock(state) == one.block, run: (state, _) => toggleBlock(state, one.block)),
  for (final one in _inserts)
    if (one.key == 'link') StyleTool(key: 'insert:${one.key}', icon: one.icon, label: one.label, hint: one.hint, lit: (_) => false, run: one.run),
];

// The hints are the plainest words for what each does, not Markdown's names for it.
const List<({Mark mark, MenuIcon icon, String label, String hint})> _marks = <({Mark mark, MenuIcon icon, String label, String hint})>[
  (mark: Mark.bold, icon: Lucide.bold, label: 'Bold', hint: 'Strong words'),
  (mark: Mark.italic, icon: Lucide.italic, label: 'Italic', hint: 'A slant'),
  (mark: Mark.strike, icon: Lucide.strikethrough, label: 'Struck', hint: 'Crossed out'),
  (mark: Mark.code, icon: Lucide.code, label: 'Code', hint: 'Exactly as typed'),
];

final List<({String key, MenuIcon icon, String label, String hint, Transaction Function(EditorState state, bool hasFocus) run})> _inserts =
    <({String key, MenuIcon icon, String label, String hint, Transaction Function(EditorState state, bool hasFocus) run})>[
      (key: 'link', icon: Lucide.link, label: 'Link', hint: 'To a page or a note', run: (state, _) => insertLink(state)),
      (key: 'table', icon: Lucide.table, label: 'Table', hint: 'Rows and columns', run: (state, hasFocus) => insertTable(state, hasFocus: hasFocus)),
      (key: 'rule', icon: Lucide.minus, label: 'Rule', hint: 'A line across the page', run: (state, hasFocus) => insertRule(state, hasFocus: hasFocus)),
    ];

const List<({Block block, MenuIcon icon, String label, String hint})> _blocks = <({Block block, MenuIcon icon, String label, String hint})>[
  (block: Block.heading, icon: Lucide.heading, label: 'Heading', hint: 'A title for a section'),
  (block: Block.quote, icon: Lucide.textQuote, label: 'Quote', hint: "Someone else's words"),
  (block: Block.bullet, icon: Lucide.list, label: 'List', hint: 'Bullets'),
  (block: Block.number, icon: Lucide.listOrdered, label: 'Numbered', hint: 'Steps in order'),
  (block: Block.task, icon: Lucide.listTodo, label: 'To-do', hint: 'A box to tick'),
];

/// The Back row's accessible name, on this page and on a field's.
const String backName = "Back to the note's actions";

/// Simple mode's More row at the end of the Style page: the word, and what it says it holds.
const String moreStylesLabel = 'More', moreStylesHint = 'Spoiler, Highlight and other looks';

/// The Style page's words, for the menu's band: Back, then the marks, the plugins' formats, the line forms, the
/// inserts (`StyleItems`). [restyled] is told after a style is pressed, for the page to read the editor again;
/// [felt] says each row's own tick.
///
/// [simple] draws each row's hint under its word, and keeps the plugins' [formats] behind a More row at the end
/// until [moreShown]; [onMore] is More pressed. Advanced lists the formats after the marks, as the page did.
List<Widget> styleItems({
  required EditorViewLike view,
  required VoidCallback onBack,
  required VoidCallback onClose,
  required VoidCallback restyled,
  required void Function(HapticKind kind) felt,
  List<BandFormat> formats = const <BandFormat>[],
  bool simple = false,
  bool moreShown = false,
  VoidCallback? onMore,
}) {
  VoidCallback style(Transaction? Function(EditorState state) run) => () {
    felt(HapticKind.selection);
    final tr = run(view.state);
    if (tr != null) view.dispatch(tr);
    restyled();
  };
  VoidCallback put(Transaction Function(EditorState state, bool hasFocus) run) => () {
    felt(HapticKind.selection);
    onClose();
    view.dispatch(run(view.state, view.hasFocus));
    view.focus();
  };
  final state = view.state;
  final lit = activeMarks(state);
  final block = activeBlock(state);
  // Where the plugins' marks stand: after Markdown's own in advanced; in simple, behind More at the end, and in
  // its place once it is pressed. They come in on the clock in the order they are laid out.
  final behindMore = simple && formats.isNotEmpty;
  final formatRows = <Widget>[
    for (final (i, format) in formats.indexed)
      StyleItem(
        key: ValueKey<String>('format:${format.name}'),
        icon: format.icon,
        label: format.name,
        hint: format.hint ?? BandFormat.plainHint,
        hintShown: simple,
        i: (behindMore ? _marks.length + _blocks.length + _inserts.length : _marks.length) + i,
        // One breath before the first of them, where they are a kind of their own at the end.
        group: behindMore && i == 0,
        lit: activeWraps(state, <String>[format.delimiter]).isNotEmpty,
        onClick: style((s) => toggleWrap(s, format.delimiter)),
      ),
  ];
  final between = behindMore ? 0 : formats.length;
  return <Widget>[
    MenuItem(key: const ValueKey<String>('back'), icon: Lucide.chevronLeft, label: 'Back', onPress: onBack, name: backName),
    for (final (i, one) in _marks.indexed)
      StyleItem(
        key: ValueKey<String>('mark:${one.mark.name}'),
        icon: one.icon,
        label: one.label,
        hint: one.hint,
        hintShown: simple,
        i: i,
        lit: lit.contains(one.mark),
        onClick: style((s) => toggleMark(s, one.mark)),
      ),
    if (!behindMore) ...formatRows,
    for (final (i, one) in _blocks.indexed)
      StyleItem(
        key: ValueKey<String>('block:${one.block.name}'),
        icon: one.icon,
        label: one.label,
        hint: one.hint,
        hintShown: simple,
        i: _marks.length + between + i,
        group: i == 0,
        lit: block == one.block,
        onClick: style((s) => toggleBlock(s, one.block)),
      ),
    for (final (i, one) in _inserts.indexed)
      StyleItem(
        key: ValueKey<String>('insert:${one.key}'),
        icon: one.icon,
        label: one.label,
        hint: one.hint,
        hintShown: simple,
        i: _marks.length + between + _blocks.length + i,
        group: i == 0,
        onClick: put(one.run),
      ),
    if (behindMore && !moreShown)
      StyleItem(
        key: const ValueKey<String>('more-styles'),
        icon: Lucide.ellipsis,
        label: moreStylesLabel,
        hint: moreStylesHint,
        hintShown: true,
        i: _marks.length + _blocks.length + _inserts.length,
        group: true,
        checkbox: false,
        onClick: () {
          felt(HapticKind.selection);
          onMore?.call();
        },
      ),
    if (behindMore && moreShown) ...formatRows,
  ];
}

/// The clock the styles come in on (`styleIn`: 260ms, each row 22ms after the one before). One stands over a
/// Style page for as long as it is up; a row asks it how far in it is. With reduced motion there is none, and
/// every row is simply there.
class StyleEntrance extends StatefulWidget {
  const StyleEntrance({super.key, required this.child});

  final Widget child;

  /// `styleIn`'s length and the step between two rows, in milliseconds.
  static const int ms = 260, stepMs = 22;

  /// How far in row [i] is, 0 to 1, eased; 1 where no entrance stands above.
  static double of(BuildContext context, int i) {
    final scope = context.dependOnInheritedWidgetOfExactType<_EntranceScope>();
    if (scope == null) return 1;
    final at = (scope.elapsedMs - i * stepMs) / ms;
    return scope.curve.transform(at.clamp(0.0, 1.0));
  }

  @override
  State<StyleEntrance> createState() => _StyleEntranceState();
}

class _StyleEntranceState extends State<StyleEntrance> with SingleTickerProviderStateMixin {
  /// Long enough for the last of a long page's rows: a ticker's count of milliseconds, not a fraction.
  static const int _lengthMs = 4000;
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(milliseconds: _lengthMs));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.tokens.reducedMotion) {
      _clock.value = 1;
    } else {
      _clock.forward();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = context.tokens.curve('glacier-ease-out');
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => _EntranceScope(elapsedMs: _clock.value * _lengthMs, curve: curve, child: widget.child),
    );
  }
}

class _EntranceScope extends InheritedWidget {
  const _EntranceScope({required this.elapsedMs, required this.curve, required super.child});

  final double elapsedMs;
  final Curve curve;

  @override
  bool updateShouldNotify(_EntranceScope oldWidget) => oldWidget.elapsedMs != elapsedMs || oldWidget.curve != curve;
}

/// A style: its icon over its word, lit (printed in reverse) while it applies, coming in out of smoke after the
/// ones before it (`StyleItem`). [hint] is its line in plain words, drawn under the word with [hintShown]
/// (menu_band.dart `BandItemBox`).
class StyleItem extends StatelessWidget {
  const StyleItem({
    super.key,
    required this.icon,
    required this.label,
    required this.i,
    this.lit = false,
    this.group = false,
    this.hint,
    this.hintShown = false,
    this.checkbox = true,
    required this.onClick,
  });

  final MenuIcon icon;
  final String label;

  /// Its place along the band (`--i`), which says how long after the first it comes in.
  final int i;
  final bool lit;
  final bool group;
  final String? hint;
  final bool hintShown;

  /// A style is a checkbox, lit while it applies; More, which opens rows, is a plain item.
  final bool checkbox;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final box = BandItemBox(icon: icon, label: label, onPress: onClick, lit: lit, group: group, checkbox: checkbox, hint: hint, hintShown: hintShown);
    final at = StyleEntrance.of(context, i);
    if (at >= 1) return box;
    // `from { opacity: 0; filter: blur(6px); transform: translateY(4px) }`.
    final blur = 6 * (1 - at);
    return Opacity(
      opacity: at,
      child: Transform.translate(
        offset: Offset(0, 4 * (1 - at)),
        child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal), child: box),
      ),
    );
  }
}
