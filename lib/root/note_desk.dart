/// One open note's editor, put together: what `src/app/editor/NoteScreen.tsx` and `Editor.tsx` do between them
/// once every piece of the editor exists. The note's screen (lib/note/note_screen.dart) is given an editor builder
/// and its seams; this makes both for one note and keeps what they share for as long as the note is open.
///
/// What is here, each from its own piece:
/// - the editor that is typed in (lib/editor/editor_widget.dart `Editor`), over the view lib/note's host keeps,
///   with every piece's extensions in one list made once: the input, the twelve marks and the five effects with
///   typing's smoke, the inline items with links between notes and the hint in an open first heading, drawn tables,
///   boards drawn as boards (lib/editor/boards), a ticket's panel and its keys' titles (lib/editor/tickets), a
///   ```query drawn as what it finds (lib/editor/queries), links, pictures and media, the + beside an empty line,
///   and find's marks; the queries and the tickets are drawn again whenever the library changes;
/// - the press-and-hold band (lib/editor/band), opened by the editor's own hold, with the marks on its Style page,
///   a list item's fields as its pages, and its rows for boards;
/// - the + and its list (lib/editor/plus), with the effects as rows, every note's title for A note, and a board, a
///   database and Make this a ticket;
/// - what takes the page for a note that is not words: the canvas (lib/canvas), a notebook's index and a journal's
///   entries (lib/book), and the bar and the foot a notebook's page wears;
/// - a tapped chip's menu (lib/editor/items `FieldMenuHost`);
/// - find and replace (lib/editor/find_bar), from the More sheet and from the band, resting on the keyboard;
/// - the bookmark (lib/editor/items `NoteBookmark`), the cheat sheet's page, and a note's sharing where the build
///   has an account.
///
/// - what a recording just wrote into the note, said with an Undo for ten seconds (`editor/useLanding.ts`): the
///   Undo is an edit in this editor, taking out exactly the pieces the recording put in, and the better words wait
///   to write the note while it is open, the editor being its one writer.
///
/// What differs from the page:
/// - **No picture can be added yet**: this build has no picker, so the band's Add image and the +'s Picture are
///   not offered. Pictures a note already names are drawn from the kept files.
/// - **No place, film or voice memo is added** from the + (no location, no player): their rows are not offered.
/// - **A link's tap** is handed to the phone where the build has a way to ([NoteDeskWorld.openLink], lib/core/open_link.dart);
///   a test, and a run with no phone half, opens nothing.
/// - **A date is not picked from a calendar** (`dayPicker` is not given): Today, Tomorrow and Next week are.
/// - **A canvas has no picture picker and no comments**, for the same reasons; a team's canvas is
///   piece 6G. A canvas is not framed in a note from the + (`AddConfig.canvases` is not given).
/// - **A landing's writes to other notes are not reversed by its Undo** (`undo_command`): the store here keeps no
///   log of a command's change (lib/capture/recorder.dart `LibraryRecorderStore`), so each is counted as changed
///   since and the toast says so. A tag waiting for the words is not let go (no note keeps a place yet).
/// - **A spoken instruction and a review the note opened with** ([NoteDesk.ask], [NoteDesk.review]) are carried
///   and not run: they are `NoteAi`'s (lib/ai/note_ai.dart), which is not on the desk yet.
/// - **A board's card has no plugin's rows** (`drawnBoards(actions:)`).
/// - **The plugins reach the note through the editor** (lib/editor/items/note_plugins.dart): a swipe on a list item
///   and the quiet words after a line are asked of the app's registry as they are used, a linked to-do's box and
///   its task are kept in step, a linked row opens its menu, and what the note is linked to is drawn at its top
///   (lib/plugins/link_marks.dart), its press the note's More sheet. The More sheet's own "Linked to" rows
///   (`NoteSeams.linked`, each plugin's page) are not given.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:glacier/glacier.dart' show GlacierToast, GlacierToastAction, GlacierToastController;
import '../account/ui_state.dart';
import '../art/lucide.g.dart';
import '../book/book_nav.dart';
import '../book/book_view.dart';
import '../book/journal_view.dart';
import '../canvas/canvas_view.dart';
import '../capture/landing.dart';
import '../core/book.dart';
import '../core/canvas_body.dart';
import '../core/images.dart';
import '../core/link_preview.dart' show LinkOpener, LinkPreviewer, noLinkPreviews;
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/preferences.dart';
import '../core/query/query.dart';
import '../editor/band/band.dart' as band;
import '../editor/boards/boards.dart' show drawnBoards;
import '../editor/editor.dart';
import '../editor/editor_widget.dart';
import '../editor/find_bar/find_bar.dart';
import '../editor/find_bar/find_marks.dart';
import '../editor/items/items.dart';
import '../editor/marks/marks.dart';
import '../editor/media/media.dart';
import '../editor/plus/plus.dart';
import '../editor/queries/queries.dart';
import '../editor/tables/tables.dart';
import '../editor/tickets/tickets.dart';
import '../editor/view/editor_view.dart';
import '../note/note_editor.dart';
import '../note/note_place.dart';
import '../note/note_screen.dart';
import '../plugins/link_marks.dart';
import '../plugins/types.dart' show NoteEditing;
import '../notes/note_templates.dart' show NoteTemplate;
import '../settings/panes/cheat_sheet.dart';
import '../shell/screen.dart' show Keyed;
import '../share/ui/share_rows.dart';

