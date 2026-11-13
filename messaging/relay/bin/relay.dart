import 'dart:io';

import 'package:ghost_relay/relay.dart';

/// `dart run bin/relay.dart [--host 127.0.0.1] [--port 8787] [--data relay-data] [--verbose]`
///
/// Listens on this machine alone unless told otherwise: on a server it sits behind the web server that holds the
/// certificate (README.md).
Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final at = args.indexOf('--$name');
    return at >= 0 && at + 1 < args.length ? args[at + 1] : fallback;
  }

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Ghost Messaging relay\n  --host <address>  where to listen (127.0.0.1)\n  --port <number>   (8787, or \$PORT)\n  --data <folder>   where channels.json is kept (relay-data)\n  --verbose         say when an end joins or leaves (never an address)');
    return;
  }
  final host = option('host', '127.0.0.1');
  final port = int.parse(option('port', Platform.environment['PORT'] ?? '8787'));
  final relay = Relay(dataDir: Directory(option('data', 'relay-data')), verbose: args.contains('--verbose'));
  final got = await relay.start(host: host, port: port);
  stdout.writeln('Ghost Messaging relay listening on ws://$host:$got (${relay.channelCount} pairings kept)');
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await relay.stop();
      exit(0);
    });
  }
}
