/// A journal, drawn where its words would be (lib/note/note_screen.dart `NoteSeams.journal`; tauri/
/// docs/DESIGN.md §142): one action, New entry, then the journal's own words, then its entries by the month each
/// was written in, newest first. A port of `src/app/book/JournalView.tsx` and `JournalView.module.css`.
///
/// A notebook's index is its order (book_view.dart); a journal's is time's, so there are no grips, no moves and no
/// Add a page here, and the Markdown behind the view switch keeps the lines in the order they were made.
///
/// The three newest months are open, and each older one is a row that opens it in place: a year is about ninety
/// rows and nine month rows, not three hundred and sixty-five. A row is what a person scans for - the day, the
/// time, where it was written, and how it starts, faded at the edge rather than cut with an ellipsis - and opens the
/// entry in the journal's tab. A page planned before a notebook was kept as a journal is listed at the end under
/// Not written yet, with the index's cross to take it out; an entry's line with no note is not drawn
/// (journal_months.dart).
///
/// New entry asks what the entry starts with (Matt: "I would like to see [the templates] when clicking new page on
/// a journal while the journal is open"): the journal's own template first, marked as its usual, then the other
/// presets and an empty page, each with a line of how it starts, filled for this minute. A tap makes the entry from
/// that one; the journal's usual template is changed only on its More sheet (template_picker.dart).
///
///     JournalView      the page
///     JournalPages     what New entry does to the library (App.tsx `newEntry`, `makeEntry`)
///
/// What differs:
/// - `dark` is not taken: the tokens say which side of the theme the page is on.
/// - The months are worked out on every build, where the page kept them until a page's note changed: here that is
///   a sort of the rows in hand and no editor is mounted for it.
/// - `@container journal (min-width: 44rem)` is asked of the room the view is given, less its own padding.
/// - **A spoken entry** (`makeEntry`'s `speak`) is the recorder's, a later stage: [JournalPages.newEntry] makes the
///   typed one. Where an entry was written (`tagEntryIfWanted`) is the shell's to ask after it, with the phone.
/// - **On a page with a dock** (lib/shell/page_dock.dart) the journal offers it New entry, its own button: the
///   templates open under it, brought into view.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/back.dart';
import '../core/book.dart' show chaptersOf, isJournalBody;
import '../core/ids.dart' show randomId;
import '../core/library.dart';
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle, titleKey;
import '../core/template.dart' show Placing, fillTemplate, openEnd;
import '../core/untouched.dart';
import '../home/home_icons.dart' show HomeGlyph;
import '../sheet/css.dart';
import '../sheet/flow.dart';
import '../shell/page_dock.dart';
import 'book_view.dart';
import 'entry_starts.dart';
import 'journal.dart';
import 'journal_months.dart';

/// Months drawn open before the older ones fold to a row each (`OPEN_MONTHS`).
const int openMonths = 3;

Color _ink(Tokens t, double part) {
  final ink = t.color('glacier-text');
  return ink.withValues(alpha: part * ink.a);
}

/// A journal's page (`JournalView`).
class JournalView extends StatefulWidget {
  const JournalView({super.key, required this.body, required this.noteOf, required this.known, required this.open, required this.onChange, this.onNewEntry, this.clock, this.drawing});

  final String body;

  /// What the journal's own words draw ([BookDrawing]); absent, the base alone.
  final BookDrawing? drawing;

  /// The note by that title, for an entry's date, place and words: null where there is none.
  final Note? Function(String title) noteOf;

  /// Whether a note by that title exists, for a link in the journal's own words.
  final bool Function(String title) known;

  /// Opens the note by that title in this tab (App.tsx `openTitleWithin`).
  final ValueChanged<String> open;
  final ValueChanged<String> onChange;

  /// New entry, from the template chosen for it; absent, no button.
  final ValueChanged<String>? onNewEntry;

  /// The minute a template's line is told for; this one where it is left out.
  final DateTime Function()? clock;

