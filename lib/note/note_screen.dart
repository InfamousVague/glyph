/// One note, open: the words in their editor, and everything that floats over or beside them. A port of
/// `src/app/editor/NoteScreen.tsx` with `NoteScreen.module.css`.
///
/// This screen owns SAVING: the words are kept by a [NoteSaving] (lib/core/library.dart, the port of
/// `useNoteSaving`), saved on a debounce, and flushed on every way the app can go away and every way off the note
/// this screen offers. Everything that changes the open note goes through the editor's view or [_onChange], never
/// round them.
///
/// One screen shows several things in one place: the note's words, or, for a note that is a canvas or a book, the
/// canvas drawn or the book's index, with the JSON or Markdown behind the view switch. The editor stays mounted
/// behind whichever of the others is up, hidden, so nothing typed is lost and its caret keeps its place.
///
/// What is here, as on the page: the header's glass with the page's smoke under it; the page that scrolls, padded
/// by the header; the byline; the editor filling the page; the note's tools, in the app's bar where there is one
/// and in this header where there is not; the More sheet with its pages; saving; the look, the name and a version
/// put back, each written through the editor as one change; landing at an item (`at`); opening where the note was
/// left; two fingers pinching the text's size; the caret asked for in a note just made; the blank note's ghost.
///
/// What differs from the page:
/// - **The editor is a seam** (lib/note/note_editor.dart): the screen is given a [NoteEditorBuilder] and works
///   through the `EditorView` it is told of. Until piece D's widget is wired the builder is the stand-in, which
///   draws and takes the screen's own changes but has no caret.
/// - **What other pieces and stages own comes in through [NoteSeams]**, each nullable, each named for the web file
///   it ports: find, the bookmark, comments, sharing, the AI, plugins' links, the place and its map card, the
///   book's bar and foot, and the canvas, book and journal views, each drawn only where it is given (lib/root gives
///   all three). The tape and its transcript, the AI's strip, the models' scene, live and team notes and pull to
///   refresh are not drawn at all yet.
/// - **The blank page's names and template cards are a sliver under the editor**, where the page drew them in a
///   block after line 1 inside it (editor/nameChips.ts): a note with no words is its one empty line, so under the
///   editor is under that line, and the page scrolls them with it. They wait for what the page's waited for: the
///   editor focused, and the page ready for words (a device with no keyboard on the screen, the keyboard up, or a
///   press of the person's own ended on the page). A map at the top's card is offered where the note keeps a place
///   ([NoteScreen.tags]).
/// - **A note keeping its place** is this screen's, as it is the page's, over what the app hands it
///   ([NoteScreen.tags], lib/core/place_tags.dart): the tag its words carry or the one waiting to be written, the
///   box held for a fix on its way, Add my location and Remove location, a name arriving. The card itself is a seam
///   ([NoteSeams.mapCard]), since the tiles and the way to the phone's maps are the app's.
/// - **The tools are handed to the bar**, not put there by a portal (shell/top_bar_tools.dart), so they listen to a
///   model this screen changes.
/// - **The page is a scroll view of slivers**: the page's padding, the byline and the editor are slivers of one
///   `CustomScrollView`, where the page was a flex column that scrolled. The scroll view is padded by what the
///   keyboard covers, since nothing above this screen shortens the window for it. The body's `flex: 1 0 auto` (the editor as
///   tall as the page at least) is a last sliver that fills what is left and gives the editor the focus on a tap.
/// - **`--wisp-under` is always the header's height**. The page falls back to 3.6rem with the smoke switched off,
///   which puts the byline under the bar (measured 2026-10-07: 79.9 against a pane 91.8 tall); that is not carried.
/// - **A note in the Trash** is [NoteScreen.readOnly]: its editor takes no typing and nothing is saved. The page
///   has no such state, since it never opens one.
/// - **A save refused for good** is said in the note's one line of problems (`.problem`), under the header, for as
///   long as the note is open; the page only logs it.
/// - The arrival (`noteRise`: the body rising 8px as it fades in) is drawn for the page as a whole.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/book.dart';
import '../core/boards/make.dart';
import '../core/canvas_body.dart';
import '../core/front_matter.dart';
import '../core/geotag.dart';
import '../core/library.dart';
import '../core/live_titles.dart';
import '../core/look.dart';
import '../core/note.dart';
import '../core/note_names.dart';
import '../core/place_tags.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../core/unfold.dart';
import '../core/untouched.dart';
import '../core/versions_file.dart';
import '../core/versions_record.dart';
import '../core/workspaces.dart';
import '../book/book_spot.dart' show ChapterSpot, writeBookSpot;
import '../book/journal.dart' show JournalWriter;
import '../book/tickets.dart' show withNotebookKey;
import '../ai/note_review.dart' show onReviewHandedBack;
import '../core/location.dart' show whyLocateFailed;
import '../editor/editor.dart';
import '../editor/looks/look.dart' show LookEnv;
import '../editor/media/map_card.dart' show MapPicture, MapSize;
import '../editor/view/editor_view.dart';
import '../editor/view/view_mode.dart';
import '../notes/note_templates.dart' show NoteTemplate, fillNoteTemplate;
import '../notes/template_cards.dart';
import '../shell/header_pane.dart';
import '../shell/screen.dart' show Caret;
import '../shell/top_bar_tools.dart';
import '../sheet/css.dart';
import 'byline.dart';
import 'land_at.dart';
import 'note_editor.dart';
import 'note_place.dart';
import 'note_settings.dart';
import 'note_tools.dart';
import 'pinch_zoom.dart';
import 'version_keeping.dart';

/// What the screen is given by pieces and stages that are not its own. Every one is optional: left out, its row,
/// its tool or its drawing is simply not there, or is a card that says which stage draws it.
@immutable
class NoteSeams {
  const NoteSeams({
    this.onFind,
    this.onShare,
    this.sharing,
    this.sharingSection,
    this.onComment,
    this.commentsSummary,
    this.onCommentsList,
    this.bookmark,
    this.writtenBookmark,
    this.onAi,
    this.linked,
    this.plugins,
    this.head,
    this.tail,
    this.saving,
    this.recordingChanged,
    this.cheatSheet,
    this.location,
    this.shareVersionsFile,
    this.mapCard,
    this.bookBar,
    this.bookFoot,
    this.canvas,
    this.book,
    this.journal,
    this.over,
    this.around,
    this.headRoom,
  });

  /// Find and replace opened in the note with its first words (editor/FindBar.tsx, piece K).
  final void Function(EditorView view, String initial)? onFind;

  /// The note's share link in a window of its own (share/ShareRows.tsx).
  final VoidCallback? onShare;

  /// Sharing's rows on the More sheet.
  final List<Widget> Function(BuildContext context)? sharing;

  /// Sharing as a section of its own, heading and group (lib/share/ui/share_rows.dart `ShareRows`), where
  /// [sharing] is the rows alone.
  final WidgetBuilder? sharingSection;

  /// A comment started on the caret's line (editor/useNoteComments.tsx), how many threads there are, and their list.
  final void Function(EditorView view)? onComment;
  final String? Function()? commentsSummary;
  final VoidCallback? onCommentsList;

  /// The bookmark (editor/useBookmark.ts): whether the note has one, and the press that sets, moves or removes it.
  final ({bool marked, VoidCallback onPress}) Function(EditorView view, ScrollPosition page)? bookmark;

  /// The bookmark written in the note's words, as a place to open at (editor/bookmarkLine.ts).
  final Place? Function(EditorView view)? writtenBookmark;

  /// A run of the AI on this note (editor/useNoteAi.ts).
  final void Function(EditorView view, String kind, [String? instruction])? onAi;

  /// What the note is linked to: plugins' rows (plugins/registry.ts), made elsewhere; and the plugins' own links
  /// and actions for the sheet to draw, each with its page ([NotePlugins]), given the note as an action changes it.
  final List<Widget> Function(BuildContext context)? linked;
  final NotePlugins? Function(EditorView view)? plugins;

  /// What sits at the top of a note of words, under its notebook's bar and its byline and over its words: the
  /// recording's tape (tapes/NoteTape.tsx) and what the note is linked to (plugins/LinkMarks.tsx), whose press is
  /// [openSettings], the note's More sheet.
  final List<Widget> Function(BuildContext context, VoidCallback openSettings)? head;

  /// What follows a note's words on its page: the phrases of its recording as they were spoken
  /// (tapes/NoteTape.tsx `TranscriptWords`).
  final List<Widget> Function(BuildContext context)? tail;

  /// Handed the way to save what is typed now ([NoteScreenState.flush]) as the screen is made: the AI flushes
  /// before a run, so the run's Undo has the note as it was.
  final void Function(VoidCallback flush)? saving;

  /// Hears that the phone's write-up changed this note (ai/summaries.ts `onRecordingChanged`, for this note alone),
  /// and answers the way to stop: the screen then reads the note and takes it, when nothing typed here is waiting
  /// to be saved; else the next save picks it up. Absent, the write-up is taken only as the note opens.
  final VoidCallback Function(VoidCallback changed)? recordingChanged;

  /// The formatting cheat sheet's page (guide/CheatSheet.tsx).
  final WidgetBuilder? cheatSheet;

