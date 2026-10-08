// What the tests of the editor's side of the plugins share: a stand-in for a plugin's reading of its marks, and the
// note drawn as test/editor/media draws one.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/mark_details.dart';

export '../../editor/media/support.dart';

/// A provider that answers from what a test put in it, and keeps what it was asked.
class StandIn extends MarkDetailsProvider {
  StandIn({this.readsUrl, this.actionsFor});

  final Map<String, MarkEntry> known = <String, MarkEntry>{};

  /// Every read asked for: the address, and whether it was to be fresh.
  final List<(String, bool)> wanted = <(String, bool)>[];
  final List<String> opened = <String>[];
  final bool Function(String url)? readsUrl;
  List<MarkAction> Function(String url, String words)? actionsFor;

  @override
  MarkEntry? peek(String url) => known[url];

  @override
  void want(String url, {bool fresh = false}) => wanted.add((url, fresh));

  @override
  Future<void> open(String url) async => opened.add(url);

  @override
  bool reads(String url) => readsUrl?.call(url) ?? false;

  @override
  List<MarkAction> actions(String url, String words) => actionsFor?.call(url, words) ?? const <MarkAction>[];
}

/// Waits, a turn of the event loop at a time, until `met` is true: for work whose number of hops is its own business.
Future<void> until(bool Function() met, {String? reason}) async {
  for (var turn = 0; turn < 500 && !met(); turn += 1) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(met(), isTrue, reason: reason ?? 'never came true');
}

/// A pointer event handed to the view's plugins as the editor's input layer hands it (lib/editor/input/gestures.dart):
/// every handler in turn, until one says it took it. Answers whether one did.
bool sendPointer(EditorView view, PointerEvent event) {
  for (final handlers in view.eventHandlers) {
    final took = switch (event) {
      PointerDownEvent() => handlers.pointerDown?.call(event, view),
      PointerMoveEvent() => handlers.pointerMove?.call(event, view),
      PointerUpEvent() => handlers.pointerUp?.call(event, view),
      PointerCancelEvent() => handlers.pointerCancel?.call(event, view),
      _ => null,
    };
    if (took ?? false) return true;
  }
  return false;
}
