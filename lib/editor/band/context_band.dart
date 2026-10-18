/// The note's own press-and-hold menu, in place of the phone's: a port of `src/app/editor/ContextMenu.tsx` with
/// `ContextMenu.module.css`.
///
/// A long press in the editor opens it over the caret (the input layer says how the press is heard, and why the
/// phone's own bar stays away). What appears is a band of Ghost.md's words above the selection: Cut and Copy on a
/// selection, Comment, Paste, Copy board on a board, Find, Select all, Duplicate, Delete, Move up and down, a list
/// item's fields, the board rows where they apply (board_actions.dart), a plugin's send for the line, Style, and
/// Add image.
///
/// Style turns the menu over to the formatting, in the same band (style_items.dart). On a list item, Due date,
/// Priority and Assign turn it over to that field's choices, and a tap on a field's chip opens the menu at the
/// chip on its page ([ContextBandController.openFields]).
///
/// A press on the band never takes the editor's focus or the selection the action is about: nothing in it asks for
/// focus. Every action closes the menu before it runs and gives the editor its focus back after. It goes on a touch
/// anywhere else, a scroll of the note, or the back gesture.
///
/// It sits above the selection, over the header and the tabs if it must (Matt: "Allow the header to be overlapped
/// by the popup menus"), and never under the status bar or the keyboard (menu_room.dart): where above would reach
/// the status bar it goes under the caret instead. Its rows say their own tick, and the Back of each page says one
/// too.
///
/// What differs:
/// - **How it is opened.** The web component heard the press itself (`usePressAndHold`) and a chip's tap
///   (`useFieldTaps`). Hearing a press is the input layer's here, so the band has a [ContextBandController]:
///   `open(held)` for a press, `openAt(view, finger)` which reads the caret's place as the web's `show` did, and
///   `openFields` for a chip. The cases of ContextMenu.test.tsx about what a press is are the input layer's.
/// - **Where it is drawn.** `position: fixed` is an [OverlayPortal] on the root overlay, so it may cover the
///   header; the web's layout effect is a layout delegate, which places the band on every layout by [placeBand].
/// - **What closes it.** The document's captured `pointerdown` is a global pointer route. Scroll events were
///   captured on the document; here the band hears the scrollable it stands in, and a scroll that bubbles up
///   through its [ContextBand.child]. The back gesture is core/back.dart's stack.
/// - **The clipboard** is a [BandClipboard] (clipboard.dart), Flutter's own unless the host hands in another.
/// - **Rows of a later stage** are left out until they are handed in, in the web's order: Comment ([onComment]),
///   Find ([onFind]), a plugin's send ([send]), Add image ([onAddImage]), the fields ([fields]), the plugins'
///   formattings on the Style page ([formats]). The board rows are ported with it and off until asked for
///   ([boards]), the boards themselves being drawn in stage 5.
/// - **What it reads when.** The page read the caret's line, the boards and the fields on each render, which a
///   React component does only when its own state changes; so here they are read when the band opens or turns a
///   page, and kept, not read again when something above rebuilds. The row for adding an item to a board acts on
///   the line it was offered for, as the web's does.
/// - **A scaled interface.** The press arrives in the window's coordinates and is turned into the overlay's before
///   the band is placed, so the band sits by the caret at every interface size; the room is the overlay's own.
/// - `data-haptics="own"` let the band's rows off the app's tap tick; the kit's tick here is only for what wears a
///   `HapticTarget`, and the rows wear none, so there is nothing to let off.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/lucide.g.dart';
import '../../core/back.dart';
import '../../core/item_links.dart';
import '../../core/item_syntax.dart';
import '../../core/preferences.dart' show preferences;
import '../commands/format.dart';
import '../editor.dart';
import '../spell/spell_marks.dart' show misspellingAt, replaceMisspelling;
import 'board_actions.dart';
import 'clipboard.dart';
import 'menu_band.dart';
import 'menu_room.dart';
import 'style_items.dart';

/// Which page of fields the band shows (`FieldPage`, editor/fieldMenu.ts).
sealed class FieldPage {
  const FieldPage();
}

/// A day: Today, Tomorrow, Next week, a date picked, or none. [key] is `due`, `start` or `scheduled`.
final class FieldDatePage extends FieldPage {
  const FieldDatePage(this.key);
  final String key;

