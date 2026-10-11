/// What a note's links are linked to, shown under them, and the drawer a tap on one opens. Ports
/// `src/app/editor/linkedRows.ts`.
///
/// Matt, on the first version's single pill: "Not all notion links are being auto formatted to have the full pill
/// showing details, I also think the notion integration might need multiple pills to represent data so let's think
/// about reworking how we show the notion data in lists". And on tapping it: "show a few options like opening the
/// ticket in notion or un linking or updating etc."
///
/// - **Every linked line gets a row.** A list item ending in a mark (`[notion](…)`, lib/core/item_links.dart), and
///   any line with an ordinary link a plugin reads (the old `[Buy milk](https://www.notion.so/…)` items, a task
///   pasted into a sentence), has a row of small pills under it, hung at the item's own indent: the service's name,
///   solid; then the stage and status; then a pill for each fact (priority, due). The mark at the end of the line
///   draws nothing while the row carries it (links.dart). A plugin that is off draws no row, and its mark is the
///   old pill again.
/// - **A tap on the row opens a drawer** from the bottom over the dimmed note (items/mark_menu.dart). A tap on the
///   dimmed note or the back gesture closes it again.
///
/// Block widgets can only come from state, so the rows are a StateField over the whole document, recomputed when
/// it changes, when details arrive (items/mark_reads.dart dispatches `detailsArrived`), and when a menu opens or
/// closes. The drawer follows which line's menu is open. Notes are short; a line without `](` is skipped at once.
///
/// What differs:
/// - The drawer is not a root of its own mounted in the page's body (`markMenuMount.tsx`): the row whose menu is
///   open builds it, and the app's sheet draws itself in the overlay wherever it is built (lib/sheet/sheet.dart).
///   What mounts it can be given ([linkedRows] `mount`), which is how a test sees what a drawer was opened with.
/// - `rowsTheme` is drawn by the row's own widgets, each rule cited where it is drawn. `title` (the task's name on
///   a hover) is the row's tooltip for a screen reader; `cursor`, `user-select` and the tap highlight have no
///   counterpart. `.cm-itemMarkHidden` is links.dart's `HiddenMark`.
/// - The row's hang is read from the line above it as it is laid out, where the page read `--hang` off the line's
///   element a frame later; a row is drawn again when its line moves, so that it reads the right one.
/// - A pill is told from the rest of the row by a hit test for it, where the page asked the event's target.
library;

import 'dart:async';

import 'package:flutter/rendering.dart' hide Decoration;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/item_links.dart';
import '../../core/item_syntax.dart' show itemTailPattern, jsTrim, markNamePattern, markUrlPattern;
import '../../core/text.dart';
import '../../plugins/mark_details.dart';
import '../editor.dart';
import '../items/mark_menu.dart';
import '../items/mark_reads.dart';
import '../looks/look.dart';
import '../view/editor_view.dart';
import '../view/line_facts.dart';
import 'images.dart' show gutterOf;
import 'inline_box.dart';

/// Whether a mark is the item's own, or a link in the words a plugin reads.
enum LinkedKind { mark, link }

/// The linked thing on a line (`Linked`).
@immutable
class Linked {
  const Linked({required this.from, required this.name, required this.url, required this.words, required this.kind, required this.item});

  /// Where the line starts, when the row was drawn.
  final int from;
  final String name;
  final String url;

  /// The line's words without the link's address: an item's words, or the link's own words in a sentence.
  final String words;
  final LinkedKind kind;
  final bool item;

  @override
  bool operator ==(Object other) => other is Linked && other.from == from && other.name == name && other.url == url && other.words == words && other.kind == kind && other.item == item;

  @override
  int get hashCode => Object.hash(from, name, url, words, kind, item);

  @override
  String toString() => 'Linked($from, $name, $url, "$words", ${kind.name}, item: $item)';
}

