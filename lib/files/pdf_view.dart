/// A PDF opened in the app: a layer over everything, the PDF's pages one at a time, drawn by the device as they are
/// wanted (lib/files/phone_documents.dart [PdfPages]; Android's own PdfRenderer).
///
/// - **Pages.** Swiped across, each fitted to the window, drawn at the window's pixels and drawn again sharper
///   once a pinch has settled on it. Pinch to zoom, up to five times, and drag about while zoomed; a double tap goes
///   back to the whole page. Only the page in view and its two neighbours are kept drawn.
/// - **Page n of N** at the top: tap it to go to a page by its number.
/// - **Find**: words on the pages, each place they stand marked and stepped through, where the device can say
///   where (Android 15 and later); otherwise the pages that hold them, from the PDF's own words or the words read in
///   it (lib/files/read_text.dart), stepped through a page at a time.
/// - **Copy text**: the page's words, its own or those read in it, onto the clipboard.
/// - **Share** and **Open with**: the file handed to another app under its own name.
///
/// The back gesture closes it, and so does the ×. Ink on the app's paper in both themes; the pages are white, as a
/// PDF's are.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/back.dart';
import 'files_kit.dart';
import 'phone_documents.dart';
import 'read_text.dart';

/// Opens the PDF at [path] over the app. [name] is what it is called (its card's words), [thing] what the words
/// read in it are kept by. Says why, where it cannot be opened.
Future<void> showPdf(BuildContext context, {required FilesKit kit, required String path, required String name, ReadThing? thing}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final back = BackScope.of(context);
  final PdfPages pages;
  try {
    pages = await kit.device.openPdf(path);
  } catch (failure) {
    if (context.mounted) _toast(context, failure is StateError ? failure.message : 'This PDF can’t be opened.');
    return;
  }
  late final OverlayEntry entry;
  VoidCallback? off;
  var shut = false;
  void close() {
    if (shut) return;
    shut = true;
    off?.call();
    entry.remove();
    entry.dispose();
    pages.close();
  }

  entry = OverlayEntry(
    builder: (context) => PdfView(
      pages: pages,
      name: name,
      readWords: thing == null ? null : () => kit.texts.wordsOf(thing),
      onClose: close,
      onShare: () => kit.device.share(path, name: name),
      onOpenWith: () => kit.device.openWith(path, name: name),
    ),
  );
  off = back.onBack(() {
    close();
    return true;
  });
  overlay.insert(entry);
}

void _toast(BuildContext context, String message) {
  try {
    GlacierToast.of(context).toast(message: Text(message));
  } catch (_) {
    debugPrint('[files] $message');
  }
}

/// A place a search found: its page, and where on it in points where the device said.
@immutable
class PdfHit {
  const PdfHit(this.page, [this.box]);
  final int page;
  final ui.Rect? box;
}

/// The pages a search's words stand on, and where: [find]'s places where the device says them, else every page
/// whose words ([words], then [read], the words read in it) hold them all.
Future<List<PdfHit>> findInPdf(PdfPages pages, String query, {String? read}) async {
  final words = query.trim();
  if (words.isEmpty) return const <PdfHit>[];
  final lower = words.toLowerCase();
  final readPages = read == null ? const <String>[] : pagesOf(read);
  final hits = <PdfHit>[];
  for (var page = 0; page < pages.count; page += 1) {
    final boxes = await pages.find(page, words);
    if (boxes != null && boxes.isNotEmpty) {
      hits.addAll(boxes.map((box) => PdfHit(page, box)));
      continue;
    }
    if (boxes != null && boxes.isEmpty) {
      // The device searched the page's own words and found none: the words read off its picture may still hold them.
      final ownWords = await pages.words(page);
      if (ownWords != null && ownWords.trim().isNotEmpty) continue;
    }
    final text = (await pages.words(page)) ?? '';
    final said = text.trim().isNotEmpty ? text : (page < readPages.length ? readPages[page] : '');
    if (said.toLowerCase().contains(lower)) hits.add(PdfHit(page));
  }
  return hits;
}

