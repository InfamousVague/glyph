import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/circles/circle.dart';
import 'package:ghost_messaging/plugins/plugin.dart';
import 'package:ghost_messaging/plugins/record_call.dart';
import 'package:ghost_messaging/plugins/registry.dart';
import 'package:ghost_messaging/plugins/scribe.dart';
import 'package:ghost_messaging/voice/mp4_names.dart';
import 'package:ghost_messaging/voice/recorder.dart';
import 'package:ghost_messaging/voice/scribe.dart';
import 'package:ghost_messaging/voice/voice.dart' show SpaceKind;

/// Recording a call (lib/voice/recorder.dart, lib/voice/mp4_names.dart, lib/plugins/record_call.dart; Matt,
/// 2026-11-19: "a "record call" plugin where it records the call to an MP4 with multiple named audio tracks", and
/// "Some plugins should be serverside / cirlce side as well").

Uint8List _box(String type, List<Uint8List> body) {
  final size = 8 + body.fold<int>(0, (n, b) => n + b.length);
  final b = BytesBuilder()
    ..add(Uint8List(4)..buffer.asByteData().setUint32(0, size))
    ..add(latin1.encode(type));
  for (final x in body) {
    b.add(x);
  }
  return b.toBytes();
}

Uint8List _bytes(List<int> l) => Uint8List.fromList(l);

/// A track as a muxer writes one: a header (version 0, enabled), a handler named SoundHandler, and one chunk offset.
Uint8List _trak(int id, int chunk) {
  final tkhd = ByteData(84)
    ..setUint32(0, 0x00000007)
    ..setUint32(12, id);
  final hdlr = BytesBuilder()
    ..add(Uint8List(4))
    ..add(Uint8List(4))
    ..add(latin1.encode('soun'))
    ..add(Uint8List(12))
    ..add(_bytes([...latin1.encode('SoundHandler'), 0]));
  final stco = ByteData(12)
    ..setUint32(4, 1)
    ..setUint32(8, chunk);
  return _box('trak', [
    _box('tkhd', [tkhd.buffer.asUint8List()]),
    _box('mdia', [
      _box('hdlr', [hdlr.toBytes()]),
      _box('minf', [
        _box('stbl', [_box('stco', [stco.buffer.asUint8List()])]),
      ]),
    ]),
  ]);
}

