/// The keyboard: one `DeltaTextInputClient` for the whole editor, which shows the keyboard a WINDOW of the note.
///
/// What CodeMirror gets from a `contenteditable` (the browser tells the keyboard what the text is, and CodeMirror
/// reads the DOM back, @codemirror/view domobserver.ts and input.ts), Flutter has to do by hand: the keyboard holds
/// a copy of some text, sends its edits as deltas against that copy, and is told when the copy changed under it.
/// The eight rules this keeps were found by experiment on Android (docs/STAGE4.md, "Piece 0, the keyboard"; the
/// throwaway app the experiment was made with, lib/spike/ime_spike.dart, is in git's history up to 2026-10-10):
///
/// 1. **The keyboard's value is always a real range of the document**: [windowFrom]-[windowTo], and [held] is what
///    the keyboard is believed to hold of it. A value is pushed only when the range, or the selection in it, is not
///    what the keyboard already holds ([_sync]); plain typing pushes nothing at all.
/// 2. **Backspace is a key**: Gboard sends `KEYCODE_DEL` and the engine applies nothing, so the key runs the keymap
///    (keymap.dart: `deleteMarkupBackward`, then `deleteCharBackward`) and the result is pushed. A deletion that
///    does arrive as a delta is taken: of a selection as it is, and of the one character before the caret as the
///    Backspace it is, through the same keymap (CodeMirror does this for Android's keyboards too, input.ts
///    `applyDOMChange`).
/// 3. **Enter is an inserted "\n"**, never `performAction`: it runs the keymap's Enter
///    (`insertNewlineContinueMarkup`, then `insertNewlineAndIndent`). `performAction(newline)` does the same, for a
///    keyboard that sends it after all.
/// 4. **A swap the keyboard cannot see is made visible**: Android drops a new value whose selection and composing
///    offsets are the ones it has, and the keyboard's suggestions go on rewriting the old words. When the text
///    changes and the offsets do not, the client attaches again, which restarts the input.
/// 5. **The window is the caret's line and a neighbour each side, kept lazily**: it stays while the selection is
///    strictly inside it (so Enter, Backspace across a line start and a caret moved to the next line push
///    nothing), is made again when the caret reaches its first or last line or it has grown past a dozen lines,
///    and is held through a composition where the selection is still somewhere in it.
/// 6. **Every delta of a batch is applied, then the keyboard is synced once.** Each delta's `oldText` is checked
///    against [held]; one made against the value before the last push (the keyboard typed before the push reached
///    it) is mapped onto the document as it is now; one against anything else is dropped, and the input is
///    restarted on what the document says.
/// 7. **Composing is kept mapped and cleared when the editor moves the caret.** The composing range is held as
///    document positions, follows changes made elsewhere in the note, and is dropped by any change of the
///    selection, or of the composing text, that the keyboard did not make (pushing a different composing text
///    restarts the input on Android). The view is told ([EditorView.setComposing]) before a composing change is
///    dispatched, so what draws the caret's line leaves it as written.
/// 8. **The keyboard is told where things are**: `setEditableSizeAndTransform`, `setCaretRect`,
///    `setComposingRect` ([sendGeometry]), after a frame, when they changed.
///
/// Deltas become transactions with CodeMirror's user events: `input.type`, `input.type.compose` while the keyboard
/// underlines what it typed, `delete.backward`, `delete.forward`, `delete.selection`, `select` for a caret the
/// keyboard moved, and `input.paste` for what [paste] is given and for a keyboard that commits several lines at
/// once (its clipboard row; a keyboard never types a line break inside other text).
///
/// Why a window: pushing a 169 kB note costs about 47 ms on Android's main thread for every change the editor
/// makes, and half a millisecond for three lines.
///
/// A selection too long to show the keyboard (past [maxSelection] characters) is shown clamped to the lines round
/// its head; a delta that replaces or deletes exactly what the keyboard thinks is selected is then applied to the
/// whole selection.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../state/change.dart';
import '../state/char.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../view/editor_view.dart';
import '../view/plugin.dart';
import 'clipboard.dart';

