import 'dart:io';

import 'package:ghost_relay/accounts.dart';
import 'package:ghost_relay/feedback.dart';
import 'package:ghost_relay/files.dart';
import 'package:ghost_relay/handles.dart';
import 'package:ghost_relay/pushes.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/invites.dart';
import 'package:ghost_relay/invite_words.dart';
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
  final verbose = args.contains('--verbose');
  // The pairings' relay at /relay/<channel>, and the hub people's apps find each other through at /hub.
  // The handles people linked are kept beside the pairings; the networks' sign-ins come from the environment
  // (GHOST_DISCORD_ID and the rest: handles.dart, docs/me.md in the app), and one that is not set is off.
  final data = Directory(option('data', 'relay-data'));
  final handles = Handles(dataDir: data, config: HandlesConfig.fromEnvironment(Platform.environment), verbose: verbose);
  // Waking a closed iPhone (pushes.dart): Apple's key from the environment (GHOST_APNS_KEY_FILE and the rest);
  // without it tokens are kept and nothing is sent.
  final pushes = Pushes(dataDir: data, config: ApnsConfig.fromEnvironment(Platform.environment));
  // Files spaces' sealed files, under the data folder; their limits from the environment (GHOST_FILES_MAX_FILE and the
  // rest: files.dart), each with a default where it is not set.
  final files = Files(dir: Directory('${data.path}/files'), config: FilesConfig.fromEnvironment(Platform.environment), verbose: verbose);
  // Invites waiting for someone not on the app yet, kept by a hash of their number and taken only by the install that
  // verified it (invites.dart; Matt, 2026-11-17: "a link that eventually follows through after they setup their account").
  final invites = Invites(dataDir: data, phoneKeyOf: handles.phoneKeyOf, whoOf: handles.whoOf, verbose: verbose);
  // Ghost accounts' sealed backups, by address (accounts.dart; Matt, 2026-11-17: "We need to have a way to login to
  // existing accounts"): usernames and the texted code for a verified number are handles'.
  final accounts = Accounts(dataDir: data, handles: handles, verbose: verbose);
  // The app's Share feedback, filed in a Notion board (feedback.dart): the integration's secret and the board from the
  // environment (GHOST_NOTION_TOKEN, GHOST_NOTION_FEEDBACK); without them it says it isn't set up.
  final feedback = Feedback(config: FeedbackConfig.fromEnvironment(Platform.environment), ownsName: handles.ownsName, verbose: verbose);
  // Circles' invite words (invite_words.dart): gogho.st/c/<word>.
  final words = InviteWords(dataDir: data);
  final relay = Relay(dataDir: data, verbose: verbose, hub: Hub(verbose: verbose, handles: handles, pushes: pushes, invites: invites, accounts: accounts, words: words), files: files, feedback: feedback);
  final got = await relay.start(host: host, port: port);
  stdout.writeln('Ghost Messaging relay listening on ws://$host:$got (${relay.channelCount} pairings kept; ${handles.linked} handles linked; ${files.spaces} Files spaces; sign-ins: ${handles.ways.entries.where((e) => e.value == 'signin').map((e) => e.key).join(', ').padRight(1, '-')})');
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await relay.stop();
      exit(0);
    });
  }
}
