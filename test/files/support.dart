// A device's documents for the files' tests (lib/files/phone_documents.dart [DocumentDevice]): words it "reads"
// from a map, a PDF whose pages it draws plain, a scanner and a picker that hand back what a test gave them.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:ghost_md/files/phone_documents.dart';

/// A small PDF of [pages] pages, each [width] x [height] points, as a writer would make it: what the viewer's
/// tests open, its page count and sizes read back from its own objects by [readPdfPages].
String tinyPdf({int pages = 3, double width = 612, double height = 792}) {
  final objects = <String>['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [${[for (var i = 0; i < pages; i++) '${3 + i} 0 R'].join(' ')}] /Count $pages >>'];
  for (var i = 0; i < pages; i++) {
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${width.round()} ${height.round()}] >>');
  }
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final at in offsets) {
    out.write('${at.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.toString();
}

final RegExp _page = RegExp(r'/Type\s*/Page\b[^>]*/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]');

/// Each page's size in points, read from a PDF's page objects: enough of a reader for a test's own small PDFs.
List<ui.Size> readPdfPages(String pdf) => <ui.Size>[
      for (final m in _page.allMatches(pdf)) ui.Size(double.parse(m.group(3)!) - double.parse(m.group(1)!), double.parse(m.group(4)!) - double.parse(m.group(2)!)),
    ];

/// A PDF open for a test: its pages drawn as plain paper with the page's number in it, its words and where a word
/// stands as the test says.
class FakePdf extends PdfPages {
  FakePdf(this.sizes, {this.pageWords = const <String>[], this.findable = true});

  @override
  final List<ui.Size> sizes;

  /// Each page's own words; a page past the list has none.
  final List<String> pageWords;

  /// Whether this device can say where words stand (Android 15).
  final bool findable;
  final List<int> drawn = <int>[];
  bool closed = false;

  @override
  Future<ui.Image?> draw(int page, int width) async {
    drawn.add(page);
    final size = sizes[page];
    final height = (width * size.height / size.width).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    final ink = ui.Paint()..color = const ui.Color(0xFF222222);
    for (var line = 0; line < 9; line++) {
      canvas.drawRect(ui.Rect.fromLTWH(width * 0.12, height * (0.12 + line * 0.07), width * (line.isEven ? 0.7 : 0.55), height * 0.018), ink);
    }
    final words = TextPainter(text: TextSpan(text: 'Page ${page + 1}', style: TextStyle(fontSize: width / 16, color: const ui.Color(0xFF222222))), textDirection: TextDirection.ltr)..layout();
    words.paint(canvas, ui.Offset(width * 0.12, height * 0.8));
    return recorder.endRecording().toImage(width, height);
  }

  @override
  Future<String?> words(int page) async => findable ? (page < pageWords.length ? pageWords[page] : '') : null;

  @override
  Future<List<ui.Rect>?> find(int page, String query) async {
    if (!findable) return null;
    final words = page < pageWords.length ? pageWords[page].toLowerCase() : '';
    final at = words.indexOf(query.toLowerCase());
    if (at < 0) return const <ui.Rect>[];
    return <ui.Rect>[ui.Rect.fromLTWH(72 + at * 6.0, 100, query.length * 6.0, 14)];
  }

  @override
  void close() => closed = true;
}

/// A device for a test: what it reads from [words] by path, what its picker and scanner hand back, and Battery
/// saver as the test sets it.
class FakeDocuments implements DocumentDevice {
  FakeDocuments({Map<String, List<String>>? words, this.picked, this.scanned, this.reads = true, this.drawsPdf = true}) : words = words ?? <String, List<String>>{};

  /// What reading each path finds, a page each; a path not here reads as one empty page.
  final Map<String, List<String>> words;
  PickedFile? picked;
  ScannedDocument? scanned;

  @override
  final bool reads;

  @override
  final bool drawsPdf;

  @override
  bool get picks => true;

  bool batterySaver = false;
  final List<String> readPaths = <String>[];
  final List<String> handed = <String>[];

  /// Held until completed by a test that wants reading to be slow.
  Completer<void>? gate;

  @override
  Future<bool> canScan() async => scanned != null;

  @override
  Future<PickedFile?> pick() async => picked;

  @override
  Future<ScannedDocument?> scan() async => scanned;

  @override
  Future<List<String>?> read(String path, {required bool pdf, int most = 60}) async {
    if (!reads) return null;
    readPaths.add(path);
    await gate?.future;
    return words[path] ?? words[path.split('/').last] ?? const <String>[''];
  }

  @override
  Future<PdfPages> openPdf(String path) async => FakePdf(readPdfPages(await File(path).readAsString()));

  @override
  Future<void> openWith(String path, {required String name}) async => handed.add('open $name');

  @override
  Future<void> share(String path, {required String name}) async => handed.add('share $name');

  @override
  Future<bool> saving() async => batterySaver;
}
