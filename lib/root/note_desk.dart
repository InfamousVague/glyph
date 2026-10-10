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
///   Undo is an edit in this editor, taking out exactly the pieces the recording put in, what it wrote to other
///   notes is taken back through the library's guarded undo ([NoteDeskWorld.undoCommandMutation]), and the better
///   words wait to write the note while it is open, the editor being its one writer.
///
/// - the tape at the top of a note that has a recording (lib/tapes/note_tape.dart), played by the app's one player,
///   with Add (talk more into the note) and Remove with its Undo (`editor/useNoteTape.ts`), and the phrases as they
///   were spoken under the words (lib/tapes/transcript_words.dart);
///
/// - the AI in the open note (lib/ai/note_ai.dart `NoteAi`, one to a desk): its extensions among the editor's own
///   (the blanks and their Fill pill, the panel a tap on one opens, what it writes arriving out of smoke, the tracked
///   changes), its layer over the page (the strip under the header, the fills' panel), a run from the More sheet,
///   a spoken instruction and a review the note was opened with, and the tape's Summarize;
///
/// - live typing (lib/live/open.dart): a team's note bound to its document for as long as it is open here, its room
///   held, the others' carets and selections drawn in their colours, and the organization told this device is
///   editing it; a note of the account's own live with the account's other devices where the switch is on;
///
/// What differs from the page:
/// - **A picture is added from the phone's chooser** ([NoteDeskWorld.pickPicture], lib/core/phone_pictures.dart):
///   the band's Add image, the +'s Picture and a canvas's picture card, each offered only where there is a
///   chooser. What goes wrong is said as a toast, where the page says it on the note's own line. A picture copied
///   to the clipboard is pasted in by the band's Paste, read by the phone's own reader ([PhoneClipboard]).
/// - **A film is added from the phone's picker** ([NoteDeskWorld.films], lib/core/phone_films.dart): the +'s A
///   video, offered only where there is a picker, its place kept from the tap, "Adding the video." said a moment
///   after its copy starts, and a film copied for a note that was left thrown away (`addVideo`). Its card plays
///   it where it is on this phone (`VideoMode.play`), by the phone's own player.
/// - **A voice memo left in a spoken note is played where it sits** (lib/editor/media/clips.dart): the editor is
///   told the note's tape ([tapeSource], in a compartment so a take added or the recording removed is followed) and
///   given the app's one player as its [MediaSeams.clipPlayer] (lib/tapes/clip_player.dart).
/// - **A place from the +** (`addPlace`): a line of its own where the caret was, kept from the tap, written once the
///   fix has come and its name with it where one comes within three seconds, later only while the line is still
///   the newest change. `afterComposition` is not waited for, and a note's own tag landing meanwhile is not counted
///   out of the history's depth (`tagSteps`), so a name that comes late then is left as its coordinates.
/// - **The map at the top of a tagged note** is drawn here for the note's screen ([NoteSeams.mapCard]): the tiles
///   where the map switch is on and Local only is off, quiet otherwise and for a draft's waiting tag, its tap the
///   phone's maps. The tag itself, and Add my location, are the screen's own over [NoteDeskWorld.tags].
/// - **A link's tap** is handed to the phone where the build has a way to ([NoteDeskWorld.openLink], lib/core/open_link.dart);
///   a test, and a run with no phone half, opens nothing.
/// - **Pick a date is the phone's own calendar** ([NoteDeskWorld.dayPicker], lib/core/phone_day.dart), as the
///   page's was the WebView's: on a list item's date page, in a ticket's panel and in a query. Without one the row
///   is not offered, and Today, Tomorrow and Next week are.
/// - **A canvas has no comments**. A team's canvas is drawn from and edited through its structure in the team's
///   document, the other members' pointers over its cards (lib/live/team_canvas.dart). A canvas is not framed in a note from the + (`AddConfig.canvases` is not given).
/// - **The strip's room is kept clear by the page** (`NoteAiLayer.onRoom`, the page's `--ai-strip-room`): the desk
///   keeps what the layer says ([NoteSeams.headRoom]) and the note's page starts that much lower while the strip
///   is up, told after the frame it was measured in.
/// - **A board's card has no plugin's rows** (`drawnBoards(actions:)`).
/// - **The plugins reach the note through the editor** (lib/editor/items/note_plugins.dart): a swipe on a list item
///   and the quiet words after a line are asked of the app's registry as they are used, a linked to-do's box and
///   its task are kept in step, a linked row opens its menu, and what the note is linked to is drawn at its top
///   (lib/plugins/link_marks.dart), its press the note's More sheet, whose "Linked to" rows are the registry's
///   links and actions ([NoteSeams.plugins]): each link's page inside the sheet, each action run on the note
///   through its editor.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, listEquals;
import 'package:glacier/glacier.dart';
import '../account/ui_state.dart';
import '../ai/available.dart' show AvailabilityController;
import '../ai/kinds.dart' show RunKind;
import '../ai/note_ai.dart';
import '../ai/note_review.dart' show ReviewHost;
import '../ai/review.dart' show ReviewHandoff;
import '../ai/summaries.dart' show SummaryStarter;
import '../capture/recorder.dart' show SpokenAsk;
import '../format/device_facts.dart' show DeviceFacts;
import '../live/editor_binding.dart' show liveBindingSlot;
import '../live/open.dart' show NoteLive, OpenLive, TeamBinding;
import '../live/team_canvas.dart' show TeamCanvasHost, TeamCanvasPeople;
import '../canvas/camera.dart' show CanvasCamera;
import '../canvas/geometry.dart' show Point;
import '../art/lucide.g.dart';
import '../book/book_nav.dart';
import '../book/book_view.dart';
import '../book/journal_view.dart';
import '../canvas/canvas_comments.dart';
import '../canvas/canvas_view.dart';
import '../capture/landing.dart';
import '../comments/ui/note_colours.dart';
import '../comments/ui/note_comments.dart';
import '../core/book.dart';
import '../core/canvas_body.dart';
import '../core/command_mutations.dart' show CommandUndoResult;
import '../core/films.dart';
import '../core/images.dart';
import 'iphone_wiring.dart';
import '../core/geotag.dart' show GeoTag;
import '../core/link_preview.dart' show LinkOpener, LinkPreviewer, noLinkPreviews;
import '../core/location.dart' show LocateFailure, MapsApp, openPlace, tagOf, whyLocateFailed;
import '../core/place_tags.dart' show PlaceTags;
import '../editor/comments/comments.dart';
import '../editor/commands/inserts.dart' show insertLineAt, nameLater, releaseSpot, reserveSpot, spotAt;
import '../core/place_refs.dart' as place_refs;
import '../core/video_refs.dart' show videoMarkdown;
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/preferences.dart';
import '../core/query/query.dart';
import '../editor/band/band.dart' as band;
import '../editor/boards/boards.dart' show drawnBoards;
import '../editor/diagrams/diagrams.dart' show drawnMermaid;
import '../editor/editor.dart';
import '../editor/editor_widget.dart';
import '../editor/find_bar/find_bar.dart';
import '../editor/find_bar/find_marks.dart';
import '../editor/items/items.dart';
import '../editor/marks/marks.dart';
import '../editor/media/canvas_frames.dart';
import '../editor/media/media.dart';
import '../editor/plus/plus.dart';
import '../editor/queries/queries.dart';
import '../editor/semantics/line_semantics.dart' show semanticsOpenLink;
import '../editor/spell/spell.dart' show PhoneSpellChecker, spellCheck;
import '../editor/tables/tables.dart';
import '../editor/tickets/tickets.dart';
import '../editor/view/editor_view.dart';
import '../editor/view/text_panel.dart' show EditorTextPanels;
import '../note/note_editor.dart';
import '../note/note_place.dart';
import '../note/note_screen.dart';
import '../plugins/link_marks.dart';
import '../note/note_settings.dart' show NotePlugins;
import '../plugins/registry.dart' show plugins;
import '../plugins/types.dart' show NoteEditing;
import '../notes/note_templates.dart' show NoteTemplate;
import '../settings/panes/cheat_sheet.dart';
import '../shell/desktop/desktop_commands.dart';
import '../shell/screen.dart' show Keyed;
import '../shell/top_bar_tools.dart' show TopBarTools;
import '../share/ui/share_rows.dart';
import '../tapes/clip_player.dart';
import '../tapes/note_tape.dart';
import '../tapes/player.dart' as tape_player show Tape, TapePlayer;
import '../tapes/transcript_words.dart';