/// The marks as the band's Style page lists them: each under its own icon (`format.icon ?? plugin.icon ?? Type`).
final List<band.BandFormat> bandFormats = <band.BandFormat>[
  for (final mark in marks) band.BandFormat.of(mark, Lucide.all[mark.icon] ?? Lucide.type),
];

/// The effects as the +'s list offers them, at More's end.
final List<PlusEffect> plusEffects = <PlusEffect>[
  for (final mark in marks)
    if (mark.look is EffectLook) PlusEffect(name: mark.name, delimiter: mark.delimiter, cue: mark.cue, icon: Lucide.all[mark.icon]),
];

/// A list item's fields as the band's pages: lib/editor/items' rows (`fieldItems`), drawn as the band's own.
final band.BandFields bandFields = band.BandFields(
  items: (context, request) {
    final page = switch (request.page) {
      band.FieldDatePage(:final key) => DatePage(key),
      band.FieldPriorityPage() => const PriorityPage(),
      band.FieldPersonPage(:final name) => PersonPage(name),
      band.FieldAssignPage() => const AssignPage(),
    };
    final items = fieldItems(request.view, request.line, page, onBack: request.onBack, onClose: request.onClose, refocus: request.refocus, redraw: request.redraw, today: request.view.state.facet(fieldsToday)?.call());
    return <Widget>[
      for (final (at, item) in (items ?? const <FieldItem>[]).indexed)
        Builder(
          key: ValueKey<String>(at == 0 && request.onBack != null ? 'back' : 'field:${item.label}'),
          builder: (context) => band.BandItemBox(
            icon: item.icon,
            label: item.label,
            name: item.name,
            lit: item.lit ?? false,
            checkbox: item.lit != null,
            onPress: () {
              final box = context.findRenderObject();
              item.onPress(box is RenderBox && box.attached ? box.localToGlobal(Offset.zero) & box.size : Rect.zero);
            },
          ),
        ),
    ];
  },
);

/// What a desk asks of the app: the notes by their titles, and what the build can do.
@immutable
class NoteDeskWorld {
  const NoteDeskWorld({
    required this.titles,
    required this.known,
    required this.open,
    this.bodyOf,
    this.pictures,
    this.services,
    this.changes,
    this.queryNotes,
    this.openAt,
    this.write,
    this.addTicket,
    this.tickets,
    this.openWithin,
    this.openCanvas,
    this.openPage,
    this.openTicket,
    this.ticketTemplates,
    this.pageTitles,
    this.noteOf,
    this.newEntry,
    this.openLink,
    this.previewer,
    this.holdNote,
    this.dropRefine,
  });

  /// Every note's title, for the +'s A note.
  final List<String> Function() titles;

  /// Whether a note by that title exists, and the way to it, made first where there is none.
  final bool Function(String title) known;
  final void Function(String title, [String? anchor]) open;

  /// A note's words by its title, for what a link draws of it.
  final String? Function(String title)? bodyOf;

  /// The kept pictures; null where there is no core to keep them.
  final PictureStore? pictures;

  /// The account, where the build has one: a note's sharing is drawn with it.
  final AccountServices? services;

  /// Says when the library changed: every query and every ticket's panel in the open note is drawn again.
  final Listenable? changes;

  /// The library a ```query reads (lib/root/library_reads.dart); absent, a query is drawn as its lines.
  final List<QueryNote> Function()? queryNotes;

