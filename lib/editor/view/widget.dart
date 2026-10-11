/// A widget drawn in the text: CodeMirror's `WidgetType` (@codemirror/view, decoration.ts) as an interface the
/// extension files code against. The view (`lib/editor/view/`, piece C) is what calls it.
///
/// It is called [EditorWidget] because it is not a Flutter `Widget`: like `WidgetType` it is a small description
/// that is cheap to make again on every redraw, compared with [eq], and only [build]s when it is new.
///
/// What maps to what:
/// - `toDOM(view)` is [build]; the view, when a widget needs it, is `EditorViewScope.of(context)` (`plugin.dart`);
/// - `ignoreEvent(event)` is [takesPointer], the same question the same way up: true (the default) means the widget
///   keeps the event and the editor does not move the caret or start a selection for it;
/// - `updateDOM` has no counterpart: Flutter rebuilds [build]'s widget in place when [eq] says the description
///   changed, and state that must outlive that lives in the built widget's `State`;
/// - `destroy(dom)` is [destroy], called when the widget leaves the view.
library;

import 'package:flutter/gestures.dart' show PointerEvent;
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/widgets.dart' show BuildContext, Rect, Widget;

/// CodeMirror's `WidgetType`: the description of something drawn in the text by a widget or replace decoration.
abstract class EditorWidget {
  const EditorWidget();

  /// The Flutter widget to draw: CodeMirror's `toDOM`.
  Widget build(BuildContext context);

  /// Whether `other`, a widget of the same class, would draw the same thing. False unless overridden, as in
  /// CodeMirror, so a widget without an `eq` is rebuilt on every change of its decoration.
  bool eq(covariant EditorWidget other) => false;

  /// CodeMirror's `compare`: the same object, or the same class and [eq].
  bool compare(EditorWidget other) => identical(this, other) || runtimeType == other.runtimeType && eq(other);

  /// How tall the widget will be, in logical pixels, before it has been laid out; -1 for "do not know". The view
  /// uses it to place lines it has not built yet.
  double get estimatedHeight => -1;

  /// For an inline widget that draws line breaks: how many. Block widgets leave this 0.
  int get lineBreaks => 0;

  /// CodeMirror's `ignoreEvent`: whether a pointer on the widget is the widget's own. True by default; a widget
  /// that returns false lets the editor treat a press on it as a press on the text.
  bool takesPointer(PointerEvent event) => true;

  /// Where a document position inside the widget is on screen, for a widget that covers text and wants a caret
  /// beside it drawn in the right place. `box` is the built widget's render box; null means "use the widget's edge".
  Rect? coordsAt(RenderBox box, int pos, int side) => null;

  /// True for a widget that draws nothing and should not get a caret stop of its own.
  bool get isHidden => false;

  /// True for a widget that holds editable content of its own (a table cell's field).
  bool get editable => false;

  /// Called when the widget leaves the view.
  void destroy() {}
}
