/// The editor as one widget for a scroll view: an [EditorView] drawn by its sliver, with the input layer round it.
/// The twin of `src/app/editor/Editor.tsx`'s host element, and of what a browser does for a `contenteditable`
/// inside it: focus, the keyboard, keys, pointers, the caret's blink, the selection's handles, keeping the caret
/// in sight.
///
/// [Editor] is a sliver. It goes in the page's `CustomScrollView` beside the page's other slivers, as
/// `EditorSliver` does, and the page scrolls it (Editor.tsx's `grow`). The view is the caller's: made with
/// `noteExtensions(more: [editorInput(), ...])` (input/input.dart); an editor given a view without the input
/// extension adds it.
///
/// What is where:
/// - `input/ime.dart`: the keyboard, a windowed delta client (docs/STAGE4.md's eight rules);
/// - `input/keymap.dart` and `input/motion.dart`: keys, CodeMirror's keymaps through a `ShortcutManager` and
///   `Actions`, and the commands only a layout can answer; Flutter's text-editing intents (what the app's default
///   shortcuts and a platform's own menus send) are answered here with the same commands;
/// - `input/gestures.dart`: taps, a press held, a mouse; `input/handles.dart`: the handles and the loupe;
/// - `input/caret.dart`: the blink; `input/felt.dart`: the hand.
///
/// Editor.tsx, lines 536-578, kept here:
/// - **the caret stays in sight when the editor's room changes under it** (the keyboard rising, a fold opening):
///   the selection's head is scrolled into view, nearest, with 56 px to spare, a frame after the window's insets or
///   size change;
/// - **`footClearAt`**: [Editor.footClear] is the room kept clear under the caret whenever it is scrolled to (the
///   page's foot smoke), held to a third of the room the page shows under its header ([Editor.headerInset]). What
///   the keyboard covers of the scroll view is added to it, for a page that does not shrink for the keyboard.
///
/// Not here: what a screen reader is told (the editor has no semantics yet), spell-check underlines, scribble and
/// the iPhone's floating cursor.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'commands/commands.dart';
import 'commands/commands.dart' as commands show selectAll;
import 'input/caret.dart';
import 'input/gestures.dart';
import 'input/handles.dart';
import 'input/ime.dart';
import 'input/input.dart';
import 'input/input_sliver.dart';
import 'input/keymap.dart';
import 'input/motion.dart';
import 'looks/look.dart';
import 'state/history.dart';
import 'state/state.dart';
import 'view/editor_view.dart';
import 'view/plugin.dart';
import 'view/sliver.dart';

export 'input/gestures.dart' show Held;
export 'input/input.dart' show assistSlot, editorInput, setAssist;
export 'input/keymap.dart' show editorKeymap;

/// What a host does to an [Editor] from outside it: the note's menu pastes through this, a bar's button hides the
/// keyboard. Give one to the editor and it answers while the editor is mounted.
class EditorController {
  _EditorState? _state;

  /// Whether an editor is listening.
  bool get attached => _state != null;

  /// The keyboard's client, for a test or a diagnostic.
  EditorIme? get ime => _state?._ime;

  /// Gives the editor the keyboard's focus and raises the keyboard.
  void focus() => _state?.takeFocus(keyboard: true);

  /// Gives the focus up: the keyboard goes.
  void unfocus() => _state?._focus.unfocus();

  /// Lowers the keyboard and keeps the caret.
  void hideKeyboard() => _state?._ime.detach();

  /// Takes the selection's handles away (a menu opening over them).
  void hideHandles() => _state?._handles.hide();

  /// The selected text onto the clipboard. False when nothing is selected.
  Future<bool> copy() async => await _state?._copy(cut: false) ?? false;

  /// The selected text onto the clipboard and out of the note.
  Future<bool> cut() async => await _state?._copy(cut: true) ?? false;

  /// Puts `text` in at the selection as a paste (`input.paste`); the clipboard's words when null. False when
  /// there was nothing to paste.
  Future<bool> paste([String? text]) async => await _state?._paste(text) ?? false;

  /// Selects the whole note.
  void selectAll() {
    final state = _state;
    if (state != null) commands.selectAll(state.widget.view);
  }
}

class Editor extends StatefulWidget {
  const Editor({
    super.key,
    required this.view,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.env,
    this.sheets = const <LookSheet>[],
    this.meHue,
    this.onHold,
    this.footClear = 0,
    this.headerInset = 0,
    this.fill = true,
  });

  /// The view to draw and type in.
  final EditorView view;

