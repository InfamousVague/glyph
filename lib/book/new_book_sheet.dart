/// Making a book (Matt: "expand the UI/UX for creating books, allow choosing existing notes as pages"): a sheet in
/// the New sheet's own look that asks for the name, then which notes are its pages and in what order. A port of
/// `src/app/book/NewBookSheet.tsx` and `NewBookSheet.module.css`.
///
/// The library's notes are listed under a search; a tap puts one in the book and a second tap takes it out, and the
/// pages so far stand above the list in the order they were chosen, each movable a place or removable. Making the
/// book writes one note with those pages as its index (lib/core/book.dart [bookNoteBody]) and opens it. Nothing is
/// written until then: closing the sheet makes nothing.
///
/// Or a journal (tauri/docs/DESIGN.md §142): a choice under the name, Notebook or Journal, and with Journal
/// chosen the pages give way to what each entry starts with and whether it keeps where it was written
/// (template_picker.dart). Its place switch starts as this device's Tag new notes, whatever the device can do, so a
/// journal made on the Mac keeps the places of the entries made on the phone.
///
///     NewBookSheet     the sheet
///     NewBooks         what its two makings write to the library (App.tsx `createBook`, `createJournal`)
///
/// What differs:
/// - **A notebook's ticket key is not asked here**, as it is not on the page: a notebook becomes a project of
///   tickets on its own More sheet (`editor/NoteSettings.tsx`'s Ticket key, lib/book/tickets.dart
///   [withNotebookKey]), which is the note screen's.
/// - `.sheet { max-block-size: min(88dvh, 44rem) }` is the sheet's own 85dvh: lib/sheet/sheet.dart takes no look
///   of its caller's.
/// - Tag new notes is read from lib/core/preferences.dart's store unless [NewBookSheet.tagNewNotes] says.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/book.dart' show bookNoteBody, isBookBody;
import '../core/item_syntax.dart' show jsTrim;
import '../core/library.dart';
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle, sameTitle;
import '../core/preferences.dart' show preferences;
import '../sheet/css.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import 'book_view.dart' show CanvasMark, PickMark, toggledTitle;
import 'journal.dart';
import 'row_drag.dart';
import 'template_picker.dart';

/// What the sheet makes (`kind`).
enum NewBookKind { notebook, journal }

/// The New notebook sheet (`NewBookSheet`).
class NewBookSheet extends StatefulWidget {
  const NewBookSheet({super.key, required this.open, required this.onClose, required this.titles, required this.onCreate, this.onCreateJournal, this.kind = NewBookKind.notebook, this.isCanvas, this.tagNewNotes, this.device = const EntryPlaceDevice(), this.clock});

  final bool open;
  final VoidCallback onClose;

  /// Every note that could be a page: the library's titles, less the books (a book of books is not a page).
  final List<String> titles;
  final void Function(String title, List<String> pages) onCreate;

  /// Makes a journal with its template and its place switch; absent, no Journal choice.
  final void Function(String title, String template, bool place)? onCreateJournal;

  /// Which is chosen as the sheet opens: the palette's New journal opens it on Journal.
  final NewBookKind kind;

  /// Whether a title is a canvas, to give it the canvas's mark as the book's index does; absent, none is marked.
  final bool Function(String title)? isCanvas;

  /// This device's Tag new notes, which a journal's place switch starts as; the preference where it is left out.
  final bool Function()? tagNewNotes;

  /// This device's side of keeping a place, for the journal's switch (template_picker.dart).
  final EntryPlaceDevice device;
  final DateTime Function()? clock;

  @override
  State<NewBookSheet> createState() => _NewBookSheetState();
}

class _NewBookSheetState extends State<NewBookSheet> {
  String _name = '';
  String _find = '';
  List<String> _pages = const <String>[];
  late NewBookKind _kind = widget.onCreateJournal != null ? widget.kind : NewBookKind.notebook;
  String _template = defaultTemplate;
  late bool _place = _tagNewNotes();
  late final RowDrag _rows = RowDrag((from, to) {
    setState(() {
      final next = [..._pages];
      if (from < 0 || from >= next.length) return;
      final moved = next.removeAt(from);
      next.insert(to.clamp(0, next.length), moved);
      _pages = next;
    });
  });

