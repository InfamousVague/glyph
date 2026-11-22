import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/circles/circle.dart';
import 'package:ghost_messaging/circles/circles.dart' show CircleRoom;
import 'package:ghost_messaging/circles/welcome.dart' show readOnlyRoomOf;
import 'package:ghost_messaging/mentions.dart';
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
///     flutter test tool/net/updates_bot.dart --dart-define=DO=read    (the last few messages in SPACE, as the relay keeps them)
///     flutter test tool/net/updates_bot.dart --dart-define=DO=check   (whether SPACE is read-only and the bot an admin)
///     flutter test tool/net/updates_bot.dart --dart-define=DO=post --dart-define=SPACE=Updates --dart-define=TEXT_FILE=/path/words.txt
///     flutter test tool/net/updates_bot.dart --dart-define=DO=edit --dart-define=MATCH='Round two' --dart-define=TEXT_FILE=/path/words.txt
///
/// `edit` changes the bot's own newest message in SPACE whose words begin with MATCH (Matt, 2026-11-21: "Edit or re post
/// your messages to credit each person with an @mention"). WHO='kevin=<ghost id>,jerbo=<ghost id>' makes each "@kevin"
/// in the words a mention of that id, in a post or an edit; an edit changes the words but notifies nobody.
///
/// Its key and the circle it is in are kept in ~/.config/mattssoftware/ghost-updates-bot.json, readable by this Mac's
/// user alone, never in the repository (which is public). `join` comes into the circle from an invite link and says it
/// joined, so it is in Members, where the owner makes it an admin; `post` writes in the read-only space named SPACE,
/// which the relay takes from the owner and admins alone.
const doing = String.fromEnvironment('DO', defaultValue: 'whoami');
const link = String.fromEnvironment('LINK');
const spaceName = String.fromEnvironment('SPACE', defaultValue: 'Updates');
const textFile = String.fromEnvironment('TEXT_FILE');
const match = String.fromEnvironment('MATCH');
const who = String.fromEnvironment('WHO');
const hub = String.fromEnvironment('HUB', defaultValue: 'wss://gogho.st/hub');
const botName = 'Ghost Bugfixes';

File get _saved => File('${Platform.environment['HOME']}/.config/mattssoftware/ghost-updates-bot.json');

Map<String, dynamic> _read() => _saved.existsSync() ? (jsonDecode(_saved.readAsStringSync()) as Map).cast<String, dynamic>() : {};

void _write(Map<String, dynamic> m) {
  _saved.parent.createSync(recursive: true);
  _saved.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(m));
  Process.runSync('chmod', ['600', _saved.path]);
}

/// Each "@name" in [words] whose name WHO gives an id for, as a mention of that id.
List<Mention> _mentions(String words) {
  final ids = {
    for (final pair in who.split(',').where((x) => x.contains('=')))
      pair.split('=').first.trim().replaceFirst('@', '').toLowerCase(): pair.split('=').last.trim(),
  };
  return [
    for (final m in RegExp(r'@([A-Za-z0-9_.]+)').allMatches(words))
      if (ids[m.group(1)!.toLowerCase()] case final id?) Mention(m.start, m.end - m.start, id),
  ];
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
  // Every device with a newer one may answer, the lowest id first: listen a while longer and keep the newest.
  await Future<void>.delayed(const Duration(seconds: 5));
  stdout.writeln('ghost-updates-bot: circle at version ${circle.manifest.version}, admin list ${circle.manifest.grantsVersion} (${circle.manifest.adminGrants.length} admins)');
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
      if (doing == 'post' || doing == 'check' || doing == 'read' || doing == 'edit') {
        final words = textFile.isEmpty ? '' : File(textFile).readAsStringSync().trim();
        if (words.isEmpty && (doing == 'post' || doing == 'edit')) fail('TEXT_FILE says nothing');
        if (doing == 'edit' && match.isEmpty) fail('MATCH names nothing to edit');
        final from = Circle.fromLink(saved['link'] as String? ?? '');
        if (from == null) fail('not in a circle yet: DO=join first');
        final (circle, room) = await _circle(route, from);
        await room.close();
        final space = circle.spaces.where((s) => s.name.toLowerCase() == spaceName.toLowerCase()).firstOrNull;
        if (space == null) fail('no space "$spaceName" in ${circle.manifest.name}: ${circle.spaces.map((s) => s.name).join(', ')}');
        final ro = readOnlyRoomOf(circle.manifest, space);
        final isAdmin = circle.manifest.adminGrants.containsKey(keys.id) || circle.manifest.owner == NetCrypto.hex(keys.public);
        stdout.writeln('ghost-updates-bot: "${space.name}" is ${ro == null ? 'not read-only' : 'read-only'}; this bot is ${isAdmin ? 'an admin' : 'NOT an admin'}');
        stdout.writeln('ghost-updates-bot: its roles here: ${circle.manifest.rolesOf(keys.id).map((r) => r.name).join(', ')}${circle.manifest.removed.contains(keys.id) ? ' (removed from the circle)' : ''}');
        if (doing == 'check') return;
        if (doing == 'read') {
          final look = HangoutRoom(channel: circle.channelOf(space), route: route, name: botName, signer: KeysSigner(keys), store: MemoryHangoutStore());
          await look.setReadOnly(ro);
          await look.open();
          await Future<void>.delayed(const Duration(seconds: 6));
          for (final m in look.messages.reversed.take(5).toList().reversed) {
            stdout.writeln('ghost-updates-bot: read [${DateTime.fromMillisecondsSinceEpoch(m.at).toUtc().toIso8601String()}] ${m.name}: ${m.text.split('\n').first}');
          }
          stdout.writeln('ghost-updates-bot: ${look.messages.length} messages in "${space.name}"');
          await look.close();
          return;
        }
        // A read-only space takes the owner's and admins' words alone: anything else the relay drops without a word.
        if (ro != null && !isAdmin) fail('not an admin of ${circle.manifest.name} yet, so "${space.name}" would drop it');
        final chat = HangoutRoom(channel: circle.channelOf(space), route: route, name: botName, signer: KeysSigner(keys), store: MemoryHangoutStore());
        await chat.setReadOnly(ro);
        await chat.open();
        await Future<void>.delayed(const Duration(seconds: 1));
        if (doing == 'edit') {
          // Its history comes from whoever is in the room, and from what the hub kept: give it a while.
          HangoutMessage? mine;
          for (var i = 0; i < 40 && mine == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            mine = chat.messages.reversed.where((m) => m.from == chat.me && m.text.startsWith(match)).firstOrNull;
          }
          if (mine == null) fail('no message of this bot\'s in "${space.name}" begins "$match" (${chat.messages.length} held)');
          final edited = chat.edit(mine, words, mentions: _mentions(words));
          await Future<void>.delayed(const Duration(seconds: 2));
          await chat.close();
          expect(edited, isTrue, reason: 'the room would not take the edit (nothing changed, or this identity may not)');
          stdout.writeln('ghost-updates-bot: edited "${mine.text.split('\n').first}" (${_mentions(words).length} mentions)');
          return;
        }
        final ok = chat.send(words, mentions: _mentions(words));
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