/// The keyboard's client for one [EditorView].
class EditorIme with TextInputClient, DeltaTextInputClient {
  EditorIme({required this.view, required this.runKey, required this.viewId, this.onPaste});

  final EditorView view;

  /// Runs a key through the editor's keymaps by CodeMirror's name (`Backspace`, `Enter`); true when a binding took
  /// it.
  final bool Function(String key) runKey;

  /// The Flutter view the editor is in, for the connection.
  final int Function() viewId;

  /// Asked before pasted text is inserted (the plugins' `paste` handlers); true when it was handled.
  final bool Function(String text)? onPaste;

  /// Says what the client does, when set: for a session on a phone (`adb logcat -s flutter`).
  static void Function(String line)? log;

  /// The longest selection the keyboard is shown whole, in characters.
  static const int maxSelection = 8000;

  /// The most lines a window is let grow to before it is made again.
  static const int maxLines = 12;

  TextInputConnection? _conn;
  TextInputConfiguration? _config;

  /// The window: the document range the keyboard is shown.
  int windowFrom = 0;
  int windowTo = 0;

  /// What the keyboard is believed to hold.
  TextEditingValue held = TextEditingValue.empty;

  /// The value before the last push, and where its range is now: a delta may still arrive against it.
  ({String text, int from, int to})? _prev;

  int? _compFrom;
  int? _compTo;
  bool _clamped = false;
  bool _applying = false;
  bool _diverged = false;
  /// Whether the view has had an update, in this batch, since it was last told the keyboard was composing.
  bool _dispatched = false;

  /// How many values were pushed and how many times the client attached, for a test to count.
  int pushes = 0;
  int attaches = 0;

  bool get attached => _conn != null && _conn!.attached;

  /// Whether the keyboard is composing: it has typed text it may still change.
  bool get composing => _compFrom != null;

  /// The composing range in the document, or null.
  ({int from, int to})? get composingRange => _compFrom == null ? null : (from: _compFrom!, to: _compTo!);

  // -- the connection ----------------------------------------------------------------------------------------------

  TextInputConfiguration _configuration() {
    final attrs = view.state.facet(EditorViewLike.contentAttributes);
    final dark = view.look?.env.dark ?? false;
    return TextInputConfiguration(
      viewId: viewId(),
      inputType: attrs.inputType ?? TextInputType.multiline,
      inputAction: attrs.enterKeyHint ?? TextInputAction.newline,
      textCapitalization: attrs.autocapitalize ?? TextCapitalization.none,
      autocorrect: attrs.autocorrect ?? false,
      enableSuggestions: attrs.suggestions ?? attrs.autocorrect ?? false,
      keyboardAppearance: dark ? Brightness.dark : Brightness.light,
      enableDeltaModel: true,
    );
  }

  /// Opens the connection (or keeps the one there is) and gives the keyboard its window. `show` raises the
  /// keyboard.
  void attach({bool show = true}) {
    if (!attached) {
      _open();
      _clearComposing();
      held = TextEditingValue.empty;
      _prev = null;
      windowFrom = windowTo = -1;
      _sync(force: true);
    }
    if (show) _conn!.show();
  }

  void _open() {
    _config = _configuration();
    _conn = TextInput.attach(this, _config!);
    _sentBox = null;
    _sentCaret = null;
    _sentComposing = null;
    attaches += 1;
    _say('attach');
  }

  /// Raises the keyboard, when there is a connection.
  void show() {
    if (attached) _conn!.show();
  }

  /// Closes the connection: the keyboard goes.
  void detach() {
    if (_conn != null) {
      if (_conn!.attached) _conn!.close();
      _conn = null;
      _say('detach');
    }
    _clearComposing();
  }