  bool _tagNewNotes() => widget.tagNewNotes?.call() ?? preferences.value.tagNewNotes;

  @override
  void didUpdateWidget(NewBookSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Each opening starts on the kind it was opened for, and a journal's switch on this device's Tag new notes. Only
    // an opening: the app hands a new `onCreateJournal` on every build, and a sync or the phone's own location prompt
    // answered each draws it again while the sheet is up, which put the choices back under the person.
    final journals = widget.onCreateJournal != null;
    if (!widget.open) return;
    if (!oldWidget.open || oldWidget.kind != widget.kind || (oldWidget.onCreateJournal != null) != journals) {
      _kind = journals ? widget.kind : NewBookKind.notebook;
      _place = _tagNewNotes();
    }
  }

  @override
  void dispose() {
    _rows.dispose();
    super.dispose();
  }

  bool _chosen(String title) => _pages.any((p) => sameTitle(p, title));

  void _toggle(String title) => setState(() => _pages = toggledTitle(_pages, title));

  void _move(String title, int by) {
    final at = _pages.indexWhere((p) => sameTitle(p, title));
    final to = at + by;
    if (at < 0 || to < 0 || to >= _pages.length) return;
    setState(() {
      final next = [..._pages];
      final held = next[at];
      next[at] = next[to];
      next[to] = held;
      _pages = next;
    });
  }

