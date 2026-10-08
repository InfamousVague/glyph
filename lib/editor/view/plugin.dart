/// What an extension sees of the view: CodeMirror's `ViewPlugin`, `PluginValue`, `ViewUpdate` and the parts of
/// `EditorView` that extension files call (@codemirror/view: extension.ts, editorview.ts), as interfaces with no
/// rendering in them. The view itself (`lib/editor/view/`, piece C) implements [EditorViewLike], makes the
/// [ViewUpdate]s and reads the facets declared here; the extension files (marks, items, tables, media...) are
/// written against this file alone.
///
/// Where `EditorView.something` is a static in CodeMirror it is `EditorViewLike.something` here:
/// `EditorView.decorations`, `.atomicRanges`, `.editable`, `.updateListener`, `.focusChangeEffect`,
/// `.scrollMargins`, `.scrollIntoView(...)`, `.editorAttributes`; `.contentAttributes` is the keyboard's
/// configuration ([EditorInputAttributes]) and `.domEventHandlers({...})` is [EditorViewLike.eventHandlers] with
/// Flutter's pointer and key events ([EditorEventHandlers]).
///
/// What is not declared, because it is DOM and has no counterpart to freeze yet: `EditorView.theme` and
/// `baseTheme` (style classes are resolved by the view's theme), `contentDOM`/`dom`/`scrollDOM`, `domAtPos`,
/// `posAtDOM`, `findFromDOM`, `lineBlockAt`.
library;

import 'package:flutter/gestures.dart' show PointerCancelEvent, PointerDeviceKind, PointerDownEvent, PointerMoveEvent, PointerUpEvent;
import 'package:flutter/services.dart' show KeyEvent, TextCapitalization, TextInputAction, TextInputType;
import 'package:flutter/widgets.dart' show BuildContext, EdgeInsets, InheritedWidget, Offset, Rect;

import '../state/change.dart';
import '../state/rangeset.dart';
import '../state/selection.dart';
import '../state/state.dart';
import 'decoration.dart';

/// A stretch of the document: what `view.viewport` and each of `view.visibleRanges` is.
class DocRange {
  const DocRange(this.from, this.to);

  final int from;
  final int to;

  @override
  bool operator ==(Object other) => other is DocRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'DocRange($from, $to)';
}

/// CodeMirror's measure request (`view.requestMeasure({read, write, key})`): `read` runs when layout is settled and
/// may only read it; `write` then runs with what it returned and may change things. Two requests with the same
/// `key` in one frame are one, the later.
class MeasureRequest<T> {
  const MeasureRequest({required this.read, this.write, this.key});

  final T Function(EditorViewLike view) read;
  final void Function(T measure, EditorViewLike view)? write;
  final Object? key;

  /// Runs `read` then `write`, for the view: typed here so the view can hold requests of any `T` together.
  void run(EditorViewLike view) {
    final measured = read(view);
    write?.call(measured, view);
  }
}

/// The part of CodeMirror's `EditorView` that extension files use. A view is also a [StateCommandTarget], so a
/// command runs on it: `undo(view)`.
abstract class EditorViewLike implements StateCommandTarget {
  /// The current state.
  @override
  EditorState get state;

  /// Applies transactions to the view, all in one update: the one thing a view has to implement to be dispatched
  /// to. CodeMirror's `dispatch(trs)`.
  void dispatchTransactions(List<Transaction> trs);

  /// CodeMirror's `view.dispatch(tr)` and `view.dispatch(spec, ...specs)`: a [Transaction], or a [TransactionSpec]
  /// (and `more` of them) to make one of against the current state.
  @override
  void dispatch(Dispatchable trOrSpec, [List<TransactionSpec> more = const <TransactionSpec>[]]) {
    switch (trOrSpec) {
      case Transaction():
        dispatchTransactions(<Transaction>[trOrSpec]);
      case TransactionSpec():
        dispatchTransactions(<Transaction>[
          state.updateAll(<TransactionSpec>[trOrSpec, ...more]),
        ]);
    }
  }