  /// Where the note was written, for its row, where something other than the screen's own answers it (a test);
  /// with [NoteScreen.tags] the screen makes the row itself, as the page does.
  final NoteLocation Function(GeoTag? tag)? location;

  /// Shares a note's versions file (core/versions/share.ts).
  final Future<String?> Function(String noteId, String title)? shareVersionsFile;

  /// The map at the top of a tagged note (editor/MapCard.tsx): `header` for a map note, else the card. `quiet` for
  /// a tag still waiting for a draft's first words, which fetches no tiles; `arrive` for a card that just appeared
  /// on the open note and `leave` for one whose tag was just taken off, which calls `onLeft` once it has gone.
  final Widget Function(BuildContext context, GeoTag tag, {required bool header, required bool quiet, required bool arrive, required bool leave, VoidCallback? onLeft})? mapCard;

  /// A chapter's book, its place in it and the chapters either side, over and under the words (book/BookNav.tsx).
  final Widget Function(BuildContext context, BookPlace place)? bookBar;
  final Widget Function(BuildContext context, BookPlace place)? bookFoot;

  /// The three views that take the page for a note that is not words: canvas/CanvasView.tsx (stage 6),
  /// book/BookView.tsx and book/JournalView.tsx (stage 5). Each is handed the body and writes the note through
  /// `onChange`, as typing does.
  final Widget Function(BuildContext context, String body, ValueChanged<String> onChange)? canvas;

  /// The notebook's view is a sliver of the note's page, where the other two are boxes.
  final Widget Function(BuildContext context, String body, ValueChanged<String> onChange)? book;
  final Widget Function(BuildContext context, String body, ValueChanged<String> onChange)? journal;

  /// What floats over the page while the note's words are up: the press-and-hold band, the + list, the find bar.
  final List<Widget> Function(BuildContext context, EditorView view)? over;

  /// The room the page keeps clear under its header for what floats there, in pixels (`--ai-strip-room`,
  /// editor/useStripRoom.ts): the AI's strip's height and 8 more while it is up, 0 once it is gone. The page starts
  /// that much lower, so the strip never sits over the tape or the note's first line.
  final ValueListenable<double>? headRoom;

  /// What stands round the page that scrolls, and so hears its scrolling: the + and its list (editor/plus
  /// `PlusLayer`), a chip's menu, the band. Given the page, it answers the page inside them. The view is null until
  /// the editor has one and while the note's words are not what is up; what it answers must keep the page in the
  /// same place in its tree either way, since a page that moves house takes a new scroll position, and the place
  /// keeper and a landing hold the one they were made with.
  final Widget Function(BuildContext context, EditorView? view, Widget page)? around;
}

class NoteScreen extends StatefulWidget {
  const NoteScreen({
    super.key,
    required this.note,
    required this.library,
    required this.workspaces,
    required this.onBack,
    required this.onDelete,
    required this.onPin,
    required this.onArchive,
    this.versions,
    this.preferences,
    this.device,
    this.untouched,
    this.liveTitles,
    this.onSpeak,
    this.onHistory,
    this.hinge,
    this.at,
    this.caret,
    this.book,
    this.takenTitles = const {},
    this.templates,
    this.onTemplates,
    this.onJournal,
    this.tags,
    this.reviewing = false,
    this.readOnly = false,
    this.editorBuilder = readOnlyNoteEditor,
    this.seams = const NoteSeams(),
    this.say,
    this.debounce = saveDebounce,
    this.lifecycle = true,
    this.clock,
  });

  final Note note;
  final NoteLibrary library;
  final WorkspaceStore workspaces;
  final VoidCallback onBack;
  final ValueChanged<String> onDelete;

  /// Pin or unpin, given the note as it stands now (`onPin({...note, starred: pinned})`).
  final ValueChanged<Note> onPin;
  final ValueChanged<Note> onArchive;

  /// The versions; without them the note has no history rows.
  final VersionsRecord? versions;

  /// The preferences (the view, the smoke); the app's own unless given.
  final PreferencesStore? preferences;

  /// This device's memory, for the places, the zoom and the untouched records; the app's own unless given.
  final Stored? device;
  final UntouchedNotes? untouched;
  final LiveTitles? liveTitles;

  /// Talk into this note; left out where nothing records.
  final ValueChanged<String>? onSpeak;

  /// The history in a side panel, from the bar's History button; left out, the More sheet's page opens.
  final VoidCallback? onHistory;

  /// The hinge's angles, for the unfold; the phone's own unless given (core/unfold.dart `hingeAngles`).
  final Stream<double>? hinge;

  /// The item to land on when the note was opened by a link pointing inside it: `^anchor`, or `line:12`.
  final String? at;

  /// A note just made, to be written in: where the caret goes.
  final Caret? caret;

  /// The book this note is a chapter of, for the bar under its header.
  final BookPlace? book;

  /// Every note's title key, for the names a blank page offers.
  final Set<String> takenTitles;

  /// Your own templates, the pages of a Templates notebook, for the blank page's cards; null for the ones built in.
  final List<NoteTemplate>? templates;

  /// Your templates, the cards' last: the notebook they are kept in, made the first time. Left out, no such card.
  final VoidCallback? onTemplates;

  /// A journal open hands the app the way to write its index through this screen, and takes it back as it goes
  /// (`onJournal`).
  final ValueChanged<JournalWriter?>? onJournal;

  /// The places notes keep (lib/core/place_tags.dart): given, the note draws its tag or the one waiting for it,
  /// holds its map's box for a fix on its way, and its More sheet adds and removes its location. Absent, a note
  /// draws only what its words say.
  final PlaceTags? tags;

  /// Whether the review after a recording is live for this note as it opens: its tag waits until the review has
  /// handed back (`reviewing`).
  final bool reviewing;

  /// A note in the Trash: read, not written.
  final bool readOnly;

  final NoteEditorBuilder editorBuilder;
  final NoteSeams seams;

  /// A toast.
  final void Function(String message)? say;

  /// For a test: the saving's debounce, whether the app's comings and goings are listened to, and the time.
  final Duration debounce;
  final bool lifecycle;
  final DateTime Function()? clock;

  @override
  State<NoteScreen> createState() => NoteScreenState();
}

/// What the note says when its save was refused for good.
const String saveStoppedWords = 'This note changed somewhere else. What you write here now is not being saved.';

class NoteScreenState extends State<NoteScreen> with TickerProviderStateMixin {
  late final NoteSaving _saving;
  VersionKeeping? _versioning;
  late final NoteZoom _zoom = NoteZoom(device: widget.device);
  final PinchTracker _pinch = PinchTracker();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _page = GlobalKey();
  final GlobalKey _unfolding = GlobalKey();
  late final AnimationController _rise = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  /// On a folding phone, the note flattens with the hinge as the phone opens (core/unfold.dart). Made once the
  /// tokens say whether motion is turned down.
  UnfoldDriver? _unfold;

  EditorView? _view;
  NotePlaceKeeper? _keeper;
  LandAt? _landing;
  Timer? _checking;

  GeoTag? _tag;
  Look? _look;

  /// The map's box held for a new note while its fix is on its way, or once it is known none is coming (`hold`).
  Held? _hold;

  /// The card just appeared on this open note: it arrives on the beat rather than at full height.
  bool _arriving = false;

  /// The tag just taken off, drawn a moment longer while its card leaves on the same beat; null otherwise.
  GeoTag? _leaving;
  late bool _reviewing = widget.reviewing;
  VoidCallback? _unwatchTag;
  VoidCallback? _unhearReview;
  late bool _wasBlank;

  /// Whether a refusal the device keeps still stands, read as the note opens: the blank page's map card says so.
  bool _refusalStands = false;

  /// The places, for a note that can be written.
  PlaceTags? get _tags => widget.readOnly ? null : widget.tags;
  late bool _pinned = widget.note.starred;
  late bool _drafted;
  late bool _untouched;
  late bool _fresh;
  bool _source = false;
  late String _typedBody = widget.note.body;
  bool _settingsOpen = false;
  NoteSettingsPage? _settingsAt;
  bool _caretPlaced = false;
  bool _stopped = false;
  ({double distance, double zoom, int? pos, double y})? _pinching;
  ScrollHoldController? _held;

  /// The blank page's offers: whether the page is ready for words, whether the editor had the focus when last
  /// asked, the cards put away by a press elsewhere on the page, and the press that may be one.
  bool _ready = !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  bool _focused = false;
  bool _cardsGone = false;
  ({int pointer, Offset at})? _armed;
  final GlobalKey _offers = GlobalKey();
  Timer? _minute;

  late final ValueNotifier<NoteToolsModel> _toolsModel = ValueNotifier(_model());
  late final Widget _tools = NoteTools(model: _toolsModel);
  late final Widget _more = NoteMore(onMore: _openMore);
  String _toolsKey = '';

  PreferencesStore get _prefs => widget.preferences ?? preferences;
  UntouchedNotes get _records => widget.untouched ?? untouchedNotes;
  LiveTitles get _live => widget.liveTitles ?? liveTitles;
  String get _id => widget.note.id;

  /// The editor's view, once it has one.
  EditorView? get view => _view;

  /// The live words.
  String get body => _saving.body;

  /// The note's name as its words say it.
  String get title => _saving.title;

  /// Whether a save was refused for good.
  bool get saveStopped => _stopped;

