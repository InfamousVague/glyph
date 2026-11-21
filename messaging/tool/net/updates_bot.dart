import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/circles/circle.dart';
import 'package:ghost_messaging/circles/circles.dart' show CircleRoom;
import 'package:ghost_messaging/circles/welcome.dart' show readOnlyRoomOf;
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/voice/hangout.dart';
import 'package:ghost_messaging/voice/voice.dart';

/// "Ghost Bugfixes": an identity of its own that posts the progress of bug fixes in the Alpha testers circle's Updates
/// space (Matt, 2026-11-21: "add a updates channel only admins can post to in the alpha testers and post progerss of
/// bugfixes there", then "A bot identity"). Run as the live relay checks are:
///
///     flutter test tool/net/updates_bot.dart --dart-define=DO=whoami
///     flutter test tool/net/updates_bot.dart --dart-define=DO=join --dart-define=LINK='https://gogho.st/join/#c.…'
///     flutter test tool/net/updates_bot.dart --dart-define=DO=check   (whether SPACE is read-only and the bot an admin)
///     flutter test tool/net/updates_bot.dart --dart-define=DO=post --dart-define=SPACE=Updates --dart-define=TEXT_FILE=/path/words.txt
///
/// Its key and the circle it is in are kept in ~/.config/mattssoftware/ghost-updates-bot.json, readable by this Mac's
/// user alone, never in the repository (which is public). `join` comes into the circle from an invite link and says it
/// joined, so it is in Members, where the owner makes it an admin; `post` writes in the read-only space named SPACE,
/// which the relay takes from the owner and admins alone.
const doing = String.fromEnvironment('DO', defaultValue: 'whoami');
const link = String.fromEnvironment('LINK');
const spaceName = String.fromEnvironment('SPACE', defaultValue: 'Updates');
const textFile = String.fromEnvironment('TEXT_FILE');
const hub = String.fromEnvironment('HUB', defaultValue: 'wss://gogho.st/hub');
const botName = 'Ghost Bugfixes';

File get _saved => File('${Platform.environment['HOME']}/.config/mattssoftware/ghost-updates-bot.json');

Map<String, dynamic> _read() => _saved.existsSync() ? (jsonDecode(_saved.readAsStringSync()) as Map).cast<String, dynamic>() : {};

void _write(Map<String, dynamic> m) {
  _saved.parent.createSync(recursive: true);
  _saved.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(m));
  Process.runSync('chmod', ['600', _saved.path]);
}

NetKeys _keys() {
  final saved = _read();
  if (saved['key'] is String) return NetKeys.fromScalar(NetCrypto.unhex(saved['key'] as String));
  final keys = NetKeys.generate();
  _write({...saved, 'key': NetCrypto.hex(keys.scalar)});
  return keys;
}

Future<HubCarrier> _connect(NetKeys keys) async {
  final c = HubCarrier(url: hub, signer: KeysSigner(keys));
  await c.start();
  for (var i = 0; i < 400 && c.state.value != CarrierState.up; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  if (c.state.value != CarrierState.up) throw StateError(c.problem ?? 'the relay did not answer');
  return c;
}

/// The circle as its room says it now: the newest manifest any member hands over, or what the saved link said.
Future<(Circle, CircleRoom)> _circle(HubVoiceRoute route, Circle from) async {
  var circle = from;
  final got = Completer<void>();
  late final CircleRoom room;
  room = CircleRoom(
    circle: circle,
    route: route,
    onManifest: (c, m) {
      final next = c.merged(m);
      if (next != null) {
        circle = next;
        room.circle = next;
      }
      if (!got.isCompleted) got.complete();
    },
  );
  await room.open();
  await got.future.timeout(const Duration(seconds: 12), onTimeout: () {});
  return (circle, room);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A store of the app's that asks the phone: no phone here.
  setUpAll(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (_) async => null));

  test('Ghost Bugfixes: $doing', () async {
    final keys = _keys();
    stdout.writeln('ghost-updates-bot: id ${keys.id}');
    if (doing == 'whoami') return;

    final saved = _read();
    final carrier = await _connect(keys);
    final route = HubVoiceRoute(carrier);
    try {
      if (doing == 'join') {
        final c = Circle.fromLink(link);
        if (c == null) fail('LINK is not a circle\'s invite link');
        final (circle, room) = await _circle(route, c);
        room.sayJoined(botName, DateTime.now().millisecondsSinceEpoch);
        await Future<void>.delayed(const Duration(seconds: 2));
        await room.close();
        _write({...saved, 'link': link});
        stdout.writeln('ghost-updates-bot: joined "${circle.manifest.name}" (${circle.spaces.length} spaces: ${circle.spaces.map((s) => s.name).join(', ')})');
        return;
      }
      if (doing == 'post' || doing == 'check') {
        final words = textFile.isEmpty ? '' : File(textFile).readAsStringSync().trim();
        if (words.isEmpty && doing == 'post') fail('TEXT_FILE says nothing');
        final from = Circle.fromLink(saved['link'] as String? ?? '');
        if (from == null) fail('not in a circle yet: DO=join first');
        final (circle, room) = await _circle(route, from);
        await room.close();
        final space = circle.spaces.where((s) => s.name.toLowerCase() == spaceName.toLowerCase()).firstOrNull;
        if (space == null) fail('no space "$spaceName" in ${circle.manifest.name}: ${circle.spaces.map((s) => s.name).join(', ')}');
        final ro = readOnlyRoomOf(circle.manifest, space);
        final isAdmin = circle.manifest.adminGrants.containsKey(keys.id) || circle.manifest.owner == NetCrypto.hex(keys.public);
        stdout.writeln('ghost-updates-bot: "${space.name}" is ${ro == null ? 'not read-only' : 'read-only'}; this bot is ${isAdmin ? 'an admin' : 'NOT an admin'}');
        if (doing == 'check') return;
        // A read-only space takes the owner's and admins' words alone: anything else the relay drops without a word.
        if (ro != null && !isAdmin) fail('not an admin of ${circle.manifest.name} yet, so "${space.name}" would drop it');
        final chat = HangoutRoom(channel: circle.channelOf(space), route: route, name: botName, signer: KeysSigner(keys), store: MemoryHangoutStore());
        await chat.setReadOnly(ro);
        await chat.open();
        await Future<void>.delayed(const Duration(seconds: 1));
        final ok = chat.send(words);
        await Future<void>.delayed(const Duration(seconds: 2));
        await chat.close();
        expect(ok, isTrue, reason: 'the room would not take it here (may this identity write in "${space.name}"?)');
        stdout.writeln('ghost-updates-bot: posted ${words.length} characters to "${space.name}"');
      }
    } finally {
      await carrier.stop();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