/// How long a place's name is waited for before its line is written with the coordinates (`NAME_WAIT_MS`).
const Duration placeNameWait = Duration(milliseconds: 3000);

/// Whether a document is a note of words, neither a canvas nor a notebook's index: asked by the + on every letter
/// and every move of the caret, and read once for each document.
final DocMemo<bool> _ofWords = DocMemo<bool>((doc) {
  final words = doc.toString();
  return !isCanvasBody(words) && !isBookBody(words);
});

/// The switched-on plugins' inline formattings (`plugins.formats()`, Editor.tsx): what the editor's parser reads and
/// its marks draw. Where nothing was ever put in the registry (a test that builds a note without the app's launch,
/// which is what puts the five that ship there: lib/root/plugin_ground.dart), the app's own marks, which is what
/// the page's registry always holds.
List<GlyphFormat> noteFormats() => plugins.all().isEmpty ? marks : plugins.formats();

/// The marks as the band's Style page lists them, read as the band is drawn (`StyleItems.tsx`): each switched-on
/// plugin's formattings, under its own icon (`format.icon ?? plugin.icon ?? Type`).
List<band.BandFormat> bandFormats() => plugins.all().isEmpty
    ? <band.BandFormat>[for (final mark in marks) band.BandFormat.of(mark, Lucide.all[mark.icon] ?? Lucide.type)]
    : <band.BandFormat>[
        for (final plugin in plugins.enabled())
          for (final format in plugin.formats) band.BandFormat.of(format, Lucide.all[format.icon ?? plugin.icon] ?? Lucide.type),
      ];

/// The effects as the +'s list offers them, at More's end, read as the list is (`addRows.ts` `readGates`).
List<PlusEffect> plusEffects() => <PlusEffect>[
      for (final mark in noteFormats())
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
    this.live,
    this.takeJump,
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
    this.tapePlayer,
    this.noteById,
    this.getNote,
    this.setNoteRecording,
    this.tapes,
    this.onSpeak,
    this.ai,
    this.pickPicture,
    this.films,
    this.dayPicker,
    this.mapTiles,
    this.tags,
    this.forgetTag,
    this.undoCommandMutation,
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

  /// What makes an open note live (lib/live/open.dart), where the build has an account: a team's note bound to its
  /// document, its room held and the others' carets drawn; a note of the account's own, with the switch on.
  final NoteLive? live;

  /// A member's caret a note was opened at (the organization's Jump to cursor), handed over once.
  final Map<String, Object?>? Function(String noteId)? takeJump;

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

  /// The app's one player of a recording (lib/tapes/phone_player.dart); absent, a spoken note draws no tape.
  final tape_player.TapePlayer? tapePlayer;

  /// The note by its id as the library has it now, and read whole from the store (its phrases with it).
  final Note? Function(String id)? noteById;
  final Future<Note?> Function(String id)? getNote;

  /// A tape's length and its phrases written beside its note (`setNoteRecording`), and the tape each note holds.
  final Future<Note?> Function(String id, int? recordingMs, List<Segment> segments)? setNoteRecording;
  final TapeIds? tapes;

  /// Talk more into this note (the tape's Add); absent where nothing records.
  final void Function(String noteId)? onSpeak;

  /// Lets the person choose a picture, keeps it and answers its name (lib/core/phone_pictures.dart); absent, no
  /// picture can be added.
  final PicturePicker? pickPicture;

  /// This phone's films (lib/core/films.dart): the picker where there is one, where each film stands and what
  /// plays it. Absent, a film's line is its poster and its length, and none is added.
  final Films? films;

  /// The calendar Pick a date opens (lib/core/phone_day.dart); absent, no such row.
  final DayPicker? dayPicker;

  /// What draws a map's tiles (lib/editor/media/map_tiles.dart); absent, every map is its quiet card.
  final MapTilesBuilder? mapTiles;

  /// The places notes keep (lib/core/place_tags.dart), where the app can say where the phone is: the map card is
  /// drawn only then, and the + offers A place.
  final PlaceTags? tags;

  /// A place waiting for the note, let go: a landing's Undo took the words it waited for (`setPendingTag(id, null)`).
  final void Function(String noteId)? forgetTag;

  /// Takes back a write a recording made to another note, only while that note is exactly what the write left
  /// (`undoCommandMutation`, lib/core/library.dart). Absent, a landing's Undo leaves such a write and says so.
  final Future<CommandUndoResult> Function(String mutationId)? undoCommandMutation;

  /// What the AI in a note stands on, asked as a desk is made: null where the build has no engine (a test, a
  /// picture, a launch before voice is made), and the desk then has no AI at all.
  final NoteAiWorld? Function()? ai;
}

