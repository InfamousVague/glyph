import 'dart:convert';
import 'dart:typed_data';


import 'crypto.dart';
import 'fast_gcm.dart';

/// A Files space's files sealed end to end (Matt, 2026-11-17: "add full functionality for filesharing in a space when
/// the space is designated a Files Space"). The relay keeps them (relay/lib/files.dart) and never has a key to them.
///
/// - Each file has a key of its own (32 random bytes) and is sealed in chunks of [chunk] bytes, each with AES-256-GCM.
///   Chunks let a file go up and come down a piece at a time, without being read into memory whole, pick up where a
///   lost connection stopped, and be fetched from the middle with a Range.
/// - A chunk's nonce is the file's eight random bytes then the chunk's number (four bytes): never the same twice under
///   one key. What each chunk is bound to (the AAD) is the file's id, its number and whether it is the last, so chunks
///   can't be swapped, reordered or a file cut short without its opening failing.
/// - The file's key and those eight bytes travel in its description, which is sealed with the space's own files key
///   ([filesKey]), made from the space's seed: whoever has the space can open its files, and nobody else.
class FileSeal {
  FileSeal._();

  /// The plain bytes in each chunk; each sealed chunk is 16 bytes more (GCM's tag).
  static const chunk = 256 * 1024;
  static const tag = 16;

  static final _label = utf8.encode('ghost-file v1');

  /// The key a space's file descriptions are sealed with, from its seed (64 hex digits).
  static Uint8List filesKey(String seed) => NetCrypto.derive(NetCrypto.unhex(seed), 'files key');

  /// The relay's name for the space's files, and the token to reach them: made from the seed as a hub room's are, under
  /// words of their own, so neither says anything of the space's chat or call.
  static String filesRoom(String seed) => NetCrypto.hex(NetCrypto.derive(NetCrypto.unhex(seed), 'files room').sublist(0, 16));
  static String filesToken(String seed) => NetCrypto.hex(NetCrypto.derive(NetCrypto.unhex(seed), 'files token'));

  /// How many chunks a file of [size] plain bytes is: at least one, so an empty file is one empty sealed chunk.
  static int chunks(int size, {int chunkSize = chunk}) => size <= 0 ? 1 : (size + chunkSize - 1) ~/ chunkSize;

  /// The sealed size of a file of [size] plain bytes.
  static int sealedSize(int size, {int chunkSize = chunk}) => (size < 0 ? 0 : size) + tag * chunks(size, chunkSize: chunkSize);

  /// Where chunk [index] starts in the sealed file.
  static int sealedOffset(int index, {int chunkSize = chunk}) => index * (chunkSize + tag);

  /// The plain length of chunk [index] of a file of [size].
  static int plainLength(int index, int size, {int chunkSize = chunk}) {
    final n = chunks(size, chunkSize: chunkSize);
    if (index < n - 1) return chunkSize;
    return size - (n - 1) * chunkSize;
  }

  static Uint8List _nonce(List<int> prefix, int index) => Uint8List.fromList([...prefix, (index >> 24) & 0xff, (index >> 16) & 0xff, (index >> 8) & 0xff, index & 0xff]);

  static Uint8List _aad(String fileId, int index, bool last) =>
      Uint8List.fromList([..._label, ...NetCrypto.unhex(fileId), (index >> 24) & 0xff, (index >> 16) & 0xff, (index >> 8) & 0xff, index & 0xff, last ? 1 : 0]);

  /// Chunk [index] of a file, sealed: its bytes then GCM's tag.
  static Uint8List sealChunk(List<int> key, List<int> prefix, String fileId, int index, bool last, List<int> plain) {
    // FastGcm: the same bytes as pointycastle's GCM at about ten times the speed (lib/net/fast_gcm.dart).
    return FastGcm(key).seal(_nonce(prefix, index), _aad(fileId, index, last), plain is Uint8List ? plain : Uint8List.fromList(plain));
  }

  /// Chunk [index] opened, or null where it was changed, moved, cut short or sealed under another key.
  static Uint8List? openChunk(List<int> key, List<int> prefix, String fileId, int index, bool last, List<int> sealed) {
    if (sealed.length < tag) return null;
    try {
      return FastGcm(key).open(_nonce(prefix, index), _aad(fileId, index, last), sealed is Uint8List ? sealed : Uint8List.fromList(sealed));
    } catch (_) {
      return null;
    }
  }

  /// Seals chunks [first] onward of [plain] (the plain bytes of those chunks, one after another): what an upload sends
  /// in one piece. Plain data, so it may be run on another isolate.
  static Uint8List sealRun(SealRun run) {
    final n = chunks(run.size, chunkSize: run.chunkSize);
    final out = BytesBuilder(copy: false);
    var at = 0, i = run.first;
    do {
      final len = plainLength(i, run.size, chunkSize: run.chunkSize);
      if (at + len > run.plain.length) throw ArgumentError('chunk $i is short');
      out.add(sealChunk(run.key, run.prefix, run.fileId, i, i == n - 1, Uint8List.sublistView(run.plain, at, at + len)));
      at += len;
      i++;
    } while (at < run.plain.length);
    return out.takeBytes();
  }

  /// Opens chunks [first] onward of [sealed]: null where any fails.
  static Uint8List? openRun(OpenRun run) {
    final out = BytesBuilder(copy: false);
    var at = 0;
    final n = chunks(run.size, chunkSize: run.chunkSize);
    for (var i = run.first; at < run.sealed.length; i++) {
      final len = plainLength(i, run.size, chunkSize: run.chunkSize) + tag;
      if (at + len > run.sealed.length) return null;
      final plain = openChunk(run.key, run.prefix, run.fileId, i, i == n - 1, Uint8List.sublistView(run.sealed, at, at + len));
      if (plain == null) return null;
      out.add(plain);
      at += len;
    }
    return out.takeBytes();
  }
}

/// What [FileSeal.sealRun] needs: plain, so it crosses to another isolate.
class SealRun {
  const SealRun({required this.key, required this.prefix, required this.fileId, required this.size, required this.first, required this.plain, this.chunkSize = FileSeal.chunk});
  final Uint8List key;
  final Uint8List prefix;
  final String fileId;
  final int size;
  final int first;
  final Uint8List plain;
  final int chunkSize;
}

class OpenRun {
  const OpenRun({required this.key, required this.prefix, required this.fileId, required this.size, required this.first, required this.sealed, this.chunkSize = FileSeal.chunk});
  final Uint8List key;
  final Uint8List prefix;
  final String fileId;
  final int size;
  final int first;
  final Uint8List sealed;
  final int chunkSize;
}
