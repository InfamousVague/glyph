/// Links, shortened: `notion.so/att…b3c` in place of the whole address. Ports `src/app/editor/links.ts`.
///
/// Matt: "For formatted links in the app don't show the full link path just show the first 3 chars after the tld
/// then a ... and the last 3 chars". A Notion task's address is a hundred characters of slug and id, and set in the
/// note's own type it pushed every other word off the line.
///
/// The first thing the editor shows in place of what is written, so it is kept to the one case and it steps aside
/// whenever the address might be edited: on the line the caret is on, the address is written out in full, exactly
/// as it is stored. Everywhere else a link's address, in `[words](address)` or said bare, shows as its host, three
/// characters, an ellipsis and three characters. Nothing about the text changes, and a read-only view (the
/// Formatted note) shows every link short.
///
/// The item mark is the other case (lib/core/item_links.dart): a list item that ends with `[notion](address)` is
/// linked to a Notion task, and the whole mark is drawn as one small solid pill with the name on it. On the
/// caret's line it, too, is written out in full. Where the mark's plugin reads what it links to ([markRead]), the
/// mark itself steps aside: the item's row of pills under it says what it is linked to.
///
/// What differs:
/// - The theme's two inline boxes are drawn by the widgets themselves, each rule of `shortLinksTheme` cited where
///   it is drawn; an inline widget is not a run of the line's text for a [LookSheet] to dress.
///   `white-space: nowrap` is what an inline widget is; `user-select: none` and the `title` (the whole address on
///   a long press) have no counterpart.
/// - `hasMarkDetails(name)` (lib/plugins/mark_details.dart) is asked as on the page; the facet [markRead] is kept
///   beside it for a caller that knows of a reader the plugins' registry does not.
/// - `coveringLooks` and `underCover` are editor/formatLooks.ts's, which is the marks' piece
///   (lib/editor/marks): until that names its covering nodes for this file, [coveringLooks] here is the facet they
///   are told through, and it is the one this file reads.
/// - `markReads({still})` (items/mark_reads.dart: the reads that keep the rows under linked lines current) comes
///   with [shortLinks], as on the page, and the marks are drawn again on its `detailsArrived`.
/// - ADDED: a tap on a link opens it ([linkTapOpener], given by `shortLinks(onOpen:)`). On the page a tap on a link
///   in the words never opens it (it lands the caret); only a card's tap does, and a card is drawn only under a line
///   that is nothing but a link. So a link among words could not be opened at all, in a note or in a table (Matt,
///   2026-10-29: "I can't open links in ghost markdown on the deep link test spot", a note of links to tap on a
///   phone so they open their app; and "Clicking links still opens the link for editing instead of opening the
///   link"). Now a plain tap or click on a link's words or its address opens it, as a `[[link]]` opens its note,
///   on the phone and the Mac alike, except where that link is being written: with the caret (or the selection)
///   already inside it, or at its edge, in a note that has the keyboard, a tap there is the caret's, unless the
///   press holds Cmd on a Mac (Ctrl elsewhere), which opens it wherever it is. A link is edited by getting the
///   caret into it some other way: a tap just after it, the arrow keys, a press held (which takes the word under
///   it) or the other button (which puts the caret there and opens the note's menu). An item's mark is not a link
///   here (a tap on its pill lands the caret, which writes it out), and an address no app may be handed
///   (lib/core/open_link.dart `canOpenLink`: a relative path, an `#anchor`) is left to the caret too. A drawn
///   table's links open the same way (tables/table_box.dart).
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/item_links.dart';
import '../../core/item_syntax.dart' show afterMark;
import '../../core/open_link.dart' show canOpenLink;
import '../../core/short_url.dart';
import '../../core/text.dart';
import '../../plugins/mark_details.dart' show hasMarkDetails;
import '../editor.dart';
import '../items/mark_reads.dart';
import '../looks/look.dart';
import '../semantics/line_semantics.dart' show linksOn;
import '../syntax/tree.dart' show SyntaxNode;
import '../view/editor_view.dart' show EditorView;
import '../view/line.dart' show EditorRunScope;
import '../view/lines.dart';
import '../view/syntax_tree.dart';
import 'inline_box.dart';

