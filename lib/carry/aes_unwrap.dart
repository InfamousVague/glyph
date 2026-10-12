/// AES, as much as opening what WebKit wrapped needs (lib/carry/webkit_stores.dart): the block cipher both ways,
/// RFC 3394's key unwrap, and AES-GCM's opening with its tag checked.
///
/// Why it is written out here: the app's own crypto is the Rust core's (`seal`, `open`), which speaks only the
/// app's sealed form, and what WebKit wrote is its own: a key wrapped by RFC 3394, then AES-128-GCM with an empty
/// IV. It runs once, on the first launch over the Tauri Mac app, over a few hundred bytes, so it is written to be
/// read and checked (test/carry/aes_unwrap_test.dart: FIPS 197, RFC 3394 and GCM's published vectors), not to be
/// fast or to keep its timing even. Nothing here is used to seal anything the app keeps; [aesKeyWrap] and
/// [aesGcmSeal] exist for the tests, which make storage as WebKit makes it.
library;

import 'dart:typed_data';

/// The AES block cipher under one key of 16, 24 or 32 bytes.
class Aes {
  Aes(Uint8List key) : _rounds = key.length ~/ 4 + 6 {
    if (key.length != 16 && key.length != 24 && key.length != 32) throw ArgumentError('An AES key is 16, 24 or 32 bytes.');
    final words = key.length ~/ 4;
    final total = 4 * (_rounds + 1);
    _schedule = Uint8List(total * 4)..setAll(0, key);
    var rcon = 1;
    for (var i = words; i < total; i += 1) {
      var a = _schedule[(i - 1) * 4], b = _schedule[(i - 1) * 4 + 1], c = _schedule[(i - 1) * 4 + 2], d = _schedule[(i - 1) * 4 + 3];
      if (i % words == 0) {
        final first = a;
        a = _sbox[b] ^ rcon;
        b = _sbox[c];
        c = _sbox[d];
        d = _sbox[first];
        rcon = _double(rcon);
      } else if (words > 6 && i % words == 4) {
        a = _sbox[a];
        b = _sbox[b];
        c = _sbox[c];
        d = _sbox[d];
      }
      _schedule[i * 4] = _schedule[(i - words) * 4] ^ a;
      _schedule[i * 4 + 1] = _schedule[(i - words) * 4 + 1] ^ b;
      _schedule[i * 4 + 2] = _schedule[(i - words) * 4 + 2] ^ c;
      _schedule[i * 4 + 3] = _schedule[(i - words) * 4 + 3] ^ d;
    }
  }

  final int _rounds;
  late final Uint8List _schedule;

  static final Uint8List _sbox = _makeSbox();
  static final Uint8List _inverse = () {
    final out = Uint8List(256);
    for (var i = 0; i < 256; i += 1) {
      out[_sbox[i]] = i;
    }
    return out;
  }();

  /// The S-box from its definition: the inverse in GF(2^8), then the affine map.
  static Uint8List _makeSbox() {
    final out = Uint8List(256);
    var p = 1, q = 1;
    do {
      // p runs over every non-zero element (times 3); q is its inverse (divided by 3).
      p = (p ^ _double(p)) & 0xff;
      q ^= q << 1;
      q ^= q << 2;
      q ^= q << 4;
      q &= 0xff;
      if (q & 0x80 != 0) q ^= 0x09;
      final rotated = q ^ _rotl(q, 1) ^ _rotl(q, 2) ^ _rotl(q, 3) ^ _rotl(q, 4);
      out[p] = (rotated ^ 0x63) & 0xff;
    } while (p != 1);
    out[0] = 0x63;
    return out;
  }

  static int _rotl(int value, int by) => ((value << by) | (value >> (8 - by))) & 0xff;

  /// Times two in GF(2^8).
  static int _double(int value) => ((value << 1) ^ (value & 0x80 != 0 ? 0x1b : 0)) & 0xff;

  static int _times(int value, int by) {
    var out = 0, a = value, b = by;
    while (b != 0) {
      if (b & 1 != 0) out ^= a;
      a = _double(a);
      b >>= 1;
    }
    return out;
  }

  void _addKey(Uint8List state, int round) {
    for (var i = 0; i < 16; i += 1) {
      state[i] ^= _schedule[round * 16 + i];
    }
  }