  // ---- what the note is ---------------------------------------------------------------------------------------------

  bool get _isCanvas => isCanvasBody(_typedBody);
  bool get _isBook => isBookBody(_typedBody);
  bool get _isJournal => isJournalBody(_typedBody);

  /// A canvas or a book: a note with a view of its own in front of its words.
  bool get _typed => _isCanvas || _isBook;
  bool get _drawing => _isCanvas && !_source;
  bool get _paging => _isBook && !_source;

  /// Whether the editor is what is showing.
  bool get _words => !_drawing && !_paging;
  NoteKind get _kind => _isCanvas ? NoteKind.canvas : (_isBook ? NoteKind.book : NoteKind.words);
  bool get _onPage => _typed ? !_source : _prefs.value.noteView == 'formatted';

  /// Whether a + may show beside an empty line, which is also when a blank page offers its names
  /// (`plusAllowed`): the note is words being written.
  bool get plusAllowed => !_typed && !widget.readOnly;

  /// Whether the blank page offers names and templates (`offering`): a note made in this run, with no words.
  bool get offering => _fresh && _saving.blank && plusAllowed;

  /// The names on offer now, or null where none are (core/note_names.dart).
  List<NameOffer>? get names => offering ? nameOffers(widget.clock?.call() ?? DateTime.now(), widget.takenTitles) : null;

  /// Whether the names are drawn now (`offersShown`): offered, the editor focused, the page ready for words.
  bool get offersShown => offering && _focused && _ready && _words;