  @override
  bool operator ==(Object other) => other is FieldDatePage && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The five priorities, and none.
final class FieldPriorityPage extends FieldPage {
  const FieldPriorityPage();
}

/// One person on the line, to take off.
final class FieldPersonPage extends FieldPage {
  const FieldPersonPage(this.name);
  final String name;

  @override
  bool operator ==(Object other) => other is FieldPersonPage && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// The people this note names, to put on the line or take off, and someone new.
final class FieldAssignPage extends FieldPage {
  const FieldAssignPage();
}

/// A reminder's times (lib/reminders), where the phone reminds ([BandFields.reminds]).
final class FieldRemindPage extends FieldPage {
  const FieldRemindPage();
}

/// A place reminder's chip: Change place and Remove (lib/reminders/place_syntax.dart).
final class FieldPlacePage extends FieldPage {
  const FieldPlacePage();
}

/// What a field page is drawn from (`FieldItemsProps`, editor/FieldItems.tsx).
class FieldItemsRequest {
  const FieldItemsRequest({required this.view, required this.line, required this.page, required this.onBack, required this.onClose, required this.refocus, required this.felt, required this.redraw});

  final EditorViewLike view;

  /// The line the fields are on, counting from 1.
  final int line;
  final FieldPage page;

  /// Back to the line's actions; null for a page a chip opened, which has nothing to go back to. It says its own
  /// tick.
  final VoidCallback? onBack;
  final VoidCallback onClose;

  /// Whether the editor had its focus when the menu opened, and so gets it back.
  final bool refocus;

  /// The band's tick, for the rows to say their own.
  final void Function(HapticKind kind) felt;

  /// Asks the band to draw the page again, after a row changed what it shows (`useRedraw`).
  final VoidCallback redraw;
}

/// The fields of a list item, for the band: which lines take them, and the rows of a field's page
/// (`takesFields` and `FieldItems`; lib/editor/items hands this in).
class BandFields {
  const BandFields({required this.items, this.takes = takesFields, this.reminds, this.places, this.atPlace});

  /// A page's rows, [MenuItem]s and the like, Back first where the request has one.
  final List<Widget> Function(BuildContext context, FieldItemsRequest request) items;

  /// Whether a line can take fields from the menu.
  final bool Function(String lineText) takes;

  /// Whether the editor offers Remind me: only where the phone reminds. Absent, never.
  final bool Function(EditorViewLike view)? reminds;

  /// Whether the editor offers Remind me at a place: only where the phone watches places. Absent, never.
  final bool Function(EditorViewLike view)? places;

  /// Remind me at a place pressed for a line (counting from 1): its sheet, which writes the place picked; [refocus]
  /// is whether the editor had its focus.
  final void Function(EditorViewLike view, int line, bool refocus)? atPlace;
}

/// Whether a line can take fields from the menu: a list item, a bullet, a step or a to-do (`takesFields`).
bool takesFields(String text) => listLead(text) != null;

/// A plugin's send for the line's words (a Notion board, a GitHub issue).
class BandSend {
  const BandSend({required this.label, required this.run, this.icon = Lucide.link});

  final String label;
  final FutureOr<void> Function(String text) run;
  final MenuIcon icon;
}

/// The pages of the band, each with the name the menu wears on it (`aria-label`).
enum BandPage {
  actions('Note actions'),
  styles('Styles'),
  fields('Fields');

  const BandPage(this.label);
  final String label;
}

/// The press, as the web's `show` read it (editor/pressAndHold.ts): the caret's place when the view has one for it
/// (the middle of its box, and its top), else the finger's; and the selection.
Held heldAt(EditorViewLike view, Offset finger) {
  final main = view.state.selection.main;
  final at = view.coordsAtPos(main.head);
  return Held(x: at == null ? finger.dx : (at.left + at.right) / 2, y: at == null ? finger.dy : at.top, from: main.from, to: main.to);
}

/// Opens and closes a [ContextBand], and says what it shows. The input layer holds one and calls [openAt] when a
/// press asks for the menu; the note screen gives the same one to its [ContextBand].
class ContextBandController extends ChangeNotifier {
  Held? _held;
  BandPage _page = BandPage.actions;
  ({FieldPage page, int line, bool back, bool refocus})? _fields;
  int _opened = 0;
  Rect? Function()? _box;

