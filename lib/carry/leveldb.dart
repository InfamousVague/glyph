/// A LevelDB folder, read and never written: what a Chromium web view keeps its `localStorage` and its IndexedDB
/// in (`app_webview/Default/Local Storage/leveldb`, `…/IndexedDB/<origin>.indexeddb.leveldb`).
///
/// Why this exists (lib/carry/tauri_carry.dart): the Tauri app this one replaces kept the account's keys as
/// `CryptoKey` objects in IndexedDB, not extractable, so no page and no web view will ever hand their bytes over.
/// Chromium writes them to disk in the clear all the same, and this reads them from there.
///
/// What is read: every `*.log` (the write-ahead log: 32 KiB blocks of records, each a batch of puts and deletes
/// with a sequence number) and every `*.ldb` or `*.sst` (a sorted table: data blocks, an index block, a footer;
/// blocks may be Snappy-compressed). For each key the entry with the highest sequence number stands, and if that
/// entry is a delete the key is gone. The MANIFEST is not read: LevelDB removes a table as soon as a compaction
/// has replaced it, so the files in the folder are the live ones, and an older file left behind can only hold
/// lower sequence numbers. No comparator is needed, since nothing is looked up in order: IndexedDB's own
/// (`idb_cmp1`) never has to be ported.
///
/// Nothing here throws for a file cut short or a block that will not parse: what could be read is read, and
/// [LevelDb.damaged] says how many pieces could not. The folder is not locked and nothing in it is changed, so it
/// must be read while no web view has it open.
library;

import 'dart:io';
import 'dart:typed_data';

/// One key's standing value in a LevelDB folder.
class LevelEntry {
  const LevelEntry(this.key, this.value, this.sequence);

  final Uint8List key;
  final Uint8List value;

  /// The sequence number of the write that stands.
  final int sequence;
}

/// The live keys and values of a LevelDB folder, as [read] found them.
class LevelDb {
  LevelDb._(this._live, this.damaged, this.files);

  final Map<String, LevelEntry> _live;

  /// How many records, blocks or files could not be read.
  final int damaged;

  /// How many log and table files were read.
  final int files;

  /// Every live entry, in no order.
  Iterable<LevelEntry> get entries => _live.values;

  /// The value under exactly [key], or null: never written, or deleted since.
  Uint8List? get(List<int> key) => _live[_name(key)]?.value;

  /// Reads the folder at [folder]. A folder that is not there is an empty database.
  static Future<LevelDb> read(Directory folder) async {
    final found = <String, ({int sequence, Uint8List key, Uint8List? value})>{};
    var damaged = 0, files = 0;
    void put(Uint8List key, Uint8List? value, int sequence) {
      final name = _name(key);
      final held = found[name];
      if (held == null || sequence >= held.sequence) found[name] = (sequence: sequence, key: key, value: value);
    }

    if (await folder.exists()) {
      final all = await folder.list(followLinks: false).where((each) => each is File).cast<File>().toList();
      for (final file in all) {
        final name = file.uri.pathSegments.last;
        final isLog = name.endsWith('.log'), isTable = name.endsWith('.ldb') || name.endsWith('.sst');
        if (!isLog && !isTable) continue;
        files += 1;
        try {
          final bytes = await file.readAsBytes();
          damaged += isLog ? _readLog(bytes, put) : _readTable(bytes, put);
        } catch (_) {
          // A file that cannot be read at all: counted, and the rest stands.
          damaged += 1;
        }
      }
    }
    final live = <String, LevelEntry>{};
    found.forEach((name, entry) {
      final value = entry.value;
      if (value != null) live[name] = LevelEntry(entry.key, value, entry.sequence);
    });
    return LevelDb._(live, damaged, files);
  }

  static String _name(List<int> key) => String.fromCharCodes(key);
}

typedef _Put = void Function(Uint8List key, Uint8List? value, int sequence);

const int _blockSize = 32768;

/// A write-ahead log: physical records of at most a block, joined into batches. Answers how many were damaged.
int _readLog(Uint8List bytes, _Put put) {
  var damaged = 0;
  BytesBuilder? joined;
  for (var block = 0; block < bytes.length; block += _blockSize) {
    final end = block + _blockSize < bytes.length ? block + _blockSize : bytes.length;
    var at = block;
    // A record's header is seven bytes: a checksum (not checked: a torn tail fails its lengths instead), the
    // length, and whether it is whole, a first part, a middle or a last.
    while (at + 7 <= end) {
      final length = bytes[at + 4] | (bytes[at + 5] << 8);
      final type = bytes[at + 6];
      if (type == 0 && length == 0) break; // The block's padding.
      final from = at + 7, to = from + length;
      if (to > end) {
        damaged += 1;
        break;
      }
      final part = Uint8List.sublistView(bytes, from, to);
      at = to;
      switch (type) {
        case 1:
          damaged += _readBatch(part, put);
          joined = null;
        case 2:
          joined = BytesBuilder(copy: false)..add(part);
        case 3:
          joined?.add(part);
        case 4:
          if (joined == null) {
            damaged += 1;
          } else {
            joined.add(part);
            damaged += _readBatch(joined.takeBytes(), put);
            joined = null;
          }
        default:
          damaged += 1;
      }
    }
  }
  return damaged;
}