  /// Whether the template cards are drawn under them (`cardsShown`).
  bool get cardsShown => offersShown && !_cardsGone;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _saving = NoteSaving(widget.library, note, onExternalChange: _external, debounce: widget.debounce, lifecycle: widget.lifecycle && !widget.readOnly)..addListener(_saved);
    _tag = geoTagOf(note.body) ?? _tags?.pendingTag(note.id);
    _look = lookOf(note.body);
    _wasBlank = _saving.blank;
    final tags = _tags;
    if (tags != null) {
      _hold = tags.heldFor(note.id);
      _unwatchTag = tags.watchTag(note.id, _tagEvent);
      if (_records.isFresh(note.id)) {
        unawaited(tags.refusalStanding().then((standing) {
          if (mounted && standing != _refusalStands) setState(() => _refusalStands = standing);
        }));
      }
      _unhearReview = onReviewHandedBack((noteId) {
        if (noteId != _id) return;
        _reviewing = false;
        _settleTag();
      });
    }
    _drafted = _records.recordOf(_id) != null;
    _untouched = _drafted && _records.isUntouched(_id, note.body, recordingMs: note.recordingMs, starred: note.starred, archivedAt: note.archivedAt);
    widget.seams.saving?.call(flush);
    if (!widget.readOnly) _unhearRecording = widget.seams.recordingChanged?.call(_recordingChanged);
    _fresh = _records.isFresh(_id);
    final versions = widget.versions;
    if (versions != null && !widget.readOnly) _versioning = VersionKeeping(versions, _id, () => _saving.body, lifecycle: widget.lifecycle)..addListener(_redraw);
    _prefs.addListener(_redraw);
    widget.seams.headRoom?.addListener(_redraw);
    widget.workspaces.addListener(_redraw);
    _zoom.addListener(_redraw);
    _caretPlaced = widget.caret == null;
    FocusManager.instance.addListener(_focusMoved);
    // A chapter open is where its book was left, so the book opens here again from outside it (book/bookSpot.ts).
    // Not a journal's entry: a journal always opens on itself, where New entry is.
    final book = widget.book;
    if (book != null && !book.journal) writeBookSpot(book.book.id, ChapterSpot(_saving.title), on: widget.device);
    if (_isJournal) _tellJournal();
    // After the frame: the tab row listens, and a listener outside this screen may not be told while the tree is
    // being built (a note opened by the shell is mounted in the middle of the shell's own build).
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _live.set(_id, _saving.title);
      });
    } else {
      _live.set(_id, _saving.title);
    }
    _rise.forward();
  }

  /// The phone's write-up changed this note: its transcript is read and shown, when nothing typed here is waiting to
  /// be saved; else the next save picks it up (NoteScreen.tsx's `onRecordingChanged` effect).
  VoidCallback? _unhearRecording;
  void _recordingChanged() {
    unawaited(widget.library.get(_id).then<void>((fresh) {
      if (fresh != null && mounted) _saving.adopt(fresh);
    }, onError: (Object _) {}));
  }

  @override
  void dispose() {
    // A new note left without a word leaves nothing behind, its waiting tag included.
    if (_saving.blank && geoTagOf(_saving.body) == null) _tags?.setPendingTag(_id, null);
    _unhearRecording?.call();
    _unwatchTag?.call();
    _unhearReview?.call();
    _slowFix?.cancel();
    FocusManager.instance.removeListener(_focusMoved);
    _minute?.cancel();
    if (_toldJournal) {
      final told = widget.onJournal;
      // After the frame: whoever listens may be building.
      if (told != null) SchedulerBinding.instance.addPostFrameCallback((_) => told(null));
    }
    _checking?.cancel();
    _keeper?.dispose();
    _landing?.dispose();
    _versioning
      ?..removeListener(_redraw)
      ..dispose();
    _prefs.removeListener(_redraw);
    widget.seams.headRoom?.removeListener(_redraw);
    widget.workspaces.removeListener(_redraw);
    _zoom
      ..removeListener(_redraw)
      ..dispose();
    _saving
      ..removeListener(_saved)
      ..dispose();
    _toolsModel.dispose();
    _scroll.dispose();
    _rise.dispose();
    _unfold?.dispose();
    super.dispose();
  }

  /// A change of state that may be asked for while the tree is building (the editor told of words from outside).
  void _redraw([VoidCallback? change]) {
    if (!mounted) return change?.call();
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      change?.call();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() => change?.call());
  }

  // ---- the blank page's offers --------------------------------------------------------------------------------------

  /// The focus moved somewhere: the names are drawn only while the editor has it.
  void _focusMoved() {
    // After the frame: the editor is told of its focus by its own listener, which may come after this one.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final focused = _view?.hasFocus ?? false;
      if (mounted && focused != _focused) setState(() => _focused = focused);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// The names follow the clock: read again at the turn of each minute while they are offered (`useMinute`).
  void _watchMinute(bool on) {
    if (!on) {
      _minute?.cancel();
      _minute = null;
      return;
    }
    if (_minute != null) return;
    final now = DateTime.now();
    _minute = Timer(Duration(seconds: 60 - now.second, milliseconds: 50), () {
      _minute = null;
      if (mounted) setState(() {});
    });
  }

  /// The page back at its top, where the note now starts (`backToTop`): a card lower down is pressed with the page
  /// scrolled, which keeps its scroll as the cards go. Once the words are laid out, and only then the caret asked
  /// into view: from the top, that only ever brings it up from below, where asked first it left the heading under
  /// the header (seen on the emulator, 2026-10-08).
  void _backToTop(EditorView editor) {
    void top() {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.minScrollExtent);
    }

    top();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(editor, _view)) return;
      top();
      editor.dispatch(const TransactionSpec(scrollIntoView: true));
    });
  }

  /// A card pressed: the blank note becomes that template, as one change, so one undo takes it back to the blank
  /// page with its names and cards. Its record first, so a note left without a word of the person's own is taken
  /// back; its name settled against every other note's; the caret in its first open line, the focus kept; and the
  /// page back at its top, where the note now starts (`startFrom`).
  void startFrom(NoteTemplate template) {
    final editor = _view;
    if (editor == null || !_records.isFresh(_id) || editor.state.doc.toString().trim().isNotEmpty) return;
    final now = widget.clock?.call() ?? DateTime.now();
    final filled = fillNoteTemplate(template, now, widget.takenTitles);
    _records.remember(_id, UntouchedRecord(title: filled.title, words: filled.words, at: now.millisecondsSinceEpoch));
    _drafted = true;
    setState(() => _untouched = true);
    editor.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: editor.state.doc.length, insert: filled.body), selection: EditorSelection.single(filled.caret.clamp(0, filled.body.length)), userEvent: 'input.template'));
    _backToTop(editor);
    flush();
    editor.focus();
    HapticsProvider.of(context)(HapticKind.selection);
    // A map at the top: the card's press is the choice to keep a place, and its box is held from now.
    final tags = _tags;
    if (tags != null && template.look == Look.map && geoTagOf(_saving.body) == null && tags.pendingTag(_id) == null && tags.heldFor(_id) != Held.waiting) {
      tags.holdFor([_id]);
      unawaited(tags.tagEntryIfWanted([_id], (reviewing: false)));
    }
  }

  // ---- a notebook's index written from outside ----------------------------------------------------------------------

  bool _toldJournal = false;

  void _tellJournal() {
    final told = widget.onJournal;
    if (told == null) return;
    _toldJournal = true;
    final writer = JournalWriter(id: _id, write: writeNotebook);
    // After the frame: whoever listens may be building.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) told(writer);
    });
  }

  /// A change to a notebook's or a journal's index made by the app (an entry's line put in or taken out): through
  /// this screen, whose next save would otherwise write the old index back, and kept at once (`writeIndex`).
  void writeNotebook(String Function(String body) change) {
    final next = change(_saving.body);
    if (next == _saving.body) return;
    if (_source && _view != null) {
      _external(next);
    } else {
      _onChange(next);
    }
    if (mounted) setState(() => _typedBody = next);
    flush();
  }

  // ---- saving -------------------------------------------------------------------------------------------------------

  /// The tab says the note's name as line 1 is written (core/liveTitles.ts), and the header its title.
  void _saved() {
    _live.set(_id, _saving.title);
    _redraw();
  }

  /// Words that arrived from outside the editor - a meeting's transcript - are put into it whole.
  void _external(String next) {
    final editor = _view;
    if (editor == null) return;
    final now = editor.state.doc.toString();
    if (now != next) editor.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: now.length, insert: next)));
  }

  /// Saves what is waiting, and looks at whether the library is still taking this screen's words.
  void flush() {
    if (widget.readOnly) return;
    _saving.flush();
    _watch();
  }

  /// After the next save has been answered: a save refused for good is said on the note.
  void _watch() {
    _checking?.cancel();
    _checking = Timer(widget.debounce + const Duration(milliseconds: 60), () {
      unawaited(_saving.settled().whenComplete(() {
        if (mounted && !_saving.writable && !_stopped) setState(() => _stopped = true);
      }));
    });
  }

  /// Every change to the words passes through here (`onChange`).
  void _onChange(String next) {
    if (widget.readOnly) return;
    _saving.onChange(next);
    _watch();
    _versioning?.changed();
    final tag = geoTagOf(next) ?? _tags?.pendingTag(_id);
    final look = lookOf(next);
    final wasBlank = _wasBlank, wasUntouched = _untouched;
    _wasBlank = _saving.blank;
    var fresh = _fresh, untouched = _untouched;
    if (_fresh) {
      _records.keepFresh(_id, next);
      fresh = _records.isFresh(_id);
    }
    if (_drafted) {
      untouched = _records.isUntouched(_id, next);
      if (!untouched) {
        // Its first own words make it the person's there and then: the record goes on the keystroke.
        _records.forget(_id);
        _drafted = false;
      }
    }
    if (tag != _tag || look != _look || fresh != _fresh || untouched != _untouched) {
      _redraw(() {
        _tag = tag;
        _look = look;
        _fresh = fresh;
        _untouched = untouched;
      });
    }
    // A new note's first words, or an entry's first of its own: the tag waiting for them lands. After this change
    // has been taken, since landing it is a change of its own.
    if (_tags != null && !_saving.blank && !untouched && (wasBlank || wasUntouched)) scheduleMicrotask(_settleTag);
  }

  // ---- the note's place (core/location.ts, NoteScreen.tsx) ------------------------------------------------------------

  void _tagEvent(TagEvent event) {
    if (!mounted) return;
    switch (event) {
      case TagPlace(:final place, :final lat, :final lon):
        _namePlace(place, lat, lon);
      case TagHeld():
        _redraw(() => _hold = _tags?.heldFor(_id));
      case TagPending():
        _settleTag();
    }
  }

  /// A tag waiting for this note lands once it may (`settle`): the better words in, the note with words. Until
  /// then the card is drawn from it. A note that says where it was written already keeps what it says.
  void _settleTag() {
    final tags = _tags;
    if (tags == null || !mounted) return;
    final waiting = tags.pendingTag(_id);
    if (waiting == null) return;
    if (geoTagOf(_saving.body) != null) {
      tags.setPendingTag(_id, null);
      return;
    }
    if (tags.settleTag(_id, _saving.body, reviewing: _reviewing) != null && writeTag(waiting)) {
      // In the note now, so its name may be asked (this device made it; lib/core/place_tags.dart decides whether).
      tags.wantPlace(_id, waiting);
      return;
    }
    if (_tag != waiting) _redraw(() => _tag = waiting);
  }

  /// A name that came for the note's tag: written into the note, or onto the tag still waiting (`namePlace`).
  void _namePlace(String place, double lat, double lon) {
    final tags = _tags;
    if (tags == null) return;
    final inBody = geoTagOf(_saving.body);
    if (inBody != null && inBody.place == null && inBody.lat == lat && inBody.lon == lon) {
      writeTag(inBody.named(place));
      return;
    }
    final waiting = tags.pendingTag(_id);
    if (waiting != null && waiting.lat == lat && waiting.lon == lon) {
      final named = waiting.named(place);
      if (waiting.place != place) tags.setPendingTag(_id, named);
      if (_tag != named) _redraw(() => _tag = named);
    }
  }

  Timer? _slowFix;

  GlacierToastController? _toaster() {
    try {
      return GlacierToast.of(context);
    } catch (_) {
      // A picture of the screen alone has nowhere to say it.
      return null;
    }
  }

  /// Add my location, from the More sheet: the fix, the tag into the note (or waiting), and its name asked for
  /// (`addLocation`).
  void addLocation() {
    final tags = _tags;
    if (tags == null) return;
    flush();
    setState(() => _settingsOpen = false);
    final toasts = _toaster();
    final haptics = HapticsProvider.of(context);
    var said = false;
    // The card arriving is the feedback; a slow fix says so after a moment.
    _slowFix?.cancel();
    final slow = _slowFix = Timer(const Duration(milliseconds: 600), () {
      said = true;
      toasts?.toast(message: const Text('Finding where you are.'), duration: const Duration(days: 1));
    });
    tags.locations.locate().then<void>((fix) {
      slow.cancel();
      if (said) toasts?.dismiss();
      tags.forgetRefusal();
      final next = tagOfFix(fix);
      // Left while the fix was coming: the tag is kept for the note and written into it where it may land.
      if (!mounted) return tags.landTag(_id, next);
      tags.setPendingTag(_id, next);
      setState(() {
        _tag = next;
        _arriving = true;
        _leaving = null;
      });
      // Into the note now (and its name asked), or waiting for the better words with the card drawn from it.
      _settleTag();
    }, onError: (Object failure) {
      slow.cancel();
      if (said) toasts?.dismiss();
      if (!mounted) return;
      final why = whyLocateFailed(failure);
      // Refused here is refused: new notes are not asked for again until location is allowed.
      tags.rememberRefusal(why);
      haptics(HapticKind.warning);
      toasts?.toast(
        message: Text(noFix[why]!),
        action: why == LocateFailure.blocked && tags.locations.onPhone ? GlacierToastAction(label: 'Open settings', onPress: () => unawaited(tags.locations.openSettings())) : null,
      );
    });
  }

  /// Where the note was written, for the More sheet's row (`location`).
  NoteLocation? _location(Preferences prefs) {
    final tags = _tags;
    if (tags == null) return null;
    final tag = _tag;
    return NoteLocation(
      tag: tag,
      cannot: tags.locations.cannotLocate,
      asksName: prefs.placeNames && !prefs.localOnly,
      refused: tag != null ? null : tags.refusedFor(widget.note.createdAt),
      onPhone: tags.locations.onPhone,
      onAdd: addLocation,
      onRemove: removeLocation,
    );
  }

  /// Remove location: the card leaves on its beat, and both keys go as one undo step (`removeLocation`).
  void removeLocation() {
    flush();
    final was = _tag;
    setState(() {
      _settingsOpen = false;
      _arriving = false;
      _leaving = was;
    });
    writeTag(null);
    _tags?.setPendingTag(_id, null);
    if (_tag != null) setState(() => _tag = null);
  }

  void _back() {
    flush();
    widget.onBack();
  }

  /// The phone's way back from the note, for whoever holds the back gesture: what is typed is saved first.
  void leave() => _back();

  // ---- the editor arriving ------------------------------------------------------------------------------------------

  void _onView(EditorView view) {
    if (!mounted) return;
    final first = _view == null;
    setState(() {
      _view = view;
      _focused = view.hasFocus;
    });
    // Words the store had newer than the copy this screen was opened with can be taken before the editor is here
    // to be handed them (the page's store answers later than its editor mounts): they are put in now.
    if (first && !(_typed && _source) && view.state.doc.toString() != _saving.body) _external(_saving.body);
    // On opening, once the editor is here: a tag waiting lands if it may, and a name that came while the note was
    // closed is written. After the frame, since the editor is told of its view while it builds.
    final tags = _tags;
    if (first && tags != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _settleTag();
        final now = geoTagOf(_saving.body);
        final known = now == null || now.place != null ? null : tags.placeFor(now);
        if (now != null && known != null) _namePlace(known, now.lat, now.lon);
      });
    }
    if (!_scroll.hasClients) return;
    final page = _scroll.position;
    _keeper?.dispose();
    _keeper = null;
    _landing?.dispose();
    _landing = null;
    final at = widget.at;
    if (at != null && at.isNotEmpty) {
      // Opened at an item, the note goes to that line rather than back to where it was left last time.
      _landing = LandAt(at: at, view: view, page: page, headerBottom: _headerBottom);
    } else {
      _keeper = NotePlaceKeeper(noteId: _id, view: view, page: page, places: NotePlaces(widget.device), writtenBookmark: widget.seams.writtenBookmark, lifecycle: widget.lifecycle);
    }
    // A note just made, to be written in: the caret where it was asked for, once the editor is here, and the focus.
    if (first && !_caretPlaced) {
      _caretPlaced = true;
      final length = view.state.doc.length;
      final asked = widget.caret?.offset;
      view.dispatch(TransactionSpec(selection: EditorSelection.single(asked == null ? length : asked.clamp(0, length)), scrollIntoView: true));
      view.focus();
    }
  }

  /// A tap on the paper under a short note: the caret at the end of its words, as a tap under the last line of a
  /// page puts it, and the keyboard. A note that cannot be written only takes the focus.
  void _tapUnder() {
    final editor = _view;
    if (editor == null) return;
    if (!widget.readOnly) editor.dispatch(TransactionSpec(selection: EditorSelection.single(editor.state.doc.length), scrollIntoView: true, userEvent: 'select.pointer'));
    editor.focus();
  }

  double _headerBottom() {
    final box = context.findRenderObject();
    final top = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero).dy : 0.0;
    return top + _headerHeight(context.tokens, TopBarTools.maybeOf(context) != null);
  }

  // ---- what the screen writes through the editor --------------------------------------------------------------------

  /// A change to the front matter alone, as one undo step, the caret kept with the words: a caret in the block, or
  /// at its end, goes to the start of the words; one in the words moves by what the block grew.
  bool _writeFrontMatter(String Function(String doc) change, String userEvent, {bool scroll = false}) {
    final editor = _view;
    if (editor == null || !mounted || !_words) return false;
    final doc = editor.state.doc.toString();
    final after = change(doc);
    if (after == doc) return false;
    final was = frontMatterOffset(doc), now = frontMatterOffset(after);
    int place(int pos) => pos <= was ? now : pos + now - was;
    final selection = EditorSelection.create([for (final range in editor.state.selection.ranges) EditorSelection.range(place(range.anchor), place(range.head))], editor.state.selection.mainIndex);
    editor.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: was, insert: after.substring(0, now)), selection: selection, scrollIntoView: scroll, userEvent: userEvent));
    return true;
  }

  /// The More sheet's Look: the key written into the front matter through the editor, as one undo step; Plain takes
  /// it off. The person's own doing, so a note given its words by the app is theirs from here (`chooseLook`).
  void chooseLook(Look? next) {
    if (!_writeFrontMatter((doc) => withLook(doc, next), 'input.look')) return;
    _records.forget(_id);
    _records.spoilFresh(_id);
    _drafted = false;
    setState(() {
      _untouched = false;
      _fresh = false;
    });
    HapticsProvider.of(context)(HapticKind.selection);
  }

  /// The tag written into the note, or taken out, as one undo step; where the editor is hidden behind a canvas or a
  /// book's index, through the words as a rename is (`writeTag`).
  bool writeTag(GeoTag? next) {
    if (_typed && !_source) {
      final after = withGeoTag(_saving.body, next);
      if (after != _saving.body) {
        _onChange(after);
        _typedBody = after;
      }
    } else if (!_writeFrontMatter((doc) => withGeoTag(doc, next), 'input.location', scroll: true)) {
      if (geoTagOf(_saving.body) == next) return true;
      return false;
    }
    setState(() => _tag = next);
    _tags?.setPendingTag(_id, null);
    return true;
  }

  /// A notebook's own keys written from the More sheet (its ticket key; kept as a journal, its template and its
  /// place switch): as the notebook's own changes are, and into the editor where its Markdown is the view, so the
  /// next keystroke there does not write the old keys back (`writeNotebook`).
  void _writeNotebook(String Function(String was) change) {
    final next = change(_saving.body);
    if (next == _saving.body) return;
    final editor = _view;
    if (_source && editor != null) {
      _external(change(editor.state.doc.toString()));
    } else {
      _onChange(next);
    }
    setState(() => _typedBody = next);
  }

  /// The notebook's rows of the More sheet are a notebook's alone, and never the Guide's: a manual is not a diary,
  /// and has no tickets (`journalRows`).
  bool get _notebookRows => _isBook && !widget.readOnly && !isGuideBook(widget.note.copyWith(body: _typedBody));

  /// The name typed in the More sheet, into the front matter; the index takes it too (`renameHere`).
  void renameHere(String next) {
    final named = withFrontMatterTitle(_saving.body, next);
    if (named == _saving.body) return;
    if (_source && _view != null) {
      _external(named);
    } else {
      _onChange(named);
    }
    setState(() => _typedBody = named);
  }

  /// A version put back: the words as they are now kept as a version first, then the version's words put in
  /// through the editor as one change, and kept as a version of their own, named for where they came from. So the
  /// history only grows, as `git revert` does (`restoreVersion`).
  void restoreVersion(String text, Version version) {
    final editor = _view;
    final versions = widget.versions;
    if (editor == null || versions == null) return;
    final now = editor.state.doc.toString();
    if (now == text) return;
    unawaited(versions.keepVersion(_id, now).then<void>((_) {}, onError: (Object _) {}));
    editor.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: now.length, insert: text), userEvent: 'input.restore', scrollIntoView: true));
    unawaited(versions.keepVersion(_id, text, label: 'Back to version ${version.n}').then<void>((_) {}, onError: (Object _) {}));
    widget.say?.call('Back to version ${version.n}.');
    HapticsProvider.of(context)(HapticKind.success);
  }

  /// The note's list laid out as a board: one change, so one Undo puts the note back as it was (`makeBoard`).
  void makeBoard() {
    final editor = _view;
    if (editor == null) return;
    final made = boardFrom(editor.state.doc.toString());
    setState(() => _settingsOpen = false);
    if (made == null) return;
    editor.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: editor.state.doc.length, insert: made.doc), userEvent: 'input.board'));
    HapticsProvider.of(context)(HapticKind.success);
    widget.say?.call('${made.cards} ${made.cards == 1 ? 'item is' : 'items are'} now cards${made.done != 0 ? ', ${made.done} in Done' : ''}.');
  }

  /// A name tapped on the blank page: the note's heading, and the caret on the line under it. Its record first, so a
  /// note named and left without a word of the person's own is taken back. One change, so one undo takes it back to
  /// a blank page with the names on it (`nameIt`).
  void nameIt(String name) {
    final editor = _view;
    if (editor == null || !_records.isFresh(_id)) return;
    final words = '# $name\n\n';
    _records.remember(_id, UntouchedRecord(title: name, words: words, at: DateTime.now().millisecondsSinceEpoch));
    _drafted = true;
    setState(() => _untouched = true);
    final from = frontMatterOffset(editor.state.doc.toString());
    editor.dispatch(TransactionSpec(changes: ChangeSpec(from: from, to: editor.state.doc.length, insert: words), selection: EditorSelection.single(from + words.length), userEvent: 'input.name'));
    _backToTop(editor);
    // Kept now, not on typing's beat: a note named and left at once is looked at by its take-back from the store.
    flush();
    editor.focus();
    HapticsProvider.of(context)(HapticKind.selection);
  }

  // ---- the tools ----------------------------------------------------------------------------------------------------

  void _chooseView(NoteView value) {
    if (_prefs.value.noteView == value.name) return;
    _prefs.update((now) => now.copyWith(noteView: value.name));
    HapticsProvider.of(context)(HapticKind.selection);
  }

  /// A canvas's or a book's own switch, between its page and its source (`showSource`).
  void _showSource(bool next) {
    if (next == _source) return;
    setState(() {
      if (!next) _typedBody = _saving.body;
      _source = next;
    });
    HapticsProvider.of(context)(HapticKind.selection);
  }

  void _switchView() => _typed ? _showSource(_onPage) : _chooseView(_onPage ? NoteView.mixed : NoteView.formatted);

  void _openMore() => _openSettings();

  void _openSettings([NoteSettingsPage? at]) => setState(() {
        _settingsAt = at;
        _settingsOpen = true;
      });

  /// Pin or unpin, from the bar or from More (`togglePin`).
  void togglePin() {
    flush();
    widget.onPin(_noteNow(starred: _pinned));
    setState(() {
      _pinned = !_pinned;
      _settingsOpen = false;
    });
    HapticsProvider.of(context)(HapticKind.selection);
  }

  void _archive() {
    flush();
    setState(() => _settingsOpen = false);
    widget.onArchive(_noteNow(starred: _pinned));
  }

  void _remove() {
    // No confirmation: it goes to the trash, with an Undo, and is only deleted for good from there.
    setState(() => _settingsOpen = false);
    HapticsProvider.of(context)(HapticKind.warning);
    flush();
    widget.onDelete(_id);
  }

  Note _noteNow({required bool starred}) {
    final note = widget.note;
    return Note(
      id: note.id,
      body: _saving.body,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      source: note.source,
      sourceName: note.sourceName,
      starred: starred,
      archivedAt: note.archivedAt,
      recordingMs: note.recordingMs,
      segments: note.segments,
      formatted: note.formatted,
      formattedFor: note.formattedFor,
      formattedModel: note.formattedModel,
      path: note.path,
      revision: note.revision,
    );
  }

  ({bool marked, VoidCallback onPress})? _bookmark() {
    final view = _view;
    final ask = widget.seams.bookmark;
    return view == null || ask == null || !_scroll.hasClients ? null : ask(view, _scroll.position);
  }

  void _speak() {
    flush();
    widget.onSpeak?.call(_id);
  }

  String? get _speakWords => widget.onSpeak == null ? null : (_isJournal ? 'Speak an entry' : 'Talk into this note');

  /// What comes out of More into the bar while there is room, in this order: Share, History, Comment, Bookmark,
  /// Pin/Unpin, Archive, Speak (`actions`). Each is there only where More would have it, and stays in More too.
  List<ToolAction> _actions() {
    final seams = widget.seams;
    final view = _view;
    final mark = _bookmark();
    final history = widget.versions != null && !_isCanvas && !widget.readOnly;
    final speak = _speakWords;
    return [
      if (seams.onShare != null) ToolAction(id: 'share', label: 'Share', icon: Lucide.share2, onPress: seams.onShare!),
      if (history) ToolAction(id: 'history', label: 'Version history', icon: Lucide.history, onPress: () => widget.onHistory != null ? widget.onHistory!() : _openSettings(NoteSettingsPage.history)),
      if (seams.onComment != null && !_typed && view != null) ToolAction(id: 'comment', label: 'Comment', icon: Lucide.messageSquarePlus, onPress: () => seams.onComment!(view)),
      if (mark != null) ToolAction(id: 'bookmark', label: mark.marked ? 'Move or remove the bookmark' : 'Bookmark this line', icon: mark.marked ? Lucide.bookmarkCheck : Lucide.bookmark, onPress: mark.onPress, on: mark.marked),
      if (!widget.readOnly) ...[
        ToolAction(id: 'pin', label: _pinned ? 'Unpin' : 'Pin to the top', icon: _pinned ? Lucide.pinOff : Lucide.pin, onPress: togglePin, on: _pinned),
        ToolAction(id: 'archive', label: 'Archive', icon: Lucide.archive, onPress: _archive),
      ],
      if (speak != null && !widget.readOnly) ToolAction(id: 'speak', label: speak, icon: Lucide.mic, onPress: _speak),
    ];
  }

  NoteToolsModel _model({bool more = true}) => NoteToolsModel(kind: _kind, page: _onPage, switchable: true, onSwitch: _switchView, onMore: _openMore, more: more, actions: _actions());

  /// The tools follow the screen: handed a new model after the frame, when what they draw has changed.
  void _syncTools({required bool more}) {
    final model = _model(more: more);
    final key = '${model.kind.name}|${model.page}|${model.more}|${[for (final action in model.actions) '${action.id}:${action.label}:${action.on}'].join(',')}';
    if (key == _toolsKey) return;
    _toolsKey = key;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _toolsModel.value = model;
    });
  }

  // ---- two fingers --------------------------------------------------------------------------------------------------

  void _pointerDown(PointerDownEvent event) {
    // The person's own touch ends a restore of where the note was left.
    _keeper?.touched();
    // A press that starts while the cards are shown, and not on them, may be the tap that puts them away.
    _armed = cardsShown && !_onOffers(event.position) ? (pointer: event.pointer, at: event.position) : null;
    if (event.kind != PointerDeviceKind.touch) return;
    _pinch.put(event.pointer, event.position);
    final view = _view;
    final mid = _pinch.middle;
    if (!_pinch.pinching || mid == null || view == null || !_words) return;
    final pos = view.posAtCoords(mid, precise: false);
    final at = pos == null ? null : view.coordsAtPos(pos);
    _pinching = (distance: _pinch.apart, zoom: _zoom.value, pos: at == null ? null : pos, y: at?.top ?? mid.dy);
    // Two fingers are a pinch, not a scroll: the page is held where it is, and the drag the first finger began is over.
    if (_scroll.hasClients) _held = _scroll.position.hold(() => _held = null);
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _pinch.put(event.pointer, event.position);
    final start = _pinching;
    if (start == null || !_pinch.pinching) return;
    final wanted = pinched(start.zoom, start.distance, _pinch.apart);
    if (wanted == _zoom.value) return;
    _zoom.value = wanted;
    // The words that were under the fingers go back under them as the lines reflow.
    SchedulerBinding.instance.addPostFrameCallback((_) => _holdUnderFingers(start));
  }

  void _holdUnderFingers(({double distance, double zoom, int? pos, double y}) start) {
    final view = _view;
    final pos = start.pos;
    if (!mounted || view == null || pos == null || !_scroll.hasClients) return;
    final at = view.coordsAtPos(pos);
    if (at == null) return;
    final page = _scroll.position;
    final to = (page.pixels + at.top - start.y).clamp(page.minScrollExtent, page.maxScrollExtent < page.minScrollExtent ? page.minScrollExtent : page.maxScrollExtent);
    if ((to - page.pixels).abs() > 0.01) page.jumpTo(to);
  }

  /// Whether a point on the screen is on the blank page's names or cards.
  bool _onOffers(Offset at) {
    final box = _offers.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize && (box.localToGlobal(Offset.zero) & box.size).contains(at);
  }

  void _pointerUp(PointerEvent event) {
    if (event is PointerUpEvent) {
      final armed = _armed;
      final tapped = armed != null && armed.pointer == event.pointer && (event.position - armed.at).distance <= kTouchSlop;
      // A tap elsewhere on the page says the page is to be written on as it is: the cards go. And any press of the
      // person's own that ends on the page makes it ready for words.
      if ((tapped && !_cardsGone) || !_ready) {
        setState(() {
          if (tapped) _cardsGone = true;
          _ready = true;
        });
      }
    }
    _armed = null;
    if (event.kind != PointerDeviceKind.touch) return;
    _pinch.lift(event.pointer);
    final start = _pinching;
    if (start == null || _pinch.fingers >= 2) return;
    _holdUnderFingers(start);
    _zoom.keep();
    _pinching = null;
    _held?.cancel();
    _held = null;
    _view?.requestMeasure<void>();
  }

  // ---- drawing ------------------------------------------------------------------------------------------------------

  /// How tall the header's glass is: with the tools in the app's bar it holds nothing and is exactly the bar
  /// (`.header:empty`); with its own row, the row and its padding.
  static double _headerHeight(Tokens t, bool inBar) => inBar ? t.len('app-safe-top') : t.len('app-safe-top') + t.space(1) + t.len('app-bar-ring') + t.space(2);

  Widget _view0(BuildContext context) {
    final seams = widget.seams;
    void write(String next) {
      _onChange(next);
      setState(() => _typedBody = next);
    }

    if (_drawing) {
      // `<div class="body canvasBody">`: the canvas is in a body too, and `.body { padding-block-end:
      // var(--app-safe-bottom) }` ends it above the phone's own bar, so its tools and its map stand clear of it as
      // the dock does. Without it the tool pill sat 84px lower than the dock's lift on a phone with a bar.
      // With the keyboard up there is no bar under the page to keep clear of (the keys are over it), as home has it:
      // kept, the card being written stood 84px too high and its bar went under the card, over the tools.
      return Padding(
        padding: EdgeInsets.only(bottom: _KeyboardUp.of(context) ? 0 : context.tokens.len('app-safe-bottom')),
        child: seams.canvas?.call(context, _typedBody, write) ?? const SizedBox.shrink(),
      );
    }
    if (_isJournal) {
      return seams.journal?.call(context, _typedBody, write) ?? const SizedBox.shrink();
    }
    return seams.book?.call(context, _typedBody, write) ?? const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  @override
  Widget build(BuildContext context) => _KeyboardWatch(child: LayoutBuilder(builder: (context, box) => _build(context, box.maxWidth)));

  Widget _build(BuildContext context, double pageWidth) {
    final t = context.tokens;
    final prefs = _prefs.value;
    final seams = widget.seams;
    final bar = TopBarTools.maybeOf(context);
    final inBar = bar != null;
    _syncTools(more: !inBar);

    final headerHeight = _headerHeight(t, inBar);
    // `--wisp-under`: the header's height as the page reads it, a whole pixel (`offsetHeight`).
    final under = headerHeight.roundToDouble();
    // `.header:empty ~ .page`: the room the header's padding used to be, kept by the page.
    final padTop = inBar ? under + t.space(1) + t.space(2) : under;
    final gutter = t.len('app-gutter');
    final look = _typed ? null : _look;
    // `.page[data-look='reading'] > .byline`: the column's own left edge, from 600px: half of what the page has past
    // 36rem, or the gutter where it has less.
    final past = (pageWidth - t.lenOf('36rem')) / 2;
    final columnStart = look == Look.reading && MediaQuery.sizeOf(context).width >= 600 ? (gutter > past ? gutter : past) : null;
    final smokes = footSmokes(prefs.wispEdge, still: t.reducedMotion);
    final authors = authorsOf(widget.note.body);
    final view = _view;
    final tag = _tag;
    final book = widget.book;

    // The keyboard up is the page ready for words, and once ready it stays ready.
    if (!_ready && _KeyboardUp.of(context)) _ready = true;
    final offered = offersShown ? names : null;
    final cards = offered != null && cardsShown;
    _watchMinute(offering);

    final spec = NoteEditorSpec(
      // A canvas's JSON or a book's Markdown, once asked for, is what the view has written by now.
      value: _typed && _source ? _saving.body : widget.note.body,
      onChange: _onChange,
      onView: _onView,
      display: _typed ? NoteView.mixed : (noteViewNamed(prefs.noteView) ?? NoteView.mixed),
      readOnly: widget.readOnly,
      look: look?.name,
      zoom: _zoom.value,
      pageWidth: pageWidth,
      headClear: headerHeight,
      pageHead: padTop + (seams.headRoom?.value ?? 0),
      // The line being typed stays above the page's foot smoke, where there is smoke to keep clear of.
      footClear: !_isCanvas && smokes ? wispEdgeFootClear : 0,
      // The names and cards are under line 1 and over the room the words keep under their last line.
      contentBottom: offered != null ? 0 : null,
      meHue: null,
    );

    final words = CustomScrollView(
      key: _page,
      controller: _scroll,
      // A canvas is not a column of words: it takes the whole page and moves under the fingers rather than scrolling.
      physics: _drawing ? const NeverScrollableScrollPhysics() : null,
      slivers: [
        // `padding-block-start: calc(var(--wisp-under) + … + var(--ai-strip-room, 0px))`
        SliverToBoxAdapter(child: SizedBox(height: padTop + (seams.headRoom?.value ?? 0))),
        // A chapter's book, its place in it and the chapters either side (docs/BOOKS.md).
        if (book != null && seams.bookBar != null) SliverToBoxAdapter(child: seams.bookBar!(context, book)),
        // Who wrote it, when it names anyone: a book says so for all its pages, in its index.
        if (!_paging && authors.isNotEmpty) SliverToBoxAdapter(child: NoteByline(authors: authors, start: columnStart)),
        // Where it was written: the map at the top of the note, where the page scrolls with the words.
        if (_words && seams.head != null)
          for (final row in seams.head!(context, _openSettings)) SliverToBoxAdapter(child: row),
        if ((tag ?? _leaving) != null && _words && seams.mapCard != null)
          SliverToBoxAdapter(
            child: _MapPlace(
              header: look == Look.map,
              columnStart: columnStart,
              child: seams.mapCard!(
                context,
                (tag ?? _leaving)!,
                header: look == Look.map,
                // A new note's tag still waiting for its first words is drawn quiet: a draft that may never be kept
                // fetches no tiles. So is an untouched entry's, which is taken back if it is left as it is.
                quiet: (_saving.blank || _untouched) && geoTagOf(_saving.body) == null,
                arrive: tag != null && _arriving,
                leave: tag == null,
                onLeft: () => setState(() => _leaving = null),
              ),
            ),
          )
        else if ((_hold != null || look == Look.map) && _words && seams.mapCard != null)
          // The box held for a new note's fix: the same box, empty, until the tag arrives in it or the note is left.
          // A map note's header is its shape, so it is drawn with no place too, saying why.
          SliverToBoxAdapter(
            child: _MapPlace(
              header: look == Look.map,
              columnStart: columnStart,
              child: MapPicture(size: look == Look.map ? MapSize.header : MapSize.card, why: _hold == Held.waiting ? null : (prefs.localOnly ? 'Local only is on.' : 'No place yet.')),
            ),
          ),
        // A canvas fills what is left of the page; a journal is one box of it; a notebook's view is slivers of its own
        // (lib/book/book_view.dart), so reading its pages straight through lays out what is near the window.
        if (_drawing) SliverFillRemaining(hasScrollBody: true, child: _view0(context)) else if (!_words) _isJournal ? SliverToBoxAdapter(child: _view0(context)) : _view0(context),
        // The editor stays mounted behind a canvas or an index, hidden, so its caret keeps its place.
        SliverOffstage(offstage: !_words, sliver: widget.editorBuilder(context, spec)),
        if (_words) ...[
          // A new note's blank page: the names under its first line, the template cards under them, and the ghost
          // under those, in the page's flow so it is never behind them.
          if (offered != null)
            SliverToBoxAdapter(
              child: _BlankOffers(
                key: _offers,
                names: offered,
                onName: nameIt,
                cards: cards ? TemplateCards(at: widget.clock?.call() ?? DateTime.now(), taken: widget.takenTitles, onChoose: startFrom, templates: widget.templates, onYours: widget.onTemplates, localOnly: prefs.localOnly, canLocate: _tags != null && _tags!.locations.cannotLocateHere == null, refused: _refusalStands ? _tags?.allowLocationWhere() : null, mapHeader: _tags == null ? null : (context) => const MapPicture(size: MapSize.header, pin: true)) : null,
              ),
            ),
          // `.cm-content { padding-block-end: var(--glacier-space-24) }` (the split layout's `space-8`), taken from
          // the editor while the offers are drawn, and `.body { padding-block-end: var(--app-safe-bottom) }`.
          SliverToBoxAdapter(child: SizedBox(height: (offered != null ? LookEnv.roomUnder(t) : 0) + t.len('app-safe-bottom'))),
          if (_words && seams.tail != null)
            for (final row in seams.tail!(context)) SliverToBoxAdapter(child: row),
          if (book != null && seams.bookFoot != null) SliverToBoxAdapter(child: seams.bookFoot!(context, book)),
          // `.page[data-scrolls] > .body { flex: 1 0 auto }`: the editor is the rest of the page, and a tap there is a tap in it.
          SliverFillRemaining(
            hasScrollBody: false,
            child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _tapUnder, child: const SizedBox.expand()),
          ),
        ],
      ],
    );

    final scroller = seams.around?.call(context, _words ? view : null, words) ?? words;
    final unfold = _unfold ??= UnfoldDriver(vsync: this, still: t.reducedMotion, angles: widget.hinge);

    // `noteRise`: 320ms ease-out, rising 8px as it fades in.
    final curve = CurvedAnimation(parent: _rise, curve: Curves.easeOut);
    final page = t.reducedMotion
        ? scroller
        : AnimatedBuilder(
            animation: curve,
            builder: (context, child) => Opacity(opacity: curve.value, child: Transform.translate(offset: Offset(0, 8 * (1 - curve.value)), child: child)),
            child: scroller,
          );

    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          TopBarFill(
            tools: inBar ? _tools : null,
            tail: inBar ? _more : null,
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerUp,
              onPointerSignal: (_) => _keeper?.touched(),
              // The note goes to smoke as it slips behind the header, and off the bottom where the dock is; not a
              // canvas, which is not a page that scrolls off its foot.
              // The page ends where the keyboard begins, as the web's does (its activity lays the page out above the
              // keyboard): the line being typed can always be scrolled clear of it, and the foot's smoke rests on it.
              child: _AboveKeyboard(
                child: WispEdge(
                  under: under,
                  foot: !_isCanvas,
                  // No scrollbar of a desktop's own on a note: the page's note has none (art/wisp_edge.dart).
                  scrollbar: false,
                  // `.screen[data-unfolding] .body`: paper folded down its middle, foreshortened, flattening as the
                  // hinge does. Only the note moves; the header and the app's own bar are the phone's.
                  child: ValueListenableBuilder<double?>(
                    valueListenable: unfold.progress,
                    child: page,
                    builder: (context, at, child) => at == null
                        ? KeyedSubtree(key: _unfolding, child: child!)
                        : Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(0.72 + 0.28 * at, 0.965 + 0.035 * at, 1),
                            child: KeyedSubtree(key: _unfolding, child: child!),
                          ),
                  ),
                ),
              ),
            ),
          ),
          // The crease's shadow while the note unfolds; nothing the rest of the time (`.crease`).
          ValueListenableBuilder<double?>(
            valueListenable: unfold.progress,
            builder: (context, at, _) => at == null ? const SizedBox.shrink() : IgnorePointer(child: UnfoldCrease(at: at, ink: t.color('app-ink'))),
          ),
          // A note with no words yet: the ghost with its pen, a little under the first line, gone at the first word.
          if (_saving.blank && !_typed && offered == null) _BlankGhost(scroll: _scroll, top: padTop + (authors.isEmpty ? 0 : t.space(2) + 1.5 * 0.85 * t.fontSize('sm')) + t.lenOf('9rem')),
          // The header: glass over the page, holding the note's own controls where the app's bar is not there to.
          HeaderPane(
            child: inBar
                ? null
                : Padding(
                    // `.header { padding-inline: gutters; padding-block: safe-top + space-1, space-2 }`
                    padding: EdgeInsets.fromLTRB(t.len('app-gutter-start'), t.space(1), t.len('app-gutter-end'), t.space(2)),
                    child: LayoutBuilder(
                      builder: (context, box) => Row(mainAxisAlignment: MainAxisAlignment.end, children: [NoteTools(model: _toolsModel, room: box.maxWidth)]),
                    ),
                  ),
          ),
          // The note's one line of problems.
          if (_stopped)
            Positioned(
              top: headerHeight,
              left: 0,
              right: 0,
              child: Semantics(
                liveRegion: true,
                child: ColoredBox(
                  color: t.color('glacier-bg'),
                  child: Padding(
                    // `.problem { padding: var(--glacier-space-1) var(--app-gutter) 0; font-size: sm; color: var(--app-ink-3) }`
                    padding: EdgeInsets.fromLTRB(gutter, t.space(1), gutter, t.space(1)),
                    child: Text(saveStoppedWords, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                  ),
                ),
              ),
            ),
          if (view != null && _words && seams.over != null) ...seams.over!(context, view),
          if (_settingsOpen) _settings(context),
        ],
      ),
    );
  }

  Widget _settings(BuildContext context) {
    final seams = widget.seams;
    final view = _view;
    final versions = widget.versions;
    final mark = _bookmark();
    final speak = _speakWords;
    final words = !_typed || _source;
    void close() => setState(() => _settingsOpen = false);
    return NoteSettings(
      noteId: _id,
      title: _saving.title,
      pinned: _pinned,
      workspaces: widget.workspaces,
      onClose: close,
      onPin: togglePin,
      onArchive: _archive,
      onDelete: _remove,
      marked: mark?.marked ?? false,
      onBookmark: mark == null
          ? null
          : () {
              close();
              mark.onPress();
            },
      onFind: seams.onFind == null || view == null
          ? null
          : () {
              close();
              seams.onFind!(view, '');
            },
      onMakeBoard: !widget.readOnly && words && boardFrom(view?.state.doc.toString() ?? _saving.body) != null ? makeBoard : null,
      name: _typed && !widget.readOnly ? NoteName(value: _saving.title, onChange: renameHere, kind: _isCanvas ? 'canvas' : (_isJournal ? 'journal' : 'notebook')) : null,
      // A notebook's ticket key (docs/DESIGN.md §157), written as its other keys are. Not a journal's.
      ticketKey: _notebookRows && !_isJournal ? NoteTicketKey(value: frontMatterValue(_typedBody, 'key') ?? '', onChange: (typed) => _writeNotebook((was) => withNotebookKey(was, typed))) : null,
      onSpeak: speak == null || widget.readOnly ? null : _speak,
      speakLabel: speak ?? 'Talk into this note',
      look: !_typed && !widget.readOnly ? NoteLook(value: _look, canMap: _tag != null || _look == Look.map, onChange: chooseLook) : null,
      onAi: seams.onAi == null || view == null ? null : (kind, [instruction]) => seams.onAi!(view, kind, instruction),
      onComment: seams.onComment == null || view == null || _typed ? null : () => seams.onComment!(view),
      commentsSummary: seams.commentsSummary?.call(),
      onCommentsList: seams.onCommentsList,
      sharing: seams.sharing?.call(context),
      sharingSection: seams.sharingSection?.call(context),
      linked: seams.linked?.call(context),
      plugins: view == null || widget.readOnly ? null : seams.plugins?.call(view),
      location: seams.location?.call(_tag) ?? _location(_prefs.value),
      history: versions != null && !_isCanvas && !widget.readOnly
          ? NoteHistory(record: versions, keeps: _versioning?.keeps ?? versions.keepsVersions(_id), current: () => _view?.state.doc.toString() ?? _saving.body, onRestore: restoreVersion, onShareFile: seams.shareVersionsFile)
          : null,
      startAt: _settingsAt,
      cheatSheet: seams.cheatSheet,
      say: widget.say,
    );
  }
}

