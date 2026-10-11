/// The input layer as an extension: what a state must hold for an `Editor` (editor_widget.dart) to type in it.
/// Editor.tsx lists these itself: `undoSlot.of(localUndo())`, `keymap.of(defaultKeymap)`, lang-markdown's own
/// keymap, `contentAttributes` in its `assist` slot, `scrollMargins`, and the update listener that fires
/// `feelTransaction`.
///
/// [editorInput] goes in `noteExtensions(more: ...)`. An `Editor` given a view whose state has none adds one
/// itself (`StateEffect.appendConfig`), at the lowest precedence; a state that wants its own keys above the
/// defaults puts [editorInput] where Editor.tsx has it.
///
/// It also supplies what commands.dart leaves to the view: [verticalMotion] by layout and [atomicRangesFor] from
/// the view's atomic ranges (motion.dart).
library;

import 'package:flutter/widgets.dart' show EdgeInsets;

import '../commands/commands.dart';
import '../commands/markdown_commands.dart' show pasteUrlAsLink;
import '../state/state.dart';
import '../state/undo_slot.dart';
import '../view/editor_view.dart';
import '../view/plugin.dart';
import 'felt.dart';
import 'keymap.dart';
import 'motion.dart';

/// What joins a state's input extension to the widget that types in it: the extension is made before there is a
/// view, and the widget comes later still.
class EditorInputHost {
  /// The view the state is in, once it has one.
  EditorView? view;

  /// Called with every update of the view: the `Editor` widget's, while it is mounted.
  void Function(ViewUpdate update)? onUpdate;

  /// Room to keep clear round the caret when it is scrolled into view: the widget's, while it is mounted.
  EdgeInsets? Function()? margins;
}

/// The host of a state's input extension, or null when it has none.
final Facet<EditorInputHost, EditorInputHost?> editorInputHost = Facet.define<EditorInputHost, EditorInputHost?>(combine: (values) => values.isEmpty ? null : values.first);

/// Editor.tsx's `assistSlot`: the keyboard's settings, swapped in place ([setAssist]).
final Compartment assistSlot = Compartment();

Extension _attrs(bool assist) => EditorViewLike.contentAttributes.of(assist ? EditorInputAttributes.prose : EditorInputAttributes.plain);

/// Sets whether the keyboard corrects, capitalises and suggests (`PROSE_ATTRS`) or leaves the words alone
/// (`PLAIN_ATTRS`).
void setAssist(EditorView view, bool assist) => view.dispatch(TransactionSpec(effects: assistSlot.reconfigure(_attrs(assist))));

class _InputPlugin extends PluginValue {
  _InputPlugin(this.host);

  final EditorInputHost host;

  @override
  void update(ViewUpdate update) {
    for (final tr in update.transactions) {
      feel(tr);
    }
    host.onUpdate?.call(update);
  }

  @override
  void destroy() {
    host.view = null;
  }
}

/// What the undo slot holds for a note on its own: undoSlot.ts `localUndo()`, the history and CodeMirror's keys for
/// it.
Extension localUndoWithKeys() => Extension.list(<Extension>[localUndo(), editorKeymap.of(historyKeymap)]);

/// What it holds while the editor is bound to its live document (liveBinding.ts `bindLive`: `yCollab(...)` and
/// `keymap.of(yUndoManagerKeymap)`): the document's undo and y-codemirror's keys for it. The history is not in
/// the state then, and comes back with nothing in it when the slot is given [localUndoWithKeys] again.
Extension liveUndoWithKeys(NoteUndo undo) => Extension.list(<Extension>[noteUndo.of(undo), editorKeymap.of(liveUndoKeymap)]);

/// The input layer's extension. `assist` is the web's prop of that name; `undo: false` leaves the undo history and
/// its keys out, for a state that fills [undoSlot] itself.
Extension editorInput({bool assist = true, bool undo = true}) {
  final host = EditorInputHost();
  return Extension.list(<Extension>[
    editorInputHost.of(host),
    // undoSlot.ts `localUndo`: the history and its keys together in the slot, so whoever swaps the slot for another
    // undo (a note live on two devices) swaps the keys with it.
    if (undo) undoSlot.of(localUndoWithKeys()),
    // lang-markdown binds its two keys above everything of ordinary precedence.
    Prec.high(editorKeymap.of(markdownBindings)),
    // And its paste: an address pasted over selected words makes them a link to it (`pasteURLAsLink`).
    EditorViewLike.eventHandlers(EditorEventHandlers(
      paste: (text, view) {
        final link = pasteUrlAsLink(view.state, text);
        if (link == null) return false;
        view.dispatch(link);
        return true;
      },
    )),
    editorKeymap.of(defaultKeymap),
    assistSlot.of(_attrs(assist)),
    verticalMotion.of((state, range, forward) {
      final view = host.view;
      return view == null ? moveVerticallyByColumn(state, range, forward) : verticalMotionOf(view, state, range, forward);
    }),
    atomicRangesFor.of((state) {
      final view = host.view;
      return view == null ? const <({int from, int to})>[] : atomicRangesOf(view, state);
    }),
    EditorViewLike.scrollMargins.of((_) => host.margins?.call()),
    ViewPlugin.define<_InputPlugin>((view) {
      host.view = view as EditorView;
      return _InputPlugin(host);
    }),
  ]);
}