  /// Where it was asked for, or null while it is closed.
  Held? get held => _held;
  bool get isOpen => _held != null;

  /// The page it shows.
  BandPage get page => _page;

  /// The page of fields it shows, for which line, whether Back leads to the line's actions, and whether the
  /// editor had its focus to give back.
  ({FieldPage page, int line, bool back, bool refocus})? get fields => _fields;

  /// Counts the times it has opened, so each is an entrance of its own.
  int get opened => _opened;

  /// Opens the band on its actions for a press at [held] (`usePressAndHold`'s callback).
  void open(Held held) {
    _page = BandPage.actions;
    _fields = null;
    _held = held;
    _opened += 1;
    notifyListeners();
  }

  /// Opens it for a press in [view] where the [finger] was, in the window's coordinates: over the caret when the
  /// view can say where that is ([heldAt]). The input layer moves the selection first, as the web's press did.
  void openAt(EditorViewLike view, Offset finger) => open(heldAt(view, finger));

  /// A chip tapped: the band at the chip ([at], in the window), on its field's page (`useFieldTaps`).
  void openFields(EditorViewLike view, {required FieldPage page, required int line, required Offset at}) {
    final head = view.state.selection.main.head;
    _page = BandPage.fields;
    _fields = (page: page, line: line, back: false, refocus: view.hasFocus);
    _held = Held(x: at.dx, y: at.dy, from: head, to: head);
    _opened += 1;
    notifyListeners();
  }

  void close() {
    if (_held == null) return;
    _held = null;
    notifyListeners();
  }

  /// Whether a point of the window is on the band, for whoever must leave a press there alone.
  bool contains(Offset global) => _box?.call()?.contains(global) ?? false;

  /// The band's box in the window while it is up.
  Rect? get rect => _box?.call();

  void _turn(BandPage page, [({FieldPage page, int line, bool back, bool refocus})? fields]) {
    _page = page;
    _fields = fields;
    notifyListeners();
  }
}

/// The press-and-hold band over [view]. It draws nothing until its [controller] is opened; [child], if given, is
/// drawn in its place in the tree, and a scroll that reaches it from below closes the band.
class ContextBand extends StatefulWidget {
  const ContextBand({
    super.key,
    required this.view,
    required this.controller,
    this.onAddImage,
    this.onPasteImage,
    this.say,
    this.onFind,
    this.send,
    this.onComment,
    this.formats = const <BandFormat>[],
    this.fields,
    this.boards = false,
    this.clipboard = const SystemClipboard(),
    this.felt,
    this.room,
    this.simple,
    this.child,
  });

  /// The editor, or null where there is none yet: nothing is drawn.
  final EditorViewLike? view;
  final ContextBandController controller;

  /// Whether the app is in simple mode (GHST-103, lib/core/preferences.dart `Preferences.simple`): Style stands
  /// first in the actions, before Cut and Copy, and the Style page wears its hints with the plugins' marks behind
  /// More (style_items.dart). Null reads the app's own preference as the band is drawn; a test says.
  final bool? simple;

  /// Opens the picture picker; null where a picture makes no sense, and the word is not shown.
  final FutureOr<void> Function()? onAddImage;

  /// Adopts a picture the clipboard's reader copied out, by path.
  final Future<void> Function(String path)? onPasteImage;

  /// A sentence for the person, when something they asked for could not be done.
  final void Function(String message)? say;

  /// Opens find and replace with the selected words; null, the word is not shown.
  final void Function(String text)? onFind;

  /// Sends the line's words where a plugin takes them; null, nothing is shown.
  final BandSend? send;

  /// Starts a comment: on the selection the menu was opened over, or on the caret's line when there is none. Null,
  /// the word is not shown.
  final void Function(({int from, int to}) range)? onComment;

  /// The switched-on plugins' formattings, for the Style page.
  final List<BandFormat> formats;

  /// A list item's fields; null, Due date, Priority and Assign are not shown.
  final BandFields? fields;

  /// Whether the board rows are offered (board_actions.dart): off until the boards are drawn.
  final bool boards;
  final BandClipboard clipboard;

  /// Says a tick; the kit's haptics where null (`fireNativeHaptic`).
  final void Function(HapticKind kind)? felt;