/// What a failed fix says (`NO_FIX`).
const Map<LocateFailure, String> noFix = <LocateFailure, String>{
  LocateFailure.refused: 'Ghost.md wasn’t allowed to know where you are.',
  LocateFailure.blocked: 'Location is off for Ghost.md.',
  LocateFailure.unavailable: 'Couldn’t find where you are. Try again with location on, or outside.',
  LocateFailure.timeout: 'Couldn’t find where you are. Try again with location on, or outside.',
  LocateFailure.none: 'This browser can’t say where you are.',
  LocateFailure.mac: 'This Mac can’t say where it is yet.',
  LocateFailure.ios: 'Ghost.md can’t find where you are on this device yet.',
  LocateFailure.localOnly: 'Local only is on.',
};

/// `.mapCard`: the card's place on the page, a little under what is above it and in from the page's edges; a map
/// note's header is the page's whole width on a phone, and a reading page's card starts at its column.
class _MapPlace extends StatelessWidget {
  const _MapPlace({required this.header, required this.columnStart, required this.child});

  final bool header;
  final double? columnStart;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gutter = t.len('app-gutter');
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final inset = header && !wide ? 0.0 : gutter;
    return Padding(
      padding: EdgeInsetsDirectional.only(top: t.space(2), start: columnStart ?? inset, end: inset),
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    );
  }
}