  /// A note a query listed, opened: the note itself, or a to-do's note at its line, from 0.
  final void Function(String noteId, int? line)? openAt;

  /// Another note's words changed from this one: a to-do ticked in a query, a card dragged to another lane, a
  /// page's status picked in its notebook's index.
  final void Function(String noteId, NoteChange change)? write;

  /// A ticket typed at the + of a lane of a query's board (App.tsx `addFromQuery`).
  final Future<bool> Function(TicketDraft draft, String title, String? from)? addTicket;

  /// What a ticket's panel and a `[[GHO-12]]` are drawn with, for the note by that id; absent, the front matter is
  /// folded as any note's is.
  final TicketOptions Function(String noteId)? tickets;

  /// A title opened from inside a notebook, in its tab's place (`openTitleWithin`); [open] where it is left out.
  final void Function(String title)? openWithin;

  /// A canvas, a page from a template and a ticket made from a notebook's index and opened in its tab
  /// (`openCanvasWithin`, `openPageWithin`, `openTicketWithin`, which is handed the notebook's words).
  final void Function(String title)? openCanvas;
  final void Function(String title, String template)? openPage;
  final void Function(String title, String notebook, NoteTemplate? template)? openTicket;

  /// The templates New ticket offers.
  final List<NoteTemplate> Function()? ticketTemplates;

  /// What can be a page of a notebook: every title but a journal's entries'; [titles] where it is left out.
  final List<String> Function()? pageTitles;

  /// The note by its title, for a journal's entries: when each was written, where, and how it starts.
  final Note? Function(String title)? noteOf;

  /// A journal's New entry, from the template chosen for it.
  final void Function(String journalId, String template)? newEntry;

  /// Hands a web address to the phone (`openLink`): a link card's tap, and a canvas's link card. Absent, a tap
  /// opens nothing.
  final LinkOpener? openLink;

  /// What knows the titles of linked pages (lib/core/link_preview.dart `KeptLinkPreviews`); absent, a link's card
  /// says its site and its path.
  final LinkPreviewer? previewer;

  /// The better words' queue told a note is open, so it waits to write it, and told to drop what it has queued for
  /// words an Undo took out (lib/capture/refine.dart `holdNote`, `dropRefine`). Absent, there is no queue.
  final void Function(String noteId, bool on)? holdNote;
  final void Function(String noteId, int fromMs)? dropRefine;
}

/// Builds a note's screen with the editor and the seams the desk made for it.
typedef NoteDeskBuilder = Widget Function(BuildContext context, NoteEditorBuilder editor, NoteSeams seams);

/// The editor and everything round it for one open note. Keyed by the note by whoever builds it, so each note
/// has its own.
class NoteDesk extends StatefulWidget {
  const NoteDesk({super.key, required this.noteId, required this.title, required this.world, required this.say, required this.builder, this.prefs, this.readOnly = false, this.landing, this.ask, this.review});

  final String noteId;

  /// The note's own title, which its + does not link to.
  final String title;
  final NoteDeskWorld world;

  /// A toast.
  final void Function(String message) say;
  final NoteDeskBuilder builder;

  /// The preferences; the app's own unless given.
  final PreferencesStore? prefs;

  /// A note in the Trash: its canvas and its index are read, not changed.
  final bool readOnly;

  /// What a recording just wrote into this note (a [CaptureLanding]), with the number that tells one landing from
  /// the next: said with its Undo as the note opens.
  final Keyed? landing;

  /// A spoken instruction about this note and the review a recording handed it, as the note was opened with them.
  final Keyed? ask;
  final Keyed? review;

  @override
  State<NoteDesk> createState() => NoteDeskState();
}

class NoteDeskState extends State<NoteDesk> {
  final EditorController _editor = EditorController();
  final band.ContextBandController _band = band.ContextBandController();
  late final PlusController _plus = PlusController(allowed: _plusAllowed);

  EditorView? _view;
  NoteBookmark? _bookmark;

  /// Find and replace, while it is up: what it opened searching for, and which opening it is.
  ({String initial, int nonce})? _finding;
  int _finds = 0;

  PreferencesStore get _prefs => widget.prefs ?? preferences;
  NoteDeskWorld get _world => widget.world;

  /// The editor's controller, for a test or a diagnostic.
  EditorController get editor => _editor;

  /// The band's controller.
  band.ContextBandController get bandController => _band;

  /// Whether find and replace is up.
  bool get finding => _finding != null;