/// What a desk's [NoteAi] is given of the app (lib/ai/note_ai.dart's own list).
@immutable
class NoteAiWorld {
  const NoteAiWorld({required this.availability, this.deviceFacts, this.reviewHost, this.openForSummaries, this.onGetModel, this.summarize, this.summaryEdited, this.opened});

  /// Whether the AI can run here: the app's one controller.
  final AvailabilityController availability;

  /// The phone as the app knows it, for the strip's card.
  final ValueListenable<DeviceFacts>? deviceFacts;

  /// What the review after a recording asks of the app, and the summary queue's door for an open note.
  final ReviewHost? reviewHost;
  final void Function(String id, SummaryStarter? starter)? openForSummaries;

  /// Settings at the Model card, for a press that needs a model on the phone.
  final VoidCallback? onGetModel;

  /// The tape's Summarize: asks the queue for the note's summary, over a section the person edited with `replace`;
  /// and whether the section in these words is no longer the one the app wrote.
  final void Function(String noteId, bool replace)? summarize;
  final bool Function(String noteId, String body)? summaryEdited;

  /// Told the AI of the note on a desk as it is made, and null as it goes: the root draws the scene over the
  /// window from it (lib/scene/at_work.dart).
  final void Function(String noteId, NoteAi? ai)? opened;
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

  /// The note as it is live in this editor, while it is (lib/live/open.dart), and a team's note's document and
  /// room once they are made: what its canvas is drawn and edited through.
  OpenLive? _live;
  TeamBinding? _team;

  /// A member's spot on this canvas to centre on, where the note was opened at one (`goTo`).
  Point? _goTo;

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

  /// The AI in this note, where the app has an engine: made with the desk and let go with it.
  late final NoteAiWorld? _aiWorld = _world.ai?.call();
  late final NoteAi? _ai = _aiWorld == null
      ? null
      : (NoteAi(
          noteId: widget.noteId,
          flush: () => _flush?.call(),
          body: () => _view?.state.doc.toString() ?? '',
          wisp: () => _prefs.value.wisp,
          toast: _aiToast,
          onGetModel: _aiWorld.onGetModel,
          availability: _aiWorld.availability,
          reviewHost: _aiWorld.reviewHost,
          openForSummaries: _aiWorld.openForSummaries,
        )..addListener(_redraw));

  /// Saves what is typed now, handed over by the note's screen as it is made.
  VoidCallback? _flush;

  /// The note's comments (editor/useNoteComments.tsx): what the drawing opens, what Comment starts, and their
  /// sheet; and whose colour each wears where the note is filed.
  late final NoteColours _wears = NoteColours(
    _world.services,
    widget.noteId,
    // The editor's rounds and washes drawn again in them; and a canvas's rounds, which the desk's own build hands
    // their colours.
    onChange: () {
      _comments.recolour();
      _redraw();
    },
  );
  late final ScreenComments _comments = ScreenComments(noteId: widget.noteId, view: () => _view, say: widget.say, colours: () => _wears.now, account: _world.services?.account)..addListener(_redraw);

  /// A line for the person, as the AI asks for one.
  void _aiToast(AiToast said) {
    if (!mounted) return;
    final action = said.onAction;
    _toasts?.toast(
      message: Text(said.message),
      duration: said.duration == null ? null : Duration(milliseconds: said.duration!),
      action: said.actionLabel == null || action == null ? null : GlacierToastAction(label: said.actionLabel!, onPress: action),
    );
  }

  /// What the note was opened with (lib/root/capture_route.dart `finished`): a spoken instruction, run once the
  /// editor and the AI are ready, and the review a recording handed it.
  void _handed() {
    final ai = _ai;
    if (ai == null) return;
    final ask = widget.ask;
    final said = ask?.value;
    if (ask != null && said is SpokenAsk) ai.ask(NoteAsk(kind: RunKind.of(said.kind) ?? RunKind.ask, instruction: said.instruction, key: ask.key));
    final review = widget.review;
    final handoff = review?.value;
    if (review != null && handoff is ReviewHandoff) ai.review(handoff, review.key);
  }

  /// Reduced motion and the Motion setting's pace, read as the editor is first made (a state field has neither a
  /// context nor a window to ask).
  late final bool _still = context.tokens.reducedMotion;
  late final double _pace = _prefs.value.motionScale;

  /// The inline formattings this note's editor parses and draws: the switched-on plugins', read as the editor is
  /// made, as the page's is (a plugin switched on or off is in the next note opened).
  late final List<GlyphFormat> _formats = noteFormats();