  /// The part of the document that is laid out: what is on screen and a margin round it.
  DocRange get viewport;

  /// The parts of the viewport that are drawn: the viewport without what is folded or hidden. A view plugin's
  /// decorations need only cover these.
  List<DocRange> get visibleRanges;

  /// Where a position is on screen, in global logical pixels, or null when it is not laid out. `side` picks which
  /// of two places a position at a line wrap means: below zero the end of the line before, above zero the start of
  /// the next.
  Rect? coordsAtPos(int pos, [int side = 1]);

  /// The document position at a global point. Null when the point is outside the text, unless `precise` is false:
  /// then the nearest position, which is null only when nothing is laid out.
  int? posAtCoords(Offset global, {bool precise = true});

  /// Asks for a measure pass: `request.read` when layout is settled, then `request.write`. Without a request, just
  /// asks the view to check its own measurements again.
  void requestMeasure<T>([MeasureRequest<T>? request]);

  /// Whether the editor has the keyboard's focus.
  bool get hasFocus;

  /// Whether the keyboard is composing text (an IME's underlined run). Extensions that hide or replace text must
  /// leave the composing line alone until this is false.
  bool get composing;

  /// Whether a composition has started and the update for it may still be on its way (CodeMirror's
  /// `compositionStarted`).
  bool get compositionStarted;

  /// The instance of a plugin in this view, or null when the view does not have it.
  V? plugin<V extends PluginValue>(ViewPlugin<V> plugin);

  /// Gives the editor the keyboard's focus.
  void focus();

  // -- The facets the view reads ----------------------------------------------------------------------------------

  /// CodeMirror's `EditorView.decorations`: the decorations to draw. An input is a [DecorationSet], or a function
  /// from the view to one (`DecorationSet Function(EditorViewLike view)`) for decorations that depend on the
  /// viewport; [resolveDecorations] reads either. Direct sets may change the height of lines; function ones are
  /// read after the viewport is known and must not.
  static final Facet<Object, List<Object>> decorations = Facet.define<Object, List<Object>>();

  /// The [DecorationSet] of one input of [decorations].
  static DecorationSet resolveDecorations(Object source, EditorViewLike view) {
    if (source is DecorationSet) return source;
    if (source is DecorationSet Function(EditorViewLike)) return source(view);
    throw ArgumentError.value(source, 'source', 'A decorations input is a DecorationSet or a function from the view to one');
  }

  /// CodeMirror's `EditorView.atomicRanges`: ranges the caret skips over as one and a delete takes whole.
  static final Facet<RangeSet<RangeValue> Function(EditorViewLike view), List<RangeSet<RangeValue> Function(EditorViewLike view)>> atomicRanges =
      Facet.define();

  /// CodeMirror's `EditorView.editable`: whether the text takes input. True unless something says otherwise; the
  /// highest precedence wins. (`EditorState.readOnlyFacet` is the other half: what commands may change.)
  static final Facet<bool, bool> editable = Facet.define<bool, bool>(combine: (values) => values.isNotEmpty ? values[0] : true);

  /// CodeMirror's `EditorView.updateListener`: called with every update of the view.
  static final Facet<void Function(ViewUpdate update), List<void Function(ViewUpdate update)>> updateListener = Facet.define();

  /// CodeMirror's `EditorView.focusChangeEffect`: asked when focus comes or goes; an effect it returns is
  /// dispatched.
  static final Facet<
    StateEffect<Object?>? Function(EditorState state, bool focusing),
    List<StateEffect<Object?>? Function(EditorState state, bool focusing)>
  >
  focusChangeEffect = Facet.define();

  /// CodeMirror's `EditorView.scrollMargins`: room to keep clear round the caret when it is scrolled into view
  /// (under a bar that covers the page's edge). The sides are added up.
  static final Facet<EdgeInsets? Function(EditorViewLike view), List<EdgeInsets? Function(EditorViewLike view)>> scrollMargins =
      Facet.define();

