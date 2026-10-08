/// A zip of a few files, stored as they are: a shared book downloaded as its pages (share.dart). A port of
/// `src/app/share/zip.ts`.
///
/// Markdown is small and a book is a handful of pages, so nothing is compressed, and a zip with nothing compressed is
/// simple enough to write here rather than bring in a library for it. Every archive tool opens it.
///
/// What differs: nothing but the types. A moment is a [DateTime], read on the local clock as the page reads its
/// `Date`.
library;

import 'dart:convert';
import 'dart:typed_data';

/// One file of the archive (`ZipFile`).
class ZipFile {
  const ZipFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// A moment as a zip's MS-DOS time and date, on the local clock, which is what a zip holds: two-second steps, 1980
/// on (`dosTime`). Without one every entry read as 1980-00-00, a date no reader shows sensibly.
({int time, int date}) dosTime(DateTime at) {
  final local = at.toLocal();
  if (local.year < 1980) return (time: 0, date: (1 << 5) | 1);
  return (
    time: (local.hour << 11) | (local.minute << 5) | (local.second >> 1),
    date: ((local.year - 1980) << 9) | (local.month << 5) | local.day,
  );
}

Uint32List? _table;

/// CRC-32, the one zip asks for (`crc32`).
int crc32(List<int> bytes) {
  var table = _table;
  if (table == null) {
    table = Uint32List(256);
    for (var n = 0; n < 256; n += 1) {
      var c = n;
      for (var k = 0; k < 8; k += 1) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      }
      table[n] = c;
    }
    _table = table;
  }
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = table[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

/// The files as one zip, each [dated] (`zipFiles`). Names are written in UTF-8 (the flag says so), so a title in any
/// script survives.
Uint8List zipFiles(List<ZipFile> files, [DateTime? dated]) {
  final (:time, :date) = dosTime(dated ?? DateTime.now());
  final locals = <Uint8List>[];
  final centrals = <Uint8List>[];
  var offset = 0;
  for (final file in files) {
    final name = utf8.encode(file.name);
    final crc = crc32(file.bytes);
    final local = Uint8List(30 + name.length);
    ByteData.sublistView(local)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint16(10, time, Endian.little)
      ..setUint16(12, date, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, file.bytes.length, Endian.little)
      ..setUint32(22, file.bytes.length, Endian.little)
      ..setUint16(26, name.length, Endian.little);
    local.setAll(30, name);
    final central = Uint8List(46 + name.length);
    ByteData.sublistView(central)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(12, time, Endian.little)
      ..setUint16(14, date, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, file.bytes.length, Endian.little)
      ..setUint32(24, file.bytes.length, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central.setAll(46, name);
    locals
      ..add(local)
      ..add(file.bytes);
    centrals.add(central);
    offset += local.length + file.bytes.length;
  }
  final size = centrals.fold<int>(0, (sum, c) => sum + c.length);
  final end = Uint8List(22);
  ByteData.sublistView(end)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, files.length, Endian.little)
    ..setUint16(10, files.length, Endian.little)
    ..setUint32(12, size, Endian.little)
    ..setUint32(16, offset, Endian.little);
  final out = BytesBuilder(copy: false);
  for (final part in [...locals, ...centrals, end]) {
    out.add(part);
  }
  return out.takeBytes();
}
