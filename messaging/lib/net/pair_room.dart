import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'crypto.dart';
import 'net.dart';

/// A QR code shown on another screen, for a phone that cannot scan its own (Google Messages' Device pairing, Signal's
/// Link new device): a room on Ghost's relay whose name, token and key come from a secret in a link
/// (`https://gogho.st/pair/#<secret>`). The page at that link joins the room and draws each code said in it, sealed
/// with the key, so the relay carries what it cannot read. Made from lib/ui/gm_web_screen.dart's, for Signal too.
class PairRoom {
  // The link's secret, with the room's name and key made from it; the code last said; and the listener for the
  // page joining.
  Uint8List? _secret;
  String? _room;
  Uint8List? _key;
  String? _said;
  StreamSubscription<Object?>? _came;

  /// The page's address, once the room is open.
  String? get link => _secret == null ? null : 'https://gogho.st/pair/#${NetCrypto.hex(_secret!)}';

  bool get open => _room != null;

  /// Opens the room; [onCame] is told when the page joins, so it is given the code as it is now.
  Future<void> openRoom({void Function()? onCame}) async {
    final r = Random.secure();
    final secret = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
    _secret = secret;
    _room = NetCrypto.hex(NetCrypto.derive(secret, 'gmpair room').sublist(0, 16));
    _key = NetCrypto.derive(secret, 'gmpair key');
    final token = NetCrypto.hex(NetCrypto.derive(secret, 'gmpair token'));
    await Net.instance.want('gmpair', true);
    for (var i = 0; i < 20; i++) {
      final hub = Net.instance.hub;
      if (hub != null) {
        try {
          await hub.join(_room!, token);
          break;
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _came = Net.instance.hub?.roomEvents.where((e) => e.room == _room && (e.came?.isNotEmpty ?? false)).listen((_) {
      _said = null;
      onCame?.call();
    });
  }

  /// Draws [url] as the page's QR code (said again only when it changes).
  void showCode(String url) {
    if (url == _said) return;
    if (_say({'t': 'qr', 'url': url})) _said = url;
  }

  /// Tells the page it is done.
  void done() => _say({'t': 'paired'});

  /// Says [m] in the room, sealed with its key; false where there is no room, or the relay can't take it.
  bool _say(Map<String, Object?> m) {
    final room = _room, key = _key, hub = Net.instance.hub;
    if (room == null || key == null || hub == null) return false;
    try {
      hub.sendRoom(room, NetCrypto.seal(key, utf8.encode(jsonEncode(m))));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Leaves the room, and no longer asks for the relay to be kept connected for it.
  void close() {
    _came?.cancel();
    final room = _room;
    if (room != null) Net.instance.hub?.leave(room);
    _room = null;
    _key = null;
    _said = null;
    unawaited(Net.instance.want('gmpair', false));
  }
}
