/// A file in the words, drawn (lib/core/attachment_refs.dart): a card under a line that is only a link to a file
/// the app keeps, and the line folded to its words, the file's own name, away from the caret.
///
///     [Lease 2026.pdf](file/<uuid>.pdf "2.4 MB")
///
/// The line keeps its Markdown, as a film's and a place's do (videos.dart, place_cards.dart), and the card is a
/// block widget under it: the file's mark by its kind (a PDF's first page, drawn), its name, and what it is and how
/// big ("PDF · 2.4 MB · 12 pages"). A tap opens it: a PDF in the app's own viewer (lib/files/pdf_view.dart) where
/// this device draws one, anything else handed to another app (Android's "Open with"); the mark at its end hands
/// any file over that way. A file not on this device says so, and where its line says it is larger than travels,
/// that it stays on the device it was added on.
///
/// Drawn only where the app keeps files ([FilesKit.current]): an iPhone, for now, shows the line as the link it is.
/// A file's line in fenced code is the code's words, with no card and no fold.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/attachment_refs.dart';
import '../../core/backup.dart' show sizeSaid;
import '../../files/files_kit.dart';
import '../../files/pdf_view.dart';
import '../../files/read_text.dart' show ReadThing;
import '../editor.dart';
import '../view/blocks.dart' show ClassedBlockWidget;
import '../view/drawn_block.dart';
import '../view/lines.dart';
import 'images.dart' show gutterOf;
import 'inline_box.dart';

/// The files a line is, kept with the document's tree (lib/editor/view/line_facts.dart).
final LineFact<AttachmentLine> attachmentFacts = LineFact<AttachmentLine>(attachmentOfLine);

/// The mark a kind of file wears on its card.
LucideIcon attachmentIcon(AttachmentKind kind) => switch (kind) {
      AttachmentKind.pdf || AttachmentKind.document => Lucide.fileText,
      AttachmentKind.sheet => Lucide.table,
      AttachmentKind.slides => Lucide.layoutGrid,
      AttachmentKind.archive => Lucide.archive,
      AttachmentKind.sound => Lucide.audioLines,
      AttachmentKind.video => Lucide.film,
      AttachmentKind.picture => Lucide.image,
      AttachmentKind.code => Lucide.fileCode,
      AttachmentKind.file => Lucide.file,
    };

/// The name a file is handed to another app by: its words, with the extension it was kept with where they lack it.
String handedName(AttachmentLine line) {
  final words = attachmentWords(line.label);
  final dot = line.name.lastIndexOf('.');
  final ext = dot < 0 ? '' : line.name.substring(dot);
  return ext.isEmpty || words.toLowerCase().endsWith(ext.toLowerCase()) ? words : '$words$ext';
}

/// What a card says under a file's name: its kind, its size and its pages where they are known, or why it is not
/// here.
String attachmentMeta(AttachmentLine line, {required bool here, int? bytes, int? pages}) {
  final kind = attachmentKindWord(line.kind);
  if (!here) {
    final said = bytesOfSize(line.size);
    if (said != null && said > attachmentSyncLimit) return '$kind · ${line.size} · It stays on the device it was added on.';
    return '$kind${line.size != null ? ' · ${line.size}' : ''} · Not on this device yet.';
  }
  final size = bytes != null ? sizeSaid(bytes) : line.size;
  return <String>[
    kind,
    ?size,
    if (pages != null) pages == 1 ? '1 page' : '$pages pages',
  ].join(' · ');
}

/// A PDF's first page, drawn small for its card: kept for the run, the last few.
class _Thumbs {
  final LinkedHashMap<String, Future<({ui.Image? image, int pages})>> _kept = LinkedHashMap<String, Future<({ui.Image? image, int pages})>>();

  Future<({ui.Image? image, int pages})> of(FilesKit kit, String name, int width) {
    final key = '$name@$width@${kit.store.landedTimes(name)}';
    final had = _kept.remove(key);
    if (had != null) return _kept[key] = had;
    final made = () async {
      final file = await kit.store.fileOf(name);
      if (file == null) return (image: null, pages: 0);
      final pdf = await kit.device.openPdf(file.path);
      try {
        return (image: await pdf.draw(0, width), pages: pdf.count);
      } finally {
        pdf.close();
      }
    }();
    _kept[key] = made;
    while (_kept.length > 12) {
      _kept.remove(_kept.keys.first);
    }
    return made;
  }
}

final _Thumbs _thumbs = _Thumbs();