  /// Every piece's extensions, once: another list would be another editor (lib/note/note_editor.dart).
  late final List<Extension> _extensions = <Extension>[
    // NoteScreen.tsx `assist={prefs.assist}`: the keyboard's aids and the spell checker, on unless the preference
    // says otherwise, read as the editor is made.
    editorInput(assist: _prefs.value.assist),
    // Empty until the note is live: then the binding to its document, and the others' carets.
    liveBindingSlot(),
    // The AI's arrivals bring the departures themselves: given twice, every ghost is drawn twice.
    markExtensions(_formats, wispTyping: _ai == null),
    wispStill.of(_still),
    wispPace.of(_pace),
    // With no AI a note has no blanks, but for an iPhone's, which are drawn with no Fill (iphone_wiring.dart).
    if (_ai != null) ...noteAiExtensions(_ai, still: _still) else ...iPhoneBlanks(noteId: () => widget.noteId, say: (message) => _toasts?.toast(message: Text(message)), still: _still),
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
    // Pick a date, on a list item's date page, in a ticket's panel and in a query: the phone's calendar.
    if (_world.dayPicker != null) dayPicker.of(_world.dayPicker!),
    // Boards drawn as boards, the fence still there to edit (Editor.tsx `drawnBoards()`).
    drawnBoards(),
    // A ```mermaid fence drawn as its diagram (Editor.tsx `drawnMermaid()`).
    drawnMermaid(),
    // A ticket's front matter as its properties, and a [[GHO-12]] with the ticket's title.
    if (_world.tickets != null) tickets(() => _world.tickets?.call(widget.noteId)),
    // A ```query fence drawn as what it finds in the library: its lines where there is none.
    if (_world.queryNotes != null) queries(() => _queries),
    // ![[A canvas]] on a line of its own draws that canvas in a frame (Editor.tsx `canvasFrames`).
    if (_world.bodyOf != null)
      canvasFrames(FrameOptions(body: (title) => _world.bodyOf?.call(title), known: (title) => _world.known(title), open: (title, [anchor]) => _world.open(title, anchor))),
    // Each `[^c1]` a round in its author's colour, and the ```comments fence drawn as its threads (Editor.tsx
    // `noteComments`).
    noteComments(() => _comments.hooks),
    mediaExtensions(
      seams: MediaSeams(
        pictures: _world.pictures,
        openLink: _world.openLink,
        linkMenus: LinkMenus(say: (message) => widget.say(message)),
        previewer: _world.previewer ?? noLinkPreviews,
        linkPreviews: () => _prefs.value.linkPreviews,
        switches: _prefs,
        placeSwitches: () => (localOnly: _prefs.value.localOnly, mapTiles: _prefs.value.mapTiles),
        onOpenPlace: _openPlace,
        mapTiles: _world.mapTiles,
        clipPlayer: _clips,
        films: FilmSeams(films: _world.films),
      ),
      // A place in the words draws its map under its line, as the note's own tag does at its top.
      places: PlaceMode.live,
      // A film plays in its note's own screen, where it is on this phone.
      videos: _world.films == null ? VideoMode.still : VideoMode.play,
    ),
    // The note's recording, for the voice memos in it: changed when a take is added or the recording removed.
    _tapeSlot.of(tapeSource.of(_tapeFor = _memoTape())),
    _plus.extension,
    findBarExtensions,
    // The phone's spell checker, asked about the words near the caret a moment after the person stops, and a red
    // wave under each it would have otherwise (lib/editor/spell; the page's `spellcheck="true"`). Nothing on a
    // device whose engine has no checker to ask.
    if (const PhoneSpellChecker().supported) spellCheck(),
    // A link a screen reader activates is opened as a tap on it is (lib/editor/semantics/line_semantics.dart).
    if (_world.openLink != null) semanticsOpenLink.of((url) => unawaited(_world.openLink!(url))),
  ];

  /// What plays a voice memo: the app's one player of a recording, where there is one.
  late final TapeClipPlayer? _clips = _world.tapePlayer == null ? null : TapeClipPlayer(_world.tapePlayer!);
  final Compartment _tapeSlot = Compartment();
  Tape _tapeFor = Tape.none;