  /// One block of 16 bytes, enciphered.
  Uint8List encryptBlock(Uint8List block) {
    if (block.length != 16) throw ArgumentError('An AES block is 16 bytes.');
    final state = Uint8List.fromList(block);
    final moved = Uint8List(16);
    _addKey(state, 0);
    for (var round = 1; round <= _rounds; round += 1) {
      // SubBytes and ShiftRows: row r of column c comes from column c + r.
      for (var c = 0; c < 4; c += 1) {
        for (var r = 0; r < 4; r += 1) {
          moved[c * 4 + r] = _sbox[state[((c + r) % 4) * 4 + r]];
        }
      }
      if (round < _rounds) {
        for (var c = 0; c < 4; c += 1) {
          final a = moved[c * 4], b = moved[c * 4 + 1], d = moved[c * 4 + 2], e = moved[c * 4 + 3];
          state[c * 4] = _double(a) ^ _double(b) ^ b ^ d ^ e;
          state[c * 4 + 1] = a ^ _double(b) ^ _double(d) ^ d ^ e;
          state[c * 4 + 2] = a ^ b ^ _double(d) ^ _double(e) ^ e;
          state[c * 4 + 3] = _double(a) ^ a ^ b ^ d ^ _double(e);
        }
      } else {
        state.setAll(0, moved);
      }
      _addKey(state, round);
    }
    return state;
  }

  /// One block of 16 bytes, deciphered.
  Uint8List decryptBlock(Uint8List block) {
    if (block.length != 16) throw ArgumentError('An AES block is 16 bytes.');
    final state = Uint8List.fromList(block);
    final moved = Uint8List(16);
    _addKey(state, _rounds);
    for (var round = _rounds - 1; round >= 0; round -= 1) {
      // InvShiftRows and InvSubBytes: row r of column c comes from column c - r.
      for (var c = 0; c < 4; c += 1) {
        for (var r = 0; r < 4; r += 1) {
          moved[c * 4 + r] = _inverse[state[((c - r + 4) % 4) * 4 + r]];
        }
      }
      state.setAll(0, moved);
      _addKey(state, round);
      if (round > 0) {
        for (var c = 0; c < 4; c += 1) {
          final a = state[c * 4], b = state[c * 4 + 1], d = state[c * 4 + 2], e = state[c * 4 + 3];
          state[c * 4] = _times(a, 14) ^ _times(b, 11) ^ _times(d, 13) ^ _times(e, 9);
          state[c * 4 + 1] = _times(a, 9) ^ _times(b, 14) ^ _times(d, 11) ^ _times(e, 13);
          state[c * 4 + 2] = _times(a, 13) ^ _times(b, 9) ^ _times(d, 14) ^ _times(e, 11);
          state[c * 4 + 3] = _times(a, 11) ^ _times(b, 13) ^ _times(d, 9) ^ _times(e, 14);
        }
      }
    }
    return state;
  }
}

final Uint8List _wrapIv = Uint8List.fromList(List.filled(8, 0xa6));

/// RFC 3394: [wrapped] opened under [kek], or null when it was not wrapped under that key (the check value it
/// ends on is not the standard's) or is not a wrapped key at all.
Uint8List? aesKeyUnwrap(Uint8List kek, Uint8List wrapped) {
  if (wrapped.length < 24 || wrapped.length % 8 != 0) return null;
  final aes = Aes(kek);
  final n = wrapped.length ~/ 8 - 1;
  final a = Uint8List.fromList(Uint8List.sublistView(wrapped, 0, 8));
  final r = Uint8List.fromList(Uint8List.sublistView(wrapped, 8));
  final block = Uint8List(16);
  for (var j = 5; j >= 0; j -= 1) {
    for (var i = n; i >= 1; i -= 1) {
      final t = n * j + i;
      block.setAll(0, a);
      for (var k = 0; k < 8; k += 1) {
        block[7 - k] ^= (t >> (8 * k)) & 0xff;
      }
      block.setRange(8, 16, r, (i - 1) * 8);
      final out = aes.decryptBlock(block);
      a.setRange(0, 8, out);
      r.setRange((i - 1) * 8, i * 8, out, 8);
    }
  }
  var wrong = 0;
  for (var i = 0; i < 8; i += 1) {
    wrong |= a[i] ^ _wrapIv[i];
  }
  return wrong == 0 ? r : null;
}

/// RFC 3394: [key] (a multiple of 8 bytes, 16 or more) wrapped under [kek]. For the tests' own storage.
Uint8List aesKeyWrap(Uint8List kek, Uint8List key) {
  if (key.length < 16 || key.length % 8 != 0) throw ArgumentError('A key to wrap is 16 bytes or more, in eights.');
  final aes = Aes(kek);
  final n = key.length ~/ 8;
  final a = Uint8List.fromList(_wrapIv);
  final r = Uint8List.fromList(key);
  final block = Uint8List(16);
  for (var j = 0; j <= 5; j += 1) {
    for (var i = 1; i <= n; i += 1) {
      block.setAll(0, a);
      block.setRange(8, 16, r, (i - 1) * 8);
      final out = aes.encryptBlock(block);
      final t = n * j + i;
      a.setRange(0, 8, out);
      for (var k = 0; k < 8; k += 1) {
        a[7 - k] ^= (t >> (8 * k)) & 0xff;
      }
      r.setRange((i - 1) * 8, i * 8, out, 8);
    }
  }
  return Uint8List(8 + r.length)
    ..setAll(0, a)
    ..setAll(8, r);
}

