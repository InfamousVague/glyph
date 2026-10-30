/// The links between notes, put on a note's screen: what lib/root hands each open note (a [NoteLinksHere]) and
/// what the side panel draws for the note on screen.
///
/// - **On the note's tools**: Links, with the number of notes that link here on its ring, which opens the More
///   sheet at the Links page (lib/note/note_screen.dart, `NoteLinksSeam`).
/// - **On the More sheet**, under "Links and outline": Links (lib/links/links_panel.dart, "Linked from" and
///   "Mentioned in"), Outline (lib/links/outline.dart, with the note's length: lib/links/word_count.dart), Local
///   graph (lib/links/graph_view.dart) and Copy link to this line (lib/links/line_link.dart).
/// - **At the foot of the note's words**: "Linked from" and "Mentioned in" (lib/links/backlinks_foot.dart), drawn
///   under its last line wherever the note has a note linking to it ([NoteLinksHere.foot]).
/// - **In the side panel**, on a screen wide enough for two panes (a Fold opened, a Mac): a Links tab and an
///   Outline tab beside the book's index and the history ([asideLinks], [asideOutline]). The outline there follows
///   the page as it scrolls, so the note's screen hands its editor and its page over as they arrive
///   ([openNotePage]).
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/lucide.g.dart';
import '../core/link_index.dart';
import '../editor/editor.dart';
import '../editor/view/editor_view.dart';
import '../note/note_screen.dart' show NoteLinksSeam;
import '../note/note_settings.dart' show NoteSheetItem, NoteSheetSection;
import '../sheet/kit.dart';
import 'backlinks_foot.dart';
import 'line_link.dart';
import 'links_panel.dart';
import 'outline.dart';
import 'word_count.dart';

/// What the app gives every note's links.
@immutable
class NoteLinksApp {
  const NoteLinksApp({required this.indexer, required this.openAt, required this.say, this.link, this.localGraph, this.placeOf, this.readable});

  final LinkIndexer indexer;

  /// Opens a note at a line, from 0.
  final void Function(String id, int line) openAt;

  /// Makes a mention a link in its note (an edit through the library, with an Undo), answering whether it did.
  final Future<bool> Function(Mention mention, LinkPlace place)? link;

  /// The local graph of a note, over the app.
  final void Function(String noteId, String title)? localGraph;

  /// A toast.
  final void Function(String message) say;

  /// Where a note is kept, in words, for the foot's rows: its workspace, else its folder.
  final String? Function(String id)? placeOf;

  /// Whether a note may be listed: a team note of an organization the account is still in, or any of its own.
  final bool Function(String id)? readable;
}

/// The note on screen's editor and page, while it has both: what the side panel's outline follows.
typedef OpenNotePage = ({String noteId, EditorView view, ScrollPosition page});

/// Said by the note on screen as its editor and page arrive, and null as they go.
final ValueNotifier<OpenNotePage?> openNotePage = ValueNotifier<OpenNotePage?>(null);

/// The links of one open note: the number on its tool, kept as the index changes, and its More sheet's rows.
class NoteLinksHere {
  NoteLinksHere({required this.app, required this.noteId}) {
    app.indexer.addListener(_changed);
    _open[noteId] = this;
  }

  /// The open notes' links, by the note's id: what the palette's Links to this note asks.
  static final Map<String, NoteLinksHere> _open = <String, NoteLinksHere>{};

  /// The links of the open note by that id, or null.
  static NoteLinksHere? of(String noteId) => _open[noteId];

  final NoteLinksApp app;
  final String noteId;

  late final ValueNotifier<int> _count = ValueNotifier<int>(app.indexer.index.backlinkCount(noteId));
  final _Asked _asked = _Asked();
  late final NoteLinksSeam seam = NoteLinksSeam(count: _count, section: _section, opened: _opened, asked: _asked);

  /// The note's screen opens its More sheet at Links (the palette's Links to this note).
  void openLinks() => _asked.tell();

  void _changed() => _count.value = app.indexer.index.backlinkCount(noteId);