  /// CodeMirror's `EditorView.editorAttributes`: attributes of the editor as a whole (`data-look`, a class), read
  /// by the view's theme. Later inputs are written under earlier ones; classes are joined.
  static final Facet<Map<String, String>, Map<String, String>> editorAttributes = Facet.define<Map<String, String>, Map<String, String>>(
    combine: (values) {
      final result = <String, String>{};
      for (var i = values.length - 1; i >= 0; i--) {
        combineAttrs(values[i], result);
      }
      return result;
    },
    compare: attrsEq,
  );

  /// CodeMirror's `EditorView.contentAttributes`, for what the web app uses it for: how the keyboard behaves. The
  /// highest precedence that says something about a setting wins.
  static final Facet<EditorInputAttributes, EditorInputAttributes> contentAttributes = Facet.define<EditorInputAttributes, EditorInputAttributes>(
    combine: (values) {
      var result = const EditorInputAttributes();
      for (var i = values.length - 1; i >= 0; i--) {
        result = result.overriddenBy(values[i]);
      }
      return result;
    },
    compare: (a, b) => a == b,
  );

  /// CodeMirror's `EditorView.domEventHandlers({...})`: handlers for pointers, taps, keys and focus. A handler that
  /// returns true has handled the event and the editor (and handlers of lower precedence) leave it alone.
  static Extension eventHandlers(EditorEventHandlers handlers) =>
      ViewPlugin.define<PluginValue>((_) => _NoValue(), eventHandlers: handlers);

  /// CodeMirror's `EditorView.domEventObservers({...})`: as [eventHandlers], but every observer is called before
  /// any handler and what it returns is ignored.
  static Extension eventObservers(EditorEventHandlers observers) =>
      ViewPlugin.define<PluginValue>((_) => _NoValue(), eventObservers: observers);

  /// The type of the effects [scrollIntoView] makes; the view looks for these.
  static final StateEffectType<ScrollTarget> scrollIntoViewEffect = StateEffect.define<ScrollTarget>(
    map: (target, changes) => target.map(changes),
  );

  /// CodeMirror's `EditorView.scrollIntoView(pos, options)`: an effect that scrolls a position or a range into
  /// view. `y` is where it should end up; `yMargin` how much room to leave beyond it.
  static StateEffect<ScrollTarget> scrollIntoView(
    int pos, {
    SelectionRange? range,
    ScrollStrategy y = ScrollStrategy.nearest,
    ScrollStrategy x = ScrollStrategy.nearest,
    double yMargin = 5,
    double xMargin = 5,
  }) => scrollIntoViewEffect.of(ScrollTarget(range ?? EditorSelection.cursor(pos), y, x, yMargin, xMargin));
}

class _NoValue extends PluginValue {}

/// Where [EditorViewLike.scrollIntoView] puts its target: CodeMirror's `"nearest" | "start" | "end" | "center"`.
enum ScrollStrategy { nearest, start, end, center }

/// CodeMirror's `ScrollTarget`: what a scroll-into-view effect carries.
class ScrollTarget {
  const ScrollTarget(this.range, this.y, this.x, this.yMargin, this.xMargin);

  final SelectionRange range;
  final ScrollStrategy y;
  final ScrollStrategy x;
  final double yMargin;
  final double xMargin;

  /// The target after `changes`.
  ScrollTarget map(ChangeDesc changes) => changes.empty ? this : ScrollTarget(range.map(changes), y, x, yMargin, xMargin);

  /// The target kept inside `state`'s document.
  ScrollTarget clip(EditorState state) =>
      range.to <= state.doc.length ? this : ScrollTarget(EditorSelection.cursor(state.doc.length), y, x, yMargin, xMargin);
}

/// How the keyboard behaves in the editor: what the web app sets through `contentAttributes` (`autocorrect`,
/// `autocapitalize`, `spellcheck`, `inputmode`, `enterkeyhint`), in Flutter's terms. A null setting says nothing.
class EditorInputAttributes {
  const EditorInputAttributes({this.autocorrect, this.autocapitalize, this.spellcheck, this.suggestions, this.inputType, this.enterKeyHint});