/// Whether a mark's plugin reads what it links to, by the mark's name (`hasMarkDetails`): the mark is then drawn
/// by the row under its line, and hidden here.
final Facet<bool Function(String name), List<bool Function(String name)>> markRead = Facet.define();

/// The names of the nodes whose look hides its words (a redaction): what sits under one is not drawn, by anything
/// (editor/formatLooks.ts `coveringLooks`).
final Facet<String, List<String>> coveringLooks = Facet.define();

/// Whether `node` sits inside a node whose look hides its words.
bool underCover(SyntaxNode node, List<String> covering) {
  if (covering.isEmpty) return false;
  for (var above = node.parent; above != null; above = above.parent) {
    if (covering.contains(above.name)) return true;
  }
  return false;
}

/// The look of the words round an inline widget: the run it stands in, or the page's body where it is drawn
/// outside a line.
({TextStyle style, double size, Color ink}) _around(BuildContext context) {
  final scope = EditorRunScope.maybeOf(context);
  if (scope != null) return (style: scope.look.style, size: scope.look.fontSize, ink: scope.look.color);
  final t = context.tokens;
  final size = t.len('app-body');
  return (style: t.textAt(size, mono: true, color: t.color('app-ink')), size: size, ink: t.color('app-ink'));
}

/// The mark as one pill with its name on it, for a mark whose plugin is off or reads nothing: where one reads it,
/// the row under the line carries the mark instead ([HiddenMark]).
class ItemMarkWidget extends EditorWidget {
  const ItemMarkWidget(this.name, this.url);

  final String name;
  final String url;

  @override
  bool eq(ItemMarkWidget other) => other.name == name && other.url == url;

