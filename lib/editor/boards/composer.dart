/// The + on a column: a field at the top of it, for the new card's words (Matt: "a button on each board to add an
/// item, it should add the item to the list the board is derived from"). Ports the field of
/// `src/app/editor/boards/composer.ts`.
///
/// The words are asked for before anything is written, and the keyboard's own done key writes the item under the
/// board's last one with an anchor named after them, and the card at the top of this column (core/boards.dart
/// `newCard`, card_edits.dart `addCard`). The field stays open and empty for the next card; Escape, or leaving it
/// empty, closes it. Nothing goes into the note's own lines by the caret, so the line is always a proper task item,
/// `- [ ] words ^anchor`.
///
/// It is drawn as the card it is about to be (Matt: "Add task input and button dont match up"): the card's corners,
/// ground and ring, an empty tick box where the card's box goes so the words start where a card's do, and an Add
/// whose corners sit inside the field's.
///
/// **The field and the note's keyboard.** The editor is the one text input client of a note (lib/editor/input):
/// while it has the focus the keyboard edits the note, and its keys are the note's. A board is built inside the
/// editor, so a field in it would by default be a child of the editor's own focus: the editor would go on counting
/// itself focused (`hasFocus` is true of a node whose child has it), keep what it believes is its connection to the
/// keyboard, attach again at the next change to the note and take the keyboard back from the field in the middle of
/// a card; and every key the field did not take (a hardware Backspace, an arrow) would bubble up into the editor's
/// keymap and edit the note. So this field's focus is hung from the page's focus scope instead, beside the
/// editor's and not under it ([Focus.parentNode]). Taking the focus then takes it from the editor, whose connection
/// closes as its focus goes (editor_widget.dart `_focusChanged`), and the field attaches its own in the same turn,
/// so the keyboard stays up and simply changes hands; its keys go up to the app's own text shortcuts and never
/// through the editor. The editor having lost its focus, no board shows its lines (view/drawn_block.dart
/// `caretIn`), so the board being typed into stays drawn. Adding a card dispatches to the note without asking for
/// its focus; the board is rebuilt in place and this field's state, focus and keyboard are kept across it, which
/// is what the page's `updateDOM` was for. One way to the editor is left by the focus alone: a text field's own
/// answers to the app's text shortcuts (delete a character, move by a word, select all, undo) are made to be
/// overridden by whoever stands above it in the page, and the editor stands above it with answers of its own to
/// every one of them, each of which edits the note. So the field is given back its own ([ownTextKeys]): an answer to
/// each of those, between the field and the editor, that only passes it on to the field's. Add is pressed without taking the focus (nothing here takes focus unless
/// it asks), so the keyboard does not drop between cards. A tap on the note gives the focus, and the keyboard, back
/// to the editor, and the field, left empty, closes.
///
/// What differs:
/// - A password manager watched the page's form (Matt: "New Tasks are popping password manager save modal") and was
///   told what it really is four ways. Here the field simply offers the phone nothing to fill ([autofillHints]
///   none, no autofill group), which is all there is to say.
/// - Enter while a keyboard is still composing a word was left to finish it on the page; the phone's done key ends
///   the composition itself before it reports.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'board_look.dart';
import 'board_words.dart';

/// An answer to a text intent that hands it straight back to the field's own (`Action.callingAction`): set between
/// a field and an ancestor that would otherwise answer for it. Of every intent at once: the field answers several
/// kinds with one action of a wider kind, which a narrower answer here could not name.
class _Own extends Action<Intent> {
  @override
  bool isEnabled(Intent intent) => callingAction?.isActionEnabled ?? false;

  @override
  bool consumesKey(Intent intent) => callingAction?.consumesKey(intent) ?? false;

  @override
  Object? invoke(Intent intent) => callingAction?.invoke(intent);
}

/// The intents the editor answers for the note (editor_widget.dart `_actions`), and the rest a text field makes
/// overridable: each handed back to the field.
final Map<Type, Action<Intent>> ownTextKeys = <Type, Action<Intent>>{
  DeleteCharacterIntent: _Own(),
  DeleteToNextWordBoundaryIntent: _Own(),
  DeleteToLineBreakIntent: _Own(),
  ExtendSelectionByCharacterIntent: _Own(),
  ExtendSelectionToNextWordBoundaryIntent: _Own(),
  ExtendSelectionToNextParagraphBoundaryIntent: _Own(),
  ExtendSelectionToLineBreakIntent: _Own(),
  ExtendSelectionVerticallyToAdjacentLineIntent: _Own(),
  ExtendSelectionVerticallyToAdjacentPageIntent: _Own(),
  ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent: _Own(),
  ExtendSelectionToDocumentBoundaryIntent: _Own(),
  ExtendSelectionToNextWordBoundaryOrCaretLocationIntent: _Own(),
  ExpandSelectionToDocumentBoundaryIntent: _Own(),
  ExpandSelectionToLineBreakIntent: _Own(),
  SelectAllTextIntent: _Own(),
  CopySelectionTextIntent: _Own(),
  PasteTextIntent: _Own(),
  RedoTextIntent: _Own(),
  UndoTextIntent: _Own(),
  TransposeCharactersIntent: _Own(),
  ReplaceTextIntent: _Own(),
  UpdateSelectionIntent: _Own(),
};