  @override
  State<JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends State<JournalView> {
  /// The older months opened by a tap.
  final Set<String> _unfolded = <String>{};

  /// New entry pressed: the templates to start it from are showing.
  bool _choosing = false;

  /// New entry's place, to bring it into view from the dock.
  final GlobalKey _newEntry = GlobalKey(debugLabel: 'journal new entry');

  /// The dock's New entry: the templates, under the journal's own New entry, in view.
  void _choose() {
    setState(() => _choosing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _newEntry.currentContext;
      if (!mounted || at == null) return;
      unawaited(Scrollable.ensureVisible(at, duration: context.tokens.reducedMotion ? Duration.zero : const Duration(milliseconds: 300), curve: Curves.easeOut));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final em = t.len('app-body');
    final body = widget.body;
    final words = bookWords(body);
    final template = templateOf(body);
    final name = noteTitle(body);
    final (:months, :unwritten) = monthsOf(pagesOf(body, widget.noteOf), template, name);
    final onNewEntry = widget.onNewEntry;
    final muted = t.color('glacier-text-muted');
    final line = snapBorder(context, 1);
    final rule = t.color('glacier-border-subtle');

    // The page's dock, where it has one: New entry.
    return DockOffer(
      actions: [if (onNewEntry != null) DockAction(id: 'journal-new-entry', label: 'New entry', glyph: HomeGlyph.plus, motion: DockMotion.turn, onPressed: _choose)],
      child: DefaultTextStyle(
        style: bookText(t, em),
        child: Padding(
          // `.journal { composes: book }`: `padding: var(--glacier-space-4) var(--glacier-space-5) var(--glacier-space-8)`
          padding: EdgeInsets.fromLTRB(t.space(5), t.space(4), t.space(5), t.space(8)),
          child: LayoutBuilder(
            builder: (context, box) {
              // `@container journal (min-width: 44rem)`: the Fold opened out, a row is one line.
              final wide = box.maxWidth >= t.lenOf('44rem');
              return CssFlow(
                children: [
                  if (onNewEntry != null)
                    CssFlow.block(
                      // `.adds { margin-block: 0 var(--glacier-space-4) }`
                      margin: EdgeInsets.only(bottom: t.space(4)),
                      child: Align(
                        key: _newEntry,
                        alignment: AlignmentDirectional.centerStart,
                        child: BookAction(key: const ValueKey('journal-new-entry'), icon: Lucide.plus, label: 'New entry', expanded: _choosing, onPressed: () => setState(() => _choosing = !_choosing)),
                      ),
                    ),
                  if (onNewEntry != null && _choosing)
                    _TemplateChoice(
                      usual: template,
                      journal: name,
                      now: widget.clock?.call() ?? DateTime.now(),
                      onPick: (text) {
                        setState(() => _choosing = false);
                        onNewEntry(text);
                      },
                      onCancel: () => setState(() => _choosing = false),
                    ),
                  if (words.before.isNotEmpty) BookWords(words: words.before, known: widget.known, open: widget.open, drawing: widget.drawing),
                  if (months.isEmpty && unwritten.isEmpty)
                    CssFlow.block(
                      // `.empty { margin-block: var(--glacier-space-3); color: var(--glacier-text-muted) }`
                      margin: EdgeInsets.symmetric(vertical: t.space(3)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          cssLines('No entries yet.', bookText(t, em, color: muted)),
                          // `.quiet { font-size: sm; color: var(--glacier-text-subtle) }`
                          cssLines(templateSentence(template), bookText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle'))),
                        ],
                      ),
                    ),
                  for (final (n, month) in months.indexed)
                    if (n < openMonths || _unfolded.contains(month.key))
                      _month(t, key: ValueKey('journal-month:${month.key}'), label: month.label, rows: [for (final entry in month.entries) _entry(t, em, entry, wide: wide)], line: line, rule: rule)
                    else
                      CssFlow.block(
                        // `.folded { margin-block-start: var(--glacier-space-2) }`, `.folded + .folded { margin-block-start: 0 }`
                        margin: EdgeInsets.only(top: n > openMonths && !_unfolded.contains(months[n - 1].key) ? 0 : t.space(2)),
                        child: GlacierPressable(
                          key: ValueKey('journal-folded:${month.key}'),
                          semanticLabel: '${month.label} · ${month.entries.length}',
                          excludeSemantics: true,
                          onPressed: () => setState(() => _unfolded.add(month.key)),
                          builder: (context, state) => DecoratedBox(
                            decoration: BoxDecoration(border: Border(top: BorderSide(color: rule, width: line))),
                            child: Padding(
                              // `padding: var(--glacier-space-3) var(--glacier-space-1)`, under its line.
                              padding: EdgeInsets.fromLTRB(t.space(1), t.space(3) + line, t.space(1), t.space(3)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: cssLines('${month.label} · ${month.entries.length}', bookText(t, em, weight: 'medium', color: muted).copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]), maxLines: 1, softWrap: false),
                                  ),
                                  lucide(Lucide.chevronRight, size: 16, color: muted),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  if (unwritten.isNotEmpty)
                    _month(
                      t,
                      key: const ValueKey('journal-unwritten'),
                      label: 'Not written yet',
                      line: line,
                      rule: rule,
                      rows: [
                        for (final title in unwritten)
                          // `.planned { display: flex; align-items: center; gap: var(--glacier-space-2) }`
                          Row(
                            spacing: t.space(2),
                            children: [
                              Expanded(
                                child: GlacierPressable(
                                  key: ValueKey('journal-planned:$title'),
                                  semanticLabel: '$title, not written yet',
                                  excludeSemantics: true,
                                  onPressed: () => widget.open(title),
                                  builder: (context, state) => Padding(
                                    // `.plannedTitle { padding: 0.35em 0.2em; color: muted; text-overflow: ellipsis }`
                                    padding: EdgeInsets.symmetric(vertical: 0.35 * em, horizontal: 0.2 * em),
                                    child: Align(alignment: AlignmentDirectional.centerStart, child: cssLines(title, bookText(t, em, color: muted), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis)),
                                  ),
                                ),
                              ),
                              GlacierPressable(
                                semanticLabel: 'Take $title out of the journal',
                                excludeSemantics: true,
                                onPressed: () => widget.onChange(withoutChapter(body, title)),
                                // `.tool`, whose 2em is of a button's own 13.33px (rows.module.css).
                                builder: (context, state) => Container(
                                  width: 2 * 13.3333,
                                  height: 2 * 13.3333,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered ? _ink(t, 0.08) : null),
                                  child: lucide(Lucide.x, size: 16, color: state.hovered ? t.color('glacier-text') : muted),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  if (words.after.isNotEmpty) BookWords(words: words.after, known: widget.known, open: widget.open, drawing: widget.drawing),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// A month over its rows (`.month`, `.monthName`, `.entries`).
  Widget _month(Tokens t, {required Key key, required String label, required List<Widget> rows, required double line, required Color rule}) {
    final lg = t.fontSize('lg');
    return CssFlow.block(
      key: key,
      // `.month { margin-block: var(--glacier-space-5) 0 }`
      margin: EdgeInsets.only(top: t.space(5)),
      child: Semantics(
        container: true,
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // `.monthName { margin: 0 0 var(--glacier-space-2); font-size: lg; line-height: var(--glacier-leading-lg);
            // font-weight: semibold; letter-spacing: var(--app-tracking-title); color: var(--app-ink) }`
            Padding(
              padding: EdgeInsets.only(bottom: t.space(2)),
              child: Semantics(
                header: true,
                child: cssLines(label, t.textAt(lg, weight: 'semibold', color: t.color('app-ink'), height: t.len('glacier-leading-lg'), tracking: t.len('app-tracking-title', em: lg))),
              ),
            ),
            for (final (n, row) in rows.indexed)
              // `.entries > li + li { border-block-start: 1px solid var(--glacier-border-subtle) }`
              n == 0 ? row : DecoratedBox(decoration: BoxDecoration(border: Border(top: BorderSide(color: rule, width: line))), child: Padding(padding: EdgeInsets.only(top: line), child: row)),
          ],
        ),
      ),
    );
  }

  /// One entry's row (`.entry`): the day over its weekday beside the time and the words; wide, one line.
  Widget _entry(Tokens t, double em, EntryRow entry, {required bool wide}) {
    final subtle = t.color('glacier-text-subtle');
    final sm = t.fontSize('sm');
    final dateEm = t.fontSize(wide ? 'lg' : 'xl');
    const tabular = <FontFeature>[FontFeature.tabularFigures()];
    // `.date { line-height: 1.1; font-weight: semibold; font-variant-numeric: tabular-nums }`
    final date = cssLines(entry.day, t.textAt(dateEm, weight: 'semibold', color: t.color('glacier-text'), height: 1.1).copyWith(fontFeatures: tabular), maxLines: 1, softWrap: false);
    // `.weekday { font-size: xs; color: subtle }`
    final weekday = cssLines(entry.weekday, bookText(t, t.fontSize('xs'), color: subtle), maxLines: 1, softWrap: false);
    // The time and where, and how it starts: one line each, faded out at the column's edge, never cut mid-letter.
    final meta = _Faded(child: cssLines('${entry.time}${entry.place != null && entry.place!.isNotEmpty ? ' · ${entry.place}' : ''}', bookText(t, sm, color: subtle).copyWith(fontFeatures: tabular), maxLines: 1, softWrap: false, overflow: TextOverflow.clip));
    final first = _Faded(child: cssLines(entry.first, bookText(t, em), maxLines: 1, softWrap: false, overflow: TextOverflow.clip));
    final Widget row;
    if (wide) {
      // `grid-template-columns: 4.6em 12em minmax(0, 1fr); align-items: center`
      row = Row(
        spacing: t.space(3),
        children: [
          SizedBox(
            width: 4.6 * em,
            // `.day { display: flex; align-items: baseline; gap: 0.4em }`
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 0.4 * em, children: [date, weekday]),
          ),
          SizedBox(width: 12 * em, child: meta),
          Expanded(child: first),
        ],
      );
    } else {
      // `grid-template-columns: 2.6em minmax(0, 1fr); grid-template-areas: 'day meta' 'day first'`
      row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: t.space(3),
        children: [
          SizedBox(width: 2.6 * em, child: Column(mainAxisSize: MainAxisSize.min, children: [date, weekday])),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [meta, first])),
        ],
      );
    }
    return GlacierPressable(
      key: ValueKey('journal-entry:${entry.title}'),
      semanticLabel: entry.label,
      excludeSemantics: true,
      onPressed: () => widget.open(entry.title),
      builder: (context, state) => DecoratedBox(
        // `.entry:hover, .entry:focus-visible { background: 6% of the ink }`
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('sm')), color: state.hovered || state.focused ? _ink(t, 0.06) : null),
        child: Padding(
          // `padding: var(--glacier-space-2) var(--glacier-space-1)`
          padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(1)),
          child: row,
        ),
      ),
    );
  }
}

/// `mask-image: linear-gradient(to right, #000 calc(100% - 32px), transparent)` over one clipped line.
class _Faded extends StatelessWidget {
  const _Faded({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: const <Color>[Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: <double>[0, bounds.width <= 32 ? 0 : (bounds.width - 32) / bounds.width, 1],
        ).createShader(bounds),
        child: ClipRect(child: Align(alignment: AlignmentDirectional.centerStart, child: child)),
      );
}

/// The templates a new entry can start from, under New entry (`TemplateChoice`, `.choose`): a card, a row a
/// template, its name over the line it starts with. The journal's usual one is first and says so.
class _TemplateChoice extends StatelessWidget {
  const _TemplateChoice({required this.usual, required this.journal, required this.now, required this.onPick, required this.onCancel});

  final String usual;
  final String journal;
  final DateTime now;
  final ValueChanged<String> onPick;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final em = t.len('app-body');
    final xs = t.fontSize('xs');
    final sm = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final line = snapBorder(context, t.len('glacier-hairline'));
    final starts = entryStarts(usual);
    final card = Semantics(
      container: true,
      label: 'Start the entry with',
      child: Container(
        key: const ValueKey('journal-choose'),
        // `.choose { padding: var(--glacier-space-2); border: var(--glacier-hairline) solid subtle;
        // border-radius: var(--glacier-radius-lg); background: 3% of the ink }`
        decoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-subtle'), width: line), borderRadius: BorderRadius.circular(t.radius('lg')), color: _ink(t, 0.03)),
        padding: EdgeInsets.all(t.space(2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              // `.chooseTitle { margin: var(--glacier-space-1) var(--glacier-space-2) var(--glacier-space-2);
              // font-size: xs; font-weight: bold; letter-spacing: 0.08em; text-transform: uppercase; color: subtle }`
              padding: EdgeInsets.fromLTRB(t.space(2), t.space(1), t.space(2), t.space(2)),
              child: Semantics(
                label: 'Start the entry with',
                child: ExcludeSemantics(child: cssLines('START THE ENTRY WITH', bookText(t, xs, weight: 'bold', color: t.color('glacier-text-subtle'), tracking: 0.08 * xs))),
              ),
            ),
            for (final start in starts)
              GlacierPressable(
                key: ValueKey('journal-start:${start.id}'),
                semanticLabel: '${start.name}${start.id == 'usual' ? ', usual' : ''}. ${startLine(start.text, journal, now)}',
                excludeSemantics: true,
                onPressed: () => onPick(start.text),
                builder: (context, state) => DecoratedBox(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('md')), color: state.hovered || state.focused ? _ink(t, 0.06) : null),
                  child: Padding(
                    // `.start { display: grid; gap: 2px; padding: var(--glacier-space-2) }`
                    padding: EdgeInsets.all(t.space(2)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: [
                        // `.startName { display: flex; align-items: center; gap: var(--glacier-space-2);
                        // font-weight: semibold; color: var(--app-ink) }`
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: t.space(2),
                          children: [
                            Flexible(child: cssLines(start.name, bookText(t, em, weight: 'semibold', color: t.color('app-ink')))),
                            if (start.id == 'usual')
                              // `.usual { padding: 0 0.5em; border-radius: 999px; font-size: xs; font-weight: medium;
                              // color: muted; background: 8% of the ink }`
                              DecoratedBox(
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: _ink(t, 0.08)),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 0.5 * xs),
                                  child: cssLines('Usual', bookText(t, xs, weight: 'medium', color: muted), maxLines: 1, softWrap: false),
                                ),
                              ),
                          ],
                        ),
                        // `.startLine { text-overflow: ellipsis; white-space: nowrap; font-size: sm; color: muted }`
                        cssLines(startLine(start.text, journal, now), bookText(t, sm, color: muted), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GlacierPressable(
                key: const ValueKey('journal-choose-cancel'),
                semanticLabel: 'Cancel',
                excludeSemantics: true,
                onPressed: onCancel,
                builder: (context, state) => Padding(
                  // `.app-word { padding: var(--glacier-space-2) 0; font-weight: medium; color: muted }`, and
                  // `.cancel { min-block-size: 0; margin-inline-start: var(--glacier-space-2); font-size: sm }`.
                  padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), 0, t.space(2)),
                  child: cssLines('Cancel', bookText(t, sm, weight: 'medium', color: state.pressed ? t.color('glacier-text') : muted), maxLines: 1, softWrap: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // The back gesture folds the choice before it leaves the journal, as the find bar and the palette take it first.
    return OnBack(
      onBack: onCancel,
      child: CssFlow.block(
        // `.choose { margin-block: 0 var(--glacier-space-4) }`
        margin: EdgeInsets.only(bottom: t.space(4)),
        // `animation: choose-in 200ms var(--glacier-ease-out) both`: from clear and 4px up.
        child: t.reducedMotion
            ? card
            : TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: card,
                builder: (context, at, child) => Opacity(opacity: at, child: Transform.translate(offset: Offset(0, -4 * (1 - at)), child: child)),
              ),
      ),
    );
  }
}

// ---- what New entry does to the library (App.tsx) -----------------------------------------------------------------

/// The library's half of a journal's page: New entry as `src/app/App.tsx` makes one (`newEntry`, `makeEntry`,
/// `writeJournal`). The entry's name is this minute's, unique against every note and every line the journal has;
/// its words are the template chosen, else the journal's own, filled for the minute; its line goes into the
/// journal's index, and the note is made with its `title:` and `date:`.
class JournalPages {
  JournalPages(this.library, {this.untouched, this.clock, this.write, Set<String>? making}) : making = making ?? {};

  final NoteLibrary library;

  /// Where an entry nobody has written in yet is remembered, to be taken back once it is left (core/untouched.ts).
  final UntouchedNotes? untouched;
  final DateTime Function()? clock;

  /// The open journal's own writer, where it is the note on screen (`journalWriter`): its index is changed through
  /// its editor's saving, not behind it. Answers whether it took the change.
  final bool Function(String journalId, String Function(String body) change)? write;

  /// Entries being made now (`making`): the take-back (lib/root/take_back.dart) leaves them alone until they are on
  /// screen. An id is put in as its record is written, and taken out by whoever opens the entry, or here where it
  /// could not be made.
  final Set<String> making;

  /// A New entry being made: a second press before it is open is the same press.
  bool _entering = false;

  /// Makes an entry in the journal [journalId], from [template] or the journal's own, and answers its note; null
  /// where the journal is gone, is not one, or an entry is already being made (`newEntry`).
  Future<Note?> newEntry(String journalId, {String? template}) async => (await _make(journalId, template: template, spoken: false))?.note;

  /// An entry to be said aloud (`makeEntry` with `speak`): made as [newEntry] makes one, its template's last line
  /// taken off until the words come, with where they go on from (core/template.dart `openEnd`).
  Future<({Note note, Placing placing})?> newSpokenEntry(String journalId) async {
    final made = await _make(journalId, spoken: true);
    return made == null ? null : (note: made.note, placing: made.placing!);
  }

  Future<({Note note, Placing? placing})?> _make(String journalId, {String? template, required bool spoken}) async {
    if (_entering) return null;
    _entering = true;
    try {
      final journal = await library.get(journalId);
      if (journal == null || !isJournalBody(journal.body)) return null;
      final name = noteTitle(journal.body);
      final now = clock?.call() ?? DateTime.now();
      await library.refresh().catchError((Object _) {});
      final taken = {
        for (final note in library.value) titleKey(noteTitle(note.body)),
        for (final chapter in chaptersOf(journal.body)) titleKey(chapter.title),
      };
      final title = uniqueTitle(entryTitle(now), taken);
      final filled = fillTemplate(template ?? templateOf(journal.body), at: now, title: title, journal: name);
      // Spoken, the words go on from the template's last line, which is taken off until they come.
      final open = spoken ? openEnd(filled) : null;
      final words = open?.base ?? filled;
      // The record first, then the line, then the note, so that an app let go at any step leaves a record the
      // take-back can finish from.
      final id = randomId();
      making.add(id);
      try {
        untouched?.remember(id, UntouchedRecord(journalId: journalId, title: title, words: words, at: now.millisecondsSinceEpoch));
        await writeJournal(journalId, (body) => withEntry(body, title));
        final note = await library.createNote(entryBody(title, localStamp(now), words), id: id);
        await library.refresh().catchError((Object _) {});
        return (note: library.noteOf(note.id) ?? note, placing: open?.placing);
      } catch (_) {
        making.remove(id);
        rethrow;
      }
    } finally {
      _entering = false;
    }
  }

  /// The journal's index changed (`writeJournal`): through the open journal's own writer where it has one, else
  /// read fresh and saved.
  Future<void> writeJournal(String journalId, String Function(String body) change) async {
    if (write?.call(journalId, change) ?? false) return;
    final fresh = await library.get(journalId);
    if (fresh == null) return;
    final next = change(fresh.body);
    if (next == fresh.body) return;
    await library.save(journalId, next);
  }
}
