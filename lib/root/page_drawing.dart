/// A page drawn to be read outside its own screen, as a note's editor draws it: what a teamspace's home page is drawn
/// with on its organization's dashboard (lib/orgs/ui/teamspace_home.dart; docs/TEAMSPACES.md, "Teamspace home": "an
/// ordinary note drawn as the space's home"), so its ```query fences are what they find, its `[[links]]` open, and
/// its tables, boards and diagrams are drawn, as anywhere.
///
/// It is a note desk's own drawing of a notebook's words (lib/root/note_desk.dart `_bookDrawing`) made from the
/// desk's world alone, with none of what belongs to an open note: no tape, no memos' player, no caret, nothing that
/// edits. A query's rows are written all the same where the library can be (a ticket carried to another lane, a
/// to-do ticked), each in its own note, through the world's writer.
library;

import 'dart:async';

import '../book/book_view.dart' show BookDrawing;
import '../core/link_preview.dart' show noLinkPreviews;
import '../core/preferences.dart';
import '../editor/boards/boards.dart' show drawnBoards;
import '../editor/diagrams/diagrams.dart' show drawnMermaid;
import '../editor/editor.dart';
import '../editor/gantt/gantt.dart' show drawnGantt;
import '../editor/items/items.dart';
import '../editor/marks/marks.dart';
import '../editor/media/canvas_frames.dart';
import '../editor/media/media.dart';
import '../editor/media/note_embeds.dart';
import '../editor/queries/queries.dart';
import '../editor/semantics/line_semantics.dart' show semanticsOpenLink;
import '../editor/tables/tables.dart';
import 'note_desk.dart' show NoteDeskWorld, noteFormats;

/// The drawing of a page read in [world], whose `[[links]]` open by [open] (a title).
BookDrawing pageDrawing(NoteDeskWorld world, {required void Function(String title) open, PreferencesStore? prefs}) {
  final store = prefs ?? preferences;
  final formats = noteFormats();
  final queries0 = world.queryNotes == null
      ? null
      : QueryOptions(
          notes: () => world.queryNotes!(),
          noteId: null,
          open: (id, line) => world.openAt?.call(id, line),
          write: (id, change) => world.write?.call(id, change),
          add: world.addTicket == null ? null : (draft, title, from) => world.addTicket!(draft, title, from),
          events: world.queryEvents,
          ticketMarks: world.ticketMarks,
          bulk: world.bulk,
          labelColours: world.labelColours,
          history: world.ticketHistory,
          listedWritable: () => world.write != null,
        );
  final seams = MediaSeams(
    pictures: world.pictures,
    openLink: world.openLink,
    previewer: world.previewer ?? noLinkPreviews,
    embeds: world.embeds ?? noEmbeds,
    linkPreviews: () => store.value.linkPreviews,
    switches: store,
    placeSwitches: () => (localOnly: store.value.localOnly, mapTiles: store.value.mapTiles),
    mapTiles: world.mapTiles,
    films: FilmSeams(films: world.films),
  );
  return BookDrawing(
    formats: formats,
    extensions: <Extension>[
      markExtensions(formats),
      itemExtensions(wiki: WikiOptions(known: (title) => world.known(title), open: (title, [anchor]) => open(title), body: (title) => world.bodyOf?.call(title))),
      drawnTables(),
      if (world.openTag != null) tagOpener.of(world.openTag!),
      drawnBoards(),
      drawnMermaid(),
      drawnGantt(() => queries0),
      if (queries0 != null) queries(() => queries0),
      if (world.bodyOf != null) canvasFrames(FrameOptions(body: (title) => world.bodyOf?.call(title), known: (title) => world.known(title), open: (title, [anchor]) => open(title))),
      if (world.bodyOf != null) noteEmbeds(EmbedOptions(body: (title) => world.bodyOf?.call(title), open: (title, [anchor]) => open(title), formats: formats)),
      mediaExtensions(seams: seams, places: PlaceMode.live, videos: VideoMode.still),
      if (world.openLink != null) semanticsOpenLink.of((url) => unawaited(world.openLink!(url))),
    ],
    changes: world.changes,
    told: (state) => <StateEffect<Object?>>[
      if (queries0 != null && queryFencesOf(state.doc).isNotEmpty) refreshQueries.of(null),
      if (world.bodyOf != null && hasFrames(state.doc)) refreshCanvasFrames.of(null),
    ],
  );
}

/// Kept so a page's drawing is made once per world, as the dashboard is built again on every tick.
final Expando<BookDrawing> _made = Expando<BookDrawing>('page drawing');

/// [pageDrawing] made once for [world] and kept with it.
BookDrawing pageDrawingOf(NoteDeskWorld world, {required void Function(String title) open}) => _made[world] ??= pageDrawing(world, open: open);
