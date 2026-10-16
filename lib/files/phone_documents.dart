/// What the device does with documents, over the channel `ghost_md/documents` (Android's
/// android/…/ghost_md/Documents.kt; the Mac's macos/Runner/GhostChannels.swift answers `pick` and `openWith`):
/// choose any file, scan one with Google's document scanner, read the words in a picture or a PDF, draw a PDF's
/// pages, and hand a file to another app.
///
/// | method | takes | answers |
/// | --- | --- | --- |
/// | `pick` | | `{path, name, bytes}` of a copy in the cache's `picked/`, `{cancelled: true}`, or an error with a sentence |
/// | `canScan` | | whether the scanner can open here (Google Play services) |
/// | `scan` | | `{pdf, pages: [jpeg paths], count}` in the cache's `picked/`, `{cancelled: true}`, or an error |
/// | `read` | `{path, pdf, most}` | `{pages: [words]}`: the words read in a picture, or in each of a PDF's first `most` pages |
/// | `pdfOpen` | `{path}` | `{id, pages: [[width, height]]}` in points |
/// | `pdfPage` | `{id, page, width}` | `{width, height, pixels}`: the page drawn `width` pixels across, RGBA |
/// | `pdfText` | `{id, page}` | the page's own words, or null where the phone cannot say (before Android 15) |
/// | `pdfFind` | `{id, page, query}` | `[[left, top, right, bottom]]` in points where the words stand, or null where it cannot say |
/// | `pdfClose` | `{id}` | null |
/// | `openWith`, `share` | `{path, name}` | null: the file handed over as `name`, through Android's chooser |
/// | `saving` | | whether Battery saver is on |
///
/// The picker asks for no permission (Android's own document picker: the app sees only the file chosen), and nor
/// does the scanner: it is Google's own screen, which takes the pictures and hands back what it made, so this app
/// never holds the camera. The words are read on the phone (ML Kit's text recognition, its Latin model inside the
/// app): nothing leaves the device to be read.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The channel the phone's documents answer on.
const MethodChannel documentsChannel = MethodChannel('ghost_md/documents');

/// What a build with no way to choose a file says.
const String cannotAddFiles = 'This build cannot add files yet.';

/// A file chosen, copied into the app's cache: its path there, the name it had, and its size.
@immutable
class PickedFile {
  const PickedFile({required this.path, required this.name, required this.bytes});
  final String path;
  final String name;
  final int bytes;
}

/// A document scanned: its pages as one PDF, and each page's picture, in the app's cache.
@immutable
class ScannedDocument {
  const ScannedDocument({required this.pdf, required this.pages});
  final String pdf;
  final List<String> pages;
}

/// A PDF open to draw: its pages' sizes in points, each page drawn, read and searched on asking.
abstract class PdfPages {
  /// Each page's width and height, in points.
  List<ui.Size> get sizes;

  int get count => sizes.length;

  /// Page [page] (from 0) drawn [width] pixels across, white under it; null where it would not draw.
  Future<ui.Image?> draw(int page, int width);

  /// Page [page]'s own words; null where this device cannot say (an image of a page has none, and says '').
  Future<String?> words(int page);

  /// Where [query] stands on page [page], in points; null where this device cannot say.
  Future<List<ui.Rect>?> find(int page, String query);

  /// Let go of the file.
  void close();
}

/// What a device does with documents.
abstract class DocumentDevice {
  /// Whether a file can be chosen here.
  bool get picks;

  /// Whether words are read in pictures and PDFs here.
  bool get reads;

  /// Whether a PDF is drawn in the app here; elsewhere it is handed to another app.
  bool get drawsPdf;

  /// Whether the document scanner can open here: asked of the device once.
  Future<bool> canScan();

  /// Lets the person choose a file; null when they chose none. Throws with a sentence.
  Future<PickedFile?> pick();

  /// Opens the scanner; null when the person left it. Throws with a sentence.
  Future<ScannedDocument?> scan();

  /// The words read in the picture or PDF at [path], a page each; null where this device reads none.
  Future<List<String>?> read(String path, {required bool pdf, int most = 60});

  /// Opens the PDF at [path] to draw. Throws with a sentence.
  Future<PdfPages> openPdf(String path);

  /// Hands the file at [path] to another app as [name]: Android's chooser, "Open with".
  Future<void> openWith(String path, {required String name});

  /// Shares the file at [path] as [name].
  Future<void> share(String path, {required String name});

  /// Whether Battery saver is on: the slow reading of what is already in the notes waits.
  Future<bool> saving();
}

String _sentence(PlatformException failure, String otherwise) => failure.message?.isNotEmpty == true ? failure.message! : otherwise;

/// The device's half over [documentsChannel]: Android's, and on a Mac the open panel and Open with.
class PhoneDocuments implements DocumentDevice {
  PhoneDocuments({MethodChannel channel = documentsChannel, TargetPlatform? platform})
      : _channel = channel,
        _platform = platform ?? defaultTargetPlatform;

  final MethodChannel _channel;
  final TargetPlatform _platform;

  bool get _android => _platform == TargetPlatform.android;

  @override
  bool get picks => _android || _platform == TargetPlatform.macOS;

  @override
  bool get reads => _android;

  @override
  bool get drawsPdf => _android;

  Future<bool>? _canScan;