/// `withFrontMatterTitle` (core/frontMatter.ts): the body named by a `title:` key, first in its front matter, or
/// with the key taken out where the name is empty, and a block that held nothing else with it.
String withFrontMatterTitle(String body, String title) {
  final clean = title.trim();
  final named = clean.isEmpty ? null : 'title: ${quotedTitle(clean, clean)}';
  final lines = body.split('\n');
  final end = frontMatterEnd(lines);
  if (end == 0) return named != null ? '---\n$named\n---\n$body' : body;
  final own = RegExp(r'^\s*title\s*:', caseSensitive: false);
  final keys = [
    ?named,
    for (final key in lines.sublist(1, end - 1))
      if (!own.hasMatch(key)) key,
  ];
  final rest = lines.sublist(end);
  if (keys.isEmpty) return rest.join('\n');
  return [lines[0], ...keys, lines[end - 1], ...rest].join('\n');
}

/// `.blankGhost`: the ghost on a note with no words, in the middle of the column, [top] down the page and going up
/// with it. Nothing to tap, so the editor under it still takes the finger.
class _BlankGhost extends StatelessWidget {
  const _BlankGhost({required this.scroll, required this.top});
  final ScrollController scroll;
  final double top;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) => Positioned(top: top - (scroll.hasClients && scroll.position.hasPixels ? scroll.position.pixels : 0), left: 0, right: 0, child: child!),
      child: const IgnorePointer(child: Ghost(scene: GhostScene.newNote, align: GhostAlign.center)),
    );
  }
}

