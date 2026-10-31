/// A ticket drawn in its note (Matt asked what Notion- and Jira-like features custom Markdown could give the app,
/// "like tickets and such", and picked tickets as notes; tauri/docs/DESIGN.md §157, docs/TICKETS.md). Ports
/// `src/app/editor/tickets.ts`. Two things, both drawn from the Markdown and writing nothing but it:
///
/// **The properties panel.** A note whose front matter says `type: ticket` is drawn with that front matter as a
/// panel, as Notion draws a page's properties over its words: the ticket's key, then Status, Assignee, Priority and
/// Due, and any of Start, Estimate, Blocked by, Parent and Labels it has (ticket_panel.dart). A tap on a value picks
/// it, and the pick is written into the front matter through lib/core/properties.dart `withProperty`, one change,
/// so one Undo takes it back ([writeProperty]). Keys a ticket does not have are a quiet line under the panel, and
/// that line, or the panel's own button, puts the caret in the front matter, where the panel steps aside for the
/// lines as they are written, as every drawn block does (view/drawn_block.dart). A ticket waiting on another that
/// is not done says so first, with a lock and the ticket it waits on.
///
/// It replaces the folded front matter for a ticket (view/extended.dart `frontMatterDrawn`), and only where the
/// screen gave the library's tickets to draw it with: a card's small note and a shared page draw the front matter
/// as before. In a view that cannot be edited the panel is read, with nothing to pick.
///
/// **A key as a link.** `[[GHO-12]]` opens the ticket whose id is GHO-12 (the screen finds it by its key as well as
/// by a title), and is drawn with the ticket's title after it, its status's colour on a dot, struck through once it
/// is done: the key alone says nothing to a reader of the note. A key no ticket has is a link to a note not written
/// yet, drawn as every such link is (items/wiki_links.dart).
///
/// The library changes under both (another ticket is closed, a person is named), so a new set of tickets is told
/// to the view ([refreshTickets]) and the panel and the titles are drawn again.
///
/// The note screen adds it to its extensions as Editor.tsx lists `tickets(() => wikiRef.current?.tickets ?? null)`:
///
///     noteExtensions(more: [tickets(() => options)])
///
/// What differs:
/// - **A title after a key is a run of small pieces, a word each** ([KeyTitle]). Something drawn in a line here is
///   one box that a line cannot break inside, where the page's `<span>` is words that wrap; a word a box, the title
///   wraps where its words do, as on the page, and its strike runs through the spaces between. One place it parts
///   from the page: a line may break after such a box whatever follows it, so a comma or a full stop straight after
///   a title can start the next line, where the page keeps it with the title's last word and breaks before that.
/// - The panel's own differences are ticket_panel.dart's.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart' show GlacierContext;

import '../../book/ticket_watchers.dart' show withAutoWatch;
import '../../core/properties.dart';
import '../editor.dart';
import '../items/field_menu.dart' show dayPicker, todayIs;
import '../items/inline_box.dart';
import '../items/task_fields.dart' show fieldsLocale, fieldsToday;
import '../items/wiki_links.dart' show WikiLink, wikiLinksIn;
import '../queries/query_look.dart';
import '../view/blocks.dart';
import '../view/drawn_block.dart';
import '../view/editor_view.dart';
import '../view/extended.dart' show frontMatter, frontMatterDrawn;
import '../view/line.dart' show EditorRunScope;
import 'ticket_panel.dart';

export 'ticket_panel.dart';
export 'ticket_follow.dart';
export 'ticket_rows.dart';

/// The library's tickets changed: every panel and key title is drawn again.
final StateEffectType<Null> refreshTickets = StateEffect.define<Null>();

/// What a property written from the panel is called in the note's history.
const String propertyUserEvent = 'input.property';

// ---- writing ------------------------------------------------------------------------------------------------------

/// One property written into the note: `withProperty` over the whole body, dispatched as the smallest change that
/// makes it, so the caret and anything typed elsewhere stay put. The key keeps the case the note wrote it in.
void writeProperty(EditorViewLike view, String key, Object? value) {
  final doc = view.state.doc.toString();
  var written = key;
  for (final property in propertiesOf(doc)) {
    if (property.key.toLowerCase() == key) {
      written = property.key;
      break;
    }
  }
  final next = withTicketProperty(doc, written, value);
  if (next == doc) return;
  var start = 0;
  while (start < doc.length && start < next.length && doc.codeUnitAt(start) == next.codeUnitAt(start)) {
    start += 1;
  }
  var end = doc.length;
  var nextEnd = next.length;
  while (end > start && nextEnd > start && doc.codeUnitAt(end - 1) == next.codeUnitAt(nextEnd - 1)) {
    end -= 1;
    nextEnd -= 1;
  }
  view.dispatch(TransactionSpec(changes: ChangeSpec(from: start, to: end, insert: next.substring(start, nextEnd)), userEvent: propertyUserEvent));
}

