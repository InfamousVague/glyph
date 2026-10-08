import 'dart:typed_data';

import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/share/share.dart';

export '../feed/signed.dart';
export '../support/fake_service.dart';

/// A note for a test (the web's `makeNote(id, body)`).
Note note(String id, String body) => Note(id: id, body: body, createdAt: 0, updatedAt: 0);

/// This device's pictures, in a map, with every read counted.
class Pictures implements SharePictures {
  Pictures([Map<String, Uint8List>? held]) : held = {...?held};
  final Map<String, Uint8List> held;
  final List<String> reads = [];
  final List<String> keptNames = [];

  /// How a picture is drawn smaller: as it is, unless a test says otherwise.
  Uint8List Function(Uint8List bytes) shrink = (bytes) => bytes;

  @override
  Future<Uint8List?> read(String name) async {
    reads.add(name);
    return held[name];
  }

  @override
  Future<Uint8List> smaller(Uint8List bytes) async => shrink(bytes);

  @override
  Future<void> keep(String name, Uint8List bytes) async {
    keptNames.add(name);
    held[name] = bytes;
  }
}

/// A picture's bytes: [size] of them, all [n].
Uint8List jpeg(int n, [int size = 8]) => Uint8List(size)..fillRange(0, size, n);
