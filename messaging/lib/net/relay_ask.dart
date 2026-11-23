import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'crypto.dart';
import 'hub_carrier.dart';
import 'hub_link.dart';

/// Why another relay could not be asked ([whoisAt]), in words to show.
class RelayAskError implements Exception {
  RelayAskError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Asks the relay at [url] itself who has the username [name] there (docs/OPEN_NETWORK.md, section 4: "where its own
/// relay doesn't link, the app asks the other relay itself"). A short hub connection, signed in as this install is
/// to its own relay, hidden (nobody watching this install there is told it came): the same `whois` an app asks its
/// own relay, then their home record where that relay keeps them (`home?`). Null where nobody has the name; a
/// [RelayAskError] where the relay could not be asked.
///
/// Signing in to a hub takes what it was keeping for this install: each packet handed over is given to [onPacket] as
/// it comes, with who it is from as that hub vouches, so nothing is lost by having asked.
///
/// Nothing here waits on a clock but [timeout] for the whole of it: a relay from before, which says nothing to
/// `home?`, is known by its answer to the `ping` sent behind it.
Future<({String id, String key, Object? home})?> whoisAt(String url, String name, {required NetSigner signer, HubDial? dial, Duration timeout = const Duration(seconds: 10), void Function(String from, Uint8List packet)? onPacket}) async {
  final HubLink link;
  try {
    link = await (dial ?? dialHub)(url).timeout(timeout);
  } catch (_) {
    throw RelayAskError('That relay couldn\'t be reached.');
  }
  final done = Completer<({String id, String key, Object? home})?>();
  void fail(String why) {
    if (!done.isCompleted) done.completeError(RelayAskError(why));
  }

  var signedIn = false;
  String? id, key;
  final sub = link.said.listen(
    (data) async {
      if (done.isCompleted) return;
      if (data is List<int>) {
        // What that relay kept for this install: `[1][from, 16 bytes][the packet]`.
        if (data.length > 17 && data[0] == 1) onPacket?.call(NetCrypto.hex(data.sublist(1, 17)), Uint8List.fromList(data.sublist(17)));
        return;
      }
      final Map m;
      try {
        m = jsonDecode(data as String) as Map;
      } catch (_) {
        return;
      }
      if (m['hello'] is String && !signedIn) {
        final List<int> sig;
        try {
          sig = await signer.sign([...utf8.encode(HubCarrier.greeting), ...NetCrypto.unhex(m['hello'] as String)]);
        } catch (_) {
          return fail('This device couldn\'t sign in there.');
        }
        if (done.isCompleted) return;
        link.say(jsonEncode({'id': signer.id, 'key': base64Encode(signer.publicKey), 'sig': base64Encode(sig), if (HubCarrier.device.isNotEmpty) 'device': HubCarrier.device, 'mode': 'invisible'}));
      } else if (m.containsKey('ok') && !signedIn) {
        if (m['ok'] != true) return fail('That relay refused this app.');
        signedIn = true;
        link.say(jsonEncode({'dir': 'whois', 'name': name}));
      } else if (m['dir'] == 'whois' && id == null) {
        if (m['none'] == true || m['id'] is! String || m['key'] is! String) return done.complete(null);
        id = m['id'] as String;
        key = m['key'] as String;
        // Their home record, where that relay keeps them; and a ping behind it, whose answer says nothing more comes.
        link.say(jsonEncode({'dir': 'home?', 'a': id}));
        link.say(jsonEncode({'ping': 1}));
      } else if (m['dir'] == 'home?' && id != null && m['a'] == id) {
        done.complete((id: id!, key: key!, home: m['rec']));
      } else if (m.containsKey('pong') && id != null) {
        done.complete((id: id!, key: key!, home: null));
      } else if (m['dir'] == 'err' && (m['about'] == 'whois' || m['about'] == 'home?')) {
        if (id != null) return done.complete((id: id!, key: key!, home: null));
        // A relay with no usernames says so; one that has had too many questions says that.
        fail('${m['err'] ?? 'That relay couldn\'t say.'}');
      }
    },
    onDone: () => fail('That relay closed the connection.'),
    onError: (_) => fail('That relay closed the connection.'),
    cancelOnError: true,
  );
  try {
    return await done.future.timeout(timeout, onTimeout: () => throw RelayAskError('That relay didn\'t answer.'));
  } finally {
    await sub.cancel().catchError((_) {});
    await link.close().timeout(const Duration(seconds: 2)).catchError((_) {});
  }
}