// ---- the panel ----------------------------------------------------------------------------------------------------

/// The front matter as text, where it is, and where the caret goes to show its lines; null where there is none.
({String text, int from, int to, int at})? _frontOf(EditorState state) {
  final front = frontMatter(state.doc);
  if (front == null) return null;
  final from = state.doc.line(front.from).from;
  final to = state.doc.line(front.to).to;
  return (text: state.doc.sliceString(from, to), from: from, to: to, at: state.doc.line(front.from + 1 < front.to ? front.from + 1 : front.to).from);
}

/// Whether the note is a ticket by its front matter.
bool _ticketNote(EditorState state) {
  final front = _frontOf(state);
  return front != null && isTicket(front.text);
}

/// Whether a document is a ticket's, by its front matter alone.
bool _ticketDoc(Doc doc) {
  final front = frontMatter(doc);
  if (front == null) return false;
  return isTicket(doc.sliceString(doc.line(front.from).from, doc.line(front.to).to));
}

/// Who a change made here makes a watcher of the ticket - its creator, a new assignee picked, whoever comments,
/// whoever is newly mentioned (lib/book/ticket_watchers.dart; Matt, 2026-10-31) - written into its `watchers:` with
/// the change itself, so one Undo takes both back. Only a change that could make one is read whole: an at sign or a
/// comment's lines typed, a letter on a line with an at sign, or the front matter touched; never another device's, an
/// undo or a redo.
Object autoWatch(Transaction tr, String? Function() me) {
  // Nor a merge's or an Unwatch's own writing (lib/root/root_tickets.dart), which says who watches itself.
  if (!tr.docChanged || tr.annotation(Transaction.remote) == true || tr.isUserEvent('undo') || tr.isUserEvent('redo') || tr.isUserEvent('ticket')) return tr;
  final who = me();
  if (who == null || who.isEmpty) return tr;
  final doc = tr.newDoc;
  if (!_ticketDoc(doc)) return tr;
  final front = frontMatter(tr.startState.doc);
  final frontEnd = front == null ? -1 : tr.startState.doc.line(front.to).to;
  var could = false;
  tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
    if (could) return;
    final text = inserted.toString();
    // A name finished by the letter or space after it is on a line that has an at sign.
    if (fromA <= frontEnd || text.contains('@') || (text.contains('\n') && text.length > 12) || doc.lineAt(fromB).text.contains('@')) could = true;
  });
  if (!could) return tr;
  final before = tr.startState.doc.toString(), after = doc.toString();
  final next = withAutoWatch(before, after, me: who, caret: tr.isUserEvent(propertyUserEvent) ? null : tr.newSelection.main.head);
  if (next == null || next == after) return tr;
  var start = 0;
  while (start < after.length && start < next.length && after.codeUnitAt(start) == next.codeUnitAt(start)) {
    start += 1;
  }
  var end = after.length, nextEnd = next.length;
  while (end > start && nextEnd > start && after.codeUnitAt(end - 1) == next.codeUnitAt(nextEnd - 1)) {
    end -= 1;
    nextEnd -= 1;
  }
  final written = ChangeSet.of(ChangeSpec(from: start, to: end, insert: next.substring(start, nextEnd)), after.length);
  return TransactionSpec(changes: tr.changes.compose(written), selection: tr.newSelection.map(written), effects: tr.effects, annotations: tr.annotations, scrollIntoView: tr.scrollIntoView);
}

/// A ticket's panel, drawn in place of its front matter.
class PanelWidget extends EditorWidget implements ClassedBlockWidget {
  const PanelWidget({required this.text, required this.at, required this.version, required this.canEdit, required this.options});

  final String text;

  /// Where the caret goes to show the lines: the first key.
  final int at;
  final int version;

  /// Whether the note can be changed here (the page's `editable`; the name is taken, [EditorWidget.editable]).
  final bool canEdit;
  final TicketOptions? Function() options;

  @override
  String get className => 'cm-ticketPanel';

  @override
  bool eq(PanelWidget other) => other.text == text && other.at == at && other.version == version && other.canEdit == canEdit;

