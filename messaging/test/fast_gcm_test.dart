import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/fast_gcm.dart';
import 'package:ghost_messaging/net/file_seal.dart';
import 'package:pointycastle/export.dart';

/// FastGcm against pointycastle's GCM, byte for byte (Matt, 2026-11-18, of uploading to a circle being slow): every
/// file already sealed opens with it, and what it seals opens with the old code.
void main() {
  final rnd = Random(42);
  Uint8List bytes(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) rnd.nextInt(256)]);
  Uint8List pc(bool seal, Uint8List key, Uint8List nonce, Uint8List aad, Uint8List data) =>
      (GCMBlockCipher(AESEngine())..init(seal, AEADParameters(KeyParameter(key), 128, nonce, aad))).process(data);

  test('the same sealed bytes as pointycastle, every length around a block, and it opens what pointycastle seals', () {
    for (final n in [0, 1, 15, 16, 17, 31, 32, 33, 100, 1000, 4095, 4096, 65536, 262144]) {
      for (final aadLen in [0, 13, 16, 41]) {
        final key = bytes(32), nonce = bytes(12), aad = bytes(aadLen), plain = bytes(n);
        final theirs = pc(true, key, nonce, aad, plain);
        final ours = FastGcm(key).seal(nonce, aad, plain);
        expect(ours, theirs, reason: 'length $n, aad $aadLen');
        expect(FastGcm(key).open(nonce, aad, theirs), plain);
        expect(pc(false, key, nonce, aad, ours), plain);
      }
    }
  });

  test('a changed byte, a wrong aad or a wrong key is refused', () {
    final key = bytes(32), nonce = bytes(12), aad = bytes(20), plain = bytes(5000);
    final sealed = FastGcm(key).seal(nonce, aad, plain);
    final bent = Uint8List.fromList(sealed)..[1234] ^= 1;
    expect(FastGcm(key).open(nonce, aad, bent), isNull);
    expect(FastGcm(key).open(nonce, bytes(20), sealed), isNull);
    expect(FastGcm(bytes(32)).open(nonce, aad, sealed), isNull);
    expect(FastGcm(key).open(nonce, aad, Uint8List.sublistView(sealed, 0, sealed.length - 1)), isNull);
  });

  test('a Files run seals and opens as before', () {
    final key = bytes(32), prefix = bytes(8), id = 'ab' * 16;
    final size = FileSeal.chunk * 2 + 777;
    final plain = bytes(size);
    final sealed = FileSeal.sealRun(SealRun(key: key, prefix: prefix, fileId: id, size: size, first: 0, plain: plain));
    expect(sealed.length, FileSeal.sealedSize(size));
    expect(FileSeal.openRun(OpenRun(key: key, prefix: prefix, fileId: id, size: size, first: 0, sealed: sealed)), plain);
  });
}