/// `.cm-blankOffers`: what a new note's blank page offers under its first line. The names it can be given, a row of
/// quiet chips that wraps (`.cm-nameChips`, editor/nameChips.ts); under them the template cards, while they are
/// shown; and under those the ghost (`.offersGhost`).
class _BlankOffers extends StatelessWidget {
  const _BlankOffers({super.key, required this.names, required this.onName, this.cards});

  final List<NameOffer> names;
  final ValueChanged<String> onName;
  final Widget? cards;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gutter = t.len('app-gutter');
    return Padding(
      // `padding-block-start: 0.75rem; padding-inline: var(--app-gutter)`: the gap under line 1 is padding, so a tap
      // aimed at the line lands on the line.
      padding: EdgeInsets.fromLTRB(gutter, t.lenOf('0.75rem'), gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (names.isNotEmpty)
            Semantics(
              container: true,
              label: 'Names for this note',
              // `display: flex; flex-wrap: wrap; gap: var(--glacier-space-2)`
              child: Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [for (final offer in names) _NameChip(offer: offer, onName: onName)]),
            ),
          ?cards,
          // `.offersGhost { padding-block: var(--glacier-space-8) var(--glacier-space-4); pointer-events: none }`
          IgnorePointer(
            child: Padding(
              padding: EdgeInsets.only(top: t.space(8), bottom: t.space(4)),
              child: const Ghost(scene: GhostScene.newNote, align: GhostAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.cm-nameChip`: one name. Quiet: the interface's face, the third ink and a hairline, a size under the words. Its
/// press takes no focus, so the caret stays where it is and the keyboard stays up.
class _NameChip extends StatelessWidget {
  const _NameChip({required this.offer, required this.onName});

  final NameOffer offer;
  final ValueChanged<String> onName;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return GlacierPressable(
      key: ValueKey('name-${offer.kind.name}'),
      semanticLabel: offer.label,
      excludeSemantics: true,
      canRequestFocus: false,
      onPressed: () => onName(offer.name),
      builder: (context, state) {
        final lit = state.hovered || state.focused;
        return GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('full'),
          child: Container(
            // `padding: var(--glacier-space-1) var(--glacier-space-3); border: hairline solid var(--app-rule);
            // border-radius: full; line-height: 1.5; white-space: nowrap`
            padding: EdgeInsets.symmetric(vertical: t.space(1), horizontal: t.space(3)),
            decoration: BoxDecoration(
              border: Border.all(color: lit ? t.color('app-ink-3') : t.color('app-rule'), width: t.len('glacier-hairline')),
              borderRadius: BorderRadius.circular(t.radius('full')),
            ),
            child: Text(offer.name, maxLines: 1, softWrap: false, style: pageText(t, sm, height: 1.5, color: lit ? t.color('app-ink-2') : t.color('app-ink-3'))),
          ),
        );
      },
    );
  }
}

/// Whether the keyboard is up, said to the note's screen as a yes or a no ([_KeyboardUp]). The screen asked the
/// window for the keyboard's height itself, which is another number at every frame of the keyboard's rise and
/// fall, and so was built again whole at each of them, a canvas and its cards with it; what it wants to know
/// (whether to keep room for the phone's bar, whether the page is ready for words) changes twice a keyboard.
class _KeyboardWatch extends StatelessWidget {
  const _KeyboardWatch({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _KeyboardUp(up: MediaQuery.viewInsetsOf(context).bottom > 0, child: child);
}

class _KeyboardUp extends InheritedWidget {
  const _KeyboardUp({required this.up, required super.child});

  final bool up;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_KeyboardUp>()?.up ?? false;

  @override
  bool updateShouldNotify(_KeyboardUp oldWidget) => oldWidget.up != up;
}

/// The page ending where the keyboard begins: the keyboard's height is asked here, where it is used, so its rise
/// lays the page out again and builds nothing of the note's screen.
class _AboveKeyboard extends StatelessWidget {
  const _AboveKeyboard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: child);
}