/// The viewer itself, over [pages].
class PdfView extends StatefulWidget {
  const PdfView({super.key, required this.pages, required this.name, required this.onClose, this.readWords, this.onShare, this.onOpenWith});

  final PdfPages pages;
  final String name;
  final VoidCallback onClose;

  /// The words read in the PDF (a sidecar's, pages apart by a form feed), where there are some.
  final String? Function()? readWords;
  final Future<void> Function()? onShare;
  final Future<void> Function()? onOpenWith;

  @override
  State<PdfView> createState() => PdfViewState();
}

enum _Bar { plain, find, jump }

class PdfViewState extends State<PdfView> {
  late final PageController _pager = PageController();
  int _page = 0;
  _Bar _bar = _Bar.plain;
  bool _zoomed = false;

  final TextEditingController _query = TextEditingController();
  final TextEditingController _jump = TextEditingController();
  List<PdfHit>? _hits;
  int _hit = 0;
  bool _finding = false;

  /// The page in view, from 0.
  int get page => _page;

  @override
  void dispose() {
    _pager.dispose();
    _query.dispose();
    _jump.dispose();
    super.dispose();
  }

  void _say(String message) => _toast(context, message);

  /// Goes to page [index] (from 0).
  void goTo(int index) {
    final to = index.clamp(0, widget.pages.count - 1);
    if (_pager.hasClients) _pager.jumpToPage(to);
    setState(() => _page = to);
  }

  Future<void> find(String query) async {
    setState(() => _finding = true);
    final hits = await findInPdf(widget.pages, query, read: widget.readWords?.call());
    if (!mounted) return;
    setState(() {
      _finding = false;
      _hits = hits;
      _hit = 0;
    });
    if (hits.isEmpty) return _say('Not in this PDF.');
    goTo(hits.first.page);
  }

  void _step(int by) {
    final hits = _hits;
    if (hits == null || hits.isEmpty) return;
    setState(() => _hit = (_hit + by) % hits.length);
    if (_hit < 0) _hit += hits.length;
    goTo(hits[_hit].page);
  }

  Future<void> _copy() async {
    final own = await widget.pages.words(_page);
    var words = own?.trim() ?? '';
    if (words.isEmpty) {
      final read = widget.readWords?.call();
      final pages = read == null ? const <String>[] : pagesOf(read);
      words = _page < pages.length ? pages[_page].trim() : '';
    }
    if (!mounted) return;
    if (words.isEmpty) return _say('No words were read on this page.');
    await Clipboard.setData(ClipboardData(text: words));
    if (mounted) _say('Copied the words on this page.');
  }

  Future<void> _hand(Future<void> Function()? how) async {
    if (how == null) return;
    try {
      await how();
    } catch (failure) {
      if (mounted) _say(failure is StateError ? failure.message : 'No app on this device opens that file.');
    }
  }