class BoardComposer extends StatefulWidget {
  const BoardComposer({super.key, required this.look, required this.name, required this.onAdd, required this.onClose});

  final BoardLook look;

  /// The column's name, for what the field is called.
  final String name;

  /// The words to add; answers whether a card was written.
  final bool Function(String words) onAdd;
  final VoidCallback onClose;

  @override
  State<BoardComposer> createState() => BoardComposerState();
}

class BoardComposerState extends State<BoardComposer> implements TextSelectionGestureDetectorBuilderDelegate {
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'New card');
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  Timer? _leaving;
  bool _handles = false;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  bool get ready => controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    focusNode.addListener(_focusMoved);
    focus();
  }

  @override
  void dispose() {
    _leaving?.cancel();
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The field focused, and the keyboard asked for: at first, and when the + is pressed again.
  void focus() {
    focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) editableTextKey.currentState?.requestKeyboard();
    });
  }

  void _focusMoved() {
    _leaving?.cancel();
    _leaving = null;
    if (focusNode.hasFocus || ready) return;
    // Left empty: closed, unless the focus is straight back (the + pressed again).
    _leaving = Timer(const Duration(milliseconds: 150), () {
      if (mounted && !focusNode.hasFocus) widget.onClose();
    });
  }

  /// The words added as a card; the field kept, emptied, for the next.
  void submit() {
    if (!ready) return;
    if (!widget.onAdd(controller.text)) return;
    controller.clear();
    fireMotor(HapticKind.selection);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final t = look.t;
    final style = look.style(look.em);
    final empty = controller.text.isEmpty;
    final field = EditableText(
      key: editableTextKey,
      controller: controller,
      focusNode: focusNode,
      style: style,
      cursorColor: look.ink,
      cursorWidth: 1,
      backgroundCursorColor: look.ink3,
      selectionColor: focusNode.hasFocus ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      showSelectionHandles: _handles,
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      keyboardType: TextInputType.text,
      // `enterKeyHint = 'done'`, `autocapitalize = 'sentences'`
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      autofillHints: null,
      maxLines: 1,
      // The done key adds the card and leaves the field where it is, for the next.
      onEditingComplete: submit,
      onTapOutside: (_) {},
      onSelectionChanged: (selection, cause) {
        final show = cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.doubleTap || (cause == SelectionChangedCause.tap && !empty);
        if (show != _handles) setState(() => _handles = show);
      },
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
      textScaler: TextScaler.noScaling,
    );
    return Container(
      height: look.composeHeight,
      padding: EdgeInsets.fromLTRB(look.cardStart, look.composePad, look.composePad, look.composePad),
      decoration: BoxDecoration(color: look.paper, borderRadius: BorderRadius.circular(look.cardRadius), boxShadow: const <BoxShadow>[BoardLook.cardShadow]),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(look.cardRadius),
        border: Border.all(color: look.composeRing, width: 1.5, strokeAlign: BorderSide.strokeAlignInside),
      ),
      child: Row(
        children: <Widget>[
          // Where the card's tick box goes, so the words typed start where a card's words do.
          Container(
            key: const ValueKey<String>('compose-tick'),
            width: look.tickSize,
            height: look.tickSize,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(look.tickRadius), border: Border.all(color: look.composeTickEdge, width: 1.5)),
          ),
          SizedBox(width: look.cardColumnGap),
          Expanded(
            child: Semantics(
              container: true,
              textField: true,
              label: 'New card in ${widget.name}',
              child: SizedBox(
                key: const ValueKey<String>('compose-field'),
                height: look.composeField,
                // Hung from the page's focus scope, not from the editor the board is built in (see the header).
                child: Focus(
                  parentNode: FocusScope.of(context),
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _key,
                  child: _gestures.buildGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: <Widget>[
                        // '.cm-boardComposeField::placeholder': { color: 'var(--app-ink-3, …)' }
                        if (empty) IgnorePointer(child: Text('New card', maxLines: 1, softWrap: false, textScaler: TextScaler.noScaling, style: style.copyWith(color: look.ink3))),
                        Actions(actions: ownTextKeys, child: field),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: look.cardColumnGap),
          Semantics(
            container: true,
    button: true,
            enabled: ready,
            label: 'Add',
            onTap: ready ? submit : null,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: submit,
              child: AnimatedContainer(
                key: const ValueKey<String>('compose-add'),
                // `transition: 'background-color 120ms ease, color 120ms ease'`
                duration: const Duration(milliseconds: 120),
                height: look.composeField,
                padding: EdgeInsets.symmetric(horizontal: look.composeAddSide),
                decoration: BoxDecoration(color: look.composeAddGround(ready: ready), borderRadius: BorderRadius.circular(look.composeAddRadius)),
                child: Align(widthFactor: 1, child: BoardWords('Add', face: look.composeAddFace(ready: ready), wrap: false, shrink: true)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
