import 'dart:io';

import 'package:flutter/widgets.dart';

import 'link/link.dart';
import 'remote.dart';
import 'store.dart';
import 'updates.dart';

/// Where the relay would be once it is on a server (docs/desktop.md): the address the wizard starts with.
const defaultRelay = 'wss://gogho.st/relay';

/// The Mac app's own parts, handed down to its screens: the link to the phone, what answers the phone's screens,
/// and what is kept on this Mac.
class DeskScope extends InheritedWidget {
  const DeskScope({super.key, required this.link, required this.calls, required this.store, this.envPeers = const [], this.updates, this.relaunch, required super.child});
  final PhoneLink link;

  /// What opens the app again in place of restarting it (restartApp), for a test.
  final Future<void> Function()? relaunch;
  final LinkCalls calls;
  final DeskStore store;

  /// The app's own updates (lib/desktop/updates.dart); null where it looks for none (a test, `GHOST_DESK_UPDATES=off`).
  final MacUpdates? updates;

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

/// Opens this app afresh and closes this copy: how a computer moves between using no phone and using a linked one,
/// since what answers the screens is chosen as it starts (lib/desktop/main.dart). A test passes [relaunch].
Future<void> restartApp({Future<void> Function()? relaunch}) async {
  if (relaunch != null) return relaunch();
  final exe = Platform.resolvedExecutable;
  if (Platform.isMacOS) {
    // The .app the running binary is inside, opened as a new copy.
    final at = exe.indexOf('.app/');
    if (at > 0) await Process.start('open', ['-n', exe.substring(0, at + 4)], mode: ProcessStartMode.detached);
  } else {
    await Process.start(exe, const [], mode: ProcessStartMode.detached);
  }
  exit(0);
}