/// GF(2^128) as GCM has it: [x] times [h], both 16 bytes, bit 0 the highest of the first byte.
Uint8List _gcmTimes(Uint8List x, Uint8List h) {
  final z = Uint8List(16);
  final v = Uint8List.fromList(h);
  for (var i = 0; i < 128; i += 1) {
    if (x[i >> 3] & (0x80 >> (i & 7)) != 0) {
      for (var k = 0; k < 16; k += 1) {
        z[k] ^= v[k];
      }
    }
    final low = v[15] & 1;
    for (var k = 15; k > 0; k -= 1) {
      v[k] = (v[k] >> 1) | ((v[k - 1] & 1) << 7);
    }
    v[0] >>= 1;
    if (low != 0) v[0] ^= 0xe1;
  }
  return z;
}

class _Ghash {
  _Ghash(this._h);

  final Uint8List _h;
  Uint8List _y = Uint8List(16);

  /// Takes [bytes] in, padded with zeros to a whole block.
  void add(Uint8List bytes) {
    for (var at = 0; at < bytes.length; at += 16) {
      final end = at + 16 < bytes.length ? at + 16 : bytes.length;
      for (var k = at; k < end; k += 1) {
        _y[k - at] ^= bytes[k];
      }
      _y = _gcmTimes(_y, _h);
    }
  }

  /// The closing block: two lengths in bits, eight bytes each.
  void lengths(int first, int second) {
    final block = ByteData(16)
      ..setUint64(0, first * 8)
      ..setUint64(8, second * 8);
    add(block.buffer.asUint8List());
  }

  Uint8List get value => _y;
}

({Uint8List text, Uint8List tag}) _gcm(Uint8List key, Uint8List iv, Uint8List input, Uint8List aad, {required bool sealing}) {
  final aes = Aes(key);
  final h = aes.encryptBlock(Uint8List(16));
  // The first counter block: the IV and a one for an IV of twelve bytes, GHASH of it for any other length. An
  // empty IV, which is what WebKit's wrap uses, comes to sixteen zeros.
  Uint8List j0;
  if (iv.length == 12) {
    j0 = Uint8List(16)
      ..setAll(0, iv)
      ..[15] = 1;
  } else {
    final hash = _Ghash(h)
      ..add(iv)
      ..lengths(0, iv.length);
    j0 = Uint8List.fromList(hash.value);
  }
  final counter = Uint8List.fromList(j0);
  final out = Uint8List(input.length);
  for (var at = 0; at < input.length; at += 16) {
    for (var k = 15; k >= 12; k -= 1) {
      counter[k] = (counter[k] + 1) & 0xff;
      if (counter[k] != 0) break;
    }
    final stream = aes.encryptBlock(counter);
    for (var k = at; k < input.length && k < at + 16; k += 1) {
      out[k] = input[k] ^ stream[k - at];
    }
  }
  final hash = _Ghash(h)
    ..add(aad)
    ..add(sealing ? out : input)
    ..lengths(aad.length, input.length);
  final mask = aes.encryptBlock(j0);
  final tag = Uint8List(16);
  for (var k = 0; k < 16; k += 1) {
    tag[k] = hash.value[k] ^ mask[k];
  }
  return (text: out, tag: tag);
}

/// AES-GCM: [sealed] opened under [key] with [iv] (of any length, none included) and [aad], or null when [tag]
/// (16 bytes) is not the one those give: the wrong key, or bytes that were changed.
Uint8List? aesGcmOpen(Uint8List key, Uint8List iv, Uint8List sealed, Uint8List tag, {Uint8List? aad}) {
  if (tag.length != 16) return null;
  final made = _gcm(key, iv, sealed, aad ?? Uint8List(0), sealing: false);
  var wrong = 0;
  for (var k = 0; k < 16; k += 1) {
    wrong |= made.tag[k] ^ tag[k];
  }
  return wrong == 0 ? made.text : null;
}

/// AES-GCM: [plain] sealed under [key], with its tag. For the tests' own storage.
({Uint8List sealed, Uint8List tag}) aesGcmSeal(Uint8List key, Uint8List iv, Uint8List plain, {Uint8List? aad}) {
  final made = _gcm(key, iv, plain, aad ?? Uint8List(0), sealing: true);
  return (sealed: made.text, tag: made.tag);
}
