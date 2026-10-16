import 'package:flutter/gestures.dart' show PointerDownEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/tags.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

/// A tap on a tag's chip opens its page (lib/editor/items/tags.dart `tagOpener`), as a press on a note link opens it
/// (test/editor/items/wiki_links_test.dart is the pattern): a view told where the press lands.
class _Told extends EditorView {
  _Told(EditorState state, this.lands) : super(state: state, wholeDocument: true);

  final int? lands;

  @override
  int? posAtCoords(Offset global, {bool precise = true}) => lands;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  bool press(EditorView view) => view.eventHandlers.any((h) => h.mouseDown?.call(const PointerDownEvent(position: Offset(10, 10)), view) ?? false);

  List<String> tapAt(String doc, int at, {bool opener = true}) {
    final opened = <String>[];
    final view = _Told(EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[tags(), if (opener) tagOpener.of(opened.add)])), at);
    final taken = press(view);
    view.destroy();
    if (opened.isNotEmpty) expect(taken, isTrue);
    return opened;
  }

  test('opens the tag a chip is drawn for, by its name, the press kept from the editor', () {
    const doc = '- [ ] Ship it #Work/Clients today';
    expect(tapAt(doc, doc.indexOf('#Work') + 3), ['work/clients']);
    expect(tapAt(doc, doc.indexOf('#Work')), ['work/clients']);
  });

  test('is the editor’s everywhere else: beside a tag, in code, and with nobody to open it', () {
    const doc = 'Ship it #web now and `#code`';
    expect(tapAt(doc, doc.indexOf('now') + 1), isEmpty);
    expect(tapAt(doc, doc.indexOf('#code') + 2), isEmpty);
    expect(tapAt(doc, doc.indexOf('#web') + 1, opener: false), isEmpty);
  });
}
