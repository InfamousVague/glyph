/// The words read in a picture (lib/files/read_text.dart), offered under it while the caret is on its line: a
/// quiet row, "Copy the words in it", that puts them on the clipboard. Tap a picture and the caret lands on its
/// line, so the row is there for the picture just tapped and nowhere else. A picture with no words read in it, or
/// none read yet, has no row. Where the app reads no words (an iPhone), nothing is added.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../files/read_text.dart';
import '../editor.dart';
import '../view/drawn_block.dart';
import '../view/line_facts.dart';
import '../view/lines.dart';
import 'images.dart' show gutterOf;
import 'inline_box.dart';

/// The row under a picture whose words were read.
class PictureWordsWidget extends EditorWidget implements DrawnBlock {
  const PictureWordsWidget(this.name);

  final String name;

  @override
  bool eq(PictureWordsWidget other) => other.name == name;

  @override
  double get estimatedHeight => 0;

  @override
  Widget build(BuildContext context) => PictureWordsRow(name: name);
}

/// "Copy the words in it", for the picture named, while it has words read.
class PictureWordsRow extends StatefulWidget {
  const PictureWordsRow({super.key, required this.name, this.texts});

  final String name;

  /// The words read here; the app's own unless given.
  final ReadTexts? texts;

  @override
  State<PictureWordsRow> createState() => _PictureWordsRowState();
}

class _PictureWordsRowState extends State<PictureWordsRow> {
  ReadTexts? get _texts => widget.texts ?? readTexts;

  @override
  void initState() {
    super.initState();
    _texts?.addListener(_changed);
  }

  @override
  void dispose() {
    _texts?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _copy(String words) async {
    await Clipboard.setData(ClipboardData(text: words));
    if (!mounted) return;
    try {
      GlacierToast.of(context).toast(message: const Text('Copied the words in the picture.'));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final words = _texts?.wordsOf(ReadThing.picture(widget.name))?.trim() ?? '';
    if (words.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final ink2 = t.color('app-ink-2');
    return Padding(
      padding: EdgeInsets.only(left: gutterOf(context), right: gutterOf(context), bottom: t.space(2)),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: Semantics(
          button: true,
          label: 'Copy the words in the picture',
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey<String>('picture-words'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_copy(words)),
            child: DecoratedBox(
              decoration: ShapeDecoration(color: t.color('app-paper-2'), shape: const StadiumBorder()),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AppIcon(Lucide.scanText, size: 16, color: ink2),
                    SizedBox(width: t.space(2)),
                    InlineWords('Copy the words in it', style: t.textAt(sm, color: ink2), lineHeight: sm * 1.6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

DecorationSet _rowsOf(EditorState state) {
  final builder = RangeSetBuilder<Decoration>();
  if (!focused(state) || pictureFacts.nowhere(state.doc)) return builder.finish();
  final lines = selectedLines(state);
  for (final number in lines.toList()..sort()) {
    final picture = pictureFacts.at(state.doc, number);
    if (picture == null) continue;
    final line = state.doc.line(number);
    builder.add(line.to, line.to, Decoration.widget(widget: PictureWordsWidget(picture.name), block: true, side: 2));
  }
  return builder.finish();
}

final StateField<DecorationSet> _rowField = StateField.define<DecorationSet>(
  create: _rowsOf,
  update: (value, tr) => tr.docChanged || tr.selection != null || focusMoved(tr) ? _rowsOf(tr.state) : value,
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// The row under a picture on the caret's line, where the app reads words.
Extension pictureWords() => readTexts == null ? Extension.list(const <Extension>[]) : Extension.list(<Extension>[trackFocus, _rowField]);