/// The card under a file's line.
class AttachmentWidget extends EditorWidget implements ClassedBlockWidget, DrawnBlock {
  const AttachmentWidget(this.file);

  final AttachmentLine file;

  @override
  String get className => 'cm-fileCard';

  @override
  bool eq(AttachmentWidget other) => other.file == file;

  @override
  double get estimatedHeight => 16 * 4.5 + 20;

  @override
  Widget build(BuildContext context) => AttachmentCard(file: file);
}

/// A file's card: its mark, its name and what it is; a tap opens it.
class AttachmentCard extends StatefulWidget {
  const AttachmentCard({super.key, required this.file, this.kit});

  final AttachmentLine file;

  /// The files of this device; the app's own unless given.
  final FilesKit? kit;

  @override
  State<AttachmentCard> createState() => _AttachmentCardState();
}

class _AttachmentCardState extends State<AttachmentCard> {
  FilesKit? get _kit => widget.kit ?? FilesKit.current;

  bool? _here;
  int? _bytes;
  int? _pages;
  ui.Image? _thumb;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _kit?.store.addListener(_landed);
    _ask();
  }

  @override
  void didUpdateWidget(AttachmentCard old) {
    super.didUpdateWidget(old);
    if (old.file.name != widget.file.name || !identical(old.kit, widget.kit)) {
      old.kit?.store.removeListener(_landed);
      _kit?.store.addListener(_landed);
      _ask();
    }
  }

  @override
  void dispose() {
    _kit?.store.removeListener(_landed);
    super.dispose();
  }

  void _landed() => _ask();

  void _ask() {
    final kit = _kit;
    if (kit == null) return;
    final asking = ++_asked;
    final name = widget.file.name;
    unawaited(kit.store.sizeOf(name).then((bytes) async {
      if (!mounted || asking != _asked) return;
      setState(() {
        _here = bytes != null;
        _bytes = bytes;
      });
      if (bytes == null || widget.file.kind != AttachmentKind.pdf || !kit.device.drawsPdf) return;
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
      try {
        final drawn = await _thumbs.of(kit, name, (_thumbWidth * ratio).round());
        if (!mounted || asking != _asked) return;
        setState(() {
          _thumb = drawn.image;
          _pages = drawn.pages;
        });
      } catch (_) {
        // A PDF that will not open is still a file: its card is its mark, and a tap hands it to another app.
      }
    }));
  }

  static const double _thumbWidth = 44;

  void _say(String message) {
    try {
      GlacierToast.of(context).toast(message: Text(message));
    } catch (_) {
      debugPrint('[files] $message');
    }
  }

  Future<void> _open({bool elsewhere = false}) async {
    final kit = _kit;
    if (kit == null) return;
    final file = await kit.store.fileOf(widget.file.name);
    if (!mounted) return;
    if (file == null) return _say(attachmentMeta(widget.file, here: false).split(' · ').last);
    final name = handedName(widget.file);
    if (!elsewhere && widget.file.kind == AttachmentKind.pdf && kit.device.drawsPdf) {
      return showPdf(context, kit: kit, path: file.path, name: name, thing: ReadThing.file(widget.file.name));
    }
    try {
      await kit.device.openWith(file.path, name: name);
    } catch (failure) {
      if (mounted) _say(failure is StateError ? failure.message : 'No app on this device opens that file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final file = widget.file;
    final here = _here ?? true;
    final ink = t.color('app-ink'), ink2 = t.color('app-ink-2'), ink3 = t.color('app-ink-3');
    final sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final space1 = t.space(1), space2 = t.space(2), space3 = t.space(3);
    final words = attachmentWords(file.label);
    final meta = attachmentMeta(file, here: here, bytes: _bytes, pages: _pages);
    final radius = t.radius('md');
    final mark = _thumb != null
        ? DecoratedBox(
            key: const ValueKey<String>('file-thumb'),
            decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(t.radius('sm'))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(t.radius('sm')),
              child: SizedBox(width: _thumbWidth, height: _thumbWidth * _thumb!.height / _thumb!.width, child: RawImage(image: _thumb, fit: BoxFit.cover)),
            ),
          )
        : DecoratedBox(
            key: const ValueKey<String>('file-mark'),
            decoration: BoxDecoration(color: t.color('app-paper'), borderRadius: BorderRadius.circular(t.radius('sm'))),
            child: SizedBox.square(dimension: _thumbWidth, child: Center(child: AppIcon(attachmentIcon(file.kind), size: 22, color: here ? ink2 : ink3))),
          );
    final card = Semantics(
      button: here,
      label: 'Open $words, $meta',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey<String>('file-open'),
        behavior: HitTestBehavior.opaque,
        onTap: here ? () => unawaited(_open()) : null,
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(radius)),
          child: Padding(
            padding: EdgeInsets.all(space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                mark,
                SizedBox(width: space3),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      InlineWords(words, key: const ValueKey<String>('file-name'), style: t.textAt(sm, color: here ? ink : ink2), lineHeight: sm * 1.4, ellipsis: true),
                      SizedBox(height: space1 / 2),
                      InlineWords(meta, key: const ValueKey<String>('file-meta'), style: t.textAt(xs, color: ink3), lineHeight: xs * 1.5, maxLines: 2, ellipsis: true),
                    ],
                  ),
                ),
                if (here)
                  Semantics(
                    button: true,
                    label: 'Open $words with another app',
                    child: GestureDetector(
                      key: const ValueKey<String>('file-elsewhere'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(_open(elsewhere: true)),
                      child: SizedBox.square(dimension: t.lenOf('2.75rem'), child: Center(child: AppIcon(Lucide.externalLink, size: 18, color: ink2))),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // '.card': the video card's margins and gutter (videos.dart), no wider than a card reads well.
    return Padding(
      padding: EdgeInsets.only(top: space2, bottom: space3),
      child: Padding(
        key: const ValueKey<String>('cm-fileCard'),
        padding: EdgeInsets.only(left: t.lenOf('var(--app-safe-left, 0px)') + gutterOf(context), right: t.lenOf('var(--app-safe-right, 0px)') + gutterOf(context)),
        child: Align(alignment: AlignmentDirectional.topStart, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: t.lenOf('30rem')), child: card)),
      ),
    );
  }
}