/// The linked thing on a line, if there is one: an item's mark first, else the first link a plugin reads.
Linked? linkedOn(String text, [int from = 0]) {
  if (!text.contains('](')) return null;
  final words = itemWords(text);
  final mark = words != null ? markOf(text) : null;
  if (mark != null && hasMarkDetails(mark.name)) return Linked(from: from, name: mark.name, url: mark.url, words: words ?? '', kind: LinkedKind.mark, item: true);
  for (final match in linkPattern.allMatches(text)) {
    final url = match.group(2) ?? '';
    final name = markNameFor(url);
    if (name == null) continue;
    final said = words != null ? jsTrim(words.replaceAllMapped(linkPattern, (m) => m.group(1) ?? '')) : jsTrim(match.group(1) ?? '');
    return Linked(from: from, name: name, url: url, words: said, kind: LinkedKind.link, item: words != null);
  }
  return null;
}

/// Whether a plugin reads the link at `url` on the line `text`: what link_cards.dart is told, so such a line has
/// its row and no card (`linkedOn(text) || markNameFor(url)` in editor/linkCards.ts).
bool pluginReadsLink(String text, String url) => linkedOn(text) != null || markNameFor(url) != null;

/// An item's mark, and after it a board's anchor or counters, which stay when the mark goes.
final RegExp _markThenTail = RegExp('\\s*\\[$markNamePattern\\]\\(($markUrlPattern)\\)((?:\\s+(?:$itemTailPattern))*)\\s*\$');

/// The line with its link taken off and its words kept.
String unlinked(String text, {required LinkedKind kind, required String url}) {
  if (kind == LinkedKind.mark) return text.replaceFirstMapped(_markThenTail, (m) => m.group(2) ?? '');
  return text.replaceFirstMapped(RegExp('\\[([^\\]]*)\\]\\(${escapeRegExp(url)}\\)'), (m) => m.group(1) ?? '');
}

/// Whether rows open menus here, and what they say with (`LinkMenus`).
class LinkMenus {
  const LinkMenus({required this.say});

  /// A sentence on the note for a few seconds: what a menu action did, or why it couldn't.
  final void Function(String message) say;
}

/// Puts a drawer up for `props`; answers how to take it down (`mountMarkMenu`).
typedef MarkMenuMount = VoidCallback Function(MarkMenuProps props);

class _Told {
  const _Told(this.menus, this.mount);
  final LinkMenus? menus;
  final MarkMenuMount? mount;
}

/// Whether rows open menus here. Absent (a read-only view): rows only.
final Facet<_Told, _Told> _menusFacet = Facet.define<_Told, _Told>(
  combine: (values) => values.firstWhere((told) => told.menus != null, orElse: () => const _Told(null, null)),
  compare: (a, b) => identical(a.menus, b.menus) && identical(a.mount, b.mount),
);

/// Opens the menu under the line starting at `from`, or closes it with null.
final StateEffectType<int?> _toggleMenu = StateEffect.define<int?>();

final StateField<int?> _openMenu = StateField.define<int?>(
  create: (_) => null,
  update: (value, tr) {
    var next = value != null && tr.docChanged ? tr.changes.mapPos(value, -1) : value;
    for (final effect in tr.effects) {
      if (effect.isOf(_toggleMenu)) next = effect.value as int?;
    }
    return next;
  },
);

/// Where the open menu's line starts, or null: for whoever asks whether a drawer is up.
int? openLinkMenu(EditorState state) => state.fieldOrNull<int?>(_openMenu);

const Map<Stage, String> _stageWords = <Stage, String>{Stage.todo: 'To do', Stage.doing: 'In progress', Stage.done: 'Done'};

/// What the row shows for an entry, as one string, so the row is redrawn only when that changes. The title is in
/// it: it is what a screen reader says, and a task renamed in its service kept its old name there.
String _faceOf(MarkEntry? entry) => switch (entry) {
  null => '',
  MarkLoading() => 'loading',
  MarkFailed() => 'failed',
  MarkReady(:final details) => <String?>[details.status?.stage.name, details.status?.label, details.brief.join('·'), details.gone ? 'gone' : '', details.title].map((part) => part ?? '').join('|'),
};

/// Which of the row's pills one is (`cm-linkPill-name`, `-status`, `-fact`, `-quiet`).
enum LinkPillKind { name, status, fact, quiet }

/// What marks a pill for a hit test: a press on one is the row's, a press on the rest of the row the note's.
const Object _pillTag = 'cm-linkPill';

/// The row under a linked line.
class LinkRowWidget extends EditorWidget {
  LinkRowWidget(this.linked, this.entry, {required this.open, required this.menus}) : face = _faceOf(entry);

