/// The clipboard, as the note's press-and-hold band reaches it: a port of `src/app/editor/clipboard.ts`.
///
/// On the page, reading was the one thing a WebView refused, so the activity read it and the browser's reader was
/// tried after. Here Flutter's own `Clipboard` reads and writes, and what the band keeps of the web's is the shape
/// of the answer: words, a picture copied out by path, or why it could not be read, and whether anything answered
/// at all, since a clipboard that could not be read is not an empty one and the band's words say which.
///
/// What differs:
/// - `readClipboard`, `writeClipboard` and `clipboardReadable` are a [BandClipboard]'s `read`, `write` and
///   `readable`, so a host with a reader of its own (one that copies a picture out and answers its path, as the
///   Android activity's did) hands the band that instead, and a test hands it a clipboard it made;
/// - [SystemClipboard] is Flutter's, which reads words alone: it never answers a `path`. A read that answers with
///   nothing is an empty clipboard (`read` true); a read that throws is the caller's to answer, as the browser's;
/// - `writeClipboard`'s fall back to `document.execCommand('copy')` has nothing to stand for here.
library;

import 'package:flutter/services.dart';

/// What was found on the clipboard: words, a picture copied out by path, or why it could not be read (`Clipboard`).
class Clip {
  const Clip({this.text, this.path, this.error});

  final String? text;
  final String? path;
  final String? error;
}

/// What a read answers: the clip, and whether anything could actually answer.
typedef ClipRead = ({Clip clip, bool read});

/// The clipboard the band reads and writes.
abstract class BandClipboard {
  const BandClipboard();

  /// Whether a Paste row is worth showing at all (`clipboardReadable`).
  bool get readable;

  /// What is on the clipboard (`readClipboard`). May throw, where the clipboard refuses outright.
  Future<ClipRead> read();

  /// Words onto the clipboard (`writeClipboard`).
  Future<void> write(String words);
}

/// The phone's clipboard, through Flutter's `Clipboard`.
class SystemClipboard extends BandClipboard {
  const SystemClipboard();

  @override
  bool get readable => true;

  @override
  Future<ClipRead> read() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    // A reader that answers, even with nothing, has told us the clipboard is empty.
    return (text != null && text.isNotEmpty) ? (clip: Clip(text: text), read: true) : (clip: const Clip(), read: true);
  }

  @override
  Future<void> write(String words) => Clipboard.setData(ClipboardData(text: words));
}