  /// The web page's prose settings (`PROSE_ATTRS` in Editor.tsx): corrections on, sentences capitalised.
  static const EditorInputAttributes prose = EditorInputAttributes(
    autocorrect: true,
    autocapitalize: TextCapitalization.sentences,
    spellcheck: true,
    suggestions: true,
    inputType: TextInputType.multiline,
    enterKeyHint: TextInputAction.newline,
  );

  /// The web page's plain settings (`PLAIN_ATTRS`): the keyboard leaves the words alone.
  static const EditorInputAttributes plain = EditorInputAttributes(
    autocorrect: false,
    autocapitalize: TextCapitalization.none,
    spellcheck: false,
    suggestions: false,
    inputType: TextInputType.multiline,
    enterKeyHint: TextInputAction.newline,
  );

  final bool? autocorrect;
  final TextCapitalization? autocapitalize;
  final bool? spellcheck;
  final bool? suggestions;
  final TextInputType? inputType;
  final TextInputAction? enterKeyHint;

  /// These settings with every one `other` speaks about replaced by its.
  EditorInputAttributes overriddenBy(EditorInputAttributes other) => EditorInputAttributes(
    autocorrect: other.autocorrect ?? autocorrect,
    autocapitalize: other.autocapitalize ?? autocapitalize,
    spellcheck: other.spellcheck ?? spellcheck,
    suggestions: other.suggestions ?? suggestions,
    inputType: other.inputType ?? inputType,
    enterKeyHint: other.enterKeyHint ?? enterKeyHint,
  );

  @override
  bool operator ==(Object other) =>
      other is EditorInputAttributes &&
      other.autocorrect == autocorrect &&
      other.autocapitalize == autocapitalize &&
      other.spellcheck == spellcheck &&
      other.suggestions == suggestions &&
      other.inputType == inputType &&
      other.enterKeyHint == enterKeyHint;

  @override
  int get hashCode => Object.hash(autocorrect, autocapitalize, spellcheck, suggestions, inputType, enterKeyHint);
}

/// A tap, a double tap or a long press on the editor, as a handler gets it: where, with what, and on which document
/// position (null when it was not on the text).
class EditorTap {
  const EditorTap({required this.global, required this.local, required this.kind, this.pos});

  /// Where, in global logical pixels.
  final Offset global;

  /// Where, in the editor's own box.
  final Offset local;

  /// A finger, a mouse, a stylus.
  final PointerDeviceKind kind;

  /// The document position under it.
  final int? pos;
}

/// The handlers of [EditorViewLike.eventHandlers]: CodeMirror's `DOMEventHandlers`, with Flutter's events in place
/// of the DOM's. Each returns true when it handled the event. The DOM names they stand for are noted on each.
class EditorEventHandlers {
  const EditorEventHandlers({
    this.pointerDown,
    this.pointerMove,
    this.pointerUp,
    this.pointerCancel,
    this.tap,
    this.doubleTap,
    this.longPress,
    this.secondaryTap,
    this.keyDown,
    this.focus,
    this.blur,
    this.paste,
  });

  /// `pointerdown` / `mousedown` / `touchstart`. Returning true keeps the editor from moving the caret for this
  /// pointer.
  final bool Function(PointerDownEvent event, EditorViewLike view)? pointerDown;

  /// `pointermove`.
  final bool Function(PointerMoveEvent event, EditorViewLike view)? pointerMove;

  /// `pointerup` / `mouseup` / `touchend`.
  final bool Function(PointerUpEvent event, EditorViewLike view)? pointerUp;

  /// `pointercancel`.
  final bool Function(PointerCancelEvent event, EditorViewLike view)? pointerCancel;

  /// `click`.
  final bool Function(EditorTap tap, EditorViewLike view)? tap;

  /// `dblclick`.
  final bool Function(EditorTap tap, EditorViewLike view)? doubleTap;