  /// Every piece's extensions, once: another list would be another editor (lib/note/note_editor.dart).
  late final List<Extension> _extensions = <Extension>[
    editorInput(),
    markExtensions(marks, wispTyping: true),
    itemExtensions(
      wiki: WikiOptions(known: (title) => _world.known(title), open: (title, [anchor]) => _world.open(title, anchor), body: (title) => _world.bodyOf?.call(title)),
      openHeading: true,
      // A swipe on an item, and the words offered after a line: the plugins', asked as they are used, so one
      // switched on or off is followed without another editor.
      swipe: () => itemSend(widget.noteId, _editing),
      suggest: (body) => lineOffers(widget.noteId, _editing, body),
      doneSyncs: true,
    ),
    drawnTables(),
    // Boards drawn as boards, the fence still there to edit (Editor.tsx `drawnBoards()`).
    drawnBoards(),
    // A ticket's front matter as its properties, and a [[GHO-12]] with the ticket's title.
    if (_world.tickets != null) tickets(() => _world.tickets?.call(widget.noteId)),
    // A ```query fence drawn as what it finds in the library: its lines where there is none.
    if (_world.queryNotes != null) queries(() => _queries),
    mediaExtensions(
      seams: MediaSeams(
        pictures: _world.pictures,
        openLink: _world.openLink,
        linkMenus: LinkMenus(say: (message) => widget.say(message)),
        previewer: _world.previewer ?? noLinkPreviews,
        linkPreviews: () => _prefs.value.linkPreviews,
        switches: _prefs,
      ),
    ),
    _plus.extension,
    findBarExtensions,
  ];

  /// The note as a plugin changes it: through the editor, so each change is one undo and saves like typing.
  NoteEditing get _editing => noteEditing(widget.noteId, _view, () => _view?.state.doc.toString() ?? '', (message) => widget.say(message));

  /// What the open note's queries read and do (shell/useQueries.ts): the library, a row opened, another note's
  /// to-do ticked or its field set, and a ticket typed at a lane's +.
  late final QueryOptions? _queries = _world.queryNotes == null
      ? null
      : QueryOptions(
          notes: () => _world.queryNotes!(),
          noteId: widget.noteId,
          open: (id, line) => _world.openAt?.call(id, line),
          write: (id, change) => _world.write?.call(id, change),
          add: _world.addTicket == null ? null : (draft, title, from) => _world.addTicket!(draft, title, from),
        );

  @override
  void initState() {
    super.initState();
    _world.changes?.addListener(_libraryChanged);
    // While the note is open the better words wait to write it: the editor is its one writer.
    _world.holdNote?.call(widget.noteId, true);
    _land();
  }