  /// The keyboard's settings changed (`contentAttributes`, the page's side).
  void configChanged() {
    if (!attached) return;
    final next = _configuration();
    final was = _config;
    if (was != null &&
        was.autocorrect == next.autocorrect &&
        was.enableSuggestions == next.enableSuggestions &&
        was.textCapitalization == next.textCapitalization &&
        was.inputType == next.inputType &&
        was.inputAction == next.inputAction &&
        was.keyboardAppearance == next.keyboardAppearance) {
      return;
    }
    _config = next;
    _conn!.updateConfig(next);
  }

  // -- the window --------------------------------------------------------------------------------------------------

  /// The range the keyboard should be shown for the selection as it is.
  (int, int) _window() {
    final doc = view.state.doc, sel = view.state.selection.main;
    final last = doc.lines;
    _clamped = sel.to - sel.from > maxSelection;
    var a = doc.lineAt(_clamped ? sel.head : sel.from).number, b = doc.lineAt(_clamped ? sel.head : sel.to).number;
    if (!_clamped && b - a > maxLines * 4) {
      _clamped = true;
      a = b = doc.lineAt(sel.head).number;
    }
    if (windowFrom >= 0 && windowTo <= doc.length && windowFrom <= windowTo) {
      final ws = doc.lineAt(windowFrom), we = doc.lineAt(windowTo);
      if (ws.from == windowFrom && we.to == windowTo && we.number - ws.number <= math.max(maxLines, b - a + 2)) {
        final inside = (ws.number < a || (a == 1 && ws.number == 1)) && (we.number > b || (b == last && we.number == last));
        final holds = ws.number <= a && we.number >= b;
        if (inside || (holds && composing)) return (windowFrom, windowTo);
      }
    }
    final from = math.max(1, a - 1), to = math.min(last, b + 1);
    return (doc.line(from).from, doc.line(to).to);
  }