  /// A press held: `contextmenu` on a touch screen.
  final bool Function(EditorTap tap, EditorViewLike view)? longPress;

  /// The other mouse button: `contextmenu` with a mouse.
  final bool Function(EditorTap tap, EditorViewLike view)? secondaryTap;

  /// `keydown`, from a hardware keyboard.
  final bool Function(KeyEvent event, EditorViewLike view)? keyDown;

  /// `focus`.
  final bool Function(EditorViewLike view)? focus;

  /// `blur`.
  final bool Function(EditorViewLike view)? blur;

  /// `paste`, with the clipboard's plain text.
  final bool Function(String text, EditorViewLike view)? paste;
}

/// CodeMirror's `PluginValue`: what a view plugin's instance may implement.
abstract class PluginValue {
  /// Called with every update of the view, after the state has changed and before the view draws.
  void update(ViewUpdate update) {}

  /// Called after the view has drawn an update.
  void docViewUpdate(EditorViewLike view) {}

  /// Called when the plugin leaves the view.
  void destroy() {}
}

int _nextPluginId = 0;

/// CodeMirror's `ViewPlugin`: something that lives as long as a view does, sees its updates, and may give it
/// decorations and handlers. `ViewPlugin.fromClass(class {...}, {decorations: (v) => v.decorations})` is
/// `ViewPlugin.fromClass(MyPlugin.new, decorations: (v) => v.decorations)`.
class ViewPlugin<V extends PluginValue> extends ExtensionProvider {
  ViewPlugin._(this.id, this.create, this.eventHandlers, this.eventObservers, List<Extension> Function(ViewPlugin<V> plugin) buildExtensions) {
    extension = Extension.list(<Extension>[...buildExtensions(this), viewPlugin.of(this)]);
  }

  final int id;

  /// Makes the plugin's instance for a view.
  final V Function(EditorViewLike view) create;

  /// The plugin's own event handlers, if it has any.
  final EditorEventHandlers? eventHandlers;

  /// The plugin's own event observers, if it has any.
  final EditorEventHandlers? eventObservers;

  @override
  late final Extension extension;

  /// Defines a plugin from a function that makes its instance. `decorations` reads the instance's decorations for
  /// the view to draw; `provide` gives other extensions that come with the plugin.
  static ViewPlugin<V> define<V extends PluginValue>(
    V Function(EditorViewLike view) create, {
    DecorationSet Function(V value)? decorations,
    EditorEventHandlers? eventHandlers,
    EditorEventHandlers? eventObservers,
    Extension Function(ViewPlugin<V> plugin)? provide,
  }) {
    return ViewPlugin<V>._(_nextPluginId++, create, eventHandlers, eventObservers, (plugin) {
      final ext = <Extension>[];
      if (decorations != null) {
        DecorationSet read(EditorViewLike view) {
          final pluginInst = view.plugin(plugin);
          return pluginInst != null ? decorations(pluginInst) : Decoration.none;
        }

        ext.add(EditorViewLike.decorations.of(read));
      }
      if (provide != null) ext.add(provide(plugin));
      return ext;
    });
  }

  /// CodeMirror's `ViewPlugin.fromClass`: the same as [define], given a constructor.
  static ViewPlugin<V> fromClass<V extends PluginValue>(
    V Function(EditorViewLike view) constructor, {
    DecorationSet Function(V value)? decorations,
    EditorEventHandlers? eventHandlers,
    EditorEventHandlers? eventObservers,
    Extension Function(ViewPlugin<V> plugin)? provide,
  }) => define<V>(constructor, decorations: decorations, eventHandlers: eventHandlers, eventObservers: eventObservers, provide: provide);
}

/// CodeMirror's `viewPlugin` facet, internal there: the plugins a state asks its view to run, each once, in order of
/// precedence. The view reads it.
final Facet<ViewPlugin<PluginValue>, List<ViewPlugin<PluginValue>>> viewPlugin = Facet.define<ViewPlugin<PluginValue>, List<ViewPlugin<PluginValue>>>(
  combine: (plugins) {
    final result = <ViewPlugin<PluginValue>>[];
    for (final p in plugins) {
      if (!result.any((seen) => identical(seen, p))) result.add(p);
    }
    return result;
  },
  compare: (a, b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  },
);