  /// The tape the note's memos are stretches of (Editor.tsx's `tape` and `tapeId`): the note's own recording, by
  /// its id, where it has one and there is a player; none otherwise, and its memos are then quiet marks.
  Tape _memoTape() {
    final note = _world.noteById?.call(widget.noteId);
    if (_world.tapePlayer == null || note == null || (note.recordingMs ?? 0) <= 0) return Tape.none;
    return Tape(src: widget.noteId, id: _world.tapes?.tapeId(widget.noteId));
  }

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
    _aiWorld?.opened?.call(widget.noteId, _ai);
    _handed();
    // A desktop's Command-F, and the Mac's Edit › Find: this note's find bar, with what is selected in it.
    _stopFind = desktopCommands.on(DesktopCommand.find, () {
      final view = _view;
      if (view == null || !mounted || _leaving) return false;
      final picked = view.state.selection.main;
      _openFind(view, picked.empty ? '' : view.state.sliceDoc(picked.from, picked.to));
      return true;
    });
  }

  VoidCallback? _stopFind;

  /// The note's tape, once it has a recording and there is a player to play it.
  tape_player.Tape? _tape;

  tape_player.Tape? _tapeNow() {
    final player = _world.tapePlayer;
    final note = _world.noteById?.call(widget.noteId);
    if (player == null || note == null) return _tape;
    final tape = _tape;
    if (tape == null) {
      if ((note.recordingMs ?? 0) <= 0) return null;
      return _tape = tape_player.Tape(note, player: player, getNote: _world.getNote)..addListener(_redraw);
    }
    if (!identical(tape.note, note)) tape.note = note;
    return tape;
  }

  /// The recording taken off the note, with an Undo that puts it back (`removeRecording`). The words stay: only
  /// the length and the phrases go, and the tape the note's voice memos play from is unnamed until the Undo.
  Future<void> _removeRecording() async {
    final tape = _tape;
    final write = _world.setNoteRecording;
    if (tape == null || write == null) return;
    final id = widget.noteId;
    final memos = hasClips(_view?.state.doc.toString() ?? '');
    await tape.player.pause().then<void>((_) {}, onError: (Object _) {});
    final full = await _world.getNote?.call(id).then<Note?>((note) => note, onError: (Object _) => null);
    final ms = tape.length;
    final segments = full?.segments ?? tape.segments ?? const <Segment>[];
    final held = _world.tapes?.tapeId(id);
    _world.tapes?.setTapeId(id, null);
    try {
      await write(id, null, const <Segment>[]);
    } catch (failure) {
      _world.tapes?.setTapeId(id, held);
      widget.say('The recording couldn’t be removed: $failure');
      return;
    }
    if (!mounted) return;
    _toasts?.toast(
      message: Text(memos ? 'Recording removed. Its voice memos are quiet until you undo.' : 'Recording removed.'),
      duration: const Duration(seconds: 5),
      action: GlacierToastAction(
        label: 'Undo',
        onPress: () {
          _world.tapes?.setTapeId(id, held);
          unawaited(write(id, ms, segments).then<void>((_) {}, onError: (Object _) {}));
        },
      ),
    );
  }

  GlacierToastController? _toasts;
  int? _landed;
  bool _saidLanding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _toasts = GlacierToast.of(context);
    _haptic = HapticsProvider.of(context);
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
        action: GlacierToastAction(label: 'Undo', onPress: () => unawaited(_undoLanding(landing))),
      );
    });
  }

  /// The Undo: exactly the pieces of text the recording put in, found where they were written and taken out as one
  /// edit, which the note's own saving writes like typing and the editor's undo can bring back. A piece edited
  /// since is left alone, and the toast says so. Writes the recording made to other notes are reversed through the
  /// library's `undo_command`, which checks each is still as it left it; one that is not is left alone and counted
  /// with the pieces. The tape is never touched.
  Future<void> _undoLanding(CaptureLanding landing) async {
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
    final undo = _world.undoCommandMutation;
    for (final mutationId in landing.others) {
      final undone = undo == null ? null : await undo(mutationId).then<CommandUndoResult?>((result) => result, onError: (Object _) => null);
      if (undone?.status != 'undone' && undone?.status != 'already-undone') missing += 1;
    }
    // Only for words taken out of this note: the better words of what stays in it still come.
    final fromMs = landing.fromMs;
    if (removed && fromMs != null) _world.dropRefine?.call(widget.noteId, fromMs.toInt());
    // And a tag that waited for those words is let go with them.
    if (removed) _world.forgetTag?.call(widget.noteId);
    // After the pressed toast has gone, which pressing its action does just after this returns. Said by the app's
    // toasts, so a note left while its other notes were asked is still told of, as on the page.
    await Future<void>.value();
    if (missing > 0) _toasts?.toast(message: Text('${landing.title} has changed since, so it was left as it is.'), duration: const Duration(seconds: 5));
  }

  @override
  void didUpdateWidget(NoteDesk oldWidget) {
    super.didUpdateWidget(oldWidget);
    _land();
    if (oldWidget.ask?.key != widget.ask?.key || oldWidget.review?.key != widget.review?.key) _handed();
    if (identical(oldWidget.world.changes, _world.changes)) return;
    oldWidget.world.changes?.removeListener(_libraryChanged);
    _world.changes?.addListener(_libraryChanged);
  }

  /// The library changed: any note changed may change what a query finds, and another ticket closed or a person
  /// named changes a panel (Editor.tsx's two effects). Told after the frame where one is being built.
  ///
  /// Told only of what the open note reads. Every change of the library used to be sent into the editor as three
  /// effects and drawn as a whole build of the desk, and the commonest change of all is this note's own save, a
  /// few times a second while it is typed in: a note with no query, no ticket's panel or key and no framed canvas
  /// reads nothing of the library and is told nothing; one that reads it is told when another note changed, or
  /// its own times where a query reads those ([_libraryMoved]); and the desk is drawn again only when the note's
  /// recording changed, which is all of the library it draws.
  void _libraryChanged() {
    void tell() {
      final view = _view;
      // The tape follows its note: a take added, the recording removed or put back.
      if (mounted && _world.tapePlayer != null && _recordingMoved()) setState(() {});
      if (!mounted || view == null) return;
      final tape = _memoTape();
      final retaped = tape != _tapeFor;
      if (retaped) {
        _tapeFor = tape;
        _clips?.stop();
      }
      final queried = _world.queryNotes != null && queryFencesOf(view.state.doc).isNotEmpty;
      final ticketed = _world.tickets != null && readsTickets(view.state);
      // A canvas framed in this note may have been drawn on: its frame is looked at again.
      final framed = _world.bodyOf != null && hasFrames(view.state.doc);
      final moved = (queried || ticketed || framed) && _libraryMoved(ownTimes: queried);
      final effects = <StateEffect<Object?>>[
        if (queried && moved) refreshQueries.of(null),
        if (ticketed && moved) refreshTickets.of(null),
        if (framed && moved) refreshCanvasFrames.of(null),
        if (retaped) _tapeSlot.reconfigure(tapeSource.of(tape)),
      ];
      if (effects.isNotEmpty) view.dispatch(TransactionSpec(effects: effects));
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      tell();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => tell());
    }
  }

  /// The note's recording as the desk last drew it: its length and its phrases, which is all the tape reads of its
  /// note beside what never changes.
  ({int? ms, List<Segment>? segments})? _recording;

  bool _recordingMoved() {
    final note = _world.noteById?.call(widget.noteId);
    final was = _recording;
    _recording = (ms: note?.recordingMs, segments: note?.segments);
    if (was == null) return true;
    return was.ms != note?.recordingMs || !(identical(was.segments, note?.segments) || listEquals(was.segments, note?.segments));
  }

  /// The library as the editor's pieces were last told of it: the notes a query reads, each by its id, its words
  /// and its times; and this note as the library held it then.
  List<QueryNote>? _toldOf;
  Note? _ownTold;

  /// Whether the library differs, in what the open note's editor reads of it, from when its pieces were last told.
  /// The note's own words never count (the editor's own are read in their place), and its own times only where a
  /// query in it reads them ([ownTimes]). A change that left this note as it was is another note's, shown or put
  /// away, and counts.
  bool _libraryMoved({required bool ownTimes}) {
    final read = _world.queryNotes;
    if (read == null) return true;
    final now = read();
    final was = _toldOf;
    _toldOf = now;
    final own = _world.noteById?.call(widget.noteId);
    final ownMoved = _world.noteById != null && !identical(own, _ownTold);
    _ownTold = own;
    if (was == null || !ownMoved) return true;
    if (identical(was, now)) return false;
    final id = widget.noteId;
    var a = 0, b = 0;
    for (;;) {
      if (!ownTimes) {
        while (a < was.length && was[a].id == id) {
          a += 1;
        }
        while (b < now.length && now[b].id == id) {
          b += 1;
        }
      }
      if (a == was.length || b == now.length) return a != was.length || b != now.length;
      final x = was[a], y = now[b];
      if (x.id != y.id || x.updatedAt != y.updatedAt || x.createdAt != y.createdAt) return true;
      if (x.id != id && !identical(x.body, y.body) && x.body != y.body) return true;
      a += 1;
      b += 1;
    }
  }

  /// Pictures put into the open note from the phone's chooser, where there is one (`useNotePictures`).
  late final NotePictures? _pictures = _world.pickPicture == null || widget.readOnly
      ? null
      : (NotePictures(view: () => _view, pick: _world.pickPicture, store: _world.pictures, onPlaced: () => _haptic?.call(HapticKind.light))..addListener(_pictureSaid));
  HapticFn? _haptic;

  /// A picture that did not come in says why.
  void _pictureSaid() {
    final problem = _pictures?.problem;
    if (problem != null && mounted) widget.say(problem);
  }

  /// A + may show: a note of words that can be written, with find put away.
  bool _plusAllowed() {
    final view = _view;
    if (view == null || view.state.readOnly || _finding != null) return false;
    return _ofWords.of(view.state.doc);
  }

  /// The desk is being let go: what its pieces say as they close is not drawn.
  bool _leaving = false;

  @override
  void dispose() {
    _leaving = true;
    _stopFind?.call();
    _world.holdNote?.call(widget.noteId, false);
    _live?.close();
    if (_ai case final ai?) {
      _aiWorld?.opened?.call(widget.noteId, null);
      ai.attach(null);
      ai.removeListener(_redraw);
      ai.dispose();
    }
    _comments.removeListener(_redraw);
    _comments.dispose();
    _wears.dispose();
    _pictures?.removeListener(_pictureSaid);
    _pictures?.dispose();
    // A memo still sounding stops with its note.
    _clips?.stop();
    _clips?.dispose();
    _tape?.removeListener(_redraw);
    _tape?.dispose();
    // Leaving the note takes its toast with it: an Undo for words no longer on screen would undo them unseen.
    if (_saidLanding) _toasts?.dismiss();
    _world.changes?.removeListener(_libraryChanged);
    _bookmark?.dispose();
    _stripRoom.dispose();
    _band.dispose();
    _plus.dispose();
    super.dispose();
  }

  /// The view the seams were last handed: what belongs to a view is made again for another.
  void _adopt(EditorView view) {
    if (identical(view, _view)) return;
    _view = view;
    // A new note takes the focus as it is built, before the desk has its view, and the + asked then is refused
    // (`_plusAllowed`): asked again once the frame is over, so the + stands beside the blank first line from the
    // start, as on the page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_view, view)) return;
      _plus.recheck(view);
      // "Add a comment" from the note's menu in a list, asked before the editor was here; and the colours the
      // rounds were first drawn without.
      _comments.takeAsk();
      _comments.recolour();
    });
    // Where the note was opened at (the dashboard's Jump to cursor): a member's caret, which the live note puts the
    // selection at, or their spot on a canvas, which the canvas is centred on.
    final jump = widget.readOnly ? null : _world.takeJump?.call(widget.noteId);
    if (jump != null && jump['x'] is num && jump['y'] is num) _goTo = (x: (jump['x']! as num).toDouble(), y: (jump['y']! as num).toDouble());
    // Live in this editor from here on: a note in the Trash is read, not typed in with anyone.
    _live?.close();
    _live = widget.readOnly
        ? null
        : _world.live?.open(view, widget.noteId, jump: jump, onTeam: (team) {
            // Told as the team's binding is made, and as it goes with the note's being taken out of the team; and
            // as the desk itself goes, when there is nothing left to draw.
            if (mounted && !_leaving) setState(() => _team = team);
          });
    _ai?.attach(view);
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
        formats: _formats,
        extensions: _extensions,
        draw: (context, view, env) => Editor(
          view: view,
          controller: _editor,
          env: env,
          meHue: spec.meHue,
          footClear: spec.footClear,
          headerInset: spec.pageHead ?? spec.headClear,
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
        config: AddConfig(
          titles: _world.titles,
          own: widget.title,
          localOnly: _prefs.value.localOnly,
          effects: plusEffects(),
          // Every canvas among the notes, for the +'s A canvas: a frame of it drawn in the words.
          canvases: _world.bodyOf == null ? null : () => <String>[for (final title in _world.titles()) if (isCanvasBody(_world.bodyOf!(title) ?? '')) title],
          boards: true,
          databases: _world.queryNotes != null,
          tickets: _world.tickets != null,
          // Not on an iPhone, where the page's + has no picture (iphone_wiring.dart); the band's Add image stays.
          onPicture: _pictures == null || !plusOffersPicture() ? null : () => unawaited(_pictures.addPhoto()),
          onVideo: _world.films?.pick == null || widget.readOnly || view == null ? null : () => unawaited(_addVideo(view)),
          // A row that can never work is not drawn: only where the phone can say where it is at all.
          onPlace: _world.tags != null && _world.tags!.locations.cannotLocateHere == null && view != null ? () => unawaited(_addPlace(view)) : null,
        ),
        child: band.ContextBand(
          view: view,
          controller: _band,
          say: widget.say,
          onFind: view == null ? null : (text) => _openFind(view, text),
          // Comment, on the selection the band was opened over or on the caret's line (ContextMenu.tsx).
          onComment: _comments.start,
          formats: bandFormats(),
          fields: bandFields,
          onAddImage: _pictures?.addPhoto,
          // The phone's own reader, which copies a picture out of the clipboard for the note to adopt.
          clipboard: const band.PhoneClipboard(),
          onPasteImage: _pictures?.pasteImage,
          boards: true,
          child: page,
        ),
      ),
    );
  }

  List<Widget> _over(BuildContext context, EditorView view) {
    _adopt(view);
    final finding = _finding;
    final ai = _ai;
    final t = context.tokens;
    // Where the header ends, as the note's screen counts it: the bar's own tools, or the header's ring under the
    // phone's status bar.
    final inBar = TopBarTools.maybeOf(context) != null;
    final headerEnd = inBar ? t.len('app-safe-top') + t.space(1) + t.space(2) : t.len('app-safe-top') + t.space(1) + t.len('app-bar-ring') + t.space(2);
    return <Widget>[
      // The panels a view shows beside its words (lib/editor/view/text_panel.dart): a result under its line.
      Positioned.fill(child: EditorTextPanels(view: view)),
      // The AI's one layer: the strip under the header and the panel a tap on a blank opens.
      if (ai != null) Positioned.fill(child: NoteAiLayer(ai: ai, top: headerEnd, onRoom: _roomFor, deviceFacts: _aiWorld?.deviceFacts, canUndo: !widget.readOnly)),
      // The comments' sheet, while one is open: drawn over the window, taking no room here.
      ?_comments.sheet(context),
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

  /// The room the AI's strip takes under the header, as its layer measures it: the page pads itself by it.
  final ValueNotifier<double> _stripRoom = ValueNotifier<double>(0);

  /// Told while the strip is being laid out, so kept after the frame: the page is one of its listeners.
  void _roomFor(double room) {
    if (room == _stripRoom.value) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _stripRoom.value = room;
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  ({bool marked, VoidCallback onPress}) _bookmarkOf(EditorView view, ScrollPosition page) {
    _adopt(view);
    final mark = _bookmark!;
    return (marked: mark.marked, onPress: mark.press);
  }

  /// The bookmark written in the note, as the place to open at: the top of its line.
  Place? _writtenBookmark(EditorView view) {
    final line = bookmarkLineOf(view.state.doc);
    if (line == null || line > view.state.doc.lines) return null;
    return Place(view.state.doc.line(line).from, 0);
  }

  /// A map's tap: the place in the phone's maps, by its name or its coordinates and never the note's title.
  void _openPlace(place_refs.GeoTag tag) {
    final open = _world.openLink;
    if (open != null) unawaited(openPlace(tag, open, MapsApp.androidGeo));
  }

  /// A place from the + beside the line (`addPlace`): a line of its own where the caret was, a link to a `geo:`
  /// address that draws its map card, apart from the note's own tag above. The place is kept from the tap, the fix
  /// is found (said after a moment), and the name is asked while it is and waited for a few seconds, so the place
  /// and its name land as one write and one Undo. A note left before the fix, or a place let go, writes nothing.
  Future<void> _addPlace(EditorView editor) async {
    final tags = _world.tags;
    if (tags == null) return;
    final toasts = _toasts;
    final haptics = HapticsProvider.of(context);
    final kept = reserveSpot(editor.state);
    editor.dispatch(kept.tr);
    var spot = kept.spot;
    var said = false;
    final slow = Timer(const Duration(milliseconds: 600), () {
      said = true;
      toasts?.toast(message: const Text('Finding where you are.'), duration: const Duration(days: 1));
    });
    void quiet() {
      slow.cancel();
      if (said) toasts?.dismiss();
    }

    bool here() => mounted && identical(_view, editor);
    void letGo() {
      if (here()) editor.dispatch(releaseSpot(editor.state, spot));
    }

    final place_refs.GeoTag tag;
    try {
      tag = tagOf(await tags.locations.locate());
    } catch (failure) {
      quiet();
      letGo();
      if (!mounted) return;
      final why = whyLocateFailed(failure);
      tags.rememberRefusal(why);
      haptics(HapticKind.warning);
      toasts?.toast(
        message: Text(noFix[why]!),
        action: why == LocateFailure.blocked && tags.locations.onPhone ? GlacierToastAction(label: 'Open settings', onPress: () => unawaited(tags.locations.openSettings())) : null,
      );
      return;
    }
    tags.forgetRefusal();
    // Left while the fix was coming, or the place was let go: nothing is asked for and nothing is written.
    if (!here() || spotAt(editor.state, spot) == null) {
      quiet();
      letGo();
      return;
    }
    String? name;
    Future<String?>? late;
    if (tags.locations.canAskPlace) {
      final asked = tags.locations.placeName(tag);
      final waited = await Future.any<Object?>(<Future<Object?>>[asked, Future<Object?>.delayed(placeNameWait, () => #waited)]);
      if (waited == #waited) {
        late = asked;
      } else {
        name = waited as String?;
      }
    }
    if (!here()) {
      quiet();
      return;
    }
    final line = place_refs.placeMarkdown(tag, name);
    final landed = insertLineAt(editor.state, spot, line, userEvent: 'input.plus.drawn', apart: true);
    editor.dispatch(landed.tr);
    letGo();
    final next = reserveSpot(editor.state, landed.lineStart);
    editor.dispatch(next.tr);
    spot = next.spot;
    final depth = undoDepth(editor.state);
    quiet();
    haptics(HapticKind.light);
    if (late == null) return letGo();
    final named = await late;
    if (named != null && here()) {
      final write = nameLater(editor.state, spot, depth, line, place_refs.placeMarkdown(tag, named));
      if (write != null) editor.dispatch(write);
    }
    letGo();
  }

  /// A film from the + beside the line (NoteScreen.tsx `addVideo`): picked with the phone's picker, copied with its
  /// poster and kept, then written as a line of its own where the caret was, its poster linked to it, which draws
  /// its card. The place is kept from the tap, since the picker leaves the app and a long film takes a while to
  /// copy; "Adding the video." says so a moment after the copy starts, and not while the picker is still up. A
  /// film copied for a note that was left, or whose place went, is thrown away rather than kept for nothing.
  Future<void> _addVideo(EditorView editor) async {
    final films = _world.films;
    final pick = films?.pick;
    if (pick == null) return;
    final toasts = _toasts;
    final haptics = HapticsProvider.of(context);
    final kept = reserveSpot(editor.state);
    editor.dispatch(kept.tr);
    final spot = kept.spot;
    var said = false;
    Timer? slow;
    void copying() {
      slow?.cancel();
      slow = Timer(const Duration(milliseconds: 600), () {
        said = true;
        toasts?.toast(message: const Text('Adding the video.'), duration: const Duration(days: 1));
      });
    }

    void quiet() {
      slow?.cancel();
      if (said) toasts?.dismiss();
    }

    bool wanted() => mounted && identical(_view, editor) && spotAt(editor.state, spot) != null;
    try {
      final film = await pick(keep: wanted, copying: copying);
      quiet();
      if (film == null || !wanted()) return;
      filmAdded(film.poster, film.width, film.height);
      final landed = insertLineAt(editor.state, spot, videoMarkdown(film.poster, film.video, film.ms), userEvent: 'input.plus.drawn', apart: true);
      editor.dispatch(landed.tr);
      haptics(HapticKind.light);
    } catch (failure) {
      quiet();
      if (!mounted) return;
      haptics(HapticKind.warning);
      widget.say(failureWords(failure));
    } finally {
      if (mounted && identical(_view, editor)) editor.dispatch(releaseSpot(editor.state, spot));
    }
  }

  /// The map at the top of a tagged note (editor/MapCard.tsx as NoteScreen.tsx draws it).
  Widget _mapCard(BuildContext context, GeoTag tag, {required bool header, required bool quiet, required bool arrive, required bool leave, VoidCallback? onLeft}) {
    final prefs = _prefs.value;
    final tiles = !prefs.localOnly && prefs.mapTiles;
    return MapCard(
      tag: place_refs.GeoTag(lat: tag.lat, lon: tag.lon, place: tag.place, rough: tag.rough),
      size: header ? MapSize.header : MapSize.card,
      mode: tiles && !quiet ? MapCardMode.map : MapCardMode.quiet,
      quietWhy: prefs.localOnly ? QuietWhy.localOnly : (!prefs.mapTiles ? QuietWhy.off : null),
      arrive: arrive,
      leave: leave,
      onLeft: onLeft,
      onOpen: _openPlace,
      tiles: _world.mapTiles,
    );
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
    final ai = _ai;
    final seams = NoteSeams(
      saving: (flush) => _flush = flush,
      // The More sheet's AI rows: a run of that kind on this note.
      // On an iPhone, which has no AI, the rows are drawn all the same and a press says so (iphone_wiring.dart).
      onAi: ai == null || widget.readOnly ? (widget.readOnly ? null : iPhoneAiRows((message) => _toasts?.toast(message: Text(message)))) : (view, kind, [instruction]) {
              final run = RunKind.of(kind);
              if (run != null) ai.runAi(run, instruction);
            },
      onFind: _openFind,
      // Comment in the bar and in More, and More's "3 comments, 1 open" with their list.
      onComment: (view) => _comments.start(),
      commentsSummary: _comments.summary,
      onCommentsList: _comments.openList,
      // The More sheet's "Linked to": each plugin's link and its page, and each action, run through this editor.
      plugins: (view) {
        _adopt(view);
        return NotePlugins(links: plugins.noteLinks(), actions: plugins.noteActions(), editing: _editing);
      },
      bookmark: _bookmarkOf,
      writtenBookmark: _writtenBookmark,
      cheatSheet: (context) => const CheatSheet(),
      // The bar's Share and the More sheet's Sharing are there signed in or out, as on the page (NoteScreen.tsx
      // `actions`, NoteSettings): without an account, or in a build with no service, the row says to sign in first.
      onShare: () => setState(() => _sharing = true),
      sharingSection: (context) => ShareRows(services: services, noteId: widget.noteId, kind: _shareKind),
      // A page's notebook, its place in it and the pages either side, over and under its words.
      bookBar: (context, place) => BookBar(place: place, open: _openWithin),
      bookFoot: (context, place) => BookFoot(place: place, open: _openWithin),
      // A change to the canvas is a change to the note: written into the body as the spec's JSON, and saved the way
      // typing is.
      canvas: (context, body, onChange) {
        Widget view(BuildContext context, String body, ValueChanged<String>? onChange, [CanvasCamera? camera, TeamCanvasPeople? people]) {
          final readOnly = widget.readOnly || onChange == null;
          Widget drawn(CanvasThreads? threads, String Function(String handle)? hue) => canvasSeam(
                wiki: CanvasWiki(known: _world.known, open: _world.open, body: _world.bodyOf, titles: _world.titles),
                pictures: _world.pictures,
                pickPicture: widget.readOnly ? null : _world.pickPicture,
                openLink: _world.openLink,
                threads: threads,
                threadHue: hue,
                readOnly: readOnly,
                camera: camera,
                // Jump to cursor from an organization's dashboard: a member's spot on the canvas.
                goTo: _goTo,
                onEditing: people?.onEditing,
                editedBy: people?.editedBy,
                team: people != null,
              )(context, body, onChange ?? (_) {});
          // A canvas that cannot change draws no rounds and has no Comment; one that can has its threads in the
          // note's own sheet, each round in its author's colour (canvas/useCanvasComments.tsx).
          if (readOnly) return drawn(null, null);
          return CanvasComments(body: body, colours: () => _wears.now, account: _world.services?.account, builder: (context, threads, hue) => drawn(threads, hue));
        }

        // A team's canvas is its structure in the team's document, drawn and edited through it, with the other
        // members' pointers over its cards (lib/live/team_canvas.dart); any other is the note's own, whole.
        final team = widget.readOnly ? null : _team;
        return team == null ? view(context, body, onChange) : TeamCanvasHost(key: ObjectKey(team.doc), team: team, body: body, onChange: onChange, draw: view);
      },
      // What the note is linked to, at its top; pressed, the note's More sheet, where a link is changed.
      head: (context, openSettings) {
        final tape = _tapeNow();
        final speak = _world.onSpeak;
        return <Widget>[
          // Only a spoken note has a tape.
          if (tape != null && tape.length > 0)
            NoteTape(
              note: tape.note,
              title: widget.title.isEmpty ? 'Untitled' : widget.title,
              tape: tape,
              onSpeak: speak == null || widget.readOnly ? null : () => speak(widget.noteId),
              onRemove: () => unawaited(_removeRecording()),
              hasMemos: hasClips(_view?.state.doc.toString() ?? ''),
              // The recording's summary: queued from here, and landed in this editor as a run. Only where the AI
              // can run.
              summary: _ai != null && _ai.canSummarize && _aiWorld?.summarize != null
                  ? TapeSummary(
                      ask: (replace) {
                        _flush?.call();
                        _aiWorld!.summarize!(widget.noteId, replace);
                      },
                      edited: () => _aiWorld?.summaryEdited?.call(widget.noteId, _view?.state.doc.toString() ?? '') ?? false,
                    )
                  : null,
            ),
          LinkMarks(noteId: widget.noteId, onPress: openSettings),
        ];
      },
      tail: (context) {
        final tape = _tape;
        return <Widget>[if (tape != null && tape.length > 0) TranscriptWords(tape: tape)];
      },
      mapCard: _world.tags != null ? _mapCard : null,
      book: _book,
      journal: _journal,
      around: _around,
      over: _over,
      headRoom: _ai == null ? null : _stripRoom,
    );
    final built = widget.builder(context, _buildEditor, seams);
    // The note's share link, from the bar's Share: the More sheet's rows in a window of their own (NoteScreen.tsx
    // `sharing`). The sheet draws in the app's overlay and takes no room here.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        built,
        if (_sharing) ShareSheet(services: services, noteId: widget.noteId, title: widget.title, kind: _shareKind, onClose: () => setState(() => _sharing = false)),
      ],
    );
  }

  /// The bar's Share was pressed, and its sheet is up.
  bool _sharing = false;

  /// `isJournal ? 'journal' : isBook ? 'notebook' : 'note'`.
  ShareKind get _shareKind {
    final doc = _view?.state.doc.toString() ?? '';
    return isJournalBody(doc) ? ShareKind.journal : (isBookBody(doc) ? ShareKind.notebook : ShareKind.note);
  }
}
