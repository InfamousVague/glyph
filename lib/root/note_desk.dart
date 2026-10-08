/// One open note's editor, put together: what `src/app/editor/NoteScreen.tsx` and `Editor.tsx` do between them
/// once every piece of the editor exists. The note's screen (lib/note/note_screen.dart) is given an editor builder
/// and its seams; this makes both for one note and keeps what they share for as long as the note is open.
///
/// What is here, each from its own piece:
/// - the editor that is typed in (lib/editor/editor_widget.dart `Editor`), over the view lib/note's host keeps,
///   with every piece's extensions in one list made once: the input, the twelve marks and the five effects with
///   typing's smoke, the inline items with links between notes and the hint in an open first heading, drawn tables,
///   links, pictures and media, the + beside an empty line, and find's marks;
/// - the press-and-hold band (lib/editor/band), opened by the editor's own hold, with the marks on its Style page
///   and a list item's fields as its pages;
/// - the + and its list (lib/editor/plus), with the effects as rows and every note's title for A note;
/// - a tapped chip's menu (lib/editor/items `FieldMenuHost`);
/// - find and replace (lib/editor/find_bar), from the More sheet and from the band, resting on the keyboard;
/// - the bookmark (lib/editor/items `NoteBookmark`), the cheat sheet's page, and a note's sharing where the build
///   has an account.
///
/// What differs from the page:
/// - **No picture can be added yet**: this build has no picker, so the band's Add image and the +'s Picture are
///   not offered. Pictures a note already names are drawn from the kept files.
/// - **No place, film or voice memo is added** from the + (no location, no player): their rows are not offered.
/// - **A link's tap opens nothing**: nothing here hands an address to the phone.
/// - **A date is not picked from a calendar** (`dayPicker` is not given): Today, Tomorrow and Next week are.
/// - **The blank page's names and template cards are not drawn**: lib/note has the logic and no place for them.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import '../account/ui_state.dart';
import '../art/lucide.g.dart';
import '../core/book.dart';
import '../core/canvas_body.dart';
import '../core/images.dart';
import '../core/preferences.dart';
import '../editor/band/band.dart' as band;
import '../editor/editor.dart';
import '../editor/editor_widget.dart';
import '../editor/find_bar/find_bar.dart';
import '../editor/find_bar/find_marks.dart';
import '../editor/items/items.dart';
import '../editor/marks/marks.dart';
import '../editor/media/media.dart';
import '../editor/plus/plus.dart';
import '../editor/tables/tables.dart';
import '../editor/view/editor_view.dart';
import '../note/note_editor.dart';
import '../note/note_place.dart';
import '../note/note_screen.dart';
import '../settings/panes/cheat_sheet.dart';
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
  const NoteDeskWorld({required this.titles, required this.known, required this.open, this.bodyOf, this.pictures, this.services});

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
}

/// Builds a note's screen with the editor and the seams the desk made for it.
typedef NoteDeskBuilder = Widget Function(BuildContext context, NoteEditorBuilder editor, NoteSeams seams);

/// The editor and everything round it for one open note. Keyed by the note by whoever builds it, so each note
/// has its own.
class NoteDesk extends StatefulWidget {
  const NoteDesk({super.key, required this.noteId, required this.title, required this.world, required this.say, required this.builder, this.prefs});

  final String noteId;

  /// The note's own title, which its + does not link to.
  final String title;
  final NoteDeskWorld world;

  /// A toast.
  final void Function(String message) say;
  final NoteDeskBuilder builder;

  /// The preferences; the app's own unless given.
  final PreferencesStore? prefs;

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
    ),
    drawnTables(),
    mediaExtensions(
      seams: MediaSeams(
        pictures: _world.pictures,
        linkPreviews: () => _prefs.value.linkPreviews,
        switches: _prefs,
      ),
    ),
    _plus.extension,
    findBarExtensions,
  ];

  /// A + may show: a note of words that can be written, with find put away.
  bool _plusAllowed() {
    final view = _view;
    if (view == null || view.state.readOnly || _finding != null) return false;
    final doc = view.state.doc.toString();
    return !isCanvasBody(doc) && !isBookBody(doc);
  }

  @override
  void dispose() {
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
        config: AddConfig(titles: _world.titles, own: widget.title, localOnly: _prefs.value.localOnly, effects: plusEffects),
        child: band.ContextBand(
          view: view,
          controller: _band,
          say: widget.say,
          onFind: view == null ? null : (text) => _openFind(view, text),
          formats: bandFormats,
          fields: bandFields,
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
      around: _around,
      over: _over,
    );
    return widget.builder(context, _buildEditor, seams);
  }
}