/// A changed stretch of the document: where it was (`fromA`-`toA`) and where it is (`fromB`-`toB`).
class ChangedRange {
  const ChangedRange(this.fromA, this.toA, this.fromB, this.toB);

  final int fromA;
  final int toA;
  final int fromB;
  final int toB;
}

/// CodeMirror's `UpdateFlag`: what changed in a view beside its state. The view sets them on [ViewUpdate.flags].
abstract final class UpdateFlag {
  static const int focus = 1;
  static const int height = 2;
  static const int viewport = 4;
  static const int viewportMoved = 8;
  static const int geometry = 16;
}

/// CodeMirror's `ViewUpdate`: what a view tells its plugins and listeners when something changed.
class ViewUpdate {
  /// Made by the view, before it takes the new state: [startState] is read from `view.state` here, as in
  /// CodeMirror.
  ViewUpdate.create(this.view, this.state, this.transactions) : startState = view.state {
    var changes = ChangeSet.emptyOf(startState.doc.length);
    for (final tr in transactions) {
      changes = changes.compose(tr.changes);
    }
    this.changes = changes;
    final ranges = <ChangedRange>[];
    changes.iterChangedRanges((fromA, toA, fromB, toB) => ranges.add(ChangedRange(fromA, toA, fromB, toB)));
    changedRanges = ranges;
  }

  /// The view.
  final EditorViewLike view;

  /// The new state.
  final EditorState state;

  /// The transactions in this update; often one, none for a change of focus or geometry alone.
  final List<Transaction> transactions;

  /// The state before.
  final EditorState startState;

  /// Every transaction's changes as one set.
  late final ChangeSet changes;

  /// The changed stretches of [changes].
  late final List<ChangedRange> changedRanges;

  /// [UpdateFlag]s, set by the view.
  int flags = 0;

  /// Whether the viewport or the visible ranges changed.
  bool get viewportChanged => flags & UpdateFlag.viewport > 0;

  /// Whether the viewport moved for another reason than the document changing under it: a scroll.
  bool get viewportMoved => flags & UpdateFlag.viewportMoved > 0;

  /// Whether the height of a block of the document changed.
  bool get heightChanged => flags & UpdateFlag.height > 0;

  /// Whether the document changed or the editor's size or its lines' did.
  bool get geometryChanged => docChanged || flags & (UpdateFlag.geometry | UpdateFlag.height) > 0;

  /// Whether focus came or went.
  bool get focusChanged => flags & UpdateFlag.focus > 0;

  /// Whether the document changed.
  bool get docChanged => !changes.empty;

  /// Whether a transaction set the selection.
  bool get selectionSet => transactions.any((tr) => tr.selection != null);

  /// Whether the keyboard is composing: `update.view.composing`, here for the plugins that ask on every update.
  bool get composing => view.composing;

  /// Whether nothing changed at all.
  bool get empty => flags == 0 && transactions.isEmpty;
}

/// Hands the view to the widgets built inside it: an [EditorWidget]'s `build` finds the view it is in with
/// `EditorViewScope.of(context)`, where CodeMirror passes it to `toDOM(view)`. The view puts one above its lines.
class EditorViewScope extends InheritedWidget {
  const EditorViewScope({super.key, required this.view, required super.child});

  final EditorViewLike view;

  /// The view above `context`. Throws when there is none.
  static EditorViewLike of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<EditorViewScope>();
    if (scope == null) throw StateError('No editor view above this widget');
    return scope.view;
  }

  /// The view above `context`, or null.
  static EditorViewLike? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<EditorViewScope>()?.view;

  @override
  bool updateShouldNotify(EditorViewScope oldWidget) => !identical(oldWidget.view, view);
}