  final Linked linked;
  final MarkEntry? entry;
  final bool open;
  final bool menus;
  final String face;

  @override
  bool eq(LinkRowWidget other) =>
      other.linked.url == linked.url && other.linked.item == linked.item && other.linked.from == linked.from && other.face == face && other.open == open && other.menus == menus;

  @override
  double get estimatedHeight => 24;

  /// Events on a pill are the row's; on the empty rest of the row, the editor's, so a tap there places the caret.
  @override
  bool takesPointer(PointerEvent event) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    return result.path.any((entry) => entry.target is RenderMetaData && (entry.target as RenderMetaData).metaData == _pillTag);
  }

  @override
  Widget build(BuildContext context) => LinkRow(this);
}

/// One pill of a row, as it is drawn.
class LinkPill extends StatelessWidget {
  const LinkPill(this.text, this.kind, {super.key, this.stage, this.late = false, this.gone = false, this.open = false, this.tip, required this.size, required this.face, required this.ink});

  final String text;
  final LinkPillKind kind;

  /// `data-stage` on a status pill.
  final Stage? stage;

  /// `data-late`: an overdue fact.
  final bool late;

  /// `data-gone`: in the service's trash.
  final bool gone;

  /// The row's menu is open: the name wears a ring.
  final bool open;

  /// Why it cannot be read, on the quiet pill (`title`).
  final String? tip;

  /// The row's font size, the face it is in, and the ink round it (`currentColor`).
  final double size;
  final TextStyle face;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final env = view is EditorView ? view.look?.env : null;
    final edge = env?.border(1) ?? 1.0;
    // '.cm-linkPill': { display: 'inline-flex', alignItems: 'center', gap: '0.4em', padding: '0 0.65em',
    //   borderRadius: '999px', border: '1px solid color-mix(in srgb, var(--app-ink, currentColor) 28%, transparent)',
    //   color: 'var(--app-ink-2, var(--glacier-text))', whiteSpace: 'nowrap' }
    var color = t.color('app-ink-2');
    var weight = face.fontWeight;
    Color? ground;
    Color? border = t.colorOf('color-mix(in srgb, var(--app-ink, currentColor) 28%, transparent)', current: ink);
    var pad = size * 0.65;
    switch (kind) {
      case LinkPillKind.name:
        // '.cm-linkPill-name': { background: 'var(--app-ink, currentColor)', borderColor: 'var(--app-ink,
        //   currentColor)', color: 'var(--app-paper, #fff)', fontWeight: '600' }
        ground = t.color('app-ink');
        border = t.color('app-ink');
        color = t.color('app-paper');
        weight = FontWeight.w600;
      case LinkPillKind.status:
        // '.cm-linkPill-status': { color: 'var(--app-ink, var(--glacier-text))', fontWeight: '600' }
        color = t.color('app-ink');
        weight = FontWeight.w600;
      case LinkPillKind.fact:
        // '.cm-linkPill-fact[data-late]': { color: 'var(--app-ink, …)', fontWeight: '700', borderColor: 'var(--app-ink, currentColor)' }
        if (late) {
          color = t.color('app-ink');
          weight = FontWeight.w700;
          border = t.color('app-ink');
        }
      case LinkPillKind.quiet:
        // '.cm-linkPill-quiet': { border: 'none', paddingInline: '0.2em', color: 'var(--app-ink-3, var(--glacier-text-muted))' }
        border = null;
        pad = size * 0.2;
        color = t.color('app-ink-3');
    }
    final style = face.copyWith(
      fontSize: size,
      color: color,
      fontWeight: weight,
      // '.cm-linkPill-status[data-gone]': { textDecoration: 'line-through' }
      decoration: gone ? TextDecoration.lineThrough : TextDecoration.none,
      decorationColor: color,
    );
    final words = InlineWords(text, key: const ValueKey<String>('cm-linkPill-words'), style: style, lineHeight: size * 1.6);
    final inside = stage == null
        ? words
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // '.cm-linkStage': { boxSizing: 'border-box', width: '0.8em', height: '0.8em', borderRadius: '50%',
              //   border: '0.13em solid currentColor' }
              ExcludeSemantics(
                child: CustomPaint(key: const ValueKey<String>('cm-linkStage'), size: Size.square(layoutUnit(size * 0.8)), painter: StagePainter(stage!, color, env?.border(size * 0.13) ?? size * 0.13)),
              ),
              SizedBox(width: layoutUnit(size * 0.4)),
              words,
            ],
          );
    final shape = StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border, width: edge));
    Widget pill = DecoratedBox(
      key: const ValueKey<String>('cm-linkPill'),
      decoration: ShapeDecoration(color: ground, shape: shape),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layoutUnit(pad) + (border == null ? 0 : edge), vertical: border == null ? 0 : edge),
        child: inside,
      ),
    );
    if (open && kind == LinkPillKind.name) {
      // '.cm-linkRow[data-open] .cm-linkPill-name': { boxShadow: '0 0 0 2px var(--app-paper, #fff), 0 0 0 3.5px
      //   var(--app-ink, currentColor)' }
      pill = CustomPaint(painter: _Ring(t.color('app-paper'), t.color('app-ink')), child: pill);
    }
    return MetaData(metaData: _pillTag, behavior: HitTestBehavior.opaque, child: Semantics(tooltip: tip, child: pill));
  }
}