  final EditorController? controller;

  /// The editor's focus, when the host wants to hold it.
  final FocusNode? focusNode;

  /// Whether the editor takes the keyboard as it appears.
  final bool autofocus;

  /// As `EditorSliver`'s.
  final LookEnv? env;
  final List<LookSheet> sheets;
  final String? meHue;

  /// The note's menu is asked for (pressAndHold.ts): a press held, or the other mouse button.
  final void Function(Held held)? onHold;

  /// The page's foot the caret is kept clear of when it is scrolled into view, in pixels (Editor.tsx `footClear`).
  final double footClear;

  /// How much of the scroll view's top the page's header covers: `footClearAt` leaves it out of the room it takes
  /// a third of.
  final double headerInset;

  /// Whether the empty paper under a short note is the editor's too: a tap there puts the caret at the end.
  final bool fill;

  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> implements EditorGesturesHost, EditorHandlesHost {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'Editor'));

  late EditorIme _ime;
  late CaretBlink _blink;
  late final EditorGestures _gestures = EditorGestures(this);
  late final EditorHandles _handles = EditorHandles(this);
  final EditorShortcuts _shortcuts = EditorShortcuts();
  final GlobalKey _sliverKey = GlobalKey(debugLabel: 'editor input');
  EditorInputHost? _host;
  EdgeDraggingAutoScroller? _scroller;
  ScrollPosition? _position;
  VoidCallback? _scrolledAgain;
  bool _wantKeyboard = false;
  bool _afterFrame = false;
  double _inset = -1;
  Size _screen = Size.zero;

  @override
  final LayerLink caretLink = LayerLink();

  @override
  EditorView get view => widget.view;

  // -- life ---------------------------------------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _adopt();
    _focus.addListener(_focusChanged);
    widget.controller?._state = this;
  }

  /// Takes up `widget.view`: its input extension (added when it has none), the keyboard's client, the blink.
  void _adopt() {
    final view = widget.view;
    var host = view.state.facet(editorInputHost);
    if (host == null) {
      view.dispatch(TransactionSpec(effects: StateEffect.appendConfig.of(editorInput())));
      host = view.state.facet(editorInputHost);
    }
    // The plugin is made with the view; a view that had the extension from the start has said so already.
    host!.view = view;
    host.onUpdate = _viewUpdated;
    host.margins = _margins;
    _host = host;
    _ime = EditorIme(view: view, runKey: (key) => runKey(view, key), viewId: () => View.of(context).viewId, onPaste: _pasteHandled);
    _blink = CaretBlink(view.caretOpacity);
    view.focusRequest = () => takeFocus(keyboard: true);
    EditorMotion.covered[view] = () => _keyboardOverlap;
  }

  void _release(EditorView view) {
    _blink.stop(solid: false);
    _ime.detach();
    final host = _host;
    if (host != null) {
      host.onUpdate = null;
      host.margins = null;
    }
    view.focusRequest = null;
    EditorMotion.covered[view] = null;
  }

  @override
  void didUpdateWidget(Editor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }
    if (!identical(oldWidget.view, widget.view)) {
      _handles.hide();
      _release(oldWidget.view);
      _adopt();
      if (_focus.hasFocus) _focusChanged();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_scheduleAfterFrame);
      _position = position;
      position?.addListener(_scheduleAfterFrame);
      _scroller = null;
    }
    // The editor's room changed under the caret: the keyboard rose or fell, a fold opened.
    final inset = MediaQuery.viewInsetsOf(context).bottom, screen = MediaQuery.sizeOf(context);
    if (inset != _inset || screen != _screen) {
      final first = _inset < 0;
      _inset = inset;
      _screen = screen;
      if (!first) _keepCaret();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _position?.removeListener(_scheduleAfterFrame);
    _focus.removeListener(_focusChanged);
    _handles.dispose();
    _gestures.dispose();
    _release(widget.view);
    if (widget.view.hasFocus) widget.view.setFocused(false);
    _ownFocus?.dispose();
    _shortcuts.dispose();
    super.dispose();
  }

  // -- focus and the keyboard --------------------------------------------------------------------------------------

  bool get _editable => view.state.facet(EditorViewLike.editable);

  @override
  void takeFocus({required bool keyboard}) {
    if (keyboard) _wantKeyboard = true;
    if (!_focus.hasFocus) {
      _focus.requestFocus();
    } else if (_editable) {
      // Focused already: the keyboard may have been put away under it.
      _ime.attach(show: keyboard);
    }
  }

  void _focusChanged() {
    final focused = _focus.hasFocus;
    if (focused == view.hasFocus) return;
    for (final handlers in view.eventHandlers) {
      if ((focused ? handlers.focus : handlers.blur)?.call(view) ?? false) break;
    }
    view.setFocused(focused);
    if (focused) {
      if (_editable) _ime.attach(show: _wantKeyboard || widget.autofocus);
      _wantKeyboard = false;
      _blink.restart();
    } else {
      _ime.detach();
      _blink.stop();
      _handles.hide();
    }
    _scheduleAfterFrame();
  }

  void _viewUpdated(ViewUpdate update) {
    _ime.viewUpdated(update);
    if (update.transactions.isNotEmpty) {
      if (view.hasFocus) _blink.restart();
      if (update.docChanged) _handles.typed();
      // Read-only now: the keyboard has nothing to type into.
      if (!_editable && _ime.attached) _ime.detach();
    }
    _scheduleAfterFrame();
  }

  /// Once the frame is drawn: the handles follow the selection, and the keyboard is told where the caret is.
  void _scheduleAfterFrame() {
    if (_afterFrame) return;
    _afterFrame = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _afterFrame = false;
      if (!mounted) return;
      _handles.update();
      final box = _input?.viewportBox;
      if (box != null) _ime.sendGeometry(box);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  RenderEditorInput? get _input => _sliverKey.currentContext?.findRenderObject() as RenderEditorInput?;

  @override
  Rect? get viewportRect {
    final box = _input?.viewportBox;
    return box == null || !box.attached || !box.hasSize ? null : MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
  }

  /// How much of the scroll view the keyboard covers.
  double get _keyboardOverlap {
    final bounds = viewportRect;
    if (bounds == null || _inset <= 0) return 0;
    return math.max(0, bounds.bottom - (_screen.height - _inset));
  }

  /// Editor.tsx `footClearAt`, and what the keyboard covers.
  EdgeInsets? _margins() {
    var bottom = _keyboardOverlap;
    if (widget.footClear > 0) {
      final height = _position?.hasViewportDimension ?? false ? _position!.viewportDimension - bottom : 0.0;
      bottom += height <= 0 ? widget.footClear : math.min(widget.footClear, math.max(0, (height - widget.headerInset) / 3));
    }
    return bottom > 0 ? EdgeInsets.only(bottom: bottom) : null;
  }

  void _keepCaret() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !view.hasFocus) return;
      view.dispatch(TransactionSpec(effects: EditorViewLike.scrollIntoView(view.state.selection.main.head, yMargin: 56)));
    });
  }

  // -- keys ---------------------------------------------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyUpEvent) {
      for (final observers in view.eventObservers) {
        observers.keyDown?.call(event, view);
      }
      for (final handlers in view.eventHandlers) {
        if (handlers.keyDown?.call(event, view) ?? false) return KeyEventResult.handled;
      }
    }
    final shortcuts = Keymap.forState(view.state).shortcuts;
    if (!identical(_shortcuts.shortcuts, shortcuts)) _shortcuts.shortcuts = shortcuts;
    final context = node.context;
    return context == null ? KeyEventResult.ignored : _shortcuts.handle(context, event);
  }

  bool _run(StateCommand command) => runCommand(view, command);

  /// Flutter's text-editing intents, answered with CodeMirror's commands: what the app's default shortcuts send for
  /// a key no keymap of the editor's took, and what a platform's menus and selectors send.
  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    EditorKeyIntent: EditorKeyAction(() => view),
    DeleteCharacterIntent: CallbackAction<DeleteCharacterIntent>(onInvoke: (intent) => runKey(view, intent.forward ? 'Delete' : 'Backspace')),
    DeleteToNextWordBoundaryIntent: CallbackAction<DeleteToNextWordBoundaryIntent>(onInvoke: (intent) => _run(intent.forward ? deleteGroupForward : deleteGroupBackward)),
    DeleteToLineBreakIntent: CallbackAction<DeleteToLineBreakIntent>(onInvoke: (intent) => deleteLineBoundary(view, intent.forward)),
    ExtendSelectionByCharacterIntent: CallbackAction<ExtendSelectionByCharacterIntent>(
      onInvoke: (intent) => _run(intent.collapseSelection ? (intent.forward ? cursorCharRight : cursorCharLeft) : (intent.forward ? selectCharRight : selectCharLeft)),
    ),
    ExtendSelectionToNextWordBoundaryIntent: CallbackAction<ExtendSelectionToNextWordBoundaryIntent>(
      onInvoke: (intent) => _run(intent.collapseSelection ? (intent.forward ? cursorGroupRight : cursorGroupLeft) : (intent.forward ? selectGroupRight : selectGroupLeft)),
    ),
    ExtendSelectionToLineBreakIntent: CallbackAction<ExtendSelectionToLineBreakIntent>(
      onInvoke: (intent) => intent.collapseSelection ? cursorLineBoundary(view, intent.forward) : selectLineBoundary(view, intent.forward),
    ),
    ExtendSelectionVerticallyToAdjacentLineIntent: CallbackAction<ExtendSelectionVerticallyToAdjacentLineIntent>(
      onInvoke: (intent) => intent.collapseSelection ? cursorByLine(view, intent.forward) : selectByLine(view, intent.forward),
    ),
    ExtendSelectionVerticallyToAdjacentPageIntent: CallbackAction<ExtendSelectionVerticallyToAdjacentPageIntent>(
      onInvoke: (intent) => intent.collapseSelection ? cursorByPage(view, intent.forward) : selectByPage(view, intent.forward),
    ),
    ExtendSelectionToDocumentBoundaryIntent: CallbackAction<ExtendSelectionToDocumentBoundaryIntent>(
      onInvoke: (intent) => _run(intent.collapseSelection ? (intent.forward ? cursorDocEnd : cursorDocStart) : (intent.forward ? selectDocEnd : selectDocStart)),
    ),
    SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(onInvoke: (_) => _run(selectAll)),
    CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(onInvoke: (intent) => _copy(cut: intent.collapseSelection)),
    PasteTextIntent: CallbackAction<PasteTextIntent>(onInvoke: (_) => _paste(null)),
    UndoTextIntent: CallbackAction<UndoTextIntent>(onInvoke: (_) => _run(undo)),
    RedoTextIntent: CallbackAction<RedoTextIntent>(onInvoke: (_) => _run(redo)),
  };

  // -- the clipboard -------------------------------------------------------------------------------------------------

  Future<bool> _copy({required bool cut}) async {
    final state = view.state, sel = state.selection.main;
    if (sel.empty) return false;
    await Clipboard.setData(ClipboardData(text: state.sliceDoc(sel.from, sel.to)));
    if (cut && !state.readOnly && mounted) {
      view.dispatch(view.state.updateAll(<TransactionSpec>[view.state.replaceSelection(''), const TransactionSpec(userEvent: 'delete.cut', scrollIntoView: true)]));
    }
    return true;
  }

  Future<bool> _paste(String? text) async {
    final words = text ?? (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (words == null || words.isEmpty || !mounted) return false;
    _ime.paste(words);
    return true;
  }

  bool _pasteHandled(String text) {
    for (final handlers in view.eventHandlers) {
      if (handlers.paste?.call(text, view) ?? false) return true;
    }
    return false;
  }

  // -- what the gestures and the handles ask --------------------------------------------------------------------------

  @override
  void showHandles() {
    _handles.show();
    _scheduleAfterFrame();
  }

  @override
  void hideHandles() => _handles.hide();

  @override
  void showMagnifier(Offset global) => _handles.showMagnifierAt(global);

  @override
  void hideMagnifier() => _handles.hideMagnifier();

  @override
  void held(Held held) => widget.onHold?.call(held);

  @override
  Offset toLocal(Offset global) => _input?.globalToSliver(global) ?? global;

  @override
  void autoScroll(Offset global, VoidCallback again) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    _scrolledAgain = again;
    final scroller = _scroller ??= EdgeDraggingAutoScroller(scrollable, onScrollViewScrolled: () => _scrolledAgain?.call(), velocityScalar: 30);
    // A finger's breadth round the point: the page starts to move before the finger is on its very edge.
    scroller.startAutoScrollIfNecessary(Rect.fromCenter(center: global, width: 1, height: 96));
  }

  @override
  void stopAutoScroll() {
    _scroller?.stopAutoScroll();
    _scrolledAgain = null;
  }

  // -- the tree -----------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: _actions,
      child: Focus(
        focusNode: _focus,
        autofocus: widget.autofocus,
        includeSemantics: false,
        onKeyEvent: _onKey,
        child: EditorInputSliver(
          key: _sliverKey,
          view: view,
          caretLink: caretLink,
          onPointer: _gestures.pointer,
          fill: widget.fill,
          child: EditorSliver(view: view, env: widget.env, sheets: widget.sheets, meHue: widget.meHue),
        ),
      ),
    );
  }
}