  @override
  Future<bool> canScan() => _canScan ??= !_android
      ? Future<bool>.value(false)
      : _channel.invokeMethod<bool>('canScan').then((can) => can ?? false, onError: (Object _) => false);

  @override
  Future<PickedFile?> pick() async {
    final Map<String, Object?>? answer;
    try {
      answer = await _channel.invokeMapMethod<String, Object?>('pick');
    } on MissingPluginException {
      throw StateError(cannotAddFiles);
    } on PlatformException catch (failure) {
      throw StateError(_sentence(failure, 'The file could not be read.'));
    }
    if (answer == null || answer['cancelled'] == true) return null;
    final path = answer['path'], name = answer['name'], bytes = answer['bytes'];
    if (path is! String || path.isEmpty) throw StateError('The file could not be read.');
    return PickedFile(path: path, name: name is String && name.isNotEmpty ? name : 'File', bytes: bytes is num ? bytes.toInt() : 0);
  }

  @override
  Future<ScannedDocument?> scan() async {
    final Map<String, Object?>? answer;
    try {
      answer = await _channel.invokeMapMethod<String, Object?>('scan');
    } on MissingPluginException {
      throw StateError('This build cannot scan documents.');
    } on PlatformException catch (failure) {
      throw StateError(_sentence(failure, 'The scanner did not open.'));
    }
    if (answer == null || answer['cancelled'] == true) return null;
    final pdf = answer['pdf'], pages = answer['pages'];
    if (pdf is! String || pdf.isEmpty) throw StateError('The scan could not be kept.');
    return ScannedDocument(pdf: pdf, pages: pages is List ? pages.whereType<String>().toList() : const <String>[]);
  }

  @override
  Future<List<String>?> read(String path, {required bool pdf, int most = 60}) async {
    if (!reads) return null;
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>('read', <String, Object?>{'path': path, 'pdf': pdf, 'most': most});
      final pages = answer?['pages'];
      return pages is List ? pages.map((page) => page is String ? page : '').toList() : null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<PdfPages> openPdf(String path) async {
    final Map<String, Object?>? answer;
    try {
      answer = await _channel.invokeMapMethod<String, Object?>('pdfOpen', <String, Object?>{'path': path});
    } on MissingPluginException {
      throw StateError('This PDF can’t be opened here.');
    } on PlatformException catch (failure) {
      throw StateError(_sentence(failure, 'This PDF can’t be opened.'));
    }
    final id = (answer?['id'] as num?)?.toInt();
    final pages = answer?['pages'];
    if (id == null || pages is! List) throw StateError('This PDF can’t be opened.');
    return _PhonePdf(_channel, id, <ui.Size>[
      for (final page in pages)
        if (page is List && page.length == 2) ui.Size((page[0] as num).toDouble(), (page[1] as num).toDouble()) else const ui.Size(612, 792),
    ]);
  }

  @override
  Future<void> openWith(String path, {required String name}) => _hand('openWith', path, name);

  @override
  Future<void> share(String path, {required String name}) => _hand('share', path, name);

  Future<void> _hand(String method, String path, String name) async {
    try {
      await _channel.invokeMethod<void>(method, <String, Object?>{'path': path, 'name': name});
    } on MissingPluginException {
      throw StateError('This device has no app to open it with.');
    } on PlatformException catch (failure) {
      throw StateError(_sentence(failure, 'No app on this device opens that file.'));
    }
  }

  @override
  Future<bool> saving() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('saving') ?? false;
    } catch (_) {
      return false;
    }
  }
}

class _PhonePdf extends PdfPages {
  _PhonePdf(this._channel, this._id, this.sizes);

  final MethodChannel _channel;
  final int _id;
  bool _closed = false;

  @override
  final List<ui.Size> sizes;

  @override
  Future<ui.Image?> draw(int page, int width) async {
    if (_closed) return null;
    final Map<String, Object?>? answer;
    try {
      answer = await _channel.invokeMapMethod<String, Object?>('pdfPage', <String, Object?>{'id': _id, 'page': page, 'width': width});
    } on PlatformException {
      return null;
    }
    final w = (answer?['width'] as num?)?.toInt(), h = (answer?['height'] as num?)?.toInt();
    final pixels = answer?['pixels'];
    if (w == null || h == null || pixels is! Uint8List || pixels.length < w * h * 4) return null;
    return _image(pixels, w, h);
  }

  @override
  Future<String?> words(int page) async {
    if (_closed) return null;
    try {
      return await _channel.invokeMethod<String>('pdfText', <String, Object?>{'id': _id, 'page': page});
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<List<ui.Rect>?> find(int page, String query) async {
    if (_closed) return null;
    try {
      final found = await _channel.invokeListMethod<Object?>('pdfFind', <String, Object?>{'id': _id, 'page': page, 'query': query});
      if (found == null) return null;
      return <ui.Rect>[
        for (final box in found)
          if (box is List && box.length == 4) ui.Rect.fromLTRB((box[0] as num).toDouble(), (box[1] as num).toDouble(), (box[2] as num).toDouble(), (box[3] as num).toDouble()),
      ];
    } on PlatformException {
      return null;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_channel.invokeMethod<void>('pdfClose', <String, Object?>{'id': _id}).then<void>((_) {}, onError: (Object _) {}));
  }
}

/// RGBA pixels as an image, made off the UI's work by the engine.
Future<ui.Image> _image(Uint8List pixels, int width, int height) {
  final made = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, made.complete);
  return made.future;
}