/// The tracks of a file as a reader finds them: each one's name boxes, handler name, flags, group and chunk offset.
List<Map<String, Object>> _read(Uint8List file) {
  Iterable<Uint8List> kids(Uint8List b, int from) sync* {
    final d = ByteData.sublistView(b);
    var at = from;
    while (at + 8 <= b.length) {
      final size = d.getUint32(at);
      yield Uint8List.sublistView(b, at, at + size);
      at += size;
    }
  }

  String type(Uint8List b) => latin1.decode(b.sublist(4, 8));
  Uint8List child(Uint8List b, String t, [int from = 8]) => kids(b, from).firstWhere((k) => type(k) == t);
  final moov = kids(file, 0).firstWhere((b) => type(b) == 'moov');
  return [
    for (final trak in kids(moov, 8).where((b) => type(b) == 'trak'))
      () {
        final tkhd = child(trak, 'tkhd');
        final hdlr = child(child(trak, 'mdia'), 'hdlr');
        final udta = child(trak, 'udta');
        final nam = child(udta, '©nam');
        final stco = child(child(child(child(trak, 'mdia'), 'minf'), 'stbl'), 'stco');
        return <String, Object>{
          'name': utf8.decode(child(udta, 'name').sublist(8)),
          'title': utf8.decode(nam.sublist(12)),
          'handler': utf8.decode(hdlr.sublist(32, hdlr.length - 1)),
          'enabled': tkhd[11] & 1 == 1,
          'group': ByteData.sublistView(tkhd).getUint16(8 + 4 + 20 + 8 + 2),
          'chunk': ByteData.sublistView(stco).getUint32(16),
        };
      }(),
  ];
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ghost-rec-'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('naming the tracks', () {
    test('the movie box last (as the platforms write it): each track named three ways, the mix alone enabled', () async {
      final ftyp = _box('ftyp', [latin1.encode('isom')]);
      final mdat = _box('mdat', [Uint8List(100)]);
      final at = ftyp.length + 8;
      final moov = _box('moov', [_box('mvhd', [Uint8List(100)]), _trak(1, at), _trak(2, at + 50), _trak(3, at + 70)]);
      final f = File('${dir.path}/a.mp4')..writeAsBytesSync([...ftyp, ...mdat, ...moov]);
      await Mp4Names.apply(f.path, ['Everyone', 'Maya', 'Sam Ó Riordáin']);
      final tracks = _read(f.readAsBytesSync());
      expect([for (final t in tracks) t['name']], ['Everyone', 'Maya', 'Sam Ó Riordáin']);
      expect([for (final t in tracks) t['title']], ['Everyone', 'Maya', 'Sam Ó Riordáin'], reason: 'libmpv, the app\'s player, reads ©nam as the title');
      expect([for (final t in tracks) t['handler']], ['Everyone', 'Maya', 'Sam Ó Riordáin']);
      expect([for (final t in tracks) t['enabled']], [true, false, false], reason: 'a player that plays one track plays the mix');
      expect([for (final t in tracks) t['group']], [1, 1, 1]);
      expect([for (final t in tracks) t['chunk']], [at, at + 50, at + 70], reason: 'the media did not move');
      expect(f.readAsBytesSync().sublist(ftyp.length, ftyp.length + mdat.length), mdat, reason: 'the media is never touched');
    });

    test('the movie box first: every chunk offset moves by however much the box grew', () async {
      final ftyp = _box('ftyp', [latin1.encode('isom')]);
      Uint8List moovAt(int at) => _box('moov', [_trak(1, at), _trak(2, at + 40)]);
      final first = moovAt(0);
      final at = ftyp.length + first.length + 8;
      final moov = moovAt(at);
      final mdat = _box('mdat', [Uint8List.fromList(List.generate(80, (i) => i))]);
      final f = File('${dir.path}/b.mp4')..writeAsBytesSync([...ftyp, ...moov, ...mdat]);
      await Mp4Names.apply(f.path, ['Everyone', 'Maya']);
      final out = f.readAsBytesSync();
      final tracks = _read(out);
      final media = out.length - mdat.length + 8;
      expect([for (final t in tracks) t['chunk']], [media, media + 40]);
      expect(out.sublist(out.length - mdat.length), mdat);
    });

    test('a file that is not an MP4 is refused, not spoilt', () async {
      final f = File('${dir.path}/c.mp4')..writeAsBytesSync(utf8.encode('not a movie at all, just words'));
      await expectLater(Mp4Names.apply(f.path, ['x']), throwsA(isA<FormatException>()));
      expect(f.readAsStringSync(), 'not a movie at all, just words');
    });
  });

  test('the mix sums every voice, holds it under clipping, and runs as long as the longest', () async {
    Uint8List pcm(List<int> s) {
      final d = ByteData(s.length * 2);
      for (var i = 0; i < s.length; i++) {
        d.setInt16(i * 2, s[i], Endian.little);
      }
      return d.buffer.asUint8List();
    }

    final a = File('${dir.path}/a.pcm')..writeAsBytesSync(pcm([1000, -2000, 30000, 5]));
    final b = File('${dir.path}/b.pcm')..writeAsBytesSync(pcm([1000, -2000, 30000]));
    mixPcm([a.path, b.path], '${dir.path}/mix.pcm');
    final d = ByteData.sublistView(File('${dir.path}/mix.pcm').readAsBytesSync());
    expect([for (var i = 0; i < d.lengthInBytes ~/ 2; i++) d.getInt16(i * 2, Endian.little)], [2000, -4000, 32767, 5]);
  });

  group('a plugin a circle holds', () {
    const plugin = RecordCallPlugin();
    final registry = PluginRegistry(const [plugin]);

    test('off until added, and listed for circles', () {
      expect(plugin.onByDefault, isFalse);
      expect(plugin.scopes, containsAll([PluginScope.device, PluginScope.circle]));
      expect(registry.circlePlugins, [plugin]);
      expect(shippedPlugins.whereType<RecordCallPlugin>(), hasLength(1));
    });

    test('in a circle\'s space it is on as the circle says, whatever this device\'s switch; elsewhere as the switch says', () {
      final store = MemoryStore();
      expect(registry.isOnIn(plugin, store), isFalse);
      expect(registry.isOnIn(plugin, store, inCircle: true), isFalse, reason: 'a circle that said nothing has it off');
      expect(registry.isOnIn(plugin, store, inCircle: true, circleOn: true), isTrue, reason: 'on for everyone, though no one added it');
      registry.setOn(plugin, store, true);
      expect(registry.isOnIn(plugin, store), isTrue);
      expect(registry.isOnIn(plugin, store, inCircle: true, circleOn: false), isFalse, reason: 'the circle turned it off');
    });

    test('the circle\'s choice is kept in its manifest, and a manifest that keeps it unread passes it on as written', () {
      final m = CircleManifest(owner: '02${'ab' * 32}', name: 'Table', version: 3);
      expect(m.pluginOn('recordcall'), isNull);
      final on = m.next(extra: m.withPlugin('recordcall', on: true));
      expect(on.pluginOn('recordcall'), isTrue);
      // An older build reads the body, keeps 'pl' among what it doesn't know, and writes it back unchanged.
      final again = CircleManifest.fromJson(on.toJson());
      expect(again, isNotNull);
      expect(again!.extra['pl'], on.extra['pl']);
      expect(again.next(name: 'Table 2').pluginOn('recordcall'), isTrue, reason: 'an unrelated change keeps it');
      final off = again.next(extra: again.withPlugin('recordcall', on: false));
      expect(off.pluginOn('recordcall'), isFalse);
    });
  });

  group('Scribe', () {
    SaidLine l(String who, int s, int e, String text) => SaidLine(who: who, start: Duration(milliseconds: s), end: Duration(milliseconds: e), text: text);

    test('each voice\'s lines put in order of time, named, whatever track they came from', () {
      final merged = mergeLines([
        [l('Maya', 0, 1500, 'Right, where were we?'), l('Maya', 9000, 10000, 'Roll for it.')],
        [l('Sam', 1800, 4000, 'The bridge, the troll under it.'), l('Sam', 9000, 9500, 'Ugh.')],
      ]);
      expect([for (final x in merged) '${x.who}: ${x.text}'], ['Maya: Right, where were we?', 'Sam: The bridge, the troll under it.', 'Maya: Roll for it.', 'Sam: Ugh.']);
    });

    test('kept as words and as subtitles the player shows', () {
      final t = Transcript(lines: [l('Maya', 0, 1500, 'Right, where were we?'), l('Sam', 61800, 64000, 'The bridge.')], summary: 'They planned the bridge.');
      expect(t.text, 'They planned the bridge.\n\n[0:00] Maya: Right, where were we?\n[1:01] Sam: The bridge.');
      expect(t.srt, '1\n00:00:00,000 --> 00:00:01,500\nMaya: Right, where were we?\n\n2\n00:01:01,800 --> 00:01:04,000\nSam: The bridge.\n');
      final again = Transcript.fromJson(t.toJson())!;
      expect(again.text, t.text);
    });

    test('a plugin a circle can hold, off until added', () {
      const s = ScribePlugin();
      expect(s.onByDefault, isFalse);
      expect(s.scopes, contains(PluginScope.circle));
      expect(shippedPlugins.whereType<ScribePlugin>(), hasLength(1));
    });
  });

  // Matt, 2026-11-19: "add icons in the compose window or header depending on what makes sense for plugins like the
  // recording plugin and allow for changing settings like save location (expect saving to have at least one file space in
  // a circle we'll save to a folder in a given space within the circle)".
  group('where a circle\'s recordings go', () {
    Circle circle(List<CircleSpace> spaces, {Map<String, Object?> extra = const {}}) =>
        Circle(seed: '5' * 64, owner: '', manifest: CircleManifest(owner: '', name: 'Band', spaces: spaces, extra: extra));
    final chat = CircleSpace.make('Chat', kind: SpaceKind.text);
    final shared = CircleSpace.make('Shared', kind: SpaceKind.files, order: 1);
    final takes = CircleSpace.make('Takes', kind: SpaceKind.files, order: 2);

    test('until the circle chooses: its first Files space, in a folder named Recordings', () {
      final to = RecordCallPlugin.saveToIn(circle([chat, shared, takes]))!;
      expect(to.space.seed, shared.seed);
      expect(to.folder, 'Recordings');
      expect(to.channel.circle, '5' * 64, reason: 'the space as its circle has it');
    });

    test('the circle\'s choice of space and folder, kept with the plugin in its manifest', () {
      final c = circle([chat, shared, takes]);
      final chosen = circle([chat, shared, takes], extra: c.manifest.withPlugin('recordcall', on: true, choices: {'space': takes.seed, 'folder': 'Sessions/2026'}));
      final to = RecordCallPlugin.saveToIn(chosen)!;
      expect(to.space.seed, takes.seed);
      expect(to.folder, 'Sessions/2026');
      expect(chosen.manifest.pluginOn('recordcall'), isTrue, reason: 'choosing a place leaves the switch as it was');
    });

    test('a chosen space that is gone, or a folder that is no folder, falls back', () {
      final c = circle([chat, shared]);
      final to = RecordCallPlugin.saveToIn(circle([chat, shared], extra: c.manifest.withPlugin('recordcall', on: true, choices: {'space': 'gone', 'folder': '../..'})))!;
      expect(to.space.seed, shared.seed);
      expect(to.folder, 'Recordings');
    });

    test('with no Files space there is nowhere in the circle to save to', () {
      expect(RecordCallPlugin.saveToIn(circle([chat])), isNull);
    });

    test('Record and Stop are in the space\'s header only while this device is in its call', () {
      List<String> header(SpacePlace p) => [
            for (final f in const RecordCallPlugin().slots)
              if (f is ActionFill<SpacePlace>) ...[for (final a in f.build(p, PluginPrefs.none)) a.label],
          ];
      const space = SpacePlace(space: 's', spaceName: 'Lounge', circle: 'c');
      expect(header(space), isEmpty, reason: 'not in its call');
      expect(header(const SpacePlace(space: 's', spaceName: 'Notes', voice: false, inCall: true)), isEmpty, reason: 'no call in a texting space');
      if (CallRecorder.supported) {
        expect(header(const SpacePlace(space: 's', spaceName: 'Lounge', circle: 'c', inCall: true)), ['Record this call']);
      }
    });
  });
}