  void _make() {
    final title = jsTrim(_name);
    if (title.isEmpty) return;
    widget.onClose();
    final journal = widget.onCreateJournal;
    if (_kind == NewBookKind.journal && journal != null) {
      journal(title, _template, _place);
    } else {
      widget.onCreate(title, _pages);
    }
    setState(() {
      _name = '';
      _find = '';
      _pages = const <String>[];
      _template = defaultTemplate;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final t = context.tokens;
    final journal = _kind == NewBookKind.journal;
    final heading = journal ? 'New journal' : 'New notebook';
    final needle = jsTrim(_find).toLowerCase();
    final found = [
      for (final title in widget.titles)
        if (jsTrim(title).isNotEmpty && (needle.isEmpty || title.toLowerCase().contains(needle))) title,
    ].take(60).toList();
    final named = jsTrim(_name).isNotEmpty;
    final line = snapBorder(context, 1);
    final rule = t.color('glacier-border-subtle');
    final muted = t.color('glacier-text-muted');
    final ink = t.color('glacier-text');
    // The sheet's own type: 1rem, in the page's ink.
    const em = 16.0;
    final words = pageText(t, em, color: ink);

    return Sheet(
      label: heading,
      onClose: widget.onClose,
      children: [
        SheetTitle.text(heading),
        // `.form { display: flex; flex-direction: column; gap: var(--glacier-space-3) }`
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(3),
          children: [
            SheetField(key: const ValueKey('book-name'), label: 'Name', value: _name, placeholder: journal ? 'Diary' : 'Field guide', autoFocus: true, onChange: (text) => setState(() => _name = text), onSubmitted: (_) => _make()),
            if (widget.onCreateJournal != null)
              // `.kind { display: flex }` round the More sheet's two-word choice (`.viewChoice`).
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _KindChoice(kind: _kind, onKind: (kind) => setState(() => _kind = kind)),
              ),
            if (journal) ...[
              TemplatePicker(template: _template, onTemplate: (text) => setState(() => _template = text), place: _place, onPlace: (on) => setState(() => _place = on), name: _name, device: widget.device, clock: widget.clock),
              SheetGroup(children: [SheetRow(key: const ValueKey('book-make'), label: 'Make the journal', hint: 'Empty, ready for its first entry.', onPress: _make, disabled: !named)]),
            ] else ...[
              const SheetNote("Its pages are notes, in the order you choose. Pick any now, or add them later from the notebook's index."),
              if (_pages.isNotEmpty)
                Semantics(
                  container: true,
                  label: 'Pages in this notebook',
                  child: Container(
                    key: const ValueKey('book-pages'),
                    // `.pages { border: 1px solid subtle; border-radius: var(--glacier-radius-md) }`
                    decoration: BoxDecoration(border: Border.all(color: rule, width: line), borderRadius: BorderRadius.circular(t.radius('md'))),
                    child: DefaultTextStyle(
                      style: words,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (i, title) in _pages.indexed) DragRow(key: ValueKey('book-page:$title'), drag: _rows, index: i, child: _page(t, i, title, em: em, line: line, rule: rule, muted: muted, words: words)),
                        ],
                      ),
                    ),
                  ),
                ),
              SheetField(key: const ValueKey('book-find'), label: 'Find a note', value: _find, placeholder: 'Type to find', onChange: (text) => setState(() => _find = text)),
              Semantics(
                container: true,
                label: 'Notes',
                child: Container(
                  key: const ValueKey('book-found'),
                  // `.found { max-block-size: 14rem; overflow-y: auto; border: 1px solid subtle; border-radius: md }`
                  constraints: BoxConstraints(maxHeight: t.lenOf('14rem')),
                  decoration: BoxDecoration(border: Border.all(color: rule, width: line), borderRadius: BorderRadius.circular(t.radius('md'))),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (found.isEmpty)
                          Padding(
                            // `.none { padding: 0.6em 0.8em; color: muted; font-size: sm }`
                            padding: EdgeInsets.symmetric(vertical: 0.6 * t.fontSize('sm'), horizontal: 0.8 * t.fontSize('sm')),
                            child: Text(widget.titles.isNotEmpty ? 'No note by that name.' : 'No notes yet: the notebook starts empty, and pages can be added from its index.', style: pageText(t, t.fontSize('sm'), color: muted)),
                          ),
                        for (final title in found)
                          () {
                            final on = _chosen(title);
                            return GlacierPressable(
                              key: ValueKey('book-pick:$title'),
                              toggled: on,
                              semanticLabel: title,
                              excludeSemantics: true,
                              onPressed: () => _toggle(title),
                              builder: (context, state) => DecoratedBox(
                                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rule, width: line)), color: state.hovered ? ink.withValues(alpha: 0.06 * ink.a) : null),
                                child: Padding(
                                  // `.pick { gap: var(--glacier-space-2); padding: 0.5em 0.7em }`
                                  padding: EdgeInsets.fromLTRB(0.7 * em, 0.5 * em, 0.7 * em, 0.5 * em + line),
                                  child: Row(
                                    children: [
                                      PickMark(on: on, size: 1.25 * em),
                                      SizedBox(width: t.space(2)),
                                      Flexible(child: Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: words)),
                                      if (widget.isCanvas?.call(title) ?? false) const CanvasMark(em: em),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }(),
                      ],
                    ),
                  ),
                ),
              ),
              SheetGroup(
                children: [
                  SheetRow(
                    key: const ValueKey('book-make'),
                    label: 'Make the notebook',
                    hint: _pages.isNotEmpty ? '${_pages.length} page${_pages.length == 1 ? '' : 's'}, in this order.' : 'Empty, with its index ready.',
                    onPress: _make,
                    disabled: !named,
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// One page chosen so far (`.page`): its grip, its number, its title and its tools, as the index's rows are.
  Widget _page(Tokens t, int i, String title, {required double em, required double line, required Color rule, required Color muted, required TextStyle words, bool ghost = false}) {
    const toolSize = 2 * 13.3333;
    Widget tool(String label, LucideIcon icon, VoidCallback? onPressed) => GlacierPressable(
          semanticLabel: label,
          excludeSemantics: true,
          onPressed: onPressed,
          builder: (context, state) => Opacity(
            opacity: state.disabled ? 0.3 : 1,
            child: Container(
              width: toolSize,
              height: toolSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered && !state.disabled ? t.color('glacier-text').withValues(alpha: 0.08) : null),
              child: lucide(icon, size: 16, color: state.hovered && !state.disabled ? t.color('glacier-text') : muted),
            ),
          ),
        );
    final last = i == _pages.length - 1;
    return DecoratedBox(
      // `.page { border-block-end: 1px solid subtle }`, `.page:last-child { border-block-end: 0 }`
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: rule, width: line))),
      child: Padding(
        // `padding: var(--glacier-space-1) var(--glacier-space-2)`
        padding: EdgeInsets.fromLTRB(t.space(2), t.space(1), t.space(2), t.space(1) + (last ? 0 : line)),
        // `grid-template-columns: 1.4em 2em minmax(0, 1fr) auto; align-items: center; gap: var(--glacier-space-2)`
        child: Row(
          spacing: t.space(2),
          children: [
            SizedBox(
              width: 1.4 * em,
              child: ghost
                  ? SizedBox(height: 2 * em, child: Center(child: lucide(Lucide.gripVertical, size: 16, color: t.color('glacier-text-subtle'))))
                  : RowGrip(
                      key: ValueKey('book-page-grip:$title'),
                      drag: _rows,
                      index: i,
                      count: _pages.length,
                      em: em,
                      ghost: (context) => DefaultTextStyle(style: words, child: _page(t, i, title, em: em, line: line, rule: rule, muted: muted, words: words, ghost: true)),
                    ),
            ),
            SizedBox(
              width: 2 * em,
              child: ExcludeSemantics(
                child: Text('${i + 1}', textAlign: TextAlign.end, maxLines: 1, style: words.copyWith(color: muted, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Flexible(child: Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: words)),
                  if (widget.isCanvas?.call(title) ?? false) CanvasMark(em: em),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                tool('Move $title up', Lucide.chevronUp, i == 0 ? null : () => _move(title, -1)),
                tool('Move $title down', Lucide.chevronDown, last ? null : () => _move(title, 1)),
                tool('Leave $title out', Lucide.x, () => _toggle(title)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Notebook or Journal, under the name: the More sheet's two-word choice (`editor/NoteSettings.module.css`
/// `.viewChoice`): `display: inline-flex; padding: 3px; border: var(--app-line) solid strong; border-radius: full`,
/// each word `min-block-size: 2rem; padding: 0 var(--glacier-space-3); font-size: sm; font-weight: semibold`, the
/// chosen one ink on the page's ground turned round.
class _KindChoice extends StatelessWidget {
  const _KindChoice({required this.kind, required this.onKind});

  final NewBookKind kind;
  final ValueChanged<NewBookKind> onKind;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final line = snapBorder(context, t.len('app-line'));
    final sm = t.fontSize('sm');
    return Semantics(
      container: true,
      label: 'What it is',
      child: Container(
        key: const ValueKey('book-kind'),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-strong'), width: line), borderRadius: BorderRadius.circular(9999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, label) in const [(NewBookKind.notebook, 'Notebook'), (NewBookKind.journal, 'Journal')])
              GlacierPressable(
                key: ValueKey('book-kind:${value.name}'),
                // `role="radio" aria-checked`
                toggled: kind == value,
                semanticLabel: label,
                excludeSemantics: true,
                onPressed: () => onKind(value),
                builder: (context, state) => GlacierFocusRing(
                  visible: state.focused,
                  radius: t.radius('full'),
                  child: Container(
                    constraints: BoxConstraints(minHeight: t.lenOf('2rem')),
                    padding: EdgeInsets.symmetric(horizontal: t.space(3)),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(9999), color: kind == value ? t.color('glacier-text') : null),
                    child: Text(label, maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'semibold', color: kind == value ? t.color('glacier-bg') : t.color('glacier-text-muted'))),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- what the sheet's makings write to the library (App.tsx) ------------------------------------------------------

/// The library's half of the sheet: `src/app/App.tsx`'s `createBook` and `createJournal`, each one note written
/// with the body the web writes ([bookNoteBody], [journalNoteBody]) and answered as the library stored it, for the
/// shell to open; and `pageTitles`, what can be a page of a new notebook.
class NewBooks {
  const NewBooks(this.library);

  final NoteLibrary library;

  /// What can be a page of a new notebook: every note's title but the notebooks' own, and none of a journal's
  /// entries, which belong to their journal (`pageTitles`).
  List<String> pageTitles() {
    final notes = [for (final n in library.value) if (n.archivedAt == null) n];
    final entries = entryPages(notes);
    return [
      for (final n in notes)
        if (!isBookBody(n.body) && !entries.contains(n.id) && jsTrim(noteTitle(n.body)).isNotEmpty) noteTitle(n.body),
    ];
  }

  Future<Note> createBook(String title, List<String> pages) async {
    final made = await library.createNote(bookNoteBody(title, pages));
    await library.refresh().catchError((Object _) {});
    return library.noteOf(made.id) ?? made;
  }

  Future<Note> createJournal(String title, String template, bool place) async {
    final made = await library.createNote(journalNoteBody(title, template, place));
    await library.refresh().catchError((Object _) {});
    return library.noteOf(made.id) ?? made;
  }
}