/// A status's dot: a ring to do, half of it filled in progress, all of it done.
class StagePainter extends CustomPainter {
  const StagePainter(this.stage, this.color, this.border);

  final Stage stage;
  final Color color;
  final double border;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final round = Path()..addOval(box);
    // '.cm-linkPill-status[data-stage="done"] .cm-linkStage': { background: 'currentColor' }
    if (stage == Stage.done) {
      canvas.drawPath(round, Paint()..color = color);
      return;
    }
    // '.cm-linkPill-status[data-stage="doing"] .cm-linkStage': { background: 'linear-gradient(90deg, currentColor
    //   50%, transparent 50%)' }
    if (stage == Stage.doing) {
      canvas
        ..save()
        ..clipPath(round)
        ..drawRect(Rect.fromLTRB(0, 0, size.width / 2, size.height), Paint()..color = color)
        ..restore();
    }
    canvas.drawOval(
      box.deflate(border / 2),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = border,
    );
  }

  @override
  bool shouldRepaint(StagePainter old) => old.stage != stage || old.color != color || old.border != border;
}

class _Ring extends CustomPainter {
  const _Ring(this.paper, this.ink);

  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    RRect grown(double by) => RRect.fromRectAndRadius((Offset.zero & size).inflate(by), Radius.circular(size.height / 2 + by));
    canvas
      ..drawRRect(grown(3.5), Paint()..color = ink)
      ..drawRRect(grown(2), Paint()..color = paper);
  }

  @override
  bool shouldRepaint(_Ring old) => old.paper != paper || old.ink != ink;
}

/// A row as it is drawn: its pills, hung under its line.
class LinkRow extends StatelessWidget {
  const LinkRow(this.row, {super.key});

  final LinkRowWidget row;

  /// The row's words, pill by pill: what the page's `.cm-linkPill` elements say.
  static List<({String text, LinkPillKind kind, Stage? stage, bool late, bool gone, String? tip})> pillsOf(Linked linked, MarkEntry? entry) {
    final pills = <({String text, LinkPillKind kind, Stage? stage, bool late, bool gone, String? tip})>[
      (text: capitalise(linked.name), kind: LinkPillKind.name, stage: null, late: false, gone: false, tip: null),
    ];
    switch (entry) {
      case MarkReady(:final details):
        final status = details.status;
        if (details.gone) {
          pills.add((text: 'In trash', kind: LinkPillKind.status, stage: null, late: false, gone: true, tip: null));
        } else if (status != null) {
          pills.add((text: status.label.isNotEmpty ? status.label : _stageWords[status.stage]!, kind: LinkPillKind.status, stage: status.stage, late: false, gone: false, tip: null));
        }
        if (!details.gone) {
          for (final fact in details.brief) {
            pills.add((text: fact, kind: LinkPillKind.fact, stage: null, late: fact.startsWith('Overdue'), gone: false, tip: null));
          }
        }
      case MarkLoading():
        pills.add((text: 'Reading…', kind: LinkPillKind.quiet, stage: null, late: false, gone: false, tip: null));
      case MarkFailed(:final message):
        pills.add((text: 'Can’t read it', kind: LinkPillKind.quiet, stage: null, late: false, gone: false, tip: message));
      case null:
    }
    return pills;
  }