  @override
  double get estimatedHeight => 240;

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.of(context);
    final state = view.state;
    return TicketPanel(
      look: QueryLook.of(context, view is EditorView ? view.look : null),
      front: text,
      options: options(),
      editable: canEdit,
      today: state.facet(fieldsToday)?.call() ?? todayIs(),
      locale: state.facet(fieldsLocale),
      dayPicker: state.facet(dayPicker),
      write: (key, value) => writeProperty(view, key, value),
      // The caret on the first key: the panel steps aside, and the lines are there to type in.
      openLines: () {
        view.focus();
        view.dispatch(TransactionSpec(selection: EditorSelection.single(at), scrollIntoView: true));
      },
    );
  }

  /// Every press in the panel is its own: a value picked, a sheet opened. None of it moves the caret.
  @override
  bool takesPointer(PointerEvent event) => true;
}

class _Panel {
  const _Panel(this.version, this.decorations);
  final int version;
  final DecorationSet decorations;
}

DecorationSet _panelOf(EditorState state, int version, TicketOptions? Function() options) {
  final front = _frontOf(state);
  if (front == null || !isTicket(front.text) || caretIn(state, front.from, front.to)) return Decoration.none;
  final widget = PanelWidget(text: front.text, at: front.at, version: version, canEdit: state.facet(EditorViewLike.editable) && !state.readOnly, options: options);
  return Decoration.set(<Range<Decoration>>[Decoration.replace(widget: widget, block: true).range(front.from, front.to)]);
}

// ---- a key's title ------------------------------------------------------------------------------------------------

/// A ticket's title after its key's link, its status's colour on a dot before it: one word of it, the first with
/// the dot.
class KeyTitle extends EditorWidget {
  const KeyTitle({required this.word, required this.first, required this.title, required this.category, required this.status});

  /// The word this piece draws.
  final String word;

  /// Whether it is the title's first: the room before it and the dot.
  final bool first;

  /// The whole title, and the ticket's status, for what a screen reader hears at the first piece.
  final String title;
  final StatusCategory category;
  final String status;

  @override
  bool eq(KeyTitle other) => other.word == word && other.first == first && other.title == title && other.category == category && other.status == status;

  /// A press on the title is a press on the link: items/wiki_links.dart opens the ticket.
  @override
  bool takesPointer(PointerEvent event) => false;

  @override
  Widget build(BuildContext context) => KeyTitleWord(piece: this);
}

class KeyTitleWord extends StatelessWidget {
  const KeyTitleWord({super.key, required this.piece});

  final KeyTitle piece;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final run = EditorRunScope.maybeOf(context)?.look;
    final em = run?.fontSize ?? t.len('app-body');
    final ink = t.color('app-ink-2');
    final done = piece.category == StatusCategory.done;
    // '.cm-ticketTitle': { marginInlineStart: '0.35em', color: 'var(--app-ink-2, …)' }
    // '.cm-ticketTitle[data-category="done"]': { textDecoration: 'line-through',
    //   textDecorationColor: 'color-mix(in oklch, currentColor 45%, transparent)' }
    final style = (run?.style ?? t.textAt(em)).copyWith(color: ink, decoration: done ? TextDecoration.lineThrough : TextDecoration.none, decorationColor: ink.withValues(alpha: ink.a * 0.45));
    final above = run?.ascent ?? em, below = run?.descent ?? 0.25 * em;
    // '.cm-ticketDot': { display: 'inline-block', inlineSize: '0.5em', blockSize: '0.5em', marginInlineEnd: '0.3em',
    //   borderRadius: '50%', verticalAlign: '0.08em', background: 'var(--app-ink-4, currentColor)' }
    // '[data-category="doing"] .cm-ticketDot': blue-9; '[data-category="done"] .cm-ticketDot': green-9
    final dot = 0.5 * em;
    final colour = switch (piece.category) {
      StatusCategory.doing => t.color('glacier-blue-9'),
      StatusCategory.done => t.color('glacier-green-9'),
      StatusCategory.todo => t.color('app-ink-4'),
    };
    final words = Text(piece.first ? piece.word : ' ${piece.word}', softWrap: false, textScaler: TextScaler.noScaling, style: style);
    return Semantics(
      label: piece.first ? (piece.status.isEmpty ? piece.title : '${piece.title} · ${piece.status}') : null,
      excludeSemantics: true,
      child: InlineBox(
        above: above,
        below: below,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (piece.first) ...<Widget>[
              SizedBox(width: 0.35 * em),
              Padding(
                padding: EdgeInsets.only(top: above - 0.08 * em - dot, right: 0.3 * em),
                child: Container(key: const ValueKey<String>('ticket-dot'), width: dot, height: dot, decoration: ShapeDecoration(color: colour, shape: const CircleBorder())),
              ),
            ],
            words,
          ],
        ),
      ),
    );
  }
}