  /// The room the band keeps to; [menuRoomOf] the overlay where null.
  final MenuRoom Function(BuildContext context)? room;
  final Widget? child;

  @override
  State<ContextBand> createState() => _ContextBandState();
}

/// What the actions page was offered for, read when the band opened or turned back to it.
class _Offered {
  const _Offered({required this.line, required this.lineWords, required this.boards, required this.fieldsHere, required this.readOnly});

  final int line;
  final String lineWords;
  final BoardOffers boards;
  final bool fieldsHere;
  final bool readOnly;
}

class _ContextBandState extends State<ContextBand> {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _menu = GlobalKey(debugLabel: 'context band');
  _Offered? _offered;
  ScrollPosition? _noteScroll;
  bool _routed = false;

  /// Simple mode's Style page with its More pressed: the plugins' marks shown, until the band opens again.
  bool _moreStyles = false;

  ContextBandController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _controller._box = _rect;
    _sync();
  }

  @override
  void didUpdateWidget(ContextBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller._box = null;
      _controller.addListener(_changed);
      _controller._box = _rect;
    }
    if (!identical(oldWidget.view, widget.view)) _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A scroll of the note the band stands in.
    final scroll = Scrollable.maybeOf(context)?.position;
    if (!identical(scroll, _noteScroll)) {
      _noteScroll?.removeListener(_close);
      _noteScroll = scroll;
      _noteScroll?.addListener(_close);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (identical(_controller._box, _rect)) _controller._box = null;
    _noteScroll?.removeListener(_close);
    _route(false);
    super.dispose();
  }

  Rect? _rect() {
    final box = _menu.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    // Through every transform above it, a scaled interface's among them.
    return MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
  }

  void _close() => _controller.close();

  /// Simple mode, as the band was told or as the app's preference says now.
  bool get _simple => widget.simple ?? preferences.value.simple;

  void _felt(HapticKind kind) => (widget.felt ?? (kind) => HapticsProvider.of(context)(kind))(kind);

  /// It leaves on a touch anywhere else.
  void _pointer(PointerEvent event) {
    if (event is! PointerDownEvent || !_controller.isOpen) return;
    if (_rect()?.contains(event.position) ?? false) return;
    _close();
  }

  void _route(bool on) {
    if (on == _routed) return;
    _routed = on;
    if (on) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    } else {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(_sync);
  }

  /// The controller's word, made the overlay's and the state's.
  void _sync() {
    final view = widget.view;
    final open = _controller.isOpen && view != null;
    if (open && _controller.page == BandPage.actions) {
      _offered = _read(view);
    } else if (!open) {
      _offered = null;
      _moreStyles = false;
    }
    _route(open);
    if (open != _portal.isShowing) open ? _portal.show() : _portal.hide();
  }

  _Offered _read(EditorViewLike view) {
    // The line the caret is on, for the actions that are about a line rather than a selection.
    final caretLine = view.state.doc.lineAt(view.state.selection.main.head);
    return _Offered(
      line: caretLine.number,
      // What the item says, as a plugin sends it: no marker, no mark, and not the board's anchor.
      lineWords: itemWords(caretLine.text) ?? jsTrim(caretLine.text),
      boards: widget.boards ? boardOffers(view) : const BoardOffers(),
      fieldsHere: widget.fields != null && !view.state.readOnly && widget.fields!.takes(caretLine.text),
      readOnly: view.state.readOnly,
    );
  }

  /// A row's press: the menu closed first, then the action, then the editor's focus back.
  VoidCallback _act(EditorViewLike view, FutureOr<void> Function() what) => () {
    unawaited(() async {
      _felt(HapticKind.selection);
      _close();
      await what();
      view.focus();
    }());
  };

  /// A page's Back: every row here says its own tick, and Back is one of them.
  VoidCallback _backFrom(VoidCallback back) => () {
    _felt(HapticKind.selection);
    back();
  };

