import 'dart:convert';
import 'dart:typed_data';

import '../crypto.dart';

/// What two devices on one network say to find each other and to prove whose they are (lan_carrier.dart): the beacon
/// said to everyone, and the knock, the proofs and the keys of a link. All of it is made from the key two accounts
/// already seal their packets with (Peer.key), so only their devices can make or recognise any of it, and nobody else
/// on the network learns who is here: no name, no account, nothing that stays the same from one ten minutes to the
/// next.
///
/// Every mark names who is saying it to whom, in that order. Both accounts of a pair hold the pair's key, so a mark
/// without them would show only "holds the key", and two devices of one account would take each other for the friend
/// (the direct route's second review found the same of its proof, S2).
abstract final class LanWords {
  /// The key a pair's local network marks are made with: from what they seal packets with, for nothing else.
  static Uint8List keyOf(List<int> pairKey) => NetCrypto.derive(pairKey, 'lan');

  /// The ten minutes [at] (ms) falls in: what a beacon's marks are good for, the one before and the one after.
  static int bucketOf(int at) => at ~/ (10 * 60 * 1000);

  static List<int> _n32(int n) => [(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
  static List<int> _n16(int n) => [(n >> 8) & 0xff, n & 0xff];

  /// The mark in a beacon that says "[from]'s device is here" to [to]'s devices, and to nobody else: eight bytes that
  /// change with the ten minutes, the device's run ([instance]) and its door's [port].
  static Uint8List mark(List<int> key, {required String from, required String to, required int bucket, required List<int> instance, required int port}) =>
      NetCrypto.hmac(key, [...utf8.encode('ghost-lan beacon v1\n'), ...NetCrypto.unhex(from), ...NetCrypto.unhex(to), ..._n32(bucket), ...instance, ..._n16(port)]).sublist(0, markLength);
  static const markLength = 8;

  /// What a device that connects says first, to the one device it means: sixteen bytes only a device of [from] could
  /// make for a device of [to], for this connection alone ([nonce]).
  static Uint8List knock(List<int> key, {required String from, required String to, required List<int> dialer, required List<int> listener, required List<int> nonce, required int bucket}) =>
      NetCrypto.hmac(key, [...utf8.encode('ghost-lan knock v1\n'), ...NetCrypto.unhex(from), ...NetCrypto.unhex(to), ...dialer, ...listener, ...nonce, ..._n32(bucket)]).sublist(0, knockLength);
  static const knockLength = 16;

  /// Everything two ends of a link said before proving: who connects to whom, each device's run, and each end's nonce.
  static Uint8List transcript({required String dialerAccount, required String listenerAccount, required List<int> dialer, required List<int> listener, required List<int> dialerNonce, required List<int> listenerNonce}) =>
      Uint8List.fromList([...NetCrypto.unhex(dialerAccount), ...NetCrypto.unhex(listenerAccount), ...dialer, ...listener, ...dialerNonce, ...listenerNonce]);

  /// Each end's proof that it holds the pair's key, over [transcript]: the listener's ([dialing] false) and the
  /// dialler's.
  static Uint8List proof(List<int> key, Uint8List transcript, {required bool dialing}) => NetCrypto.hmac(key, [...utf8.encode('ghost-lan link v1 ${dialing ? 'd' : 'l'}\n'), ...transcript]);

  /// What one end seals everything it sends on the link with, made for this link alone: the dialler's ([dialing]) and
  /// the listener's are two keys.
  static Uint8List sealKey(List<int> key, Uint8List transcript, {required bool dialing}) => NetCrypto.hmac(key, [...utf8.encode('ghost-lan key v1 ${dialing ? 'd' : 'l'}\n'), ...transcript]);

  /// Whether [a] and [b] are the same bytes, in the same time whatever they are.
  static bool same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}

/// A beacon: what a device says to everyone on the network every few seconds. It names nobody: the run of the app it
/// came from ([instance], random each start), the port its door is at, which ten minutes its marks are for, and marks,
/// each of which one account's devices can recognise ([LanWords.mark]) and the rest take for noise.
///
///     "GL" [1] [instance: 8] [port: 2] [bucket: 4] [how many: 1] [marks: 8 each]
class LanBeacon {
  const LanBeacon({required this.instance, required this.port, required this.bucket, required this.marks});
  final Uint8List instance;
  final int port, bucket;
  final List<Uint8List> marks;

  static const instanceLength = 8;

  /// The most marks in one beacon; a device with more people than that names a different lot of them each time.
  static const mostMarks = 48;

  /// Marks are made up to a multiple of this with noise, so how many there are says little of how many friends the
  /// device has.
  static const padTo = 8;

  static const _magic = [0x47, 0x4c, 1];
  static const _head = 3 + instanceLength + 2 + 4 + 1;

  Uint8List encode() {
    final out = BytesBuilder();
    out.add(_magic);
    out.add(instance);
    out.add([(port >> 8) & 0xff, port & 0xff]);
    out.add([(bucket >> 24) & 0xff, (bucket >> 16) & 0xff, (bucket >> 8) & 0xff, bucket & 0xff]);
    out.addByte(marks.length);
    for (final m in marks) {
      out.add(m);
    }
    return out.toBytes();
  }

  /// What [bytes] says, or null where it is no beacon of this kind.
  static LanBeacon? decode(Uint8List bytes) {
    if (bytes.length < _head || bytes[0] != _magic[0] || bytes[1] != _magic[1] || bytes[2] != _magic[2]) return null;
    final count = bytes[_head - 1];
    if (count > mostMarks || bytes.length != _head + count * LanWords.markLength) return null;
    final d = ByteData.sublistView(bytes);
    final port = d.getUint16(3 + instanceLength);
    if (port == 0) return null;
    return LanBeacon(
      instance: Uint8List.sublistView(bytes, 3, 3 + instanceLength),
      port: port,
      bucket: d.getUint32(3 + instanceLength + 2),
      marks: [for (var i = 0; i < count; i++) Uint8List.sublistView(bytes, _head + i * LanWords.markLength, _head + (i + 1) * LanWords.markLength)],
    );
  }
}