final RegExp _spaces = RegExp(r'\s+');

/// The links on a line that are a ticket's key, `[[GHO-12]]`, counted from the line's start. Kept for every line
/// of a document (`LineFact`), so the library is asked for its tickets only by a note that names one.
final LineFact<List<WikiLink>> _keyLinks = LineFact<List<WikiLink>>((text) {
  if (!text.contains('[[')) return null;
  final keys = <WikiLink>[
    for (final link in wikiLinksIn(text))
      if (link.anchor == null && issueKeyOf(link.title) != null) link,
  ];
  return keys.isEmpty ? null : keys;
});

/// Whether anything in the note is drawn from the library's tickets: its own panel, or a key's title. A note of
/// which neither is true has nothing to draw again when the library changes.
bool readsTickets(EditorState state) => !_keyLinks.nowhere(state.doc) || _ticketNote(state);

DecorationSet _keyTitles(EditorViewLike view, TicketOptions? Function() options) {
  final doc = view.state.doc;
  // The keys among the lines on screen, from what the tree keeps of them: with none, the library is not asked.
  final lines = <FactLine<List<WikiLink>>>[
    for (final range in view.visibleRanges) ..._keyLinks.between(doc, doc.lineAt(range.from).number, doc.lineAt(range.to).number),
  ];
  if (lines.isEmpty) return Decoration.none;
  final lookup = options();
  if (lookup == null) return Decoration.none;
  final found = <Range<Decoration>>[];
  // Not in the front matter, whose `blocked-by: "[[GHO-9]]"` is a line of keys, drawn as the panel or typed as it is.
  final front = frontMatter(doc);
  final after = front == null ? -1 : doc.line(front.to).to;
  for (final line in lines) {
    if (line.from <= after) continue;
    for (final link in line.fact) {
      final ticket = lookup.find(link.title);
      if (ticket == null || ticket.title.isEmpty) continue;
      final words = ticket.title.trim().split(_spaces);
      for (final (index, word) in words.indexed) {
        found.add(Decoration.widget(widget: KeyTitle(word: word, first: index == 0, title: ticket.title, category: ticket.category, status: ticket.status ?? ''), side: 1).range(line.from + link.to));
      }
    }
  }
  return Decoration.set(found, true);
}

class _KeyTitles extends PluginValue {
  _KeyTitles(EditorViewLike view, this.options) : decorations = _keyTitles(view, options);

  final TicketOptions? Function() options;
  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    final refreshed = update.transactions.any((tr) => tr.effects.any((effect) => effect.isOf(refreshTickets)));
    if (update.docChanged || update.viewportChanged || refreshed) decorations = _keyTitles(update.view, options);
  }
}

/// A ticket's panel over its words and its key's title after a `[[GHO-12]]`, read from the library through
/// `options` when they are drawn; nothing where it answers null.
Extension tickets(TicketOptions? Function() options) {
  final panel = StateField.define<_Panel>(
    // Whether the note is a ticket is asked first, of its own front matter: the library is asked for its tickets
    // (every note read, in the root's keeping) only by a note that is one.
    create: (state) => _Panel(0, _ticketNote(state) && options() != null ? _panelOf(state, 0, options) : Decoration.none),
    update: (value, tr) {
      final refreshed = tr.effects.any((effect) => effect.isOf(refreshTickets));
      if (!refreshed && !tr.docChanged && tr.selection == null && !tr.reconfigured && !focusMoved(tr)) return value;
      final version = value.version + (refreshed ? 1 : 0);
      return _Panel(version, _ticketNote(tr.state) && options() != null ? _panelOf(tr.state, version, options) : Decoration.none);
    },
    provide: (field) => EditorViewLike.decorations.from<_Panel>(field, (value) => value.decorations),
  );
  return Extension.list(<Extension>[
    trackFocus,
    panel,
    // A ticket's watchers kept up as it is written (lib/book/ticket_watchers.dart).
    EditorState.transactionFilter.of((tr) => autoWatch(tr, () => options()?.follow?.me())),
    // The folded front matter steps aside for a ticket's panel (view/extended.dart).
    frontMatterDrawn.of((state) => _ticketNote(state) && options() != null),
    ViewPlugin.define<_KeyTitles>((view) => _KeyTitles(view, options), decorations: (value) => value.decorations),
  ]);
}