  List<Widget> _actions(EditorViewLike view, Held held, _Offered offered) {
    final from = held.from, to = held.to;
    final selected = from != to;
    String text() => view.state.sliceDoc(from, to);
    final say = widget.say;
    final boards = offered.boards;
    final board = boards.copy;

    Future<void> copy() => widget.clipboard.write(text());

    Future<void> cut() async {
      await copy();
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: ''), selection: EditorSelection.single(from)));
    }

    Future<void> paste() async {
      ClipRead got;
      try {
        got = await widget.clipboard.read();
      } on Object {
        // Refused outright: nothing is pasted, and the person is told why rather than left guessing at a dead row.
        say?.call('Ghost.md couldn’t reach the clipboard here. Tap into the note and paste from your keyboard instead.');
        return;
      }
      final (:clip, :read) = got;
      if (clip.error != null && clip.error!.isNotEmpty) {
        say?.call(clip.error!);
        return;
      }
      if (clip.path != null && clip.path!.isNotEmpty && widget.onPasteImage != null) {
        await widget.onPasteImage!(clip.path!);
        return;
      }
      final words = clip.text;
      if (words == null || words.isEmpty) {
        // Nothing came back. Only a reader that answered can say the clipboard is empty; otherwise it went unread.
        say?.call(
          read
              ? 'Nothing on the clipboard to paste. Copy the words again, then hold here.'
              : 'Nothing came back from the clipboard. Copy it again, or tap into the note and paste from your keyboard.',
        );
        return;
      }
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: words), selection: EditorSelection.single(from + words.length)));
    }

    void selectAll() => view.dispatch(TransactionSpec(selection: EditorSelection.single(0, view.state.doc.length)));

    // A row that works on lines, run on a board: the whole fence is taken first (`selectBoard`).
    void Function() whole(Transaction? Function(EditorState state) run) => () {
      if (boards.fence != null) selectBoard(view, boards.fence!);
      final tr = run(view.state);
      if (tr != null) view.dispatch(tr);
    };

    // A field's page for the caret's line, from the line's own actions.
    VoidCallback fieldPage(FieldPage page) => () {
      _felt(HapticKind.selection);
      _controller._turn(BandPage.fields, (page: page, line: offered.line, back: true, refocus: view.hasFocus));
    };

    void listToBoard() {
      if (boards.list == null) return;
      final made = makeListBoard(view, boards.list!);
      if (made == null) return;
      _felt(HapticKind.success);
      say?.call(boardMadeWords(made, 'a board'));
    }

    void putOnBoard() {
      final column = joinBoard(view, offered.line);
      if (column == null) return;
      _felt(HapticKind.success);
      say?.call('Added to $column.');
    }

    final onComment = widget.onComment, onFind = widget.onFind, send = widget.send, onAddImage = widget.onAddImage;
    // The word under the caret, when the spell checker would have it otherwise (lib/editor/spell): what it offers.
    final misspelled = selected ? null : misspellingAt(view.state, view.state.selection.main.head);
    final style = MenuItem(
      key: const ValueKey<String>('style'),
      icon: Lucide.type,
      label: 'Style',
      onPress: () {
        _felt(HapticKind.selection);
        _controller._turn(BandPage.styles);
      },
    );
    final simple = _simple;
    return <Widget>[
      // First, so the right word is one press away: the page's WebView offered them in a popup of its own on a
      // word it had underlined. Three at most; the band is a line.
      if (misspelled != null)
        for (final suggestion in misspelled.suggestions.take(3))
          MenuItem(
            key: ValueKey<String>('spell-$suggestion'),
            icon: Lucide.spellCheck,
            label: suggestion,
            name: 'Change to $suggestion',
            onPress: _act(view, () {
              final still = misspellingAt(view.state, misspelled.from);
              if (still != null) view.dispatch(replaceMisspelling(still, suggestion));
            }),
          ),
      // In simple mode Style leads, before Cut and Copy: the menu is where formatting is found, and someone new
      // to the app is looking for Bold more often than the clipboard (GHST-103). A misspelling's words stay ahead
      // of it: a wrong word wants its right one first.
      if (simple) style,
      if (selected) ...<Widget>[
        MenuItem(key: const ValueKey<String>('cut'), icon: Lucide.scissors, label: 'Cut', onPress: _act(view, cut)),
        MenuItem(key: const ValueKey<String>('copy'), icon: Lucide.copy, label: 'Copy', onPress: _act(view, copy)),
      ],
      // Second only to Cut and Copy, so it is in reach without scrolling the band (Matt: "add them to ... the
      // popover toolbar so we can quickly click to add comments"). The sheet it opens takes the focus for its
      // field, so the editor is not given it back.
      if (onComment != null && !offered.readOnly)
        MenuItem(
          key: const ValueKey<String>('comment'),
          icon: Lucide.messageSquarePlus,
          label: 'Comment',
          onPress: () {
            _felt(HapticKind.selection);
            _close();
            onComment((from: from, to: to));
          },
        ),
      if (widget.clipboard.readable) MenuItem(key: const ValueKey<String>('paste'), icon: Lucide.clipboardPaste, label: 'Paste', onPress: _act(view, paste)),
      // A board is drawn as columns, so it cannot be dragged over: this takes the whole of it at once.
      if (board != null) MenuItem(key: const ValueKey<String>('copy-board'), icon: Lucide.copy, label: 'Copy board', onPress: _act(view, () => widget.clipboard.write(board))),
      if (selected && onFind != null && to - from <= 120)
        MenuItem(
          key: const ValueKey<String>('find'),
          icon: Lucide.textSearch,
          label: 'Find',
          onPress: () {
            _felt(HapticKind.selection);
            _close();
            onFind(text());
          },
        ),
      MenuItem(key: const ValueKey<String>('select-all'), icon: Lucide.squareDashedText, label: 'Select all', onPress: _act(view, selectAll)),
      MenuItem(key: const ValueKey<String>('duplicate'), icon: Lucide.copyPlus, label: 'Duplicate', onPress: _act(view, whole(duplicateSelection))),
      MenuItem(key: const ValueKey<String>('delete'), icon: Lucide.trash, label: 'Delete', onPress: _act(view, whole(deleteSelection))),
      MenuItem(key: const ValueKey<String>('move-up'), icon: Lucide.arrowUpToLine, label: 'Move up', onPress: _act(view, whole((state) => moveLines(state, -1)))),
      MenuItem(key: const ValueKey<String>('move-down'), icon: Lucide.arrowDownToLine, label: 'Move down', onPress: _act(view, whole((state) => moveLines(state, 1)))),
      // A list item's fields: when it is due, how much it matters, who it is for.
      if (offered.fieldsHere) ...<Widget>[
        MenuItem(key: const ValueKey<String>('due'), icon: Lucide.calendarDays, label: 'Due date', onPress: fieldPage(const FieldDatePage('due'))),
        MenuItem(key: const ValueKey<String>('priority'), icon: Lucide.flag, label: 'Priority', onPress: fieldPage(const FieldPriorityPage())),
        MenuItem(key: const ValueKey<String>('assign'), icon: Lucide.userPlus, label: 'Assign', onPress: fieldPage(const FieldAssignPage())),
        if (widget.fields?.reminds?.call(view) ?? false) MenuItem(key: const ValueKey<String>('remind'), icon: Lucide.alarmClock, label: 'Remind me', onPress: fieldPage(const FieldRemindPage())),
        // A sheet of its own, not a page of the band: a search, the note's places and here.
        if ((widget.fields?.places?.call(view) ?? false) && widget.fields?.atPlace != null)
          MenuItem(
            key: const ValueKey<String>('remind-place'),
            icon: Lucide.mapPin,
            label: 'Remind me at a place',
            onPress: () {
              _felt(HapticKind.selection);
              final refocus = view.hasFocus;
              _close();
              widget.fields!.atPlace!(view, offered.line, refocus);
            },
          ),
      ],
      if (boards.joinable) MenuItem(key: const ValueKey<String>('join-board'), icon: Lucide.layoutGrid, label: 'Add to board', onPress: _act(view, putOnBoard)),
      if (boards.list != null) MenuItem(key: const ValueKey<String>('list-board'), icon: Lucide.squareKanban, label: 'Board from list', onPress: _act(view, listToBoard)),
      if (send != null && offered.lineWords.isNotEmpty) MenuItem(key: const ValueKey<String>('send'), icon: send.icon, label: send.label, onPress: _act(view, () => send.run(offered.lineWords))),
      if (!simple) style,
      if (onAddImage != null) MenuItem(key: const ValueKey<String>('add-image'), icon: Lucide.imagePlus, label: 'Add image', onPress: _act(view, onAddImage)),
    ];
  }

  Widget _overlay(BuildContext context) {
    final view = widget.view;
    final held = _controller.held;
    if (view == null || held == null) return const SizedBox.shrink();
    final page = _controller.page;
    final fields = _controller.fields;
    void toActions() => _controller._turn(BandPage.actions);
    final List<Widget> rows;
    var entrance = false;
    if (page == BandPage.fields && fields != null && widget.fields != null) {
      rows = widget.fields!.items(
        context,
        FieldItemsRequest(view: view, line: fields.line, page: fields.page, onBack: fields.back ? _backFrom(toActions) : null, onClose: _close, refocus: fields.refocus, felt: _felt, redraw: _changed),
      );
    } else if (page == BandPage.styles) {
      entrance = true;
      rows = styleItems(
        view: view,
        onBack: _backFrom(toActions),
        onClose: _close,
        restyled: _changed,
        felt: _felt,
        formats: widget.formats,
        simple: _simple,
        moreShown: _moreStyles,
        onMore: () => setState(() => _moreStyles = true),
      );
    } else {
      rows = _actions(view, held, _offered ??= _read(view));
    }
    Widget band = MenuBand(children: rows);
    // One clock for a Style page's rows, a new one each time the page is turned to.
    if (entrance) band = StyleEntrance(key: ValueKey<int>(_controller.opened), child: band);
    final room = (widget.room ?? menuRoomOf)(context);
    final window = MediaQuery.sizeOf(context);
    // The press is in the window's coordinates and the band is placed in the overlay's, which are the same until
    // the interface is scaled (app/ghost_app.dart magnifies everything under it, the overlay too).
    final overlay = Overlay.maybeOf(this.context, rootOverlay: true)?.context.findRenderObject();
    final at = overlay is RenderBox && overlay.hasSize ? overlay.globalToLocal(Offset(held.x, held.y)) : Offset(held.x, held.y);
    return CustomSingleChildLayout(
      delegate: _BandPlacing(held: Held(x: at.dx, y: at.dy, from: held.from, to: held.to), room: room, most: window.width - 2 * menuEdge),
      child: _MenuIn(
        key: ValueKey<int>(_controller.opened),
        child: Semantics(
          key: _menu,
          container: true,
          explicitChildNodes: true,
          scopesRoute: false,
          label: page.label,
          child: band,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = _controller.isOpen && widget.view != null;
    final child = widget.child;
    return OnBack(
      active: open,
      onBack: _close,
      child: OverlayPortal(
        controller: _portal,
        overlayLocation: OverlayChildLocation.rootOverlay,
        overlayChildBuilder: _overlay,
        child: child == null
            ? const SizedBox.shrink()
            : NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) {
                  // A scroll along the menu's own band is not a scroll of the note: the band is in the overlay, and
                  // never bubbles through here.
                  if (_controller.isOpen) _close();
                  return false;
                },
                child: child,
              ),
      ),
    );
  }
}