  GlacierToastController? _toasts;
  int? _landed;
  bool _saidLanding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _toasts = GlacierToast.of(context);
  }

  /// A note opened by the recording that just wrote into it: "Added to House TODOs", with an Undo, for ten seconds
  /// (`useLanding`). One toast for each landing, told apart by its key; said once the first frame is drawn.
  void _land() {
    final keyed = widget.landing;
    final landing = keyed?.value;
    if (keyed == null || landing is! CaptureLanding || keyed.key == _landed) return;
    _landed = keyed.key;
    if (landing.noteId != widget.noteId || (landing.blocks.isEmpty && landing.others.isEmpty)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _saidLanding = true;
      _toasts?.toast(
        message: Text(landingLine(landing)),
        duration: const Duration(seconds: 10),
        action: GlacierToastAction(label: 'Undo', onPress: () => _undoLanding(landing)),
      );
    });
  }

  /// The Undo: exactly the pieces of text the recording put in, found where they were written and taken out as one
  /// edit, which the note's own saving writes like typing and the editor's undo can bring back. A piece edited
  /// since is left alone, and the toast says so. The tape is never touched.
  void _undoLanding(CaptureLanding landing) {
    var missing = 0;
    var removed = false;
    final view = _view;
    if (landing.blocks.isNotEmpty) {
      if (view != null) {
        final out = takeOut(view.state.doc.toString(), landing.blocks);
        missing = out.missing;
        if (out.changes.isNotEmpty) {
          view.dispatch(TransactionSpec(changes: ChangeSet.of([for (final change in out.changes) ChangeSpec(from: change.from, to: change.to, insert: '')], view.state.doc.length), userEvent: 'delete'));
          removed = true;
        }
      } else {
        missing = landing.blocks.length;
      }
    }
    // Writes the recording made to other notes cannot be reversed here (see the header): each has changed since, as
    // far as this can tell.
    missing += landing.others.length;
    // Only for words taken out of this note: the better words of what stays in it still come.
    final fromMs = landing.fromMs;
    if (removed && fromMs != null) _world.dropRefine?.call(widget.noteId, fromMs.toInt());
    if (missing > 0) {
      // After the pressed toast has gone, which pressing its action does just after this returns.
      scheduleMicrotask(() {
        if (mounted) _toasts?.toast(message: Text('${landing.title} has changed since, so it was left as it is.'), duration: const Duration(seconds: 5));
      });
    }
  }

  @override
  void didUpdateWidget(NoteDesk oldWidget) {
    super.didUpdateWidget(oldWidget);
    _land();
    if (identical(oldWidget.world.changes, _world.changes)) return;
    oldWidget.world.changes?.removeListener(_libraryChanged);
    _world.changes?.addListener(_libraryChanged);
  }

  /// The library changed: any note changed may change what a query finds, and another ticket closed or a person
  /// named changes a panel (Editor.tsx's two effects). Told after the frame where one is being built.
  void _libraryChanged() {
    void tell() {
      final view = _view;
      if (!mounted || view == null) return;
      view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[if (_world.queryNotes != null) refreshQueries.of(null), if (_world.tickets != null) refreshTickets.of(null)]));
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      tell();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => tell());
    }
  }

  /// A + may show: a note of words that can be written, with find put away.
  bool _plusAllowed() {
    final view = _view;
    if (view == null || view.state.readOnly || _finding != null) return false;
    final doc = view.state.doc.toString();
    return !isCanvasBody(doc) && !isBookBody(doc);
  }

  @override
  void dispose() {
    _world.holdNote?.call(widget.noteId, false);
    // Leaving the note takes its toast with it: an Undo for words no longer on screen would undo them unseen.
    if (_saidLanding) _toasts?.dismiss();
    _world.changes?.removeListener(_libraryChanged);
    _bookmark?.dispose();
    _band.dispose();
    _plus.dispose();
    super.dispose();
  }

  /// The view the seams were last handed: what belongs to a view is made again for another.
  void _adopt(EditorView view) {
    if (identical(view, _view)) return;
    _view = view;
    _bookmark?.dispose();
    _bookmark = NoteBookmark(view: view, say: widget.say)..addListener(_redraw);
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _openFind(EditorView view, String initial) {
    _band.close();
    _plus.close();
    setState(() => _finding = (initial: initial, nonce: _finds += 1));
    _plus.recheck(view);
  }

  void _closeFind() {
    if (_finding == null || !mounted) return;
    setState(() => _finding = null);
    final view = _view;
    if (view != null) _plus.recheck(view);
  }

  Widget _buildEditor(BuildContext context, NoteEditorSpec spec) => NoteEditorHost(
        spec: spec,
        formats: marks,
        extensions: _extensions,
        draw: (context, view, env) => Editor(
          view: view,
          controller: _editor,
          env: env,
          meHue: spec.meHue,
          footClear: spec.footClear,
          headerInset: spec.headClear,
          // The paper under a short note is the screen's own last sliver (lib/note/note_screen.dart), which puts the
          // caret at the end; were the editor to fill the page too, the page's foot would make a short note scroll.
          fill: false,
          // A press held: the note's own menu over the caret, in place of the phone's.
          onHold: (held) => _band.open(band.Held(x: held.x, y: held.y, from: held.from, to: held.to)),
        ),
      );

  /// The page inside the layers that hear it scroll. The same widgets with a view and without, so the page keeps
  /// its place in the tree (and its scroll position) when the editor's view arrives.
  Widget _around(BuildContext context, EditorView? view, Widget page) {
    if (view != null) _adopt(view);
    return FieldMenuHost(
      view: view,
      child: PlusLayer(
        view: view,
        controller: _plus,
        config: AddConfig(titles: _world.titles, own: widget.title, localOnly: _prefs.value.localOnly, effects: plusEffects, boards: true, databases: _world.queryNotes != null, tickets: _world.tickets != null),
        child: band.ContextBand(
          view: view,
          controller: _band,
          say: widget.say,
          onFind: view == null ? null : (text) => _openFind(view, text),
          formats: bandFormats,
          fields: bandFields,
          boards: true,
          child: page,
        ),
      ),
    );
  }

  List<Widget> _over(BuildContext context, EditorView view) {
    _adopt(view);
    final finding = _finding;
    return <Widget>[
      if (finding != null)
        Positioned(
          left: 0,
          right: 0,
          // On top of the keyboard: the page does not shorten for it, so the bar is lifted by what it covers.
          bottom: MediaQuery.viewInsetsOf(context).bottom,
          child: FindBar(key: ValueKey<int>(finding.nonce), view: view, initial: finding.initial, onClose: _closeFind),
        ),
    ];
  }

  ({bool marked, VoidCallback onPress}) _bookmarkOf(EditorView view, ScrollPosition page) {
    _adopt(view);
    final mark = _bookmark!;
    return (marked: mark.marked, onPress: mark.press);
  }

  /// The bookmark written in the note, as the place to open at: the top of its line.
  Place? _writtenBookmark(EditorView view) {
    final line = bookmarkLineIn(view.state.doc.toString());
    if (line == null || line > view.state.doc.lines) return null;
    return Place(view.state.doc.line(line).from, 0);
  }

  void _openWithin(String title) => (_world.openWithin ?? _world.open)(title);

  /// A page's ticket status picked in its notebook's index, written into that page through the queries' writer
  /// (lib/core/query/move.dart), which reads the library again after.
  void _setStatus(String page, String? status) {
    final key = titleKey(page);
    for (final note in _world.queryNotes?.call() ?? const <QueryNote>[]) {
      if (titleKey(noteTitle(note.body)) != key) continue;
      _world.write?.call(note.id, (body) => movedBody(body, -1, '', RecordKind.ticket, 'status', status));
      return;
    }
  }

  /// A notebook's index (book/BookView.tsx), in place of its Markdown.
  Widget _book(BuildContext context, String body, ValueChanged<String> onChange) => BookView(
        body: body,
        title: noteTitle(body),
        known: _world.known,
        open: _openWithin,
        openCanvas: widget.readOnly ? null : _world.openCanvas,
        openNew: widget.readOnly ? null : _world.openPage,
        openTicket: widget.readOnly || _world.openTicket == null ? null : (title, template) => _world.openTicket!(title, body, template),
        ticketTemplates: _world.ticketTemplates?.call() ?? const <NoteTemplate>[],
        titles: _world.pageTitles ?? _world.titles,
        bodyOf: _world.bodyOf,
        spot: widget.noteId,
        setStatus: widget.readOnly || _world.write == null ? null : _setStatus,
        readOnly: widget.readOnly,
        onChange: onChange,
      );

  /// A journal's entries by month (book/JournalView.tsx).
  Widget _journal(BuildContext context, String body, ValueChanged<String> onChange) => JournalView(
        body: body,
        noteOf: (title) => _world.noteOf?.call(title),
        known: _world.known,
        open: _openWithin,
        onNewEntry: widget.readOnly || _world.newEntry == null ? null : (template) => _world.newEntry!(widget.noteId, template),
        onChange: onChange,
      );

  @override
  Widget build(BuildContext context) {
    final services = _world.services;
    final seams = NoteSeams(
      onFind: _openFind,
      bookmark: _bookmarkOf,
      writtenBookmark: _writtenBookmark,
      cheatSheet: (context) => const CheatSheet(),
      // A share is kept with an account: no rows in a build that has none.
      sharingSection: services == null ? null : (context) => ShareRows(services: services, noteId: widget.noteId),
      // A page's notebook, its place in it and the pages either side, over and under its words.
      bookBar: (context, place) => BookBar(place: place, open: _openWithin),
      bookFoot: (context, place) => BookFoot(place: place, open: _openWithin),
      // A change to the canvas is a change to the note: written into the body as the spec's JSON, and saved the way
      // typing is.
      canvas: canvasSeam(
        wiki: CanvasWiki(known: _world.known, open: _world.open, body: _world.bodyOf, titles: _world.titles),
        pictures: _world.pictures,
        openLink: _world.openLink,
        readOnly: widget.readOnly,
      ),
      // What the note is linked to, at its top; pressed, the note's More sheet, where a link is changed.
      head: (context, openSettings) => <Widget>[LinkMarks(noteId: widget.noteId, onPress: openSettings)],
      book: _book,
      journal: _journal,
      around: _around,
      over: _over,
    );
    return widget.builder(context, _buildEditor, seams);
  }
}