  /// A tap lands the caret here, which writes the mark out in full for editing.
  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final around = _around(context);
    // '.cm-itemMark': { display: 'inline-block', textIndent: '0', marginInlineStart: '0.6em', padding: '0 0.6em',
    //   borderRadius: '999px', background: 'var(--app-ink, currentColor)', color: 'var(--app-paper, #fff)',
    //   fontSize: '0.68em', lineHeight: '1.7', verticalAlign: '0.15em', whiteSpace: 'nowrap', userSelect: 'none' }
    final size = around.size * 0.68;
    final style = around.style.copyWith(fontSize: size, color: t.color('app-paper'), decoration: TextDecoration.none);
    return Semantics(
      label: capitalise(name),
      child: InlineRaise(
        by: size * 0.15,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: layoutUnit(size * 0.6)),
          child: DecoratedBox(
            key: const ValueKey<String>('cm-itemMark'),
            decoration: ShapeDecoration(color: t.color('app-ink'), shape: const StadiumBorder()),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: layoutUnit(size * 0.6)),
              // '.cm-itemMark-name': { opacity: '0.72' }
              child: InlineWords(capitalise(name), key: const ValueKey<String>('cm-itemMark-name'), style: style, lineHeight: size * 1.7, opacity: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the row under the item carries the mark, the mark itself draws nothing.
class HiddenMark extends EditorWidget {
  const HiddenMark();

  @override
  bool eq(HiddenMark other) => true;

  @override
  bool takesPointer(_) => false;

  @override
  bool get isHidden => true;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink(key: ValueKey<String>('cm-itemMarkHidden'));
}

/// An address, short.
class ShortLinkWidget extends EditorWidget {
  const ShortLinkWidget(this.url);

  final String url;

  @override
  bool eq(ShortLinkWidget other) => other.url == url;

  /// A tap lands the caret here, which writes the address out in full for editing.
  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final around = _around(context);
    // '.cm-shortLink': { color: 'var(--glacier-text-muted)', textDecoration: 'none', whiteSpace: 'nowrap' }
    final style = around.style.copyWith(color: context.tokens.color('glacier-text-muted'), decoration: TextDecoration.none);
    return InlineWords(shortUrl(url), key: const ValueKey<String>('cm-shortLink'), style: style);
  }
}

/// Whether what follows a link is nothing, or only a board's anchor (core/boards.ts): the link is then the item's
/// mark.
bool _lastOnLine(String after) => afterMark.hasMatch(after);

/// The item's mark the link at `from`-`to` is, if it is one: the last thing on an item's line, its words one name.
({String name, String url})? _itemMark(EditorState state, int from, int to) {
  final text = state.sliceDoc(from, to);
  final mark = markOf(text);
  if (mark == null || text != '[${mark.name}](${mark.url})') return null;
  final line = state.doc.lineAt(from);
  return _lastOnLine(line.text.substring(to - line.from)) && itemWords(line.text) != null ? (name: mark.name, url: mark.url) : null;
}

DecorationSet _decorate(EditorViewLike view) {
  final builder = RangeSetBuilder<Decoration>();
  final state = view.state;
  final editable = state.facet(EditorViewLike.editable);
  // The lines the selection touches show their links whole, while the note is being written.
  final active = editable && view.hasFocus ? selectedLines(state) : const <int>{};
  final covering = state.facet(coveringLooks);
  final reads = state.facet(markRead);
  for (final range in view.visibleRanges) {
    syntaxTree(state).iterate(
      from: range.from,
      to: range.to,
      enter: (node) {
        if (node.name == 'Link') {
          // A mark: the link is the last thing on an item's line and its words are one name.
          final mark = _itemMark(state, node.from, node.to);
          if (mark != null) {
            if (!active.contains(state.doc.lineAt(node.from).number)) {
              final EditorWidget widget = hasMarkDetails(mark.name) || reads.any((read) => read(mark.name)) ? const HiddenMark() : ItemMarkWidget(mark.name, mark.url);
              builder.add(node.from, node.to, Decoration.replace(widget: widget));
            }
            return false;
          }
          return null;
        }
        if (node.name != 'URL') return null;
        // Under a look that hides its words (a redaction's bar) the address stays as it is, under the bar: a
        // widget is not text for the bar to cover, and drew the short address beside it.
        if (underCover(node, covering)) return null;
        final url = state.sliceDoc(node.from, node.to);
        if (shortUrl(url).length >= url.length - 1) return null;
        if (active.contains(state.doc.lineAt(node.from).number)) return null;
        builder.add(node.from, node.to, Decoration.replace(widget: ShortLinkWidget(url)));
        return null;
      },
    );
  }
  return builder.finish();
}

/// Addresses shown short and marks as pills, drawn again whenever what they show may have moved.
class _ShortLinks extends PluginValue {
  _ShortLinks(EditorViewLike view) : decorations = _decorate(view), _active = ActiveLines(view);

  DecorationSet decorations;

  /// The lines the selection was on when the links were last drawn: what a selection changes of them.
  final ActiveLines _active;

  @override
  void update(ViewUpdate update) {
    // While an IME composes, the line must not be replaced (glyph_lines.dart).
    if (update.view.composing) {
      if (update.docChanged) decorations = decorations.map(update.changes);
      return;
    }
    // Details arrived from a plugin (items/mark_reads.dart): a mark it reads steps aside for its row.
    final arrived = update.transactions.any((tr) => tr.effects.any((effect) => effect.isOf(detailsArrived)));
    // A selection that stays on its lines shows the same links whole: nothing is walked for it.
    if (arrived || update.docChanged || update.viewportChanged || (update.selectionSet && _active.differ(update.view)) || update.focusChanged || !identical(syntaxTree(update.startState), syntaxTree(update.state))) {
      _active.take(update.view);
      decorations = _decorate(update.view);
    }
  }
}

final ViewPlugin<_ShortLinks> _shortLinksPlugin = ViewPlugin.define<_ShortLinks>(_ShortLinks.new, decorations: (plugin) => plugin.decorations, eventHandlers: const EditorEventHandlers(mouseDown: _pressLink));

/// How a tapped link's address is opened in this editor: the app's own way of handing an address to the phone
/// (lib/core/open_link.dart `openLink`, given by the note's desk through `shortLinks(onOpen:)`). Absent, a tap on
/// a link is the caret's, as on the page. A drawn table's links are opened by it too.
final Facet<void Function(String url), void Function(String url)?> linkTapOpener = Facet.define<void Function(String url), void Function(String url)?>(
  combine: (values) => values.isEmpty ? null : values.first,
);

/// How far outside a link's words a press still lands on it, in px.
const double _slop = 3;

/// Whether the press asks for a link to be opened even where it is being written: Cmd on a Mac or an iPad's
/// keyboard, Ctrl elsewhere, as in a browser's editor.
bool opensAnyway() {
  final keys = HardwareKeyboard.instance;
  final apple = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
  return apple ? keys.isMetaPressed : keys.isControlPressed;
}

/// Whether a press with these keys held may open a link at all: Shift extends the selection and Alt is the
/// keyboard's own, and on a Mac Ctrl with a press is the other button's.
bool _pressOpens() {
  final keys = HardwareKeyboard.instance;
  if (keys.isShiftPressed || keys.isAltPressed) return false;
  final apple = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
  return !(apple && keys.isControlPressed);
}

/// The link a press at `global` lands on: its words or its address (`[words](address)`, an address said bare, an
/// `<address>`), on a line of the note's text and not a block drawn over its lines.
({int from, int to, String url})? linkUnder(EditorViewLike view, Offset global) {
  final pos = view.posAtCoords(global);
  if (pos == null) return null;
  final state = view.state;
  final line = state.doc.lineAt(pos);
  for (final link in linksOn(state, line.from, line.to)) {
    if (pos < link.from || pos > link.to) continue;
    if (!_landsOn(view, global, link.from, link.to)) continue;
    return (from: link.from, to: link.to, url: link.url);
  }
  return null;
}

/// Whether `global` is on the drawn words of `from`-`to` (a link wrapped over two rows is on both), not only
/// nearest to them: past a line's end the nearest position is the line's last, which may be a link's.
bool _landsOn(EditorViewLike view, Offset global, int from, int to) {
  if (view is! EditorView) return true;
  final hit = view.hitAt(global);
  final line = hit?.line;
  if (hit == null || !hit.inside || line == null) return false;
  final local = line.globalToLocal(global);
  return line.rectsForRange(from - line.from, to - line.from).any((rect) => rect.inflate(_slop).contains(local));
}

/// Whether the link at `from`-`to` is being written: the caret or the selection in it or at its edge, in a note
/// that has the keyboard. Elsewhere on its line (where it is shown whole) it is only being read.
bool _writing(EditorViewLike view, int from, int to) {
  final state = view.state;
  return state.facet(EditorViewLike.editable) && view.hasFocus && state.selection.ranges.any((range) => range.from <= to && range.to >= from);
}

/// A press on a link opens it, before the caret moves (see the header). Asked when a browser would send its
/// `mousedown`: a mouse's as it lands, a finger's once its tap is done, so a finger that scrolls opens nothing.
bool _pressLink(PointerDownEvent event, EditorViewLike view) {
  final open = view.state.facet(linkTapOpener);
  if (open == null) return false;
  if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryButton) return false;
  if (!_pressOpens()) return false;
  final link = linkUnder(view, event.position);
  if (link == null || !canOpenLink(link.url) || _itemMark(view.state, link.from, link.to) != null) return false;
  if (_writing(view, link.from, link.to) && !opensAnyway()) return false;
  open(link.url);
  return true;
}

/// Link addresses shown short, and item marks as pills, away from the caret's line. With them come the reads that
/// keep the rows under linked lines current (items/mark_reads.dart), which `still` stops: a note drawn small on a
/// card is drawn from what is already known. `onOpen` is how a tapped link is opened ([linkTapOpener]); without
/// it a tap on a link is the caret's.
Extension shortLinks({bool still = false, void Function(String url)? onOpen}) => Extension.list(<Extension>[
  _shortLinksPlugin,
  markReads(still: still),
  if (onOpen != null) linkTapOpener.of(onOpen),
]);