  /// The task's name, where it has been read (`row.title`).
  String get title => switch (row.entry) { MarkReady(:final details) => details.title, _ => '' };

  /// What a screen reader says of a row that opens a menu (`aria-label`).
  String get label => '${row.linked.name}: ${title.isNotEmpty ? title : 'linked'}. ${row.open ? 'Close' : 'Open'} its menu.';

  void _toggle(EditorViewLike view) {
    // The row sits after its line; find the linked line.
    final doc = view.state.doc;
    var line = doc.lineAt(row.linked.from.clamp(0, doc.length));
    if (linkedOn(line.text) == null && line.number > 1) line = doc.line(line.number - 1);
    final opened = view.state.fieldOrNull<int?>(_openMenu);
    final isOpen = opened != null && opened >= line.from && opened <= line.to;
    view.dispatch(TransactionSpec(effects: _toggleMenu.of(isOpen ? null : line.from)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final look = view is EditorView ? view.look : null;
    final base = look?.line(LookElement(null)).base;
    final em = base?.fontSize ?? t.len('app-body');
    final ink = base?.color ?? t.color('app-ink');
    final face = (base?.style ?? t.textAt(em, mono: true)).copyWith(color: ink, decoration: TextDecoration.none);
    // '.cm-linkRow': { display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '0.35em',
    //   paddingInline: 'calc(var(--app-gutter) + var(--row-hang, 0px)) var(--app-gutter)',
    //   paddingBlock: '0.1em 0.4em', fontSize: '0.7em', lineHeight: '1.6' }
    final size = em * 0.7;
    final gutter = gutterOf(context);
    // Hung at the item's own indent: the line before carries it (glyph_lines.dart `--hang`).
    final hang = view is EditorView ? (view.lineAt(row.linked.from)?.spec.look.hang ?? 0.0) : 0.0;
    final gap = layoutUnit(size * 0.35);
    final tap = row.menus && view != null ? () => _toggle(view) : null;
    final pills = <Widget>[
      for (final pill in pillsOf(row.linked, row.entry))
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: LinkPill(pill.text, pill.kind, stage: pill.stage, late: pill.late, gone: pill.gone, open: row.open, tip: pill.tip, size: size, face: face, ink: ink),
        ),
    ];
    Widget drawn = Padding(
      key: const ValueKey<String>('cm-linkRow'),
      padding: EdgeInsets.only(left: gutter + hang, right: gutter, top: layoutUnit(size * 0.1), bottom: layoutUnit(size * 0.4)),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(spacing: gap, runSpacing: gap, crossAxisAlignment: WrapCrossAlignment.center, children: pills),
      ),
    );
    drawn = row.menus
        ? Semantics(container: true, button: true, expanded: row.open, label: label, tooltip: title.isEmpty ? null : title, onTap: tap, child: drawn)
        : Semantics(container: true, tooltip: title.isEmpty ? null : title, child: drawn);
    if (!row.open || view == null) return drawn;
    // The drawer for this line, over the page while its menu is open.
    final drawer = view.plugin(_menuDrawer);
    if (drawer == null) return drawn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        drawn,
        ValueListenableBuilder<MarkMenuProps?>(
          valueListenable: drawer.shown,
          builder: (context, props, _) => props == null ? const SizedBox.shrink() : MarkMenu(key: ValueKey<String>('${props.name}\n${props.url}'), props: props),
        ),
      ],
    );
  }
}

/// The drawer for the line whose menu is open, up while it is, and taken down when it closes.
class _MenuDrawer extends PluginValue {
  _MenuDrawer(this.view) {
    _sync();
  }

  final EditorViewLike view;
  String _key = '';
  VoidCallback? _unmount;
  bool _gone = false;

  /// The drawer the open row draws, where nothing else mounts it.
  final ValueNotifier<MarkMenuProps?> shown = ValueNotifier<MarkMenuProps?>(null);

  @override
  void update(ViewUpdate update) {
    final toggled = update.transactions.any((tr) => tr.effects.any((effect) => effect.isOf(_toggleMenu)));
    if (toggled || update.docChanged || !identical(update.startState.facet(_menusFacet), update.state.facet(_menusFacet))) _sync();
  }

