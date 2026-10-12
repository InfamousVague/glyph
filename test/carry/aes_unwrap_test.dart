// lib/carry/aes_unwrap.dart against the standards' own published vectors: FIPS 197's appendix C, RFC 3394's
// section 4, and the GCM specification's test cases 2, 4 and 6 (a 96-bit IV, one with associated data, and an IV
// of another length, which is the road an empty IV takes).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/carry/aes_unwrap.dart';

Uint8List hex(String text) => Uint8List.fromList([for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);
String said(Uint8List bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
Uint8List counted(int length) => Uint8List.fromList(List.generate(length, (i) => i));

void main() {
  final block = hex('00112233445566778899aabbccddeeff');

  test('the block cipher, both ways, at each length of key (FIPS 197, appendix C)', () {
    const expected = {16: '69c4e0d86a7b0430d8cdb78070b4c55a', 24: 'dda97ca4864cdfe06eaf70a0ec0d7191', 32: '8ea2b7ca516745bfeafc49904b496089'};
    for (final entry in expected.entries) {
      final aes = Aes(counted(entry.key));
      expect(said(aes.encryptBlock(block)), entry.value);
      expect(said(aes.decryptBlock(hex(entry.value))), said(block));
    }
    expect(() => Aes(Uint8List(15)), throwsArgumentError);
  });

  test('a key unwrapped, and wrapped (RFC 3394, 4.1 and 4.6)', () {
    const short = '1fa68b0a8112b447aef34bd8fb5a7b829d3e862371d2cfe5';
    expect(said(aesKeyWrap(counted(16), block)), short);
    expect(said(aesKeyUnwrap(counted(16), hex(short))!), said(block));
    final long = hex('00112233445566778899aabbccddeeff000102030405060708090a0b0c0d0e0f');
    const wrapped = '28c9f404c4b810f4cbccb35cfb87f8263f5786e2d80ed326cbc7f0e71a99f43bfb988b9b7a02dd21';
    expect(said(aesKeyWrap(counted(32), long)), wrapped);
    expect(said(aesKeyUnwrap(counted(32), hex(wrapped))!), said(long));
  });

  test('a key wrapped under another key, or changed, or not a wrapped key at all, is no key', () {
    final wrapped = hex('1fa68b0a8112b447aef34bd8fb5a7b829d3e862371d2cfe5');
    expect(aesKeyUnwrap(Uint8List(16), wrapped), isNull);
    expect(aesKeyUnwrap(counted(16), Uint8List.fromList(wrapped)..[9] ^= 1), isNull);
    expect(aesKeyUnwrap(counted(16), Uint8List(16)), isNull);
    expect(aesKeyUnwrap(counted(16), Uint8List(25)), isNull);
  });

  group('AES-GCM', () {
    final key = hex('feffe9928665731c6d6a8f9467308308');
    final plain = hex('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39');
    final aad = hex('feedfacedeadbeeffeedfacedeadbeefabaddad2');

    test('zeros under a key of zeros (test case 2)', () {
      final made = aesGcmSeal(Uint8List(16), Uint8List(12), Uint8List(16));
      expect(said(made.sealed), '0388dace60b6a392f328c2b971b2fe78');
      expect(said(made.tag), 'ab6e47d42cec13bdf53a67b21257bddf');
      expect(said(aesGcmOpen(Uint8List(16), Uint8List(12), made.sealed, made.tag)!), '0' * 32);
    });

    test('a 96-bit IV with associated data, and a text that ends inside a block (test case 4)', () {
      final iv = hex('cafebabefacedbaddecaf888');
      const sealed = '42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091';
      const tag = '5bc94fbc3221a5db94fae95ae7121a47';
      final made = aesGcmSeal(key, iv, plain, aad: aad);
      expect(said(made.sealed), sealed);
      expect(said(made.tag), tag);
      expect(said(aesGcmOpen(key, iv, hex(sealed), hex(tag), aad: aad)!), said(plain));
    });

    test('an IV that is not 96 bits is hashed into the first counter (test case 6)', () {
      final iv = hex('9313225df88406e555909c5aff5269aa6a7a9538534f7da1e4c303d2a318a728c3c0c95156809539fcf0e2429a6b525416aedbf5a0de6a57a637b39b');
      const sealed = '8ce24998625615b603a033aca13fb894be9112a5c3a211a8ba262a3cca7e2ca701e4a9a4fba43c90ccdcb281d48c7c6fd62875d2aca417034c34aee5';
      const tag = '619cc5aefffe0bfa462af43c1699d050';
      expect(said(aesGcmOpen(key, iv, hex(sealed), hex(tag), aad: aad)!), said(plain));
    });

    test('an empty IV, as WebKit wraps a stored key: the counter starts from zeros', () {
      // The first block of the stream is then AES of fifteen zeros and a one, which under a key of zeros is the
      // specification's own value for it (test case 1's tag).
      final made = aesGcmSeal(Uint8List(16), Uint8List(0), Uint8List(16));
      expect(said(made.sealed), '58e2fccefa7e3061367f1d57a4e7455a');
      expect(aesGcmOpen(Uint8List(16), Uint8List(0), made.sealed, made.tag), Uint8List(16));
    });

    test('the wrong key, a changed byte, a changed tag or other associated data opens nothing', () {
      final iv = hex('cafebabefacedbaddecaf888');
      final made = aesGcmSeal(key, iv, plain, aad: aad);
      expect(aesGcmOpen(Uint8List(16), iv, made.sealed, made.tag, aad: aad), isNull);
      expect(aesGcmOpen(key, iv, Uint8List.fromList(made.sealed)..[3] ^= 1, made.tag, aad: aad), isNull);
      expect(aesGcmOpen(key, iv, made.sealed, Uint8List.fromList(made.tag)..[15] ^= 1, aad: aad), isNull);
      expect(aesGcmOpen(key, iv, made.sealed, made.tag), isNull);
      expect(aesGcmOpen(key, iv, made.sealed, Uint8List(12), aad: aad), isNull);
    });
  });
}
