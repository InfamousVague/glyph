import 'dart:io';

import 'package:flutter/widgets.dart';

import 'link/link.dart';
import 'remote.dart';
import 'store.dart';

/// Where the relay would be once it is on a server (docs/desktop.md): the address the wizard starts with.
const defaultRelay = 'wss://ghost-sms.com/relay';

/// The Mac app's own parts, handed down to its screens: the link to the phone, what answers the phone's screens,
/// and what is kept on this Mac.
class DeskScope extends InheritedWidget {
  const DeskScope({super.key, required this.link, required this.calls, required this.store, this.envPeers = const [], required super.child});
  final PhoneLink link;
  final LinkCalls calls;
  final DeskStore store;

  /// Addresses for the phone given as the app was started (GHOST_DESK_PEERS), kept beside one given in Settings.
  final List<Peer> envPeers;

  static DeskScope of(BuildContext context) => context.getInheritedWidgetOfExactType<DeskScope>()!;

  @override
  bool updateShouldNotify(DeskScope old) => false;
}

/// Whether a relay answers at [relay]: asked the way a browser would, where the relay says what it is.
Future<bool> relayAnswers(String relay) async {
  final uri = Uri.tryParse(relay.trim());
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'ws' && uri.scheme != 'wss')) return false;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  try {
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    final request = await client.getUrl(uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http', path: path)).timeout(const Duration(seconds: 5));
    final response = await request.close().timeout(const Duration(seconds: 5));
    final body = await response.take(1).map(String.fromCharCodes).join().timeout(const Duration(seconds: 5));
    return response.statusCode == 200 && body.contains('Ghost Messaging relay');
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