  TextEditingValue _valueFor(int from, int to) {
    final doc = view.state.doc, sel = view.state.selection.main;
    final text = doc.sliceString(from, to);
    var composing = TextRange.empty;
    final cf = _compFrom, ct = _compTo;
    if (cf != null && ct != null && cf >= from && ct <= to && cf < ct) composing = TextRange(start: cf - from, end: ct - from);
    return TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: (sel.anchor - from).clamp(0, text.length), extentOffset: (sel.head - from).clamp(0, text.length)),
      composing: composing,
    );
  }

  static bool _same(TextEditingValue a, TextEditingValue b) =>
      a.text == b.text &&
      a.selection.baseOffset == b.selection.baseOffset &&
      a.selection.extentOffset == b.selection.extentOffset &&
      a.composing.start == b.composing.start &&
      a.composing.end == b.composing.end;

  /// Makes the keyboard's value the window the selection wants. Nothing is sent when the keyboard already holds
  /// it. `restart` attaches again whatever changed.
  void _sync({bool force = false, bool restart = false}) {
    if (!attached) return;
    final (from, to) = _window();
    final next = _valueFor(from, to);
    if (!force && !restart && _same(next, held)) {
      // The same words at the same offsets: there is nothing to tell, wherever in the note they are.
      windowFrom = from;
      windowTo = to;
      return;
    }
    final textMoved = next.text != held.text;
    final unseen = textMoved && next.selection.baseOffset == held.selection.baseOffset && next.selection.extentOffset == held.selection.extentOffset && next.composing == held.composing;
    _prev = (text: held.text, from: windowFrom < 0 ? from : windowFrom, to: windowTo < 0 ? to : windowTo);
    windowFrom = from;
    windowTo = to;
    held = next;
    if (restart || (unseen && !force)) {
      _open();
      _say('reattach${unseen ? ' (same offsets, new text)' : ''}');
    }
    pushes += 1;
    _say('push @$from len=${next.text.length} sel=${next.selection.baseOffset}..${next.selection.extentOffset} comp=${next.composing.start}..${next.composing.end}');
    _conn!.setEditingState(next);
  }

  // -- what the view tells ------------------------------------------------------------------------------------------

  /// Every update of the view comes through here (the input plugin's `update`).
  void viewUpdated(ViewUpdate update) {
    if (update.docChanged) {
      final changes = update.changes;
      if (windowFrom >= 0) {
        windowFrom = changes.mapPos(windowFrom, -1);
        windowTo = changes.mapPos(windowTo, 1);
      }
      final prev = _prev;
      if (prev != null) _prev = (text: prev.text, from: changes.mapPos(prev.from, -1), to: changes.mapPos(prev.to, 1));
      if (_compFrom != null) {
        if (!_applying && changes.touchesRange(_compFrom!, _compTo!) != Touch.none) {
          _clearComposing();
        } else {
          _compFrom = changes.mapPos(_compFrom!, 1);
          _compTo = changes.mapPos(_compTo!, -1);
          if (_compFrom! >= _compTo!) _clearComposing();
        }
      }
    }
    if (_applying) {
      _dispatched = !view.composing;
      return;
    }
    // Focus, a scroll, lines measured: nothing the keyboard holds has changed.
    if (update.transactions.isEmpty) return;
    // A caret the editor moved ends what the keyboard was composing.
    if (composing && !update.state.selection.main.eq(update.startState.selection.map(update.changes).main)) _clearComposing();
    if (!identical(update.state.facet(EditorViewLike.contentAttributes), update.startState.facet(EditorViewLike.contentAttributes))) configChanged();
    _sync();
  }

  void _clearComposing() {
    _compFrom = _compTo = null;
    view.setComposing(false);
  }

  void _setComposing(TextRange range) {
    if (range.isValid && !range.isCollapsed) {
      _compFrom = windowFrom + range.start;
      _compTo = windowFrom + range.end;
    } else {
      _compFrom = _compTo = null;
    }
  }

  // -- TextInputClient ---------------------------------------------------------------------------------------------

  @override
  TextEditingValue? get currentTextEditingValue => held;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    // A keyboard that answers without deltas: the difference from what it held, as one.
    final before = held.text, after = value.text;
    var prefix = 0;
    final most = math.min(before.length, after.length);
    while (prefix < most && before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix += 1;
    }
    var suffix = 0;
    while (suffix < most - prefix && before.codeUnitAt(before.length - 1 - suffix) == after.codeUnitAt(after.length - 1 - suffix)) {
      suffix += 1;
    }
    final TextEditingDelta delta;
    if (before == after) {
      delta = TextEditingDeltaNonTextUpdate(oldText: before, selection: value.selection, composing: value.composing);
    } else {
      delta = TextEditingDeltaReplacement(
        oldText: before,
        replacementText: after.substring(prefix, after.length - suffix),
        replacedRange: TextRange(start: prefix, end: before.length - suffix),
        selection: value.selection,
        composing: value.composing,
      );
    }
    updateEditingValueWithDeltas(<TextEditingDelta>[delta]);
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    if (!view.state.facet(EditorViewLike.editable)) {
      _sync(force: true);
      return;
    }
    final wasComposing = composing;
    _applying = true;
    _diverged = false;
    _dispatched = false;
    try {
      for (final delta in textEditingDeltas) {
        _apply(delta);
      }
    } finally {
      _applying = false;
    }
    // A composition that ended with nothing changed since: the caret's line is drawn as itself again.
    if (wasComposing && !composing) {
      view.setComposing(false);
      if (!_dispatched) view.dispatch(const TransactionSpec());
    }
    if (_diverged) _clearComposing();
    _sync(restart: _diverged);
  }

  void _apply(TextEditingDelta delta) {
    if (delta.oldText != held.text) {
      final prev = _prev;
      _diverged = true;
      if (prev != null && delta.oldText == prev.text) {
        _say('delta against the value before the last push: mapped');
        _applyStale(delta, prev);
      } else {
        _say('delta against text the keyboard should not hold (${delta.oldText.length} for ${held.text.length}): dropped');
      }
      return;
    }
    final before = held;
    final after = delta.apply(before);
    switch (delta) {
      case TextEditingDeltaInsertion():
        _say('ins @${delta.insertionOffset} "${_esc(delta.textInserted)}"');
        _replace(windowFrom + delta.insertionOffset, windowFrom + delta.insertionOffset, delta.textInserted, before, after);
      case TextEditingDeltaDeletion():
        _say('del ${delta.deletedRange.start}..${delta.deletedRange.end}');
        _delete(windowFrom + delta.deletedRange.start, windowFrom + delta.deletedRange.end, before, after);
      case TextEditingDeltaReplacement():
        _say('rep ${delta.replacedRange.start}..${delta.replacedRange.end} "${_esc(delta.replacementText)}"');
        // Only what differs: "hel" made "hell" is an l typed.
        final old = delta.textReplaced, text = delta.replacementText;
        var prefix = 0;
        final most = math.min(old.length, text.length);
        while (prefix < most && old.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
          prefix += 1;
        }
        // Not through the middle of a pair.
        if (prefix > 0 && prefix < old.length && old.codeUnitAt(prefix - 1) & 0xFC00 == 0xD800) prefix -= 1;
        var suffix = 0;
        while (suffix < most - prefix && old.codeUnitAt(old.length - 1 - suffix) == text.codeUnitAt(text.length - 1 - suffix)) {
          suffix += 1;
        }
        if (suffix > 0 && old.codeUnitAt(old.length - suffix) & 0xFC00 == 0xDC00) suffix -= 1;
        final from = windowFrom + delta.replacedRange.start + prefix, to = windowFrom + delta.replacedRange.end - suffix;
        final exact = _clamped && delta.replacedRange.start == before.selection.start && delta.replacedRange.end == before.selection.end;
        if (exact) {
          _replace(windowFrom + delta.replacedRange.start, windowFrom + delta.replacedRange.end, text, before, after);
        } else if (prefix + suffix == text.length) {
          _delete(from, to, before, after);
        } else {
          _replace(from, to, text.substring(prefix, text.length - suffix), before, after);
        }
      case TextEditingDeltaNonTextUpdate():
        _say('sel ${delta.selection.baseOffset}..${delta.selection.extentOffset} comp=${delta.composing.start}..${delta.composing.end}');
        _select(after);
    }
  }

  /// Whether `from`-`to` is what the keyboard believes is selected while the real selection is longer than it was
  /// shown.
  bool _standsForSelection(int from, int to, TextEditingValue before) =>
      _clamped && !before.selection.isCollapsed && from == windowFrom + before.selection.start && to == windowFrom + before.selection.end;

  void _replace(int from, int to, String text, TextEditingValue before, TextEditingValue after) {
    final state = view.state, sel = state.selection.main;
    final isComposing = after.composing.isValid && !after.composing.isCollapsed;
    var literal = true;
    if (_standsForSelection(from, to, before)) {
      from = sel.from;
      to = sel.to;
      literal = false;
    }
    if (text == '\n' && !isComposing) {
      // Enter. The keymap answers for the selection, so the selection is what the keyboard replaced.
      if (sel.from != from || sel.to != to) view.dispatch(TransactionSpec(selection: EditorSelection.single(from, to)));
      held = after;
      _setComposing(TextRange.empty);
      if (!runKey('Enter')) {
        view.dispatch(view.state.update(TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: '\n'), selection: EditorSelection.single(from + 1), userEvent: 'input', scrollIntoView: true)));
      }
      return;
    }
    final pasted = !isComposing && text.length > 1 && text.contains('\n');
    if (pasted && (onPaste?.call(text) ?? false)) {
      held = after;
      return;
    }
    view.setComposing(isComposing);
    final anchor = literal ? windowFrom + after.selection.baseOffset : from + text.length;
    final head = literal ? windowFrom + after.selection.extentOffset : from + text.length;
    final length = state.doc.length - (to - from) + text.length;
    view.dispatch(
      TransactionSpec(
        changes: ChangeSpec(from: from, to: to, insert: text),
        selection: after.selection.isValid ? EditorSelection.single(anchor.clamp(0, length), head.clamp(0, length)) : null,
        userEvent: isComposing ? 'input.type.compose' : (pasted ? 'input.paste' : 'input.type'),
        scrollIntoView: true,
      ),
    );
    held = after;
    _setComposing(after.composing);
  }

  void _delete(int from, int to, TextEditingValue before, TextEditingValue after) {
    final state = view.state, sel = state.selection.main;
    final wasComposing = before.composing.isValid && !before.composing.isCollapsed;
    final isComposing = after.composing.isValid && !after.composing.isCollapsed;
    if (_standsForSelection(from, to, before)) {
      from = sel.from;
      to = sel.to;
    }
    if (!wasComposing && !isComposing && sel.empty && from < to) {
      // One character either side of the caret is the key it stands for.
      final line = state.doc.lineAt(sel.head);
      final at = sel.head - line.from;
      final back = to == sel.head && (at == 0 ? from == sel.head - 1 : from == line.from + findClusterBreak(line.text, at, false));
      final forward = from == sel.head && (at == line.length ? to == sel.head + 1 : to == line.from + findClusterBreak(line.text, at));
      if (back || forward) {
        held = after;
        _setComposing(TextRange.empty);
        if (runKey(back ? 'Backspace' : 'Delete')) return;
      }
    }
    final event = !sel.empty && from == sel.from && to == sel.to ? 'delete.selection' : (to <= sel.head ? 'delete.backward' : 'delete.forward');
    view.setComposing(isComposing);
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: from, to: to), selection: EditorSelection.single(from), userEvent: event, scrollIntoView: true));
    held = after;
    _setComposing(after.composing);
  }

  void _select(TextEditingValue after) {
    final sel = view.state.selection.main;
    final isComposing = after.composing.isValid && !after.composing.isCollapsed;
    view.setComposing(isComposing);
    held = after;
    _setComposing(after.composing);
    if (!after.selection.isValid || _clamped) return;
    final anchor = windowFrom + after.selection.baseOffset, head = windowFrom + after.selection.extentOffset;
    if (anchor == sel.anchor && head == sel.head) return;
    view.dispatch(TransactionSpec(selection: EditorSelection.single(anchor, head), userEvent: 'select', scrollIntoView: true));
  }

  /// A delta the keyboard made against `prev`, the value it held before the last push: its offsets are found in
  /// the document as it is now by what the two have in common at each end.
  void _applyStale(TextEditingDelta delta, ({String text, int from, int to}) prev) {
    final doc = view.state.doc;
    final from = prev.from.clamp(0, doc.length), to = prev.to.clamp(from, doc.length);
    final now = doc.sliceString(from, to), old = prev.text;
    final most = math.min(old.length, now.length);
    var prefix = 0;
    while (prefix < most && old.codeUnitAt(prefix) == now.codeUnitAt(prefix)) {
      prefix += 1;
    }
    var suffix = 0;
    while (suffix < most - prefix && old.codeUnitAt(old.length - 1 - suffix) == now.codeUnitAt(now.length - 1 - suffix)) {
      suffix += 1;
    }
    int at(int offset) {
      if (offset < prefix) return from + offset;
      if (offset >= old.length - suffix) return to - (old.length - offset);
      return to - suffix;
    }

    final (int a, int b, String text) = switch (delta) {
      TextEditingDeltaInsertion() => (at(delta.insertionOffset), at(delta.insertionOffset), delta.textInserted),
      TextEditingDeltaDeletion() => (at(delta.deletedRange.start), at(delta.deletedRange.end), ''),
      TextEditingDeltaReplacement() => (at(delta.replacedRange.start), at(delta.replacedRange.end), delta.replacementText),
      _ => (-1, -1, ''),
    };
    if (a < 0) {
      if (delta.selection.isValid) {
        view.dispatch(TransactionSpec(selection: EditorSelection.single(at(delta.selection.baseOffset), at(delta.selection.extentOffset)), userEvent: 'select'));
      }
      return;
    }
    if (a == b && text.isEmpty) return;
    view.dispatch(
      TransactionSpec(
        changes: ChangeSpec(from: a, to: math.max(a, b), insert: text),
        selection: EditorSelection.single(a + text.length),
        userEvent: text.isEmpty ? 'delete.backward' : 'input.type',
        scrollIntoView: true,
      ),
    );
  }

  /// Text put in at the selection as a paste: the plugins' `paste` handlers are asked first.
  void paste(String text) {
    if (text.isEmpty || view.state.readOnly) return;
    if (onPaste?.call(text) ?? false) return;
    final state = view.state;
    view.dispatch(state.updateAll(<TransactionSpec>[pasteOf(state, text), const TransactionSpec(userEvent: 'input.paste', scrollIntoView: true)]));
  }

  @override
  void performAction(TextInputAction action) {
    _say('performAction $action');
    if (action == TextInputAction.newline && view.state.facet(EditorViewLike.editable)) runKey('Enter');
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _say('connectionClosed');
    _conn = null;
    _clearComposing();
  }

  // -- where things are ---------------------------------------------------------------------------------------------

  Rect? _sentBox;
  Rect? _sentCaret;
  Rect? _sentComposing;

  /// Tells the keyboard where the editor's box is on the screen (`box`, a render box and its size), and in it the
  /// caret and what is being composed. Sent only when something moved.
  void sendGeometry(RenderBox box) {
    if (!attached || !box.attached || !box.hasSize) return;
    final transform = box.getTransformTo(null);
    final bounds = MatrixUtils.transformRect(transform, Offset.zero & box.size);
    if (bounds != _sentBox) {
      _sentBox = bounds;
      _conn!.setEditableSizeAndTransform(box.size, transform);
    }
    final sel = view.state.selection.main;
    final at = view.coordsAtPos(sel.head, sel.assoc == 0 ? 1 : sel.assoc);
    if (at == null) return;
    // In the box's own pixels, which the transform above carries to the screen: `coordsAtPos` answers the screen's,
    // and inside a canvas zoomed in or out (lib/canvas, a card of words being written) the two differ by the zoom.
    Rect own(Rect screen) => Rect.fromPoints(box.globalToLocal(screen.topLeft), box.globalToLocal(screen.bottomRight));
    final caret = own(Rect.fromLTRB(at.left, at.top, at.left + 1, at.bottom));
    if (caret != _sentCaret) {
      _sentCaret = caret;
      _conn!.setCaretRect(caret);
    }
    var composed = caret;
    final range = composingRange;
    if (range != null) {
      final a = view.coordsAtPos(range.from, 1), b = view.coordsAtPos(range.to, -1);
      if (a != null && b != null) composed = own(Rect.fromLTRB(math.min(a.left, b.left), math.min(a.top, b.top), math.max(a.right, b.right), math.max(a.bottom, b.bottom)));
    }
    if (composed != _sentComposing) {
      _sentComposing = composed;
      _conn!.setComposingRect(composed);
    }
  }

  static String _esc(String text) {
    final shown = text.replaceAll('\n', r'\n');
    return shown.length <= 40 ? shown : '${shown.substring(0, 18)}…${shown.substring(shown.length - 18)}';
  }

  void _say(String line) => log?.call(line);
}