  void _toggleLater(int? to) => scheduleMicrotask(() {
    if (!_gone && (to != null || view.state.fieldOrNull<int?>(_openMenu) != null)) view.dispatch(TransactionSpec(effects: _toggleMenu.of(to)));
  });

  void _sync() {
    final state = view.state;
    final told = state.facet(_menusFacet);
    final menus = told.menus;
    final from = state.fieldOrNull<int?>(_openMenu);
    final line = menus != null && from != null ? state.doc.lineAt(from) : null;
    final linked = line != null ? linkedOn(line.text, line.from) : null;
    final key = linked != null ? <String>[linked.name, linked.url, linked.words, linked.kind.name].join('\n') : '';
    if (key == _key) return;
    _close();
    _key = key;
    if (linked == null || menus == null) {
      // The line lost its link under an open menu: the menu is closed too, once this update is done.
      if (from != null) _toggleLater(null);
      return;
    }
    // The keyboard must not come up under the drawer: a tap on a pill does not move the caret, but the note may
    // have been being typed in (Matt: "tapping notion pill also opens keyboard so the keyboard opens on top of the
    // drawer").
    if (view.hasFocus) FocusManager.instance.primaryFocus?.unfocus();
    Line? lineNow() {
      final at = view.state.fieldOrNull<int?>(_openMenu);
      return at == null ? null : view.state.doc.lineAt(at);
    }

    final props = MarkMenuProps(
      name: linked.name,
      url: linked.url,
      words: linked.words,
      say: menus.say,
      close: () {
        if (!_gone) view.dispatch(TransactionSpec(effects: _toggleMenu.of(null)));
      },
      unlink: () {
        final now = lineNow();
        if (now == null || _gone) return;
        view.dispatch(TransactionSpec(changes: ChangeSpec(from: now.from, to: now.to, insert: unlinked(now.text, kind: linked.kind, url: linked.url)), effects: _toggleMenu.of(null)));
      },
    );
    final mount = told.mount;
    if (mount != null) {
      _unmount = mount(props);
    } else {
      shown.value = props;
      _unmount = () => shown.value = null;
    }
  }

  void _close() {
    final unmount = _unmount;
    _unmount = null;
    unmount?.call();
  }

  @override
  void destroy() {
    _gone = true;
    _close();
  }
}

final ViewPlugin<_MenuDrawer> _menuDrawer = ViewPlugin.define<_MenuDrawer>(_MenuDrawer.new);

DecorationSet _build(EditorState state) {
  final menus = state.facet(_menusFacet).menus;
  final open = state.fieldOrNull<int?>(_openMenu);
  final ranges = <Range<Decoration>>[];
  // A linked thing is a link to a web address: only the lines the tree keeps as having one are asked
  // (lib/editor/view/line_facts.dart). Whether a plugin reads it is asked each time, since that changes.
  for (final line in webLinkFacts.of(state.doc)) {
    final linked = linkedOn(line.text, line.from);
    if (linked == null) continue;
    final entry = peekMarkDetails(linked.name, linked.url);
    // An ordinary link that has never been read draws nothing extra; a mark always has its row.
    if (linked.kind == LinkedKind.link && entry == null) continue;
    final isOpen = menus != null && open != null && open >= line.from && open <= line.to;
    ranges.add(Decoration.widget(widget: LinkRowWidget(linked, entry, open: isOpen, menus: menus != null), block: true, side: 1).range(line.to));
  }
  return Decoration.set(ranges, true);
}

final StateField<DecorationSet> _rows = StateField.define<DecorationSet>(
  create: _build,
  update: (value, tr) {
    final changed =
        tr.docChanged || tr.effects.any((effect) => effect.isOf(detailsArrived) || effect.isOf(_toggleMenu)) || !identical(tr.startState.facet(_menusFacet), tr.state.facet(_menusFacet));
    return changed ? _build(tr.state) : value;
  },
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// Rows of pills under linked lines, and, with `menus`, the drawer a tap on a row opens. `mount` puts the drawer
/// up in place of the row itself, for whoever draws it elsewhere (a test).
Extension linkedRows(LinkMenus? menus, {MarkMenuMount? mount}) => Extension.list(<Extension>[_menusFacet.of(_Told(menus, mount)), _openMenu, _rows, _menuDrawer]);