/// Places the band for the press it was opened by, in the overlay's own box: the web's layout effect.
class _BandPlacing extends SingleChildLayoutDelegate {
  const _BandPlacing({required this.held, required this.room, required this.most});

  final Held held;
  final MenuRoom room;

  /// `max-inline-size: calc(100vw - 16px)`.
  final double most;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(maxWidth: most < 0 ? 0 : most);

  @override
  Offset getPositionForChild(Size size, Size childSize) => placeBand(held, offsetSize(childSize), room);

  @override
  bool shouldRelayout(_BandPlacing oldDelegate) => oldDelegate.held != held || oldDelegate.room != room || oldDelegate.most != most;
}

/// `menuIn`: 140ms out of a touch smaller and lower, once for each time the band opens; none with reduced motion.
class _MenuIn extends StatefulWidget {
  const _MenuIn({super.key, required this.child});

  final Widget child;

  @override
  State<_MenuIn> createState() => _MenuInState();
}

class _MenuInState extends State<_MenuIn> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.tokens.reducedMotion) {
      _clock.value = 1;
    } else {
      _clock.forward();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = context.tokens.curve('glacier-ease-out');
    return AnimatedBuilder(
      animation: _clock,
      child: widget.child,
      builder: (context, child) {
        final at = curve.transform(_clock.value);
        if (at >= 1) return child!;
        return Opacity(
          opacity: at,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(0, 4 * (1 - at), 0)..scaleByDouble(0.98 + 0.02 * at, 0.98 + 0.02 * at, 1, 1),
            child: child,
          ),
        );
      },
    );
  }
}