DecorationSet _cardsOf(EditorState state) {
  final builder = RangeSetBuilder<Decoration>();
  final files = attachmentFacts.of(state.doc);
  if (files.isEmpty) return builder.finish();
  final fences = DocFences.of(state.doc);
  for (final line in files) {
    if (!fences.covers(line.number)) builder.add(line.to, line.to, Decoration.widget(widget: AttachmentWidget(line.fact), block: true, side: 1));
  }
  return builder.finish();
}

final StateField<DecorationSet> _cardField = StateField.define<DecorationSet>(
  create: _cardsOf,
  update: (value, tr) => tr.docChanged ? _cardsOf(tr.state) : value,
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// The `[` and the `](file/… "…")` of a file's line, as ranges of the document: its words are what reads.
List<({int from, int to})> _foldsOf(int from, String text) {
  final found = attachmentRef.firstMatch(text);
  if (found == null) return const <({int from, int to})>[];
  final open = from + found.start;
  final close = open + 1 + (found.group(1)?.length ?? 0);
  return <({int from, int to})>[(from: open, to: open + 1), (from: close, to: open + found.group(0)!.length)];
}

final Decoration _hidden = Decoration.replace();

DecorationSet _foldAll(EditorViewLike view) {
  final builder = RangeSetBuilder<Decoration>();
  final state = view.state;
  final editable = state.facet(EditorViewLike.editable);
  final active = editable && view.hasFocus ? selectedLines(state) : const <int>{};
  final doc = state.doc;
  if (attachmentFacts.nowhere(doc)) return builder.finish();
  final fences = DocFences.of(doc);
  for (final range in view.visibleRanges) {
    for (final line in attachmentFacts.between(doc, doc.lineAt(range.from).number, doc.lineAt(range.to).number)) {
      if (active.contains(line.number) || fences.covers(line.number)) continue;
      for (final fold in _foldsOf(line.from, line.text)) {
        builder.add(fold.from, fold.to, _hidden);
      }
    }
  }
  return builder.finish();
}

class _Folds extends PluginValue {
  _Folds(EditorViewLike view) : decorations = _foldAll(view);

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.view.composing) {
      if (update.docChanged) decorations = decorations.map(update.changes);
      return;
    }
    if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged) decorations = _foldAll(update.view);
  }
}

final ViewPlugin<_Folds> _folds = ViewPlugin.define<_Folds>(_Folds.new, decorations: (plugin) => plugin.decorations);

/// Files in the words: a card under each line and the lines folded to their words, where the app keeps files.
Extension attachmentCards() => FilesKit.current == null ? Extension.list(const <Extension>[]) : Extension.list(<Extension>[_cardField, _folds]);