/// A batch: its first sequence number, how many writes, then each write.
int _readBatch(Uint8List batch, _Put put) {
  if (batch.length < 12) return 1;
  final data = ByteData.sublistView(batch);
  var sequence = data.getUint32(0, Endian.little) + data.getUint32(4, Endian.little) * 0x100000000;
  final count = data.getUint32(8, Endian.little);
  final reader = _Reader(batch, 12);
  try {
    for (var i = 0; i < count; i += 1) {
      final kind = reader.byte();
      final key = reader.slice(reader.varint());
      if (kind == 1) {
        put(key, reader.slice(reader.varint()), sequence);
      } else if (kind == 0) {
        put(key, null, sequence);
      } else {
        return 1;
      }
      sequence += 1;
    }
  } on RangeError {
    return 1;
  }
  return 0;
}

/// A sorted table: the footer names the index block, whose entries name the data blocks. A key in a table is
/// the key as written, then eight bytes: the sequence number over the kind of write.
int _readTable(Uint8List bytes, _Put put) {
  if (bytes.length < 48) return 1;
  final footer = _Reader(bytes, bytes.length - 48);
  try {
    footer
      ..varint()
      ..varint(); // The metaindex block's handle: filters, which a full read never asks.
    final indexAt = footer.varint(), indexSize = footer.varint();
    final index = _block(bytes, indexAt, indexSize);
    if (index == null) return 1;
    var damaged = 0;
    for (final (_, handle) in _entries(index)) {
      final where = _Reader(handle, 0);
      final block = _block(bytes, where.varint(), where.varint());
      if (block == null) {
        damaged += 1;
        continue;
      }
      for (final (key, value) in _entries(block)) {
        if (key.length < 8) {
          damaged += 1;
          continue;
        }
        final tail = ByteData.sublistView(key, key.length - 8);
        final low = tail.getUint32(0, Endian.little), high = tail.getUint32(4, Endian.little);
        final kind = low & 0xff;
        final sequence = (low >> 8) + high * 0x1000000;
        final plain = Uint8List.fromList(Uint8List.sublistView(key, 0, key.length - 8));
        put(plain, kind == 1 ? value : null, sequence);
      }
    }
    return damaged;
  } on RangeError {
    return 1;
  }
}

/// The block of [size] bytes at [at], unpacked if it was compressed, or null for one that cannot be had.
Uint8List? _block(Uint8List bytes, int at, int size) {
  if (at < 0 || size < 0 || at + size + 1 > bytes.length) return null;
  final raw = Uint8List.sublistView(bytes, at, at + size);
  switch (bytes[at + size]) {
    case 0:
      return raw;
    case 1:
      return snappyUnpack(raw);
    default:
      // Zstandard, which Chromium does not turn on for these.
      return null;
  }
}

/// A block's entries: each key shares a prefix with the one before, and the restart points at the end are only
/// for seeking, which a full read never does.
Iterable<(Uint8List, Uint8List)> _entries(Uint8List block) sync* {
  if (block.length < 4) return;
  final restarts = ByteData.sublistView(block).getUint32(block.length - 4, Endian.little);
  final end = block.length - 4 - restarts * 4;
  if (end < 0) return;
  final reader = _Reader(block, 0);
  var last = Uint8List(0);
  try {
    while (reader.at < end) {
      final shared = reader.varint(), fresh = reader.varint(), valueLength = reader.varint();
      if (shared > last.length) return;
      final key = Uint8List(shared + fresh)
        ..setRange(0, shared, last)
        ..setRange(shared, shared + fresh, reader.slice(fresh));
      final value = reader.slice(valueLength);
      last = key;
      yield (key, value);
    }
  } on RangeError {
    // Cut short: what came before it stands.
    return;
  }
}

/// Snappy's raw format, unpacked: a length, then literals and copies from what was already written. Null for
/// anything that is not it.
Uint8List? snappyUnpack(Uint8List packed) {
  try {
    final reader = _Reader(packed, 0);
    final length = reader.varint();
    if (length > 256 * 1024 * 1024) return null;
    final out = Uint8List(length);
    var to = 0;
    while (reader.at < packed.length) {
      final tag = reader.byte();
      var count = 0, back = 0;
      switch (tag & 3) {
        case 0:
          count = tag >> 2;
          if (count >= 60) {
            final more = count - 59;
            count = 0;
            for (var i = 0; i < more; i += 1) {
              count |= reader.byte() << (8 * i);
            }
          }
          count += 1;
          out.setRange(to, to + count, reader.slice(count));
          to += count;
          continue;
        case 1:
          count = ((tag >> 2) & 7) + 4;
          back = ((tag >> 5) << 8) | reader.byte();
        case 2:
          count = (tag >> 2) + 1;
          back = reader.byte() | (reader.byte() << 8);
        case 3:
          count = (tag >> 2) + 1;
          back = reader.byte() | (reader.byte() << 8) | (reader.byte() << 16) | (reader.byte() << 24);
      }
      if (back == 0 || back > to || to + count > length) return null;
      // Byte by byte: a copy may run into what it is itself writing.
      for (var i = 0; i < count; i += 1) {
        out[to] = out[to - back];
        to += 1;
      }
    }
    return to == length ? out : null;
  } on RangeError {
    return null;
  }
}

/// Bytes read forward. Past the end is a [RangeError], which every caller reads as "cut short".
class _Reader {
  _Reader(this.bytes, this.at);

  final Uint8List bytes;
  int at;

  int byte() {
    if (at >= bytes.length) throw RangeError('past the end');
    return bytes[at++];
  }

  int varint() {
    var value = 0, shift = 0;
    while (true) {
      final next = byte();
      value |= (next & 0x7f) << shift;
      if (next & 0x80 == 0) return value;
      shift += 7;
      if (shift > 63) throw RangeError('a number too long');
    }
  }

  Uint8List slice(int length) {
    if (length < 0 || at + length > bytes.length) throw RangeError('past the end');
    final out = Uint8List.sublistView(bytes, at, at + length);
    at += length;
    return out;
  }
}