  Widget _button(BuildContext context, LucideIcon icon, String label, VoidCallback? onTap, {Key? key}) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(dimension: t.lenOf('2.75rem'), child: Center(child: AppIcon(icon, size: 20, color: t.color(onTap == null ? 'app-ink-3' : 'app-ink')))),
      ),
    );
  }

  Widget _bar$(BuildContext context) {
    final t = context.tokens;
    final count = widget.pages.count;
    final sm = t.fontSize('sm'), xs = t.fontSize('xs');
    switch (_bar) {
      case _Bar.find:
        final hits = _hits;
        return Row(
          children: <Widget>[
            _button(context, Lucide.x, 'Stop finding', () => setState(() {
                  _bar = _Bar.plain;
                  _hits = null;
                }), key: const ValueKey<String>('pdf-find-close')),
            Expanded(
              child: GlacierSearchField(
                key: const ValueKey<String>('pdf-find'),
                controller: _query,
                placeholder: 'Find in this PDF',
                autoFocus: true,
                size: GlacierFieldSize.sm,
                enterKeyHint: TextInputAction.search,
                onSubmitted: (query) => unawaited(find(query)),
              ),
            ),
            SizedBox(width: t.space(2)),
            if (_finding)
              Text('Looking', style: t.textAt(xs, color: t.color('app-ink-3')))
            else if (hits != null)
              Text(hits.isEmpty ? 'None' : '${_hit + 1} of ${hits.length}', key: const ValueKey<String>('pdf-hits'), style: t.textAt(xs, color: t.color('app-ink-2'))),
            _button(context, Lucide.chevronUp, 'The place before', hits == null || hits.length < 2 ? null : () => _step(-1)),
            _button(context, Lucide.chevronDown, 'The next place', hits == null || hits.length < 2 ? null : () => _step(1)),
          ],
        );
      case _Bar.jump:
        return Row(
          children: <Widget>[
            _button(context, Lucide.x, 'Stay on this page', () => setState(() => _bar = _Bar.plain)),
            Text('Go to page', style: t.textAt(sm, color: t.color('app-ink-2'))),
            SizedBox(width: t.space(2)),
            SizedBox(
              width: t.lenOf('5rem'),
              child: GlacierInput(
                key: const ValueKey<String>('pdf-jump'),
                controller: _jump,
                size: GlacierFieldSize.sm,
                autoFocus: true,
                inputMode: TextInputType.number,
                enterKeyHint: TextInputAction.go,
                ariaLabel: 'Page number',
                onSubmitted: (said) {
                  final number = int.tryParse(said.trim());
                  if (number != null) goTo(number - 1);
                  setState(() => _bar = _Bar.plain);
                },
              ),
            ),
            SizedBox(width: t.space(2)),
            Text('of $count', style: t.textAt(sm, color: t.color('app-ink-3'))),
          ],
        );
      case _Bar.plain:
        return Row(
          children: <Widget>[
            _button(context, Lucide.x, 'Close', widget.onClose, key: const ValueKey<String>('pdf-close')),
            Expanded(
              child: Semantics(
                button: true,
                label: 'Page ${_page + 1} of $count. Go to a page',
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey<String>('pdf-page'),
                  behavior: HitTestBehavior.opaque,
                  onTap: count < 2
                      ? null
                      : () => setState(() {
                            _jump.text = '${_page + 1}';
                            _bar = _Bar.jump;
                          }),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textAt(sm, color: t.color('app-ink'))),
                      Text('Page ${_page + 1} of $count', key: const ValueKey<String>('pdf-count'), style: t.textAt(xs, color: t.color('app-ink-3'))),
                    ],
                  ),
                ),
              ),
            ),
            _button(context, Lucide.search, 'Find in this PDF', () => setState(() => _bar = _Bar.find), key: const ValueKey<String>('pdf-find-open')),
            _button(context, Lucide.copy, 'Copy the words on this page', () => unawaited(_copy()), key: const ValueKey<String>('pdf-copy')),
            if (widget.onShare != null) _button(context, Lucide.share2, 'Share', () => unawaited(_hand(widget.onShare))),
            if (widget.onOpenWith != null) _button(context, Lucide.externalLink, 'Open with another app', () => unawaited(_hand(widget.onOpenWith))),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hits = _hits;
    final boxes = <int, List<ui.Rect>>{};
    if (hits != null) {
      for (final hit in hits) {
        if (hit.box != null) (boxes[hit.page] ??= <ui.Rect>[]).add(hit.box!);
      }
    }
    final top = t.lenOf('var(--app-inset-top, 0px)') + MediaQuery.paddingOf(context).top;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: '${widget.name}, a PDF',
      child: ColoredBox(
        color: t.color('app-paper'),
        child: Column(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule'), width: 1))),
              child: Padding(
                padding: EdgeInsets.only(top: top, left: t.space(1), right: t.space(1)),
                child: SizedBox(height: t.lenOf('3.5rem'), child: _bar$(context)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const ValueKey<String>('pdf-pages'),
                controller: _pager,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                itemCount: widget.pages.count,
                onPageChanged: (index) => setState(() {
                  _page = index;
                  _zoomed = false;
                }),
                itemBuilder: (context, index) => PdfPageView(
                  key: ValueKey<int>(index),
                  pages: widget.pages,
                  index: index,
                  marks: boxes[index] ?? const <ui.Rect>[],
                  current: hits != null && hits.isNotEmpty && hits[_hit].page == index ? hits[_hit].box : null,
                  onZoomed: (zoomed) {
                    if (zoomed != _zoomed && index == _page) setState(() => _zoomed = zoomed);
                  },
                ),
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}

/// One page of a PDF, fitted to its room, drawn on asking and drawn again sharper when zoomed.
class PdfPageView extends StatefulWidget {
  const PdfPageView({super.key, required this.pages, required this.index, this.marks = const <ui.Rect>[], this.current, this.onZoomed});

  final PdfPages pages;
  final int index;

  /// Where found words stand on it, in points, and the one stepped to.
  final List<ui.Rect> marks;
  final ui.Rect? current;
  final ValueChanged<bool>? onZoomed;

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  final TransformationController _zoom = TransformationController();
  ui.Image? _drawn;
  int _drawnWidth = 0;
  int _asking = 0;
  Size? _fit;

  @override
  void dispose() {
    _zoom.dispose();
    _drawn?.dispose();
    super.dispose();
  }

  void _draw(int width) {
    if (width <= _drawnWidth || width <= 0) return;
    final asking = ++_asking;
    unawaited(widget.pages.draw(widget.index, width).then((image) {
      if (image == null) return;
      if (!mounted || asking != _asking) {
        image.dispose();
        return;
      }
      setState(() {
        _drawn?.dispose();
        _drawn = image;
        _drawnWidth = width;
      });
    }));
  }

  void _settled() {
    final scale = _zoom.value.getMaxScaleOnAxis();
    widget.onZoomed?.call(scale > 1.01);
    final fit = _fit;
    if (fit == null) return;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    // Sharper only once the pinch has settled, and never more than the device would draw.
    _draw(math.min(4096, (fit.width * ratio * math.min(scale, 3.0)).round()));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = widget.pages.sizes[widget.index];
    return LayoutBuilder(builder: (context, room) {
      final pad = t.space(3);
      final width = math.max(1.0, room.maxWidth - pad * 2), height = math.max(1.0, room.maxHeight - pad * 2);
      final scale = math.min(width / size.width, height / size.height);
      final fit = Size(size.width * scale, size.height * scale);
      _fit = fit;
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final want = (fit.width * ratio).round();
      if (_drawnWidth < want) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _draw(want) : null);
      final paper = SizedBox(
        width: fit.width,
        height: fit.height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xFFFFFFFF), boxShadow: <BoxShadow>[BoxShadow(color: t.color('app-scrim').withValues(alpha: 0.25), blurRadius: 12)]),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (_drawn != null) RawImage(key: const ValueKey<String>('pdf-drawn'), image: _drawn, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
              // The highlighter's wash (`--app-mark`), the one colour among the marks; the one stepped to ringed in
              // black, since the page is white in both themes.
              if (widget.marks.isNotEmpty) CustomPaint(painter: _Marks(widget.marks, widget.current, scale, t.color('app-mark'))),
            ],
          ),
        ),
      );
      return GestureDetector(
        onDoubleTap: () {
          _zoom.value = Matrix4.identity();
          _settled();
        },
        child: InteractiveViewer(
          transformationController: _zoom,
          minScale: 1,
          maxScale: 5,
          panEnabled: true,
          onInteractionEnd: (_) => _settled(),
          child: SizedBox(width: room.maxWidth, height: room.maxHeight, child: Center(child: Semantics(label: 'Page ${widget.index + 1}', image: true, child: paper))),
        ),
      );
    });
  }
}

class _Marks extends CustomPainter {
  _Marks(this.marks, this.current, this.scale, this.wash);

  final List<ui.Rect> marks;
  final ui.Rect? current;
  final double scale;
  final Color wash;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = wash;
    final strong = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final box in marks) {
      final at = Rect.fromLTRB(box.left * scale, box.top * scale, box.right * scale, box.bottom * scale).inflate(1);
      canvas.drawRect(at, soft);
      if (box == current) canvas.drawRect(at, strong);
    }
  }

  @override
  bool shouldRepaint(_Marks old) => old.marks != marks || old.current != current || old.scale != scale || old.wash != wash;
}
