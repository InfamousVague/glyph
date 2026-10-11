/// How tall a drawn block was, remembered by what it shows: in memory while the app is open, and across launches. A
/// port of `src/app/editor/heightMemory.ts`.
///
/// A block widget is drawn after the note is laid out (a board once its cards are measured, a diagram once it is
/// drawn), and until then the editor counts it at its estimate. Counted as one line, it grew by a screenful as it
/// came into view and the page moved under the finger. So the height each one was drawn at is kept, and a note
/// opened again knows it before drawing.
///
/// Kept newest last, the oldest let go past a cap, and written half a second after the first change since the last
/// write. Each kind of block keeps the storage key, the cap and the rounding it has always had.
///
/// What differs: nothing in what is kept or when. A [HeightStore] over this device's memory is
/// [HeightStore.kept]; the blocks that use one (boards, diagrams) arrive with their own pieces.
library;

import 'dart:async';

import '../core/stored.dart';

/// Where a memory is kept: what storage holds under its key, as JSON, and writing the pairs back there.
class HeightStore {
  const HeightStore({required this.read, required this.write});

  /// The device's memory under [key] (`readStored`, `writeStored`).
  factory HeightStore.kept(String key, {Stored? device}) => HeightStore(
        read: () => (device ?? stored).read<Object?>(key, null, (raw) => raw),
        write: (pairs) => (device ?? stored).write(key, [
          for (final (face, height) in pairs) [face, height],
        ]),
      );

  final Object? Function() read;
  final void Function(List<(String, double)> pairs) write;
}

/// A write waits this long after the first change since the last one (`SAVE_AFTER_MS`).
const Duration heightSaveAfter = Duration(milliseconds: 500);

/// A memory kept in [store], holding at most [kept] blocks, each height passed through [round] first. The store is
/// read the first time the memory is asked, not when it is made (`heightMemory`).
class HeightMemory {
  HeightMemory(this.store, this.kept, this.round);

  final HeightStore store;
  final int kept;
  final double Function(double height) round;

  Map<String, double>? _heights;
  Timer? _saving;

  Map<String, double> _all() {
    final held = _heights;
    if (held != null) return held;
    final heights = _heights = <String, double>{};
    // No storage, or something other than pairs in it: blocks are guessed at until they are drawn.
    final read = store.read();
    for (final entry in read is List ? read : const <Object?>[]) {
      if (entry is List && entry.length >= 2 && entry[0] is String && entry[1] is num) heights[entry[0] as String] = (entry[1] as num).toDouble();
    }
    return heights;
  }

  /// The height [face] was last drawn at, or null for one never drawn.
  double? known(String face) => _all()[shortKey(face)];

  /// Remembers [height] for [face], rounded the memory's way.
  void keep(String face, double height) {
    final held = _all();
    final name = shortKey(face);
    final px = round(height);
    if (held[name] == px) return;
    // Newest last, so the oldest are the first let go.
    held.remove(name);
    held[name] = px;
    while (held.length > kept) {
      held.remove(held.keys.first);
    }
    if (_saving != null) return;
    _saving = Timer(heightSaveAfter, () {
      _saving = null;
      store.write([for (final entry in held.entries) (entry.key, entry.value)]);
    });
  }
}

/// A short name for what a block shows: its length and an FNV-1a hash, both in base 36 (`shortKey`).
String shortKey(String face) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < face.length; i += 1) {
    hash ^= face.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return '${face.length.toRadixString(36)}.${hash.toRadixString(36)}';
}