  VoidCallback _opened(EditorView view, ScrollPosition page) {
    final mine = (noteId: noteId, view: view, page: page);
    void tell(OpenNotePage? value) {
      // Told while the screen builds; the side panel hears it after the frame.
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) => openNotePage.value = value);
      } else {
        openNotePage.value = value;
      }
    }

    tell(mine);
    return () {
      final now = openNotePage.value;
      if (now != null && identical(now.view, view)) tell(null);
    };
  }

  NoteSheetSection _section(BuildContext context, EditorView? view, ScrollPosition? page) {
    final count = _count.value;
    final writable = view?.state.facet(EditorViewLike.editable) ?? false;
    final doc = view?.state.doc;
    final body = doc?.toString() ?? app.indexer.bodyOf(noteId) ?? '';
    final selection = view?.state.selection.main;
    final picked = selection == null || selection.empty ? null : view!.state.sliceDoc(selection.from, selection.to);
    final length = noteLength(body);
    final title = app.indexer.index.factsOf(noteId)?.title ?? '';
    final lengthHint = picked == null ? lengthWords(length) : 'Selected: ${lengthWords(countWords(picked, whole: false))}';
    return (
      heading: 'Links and outline',
      items: [
        NoteSheetItem(
          id: 'links',
          icon: Lucide.link2,
          label: 'Links',
          hint: count == 0 ? 'No note links here yet. Notes that name it without a link are here too.' : '${count == 1 ? 'One note links' : '$count notes link'} here. And the notes that name it without a link.',
          page: (context, close) => [
            LinksPanel(
              indexer: app.indexer,
              noteId: noteId,
              title: title,
              onOpen: (id, line) {
                close();
                app.openAt(id, line);
              },
              onLink: app.link,
            ),
          ],
        ),
        NoteSheetItem(
          id: 'outline',
          icon: Lucide.listTree,
          label: 'Outline',
          hint: lengthHint,
          page: (context, close) => [
            SheetNote(picked == null ? '${lengthWords(length)}.' : 'The selection: ${lengthWords(countWords(picked, whole: false))}. The note: ${lengthWords(length)}.'),
            if (view != null && page != null)
              LiveOutline(view: view, page: page, onPicked: close)
            else
              OutlineList(headings: doc == null ? const [] : outlineOf(doc), current: -1, onPick: (_) => close()),
          ],
        ),
        if (app.localGraph != null)
          NoteSheetItem(
            id: 'graph',
            icon: Lucide.network,
            label: 'Local graph',
            hint: 'This note and the notes it links with, one or two links out.',
            onPress: () => app.localGraph!(noteId, title),
          ),
        if (view != null && writable)
          NoteSheetItem(
            id: 'line-link',
            icon: Lucide.link,
            label: 'Copy link to this line',
            hint: 'A link to the line the caret is on, to paste in another note. A line with no name is given one at its end.',
            onPress: () async {
              final said = await copyLineLink(view);
              app.say(said ?? 'That line has nothing to link to. Put the caret on a line of words.');
            },
          ),
      ],
    );
  }

  /// "Linked from" at the foot of the note's words (lib/links/backlinks_foot.dart). [writable] is whether a
  /// mention may be linked from here: not from a note in the Trash.
  Widget foot(BuildContext context, {double? start, bool writable = true}) => BacklinksFoot(
        key: ValueKey('backlinks-foot:$noteId'),
        indexer: app.indexer,
        noteId: noteId,
        onOpen: app.openAt,
        onLink: writable ? app.link : null,
        placeOf: app.placeOf,
        readable: app.readable,
        start: start,
        end: start,
      );

  void dispose() {
    if (identical(_open[noteId], this)) _open.remove(noteId);
    app.indexer.removeListener(_changed);
    _count.dispose();
    _asked.dispose();
  }
}

class _Asked extends ChangeNotifier {
  void tell() => notifyListeners();
}

/// The side panel's Links tab for [noteId].
Widget asideLinks(BuildContext context, {required NoteLinksApp app, required String noteId, required String title}) => LinksPanel(
      key: ValueKey('aside-links:$noteId'),
      indexer: app.indexer,
      noteId: noteId,
      title: title,
      compact: true,
      onOpen: app.openAt,
      onLink: app.link,
    );

/// The side panel's Outline tab for [noteId]: the open note's, following its page, once its screen has handed them
/// over; till then the headings of its words as the library has them.
class AsideOutline extends StatelessWidget {
  const AsideOutline({super.key, required this.noteId, required this.body});

  final String noteId;

  /// The note's words as the library has them.
  final String Function() body;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<OpenNotePage?>(
        valueListenable: openNotePage,
        builder: (context, open, _) {
          final t = context.tokens;
          final length = noteLength(open != null && open.noteId == noteId ? open.view.state.doc.toString() : body());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(t.space(1), 0, t.space(1), t.space(2)),
                child: Text('${lengthWords(length)}.', style: t.textAt(t.fontSize('xs'), color: t.color('glacier-text-muted'))),
              ),
              if (open != null && open.noteId == noteId)
                LiveOutline(key: ValueKey('aside-outline:$noteId'), view: open.view, page: open.page, compact: true)
              else
                OutlineList(headings: outlineOf(Doc.ofString(body())), current: -1, compact: true, onPick: (_) {}),
            ],
          );
        },
      );
}
