import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/accent.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/art/pixel_icons.g.dart';
import 'package:ghost_messaging/looks.dart';
import 'package:ghost_messaging/packs/pack_paint.dart';
import 'package:ghost_messaging/packs/resource_pack.dart';
import 'package:ghost_messaging/ui/dialup/dialup.dart';
import 'package:glacier/glacier.dart';
import 'package:image/image.dart' as img;

/// Resource packs for the look Runestone (lib/packs/; Matt, 2026-11-27: "see how we can get the dark vanilla texture
/// pack", then "let's try the duckscape theme instead and bring in the pixelated looks"). A pack is fetched to the
/// device from its hub and never part of the app, so every pack here is one made in the test: flat colours under the
/// hub's own file names, served by a stand-in for the hub on this machine. Nothing is fetched from anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const good = PackEntry(id: 'pack-made-here', name: 'Made here', author: 'A test', commit: '0123456789abcdef0123456789abcdef01234567');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost/sms'), (call) async => call.method == 'prefs' ? <String, String>{} : null);
  });
  tearDown(() => ResourcePacks.instance = ResourcePacks());

  test('a pack of the hub\'s list is taken only with a branch\'s name and a whole commit', () {
    final e = PackEntry.from({'internalName': 'pack-duckscape', 'displayName': 'duckscape', 'author': 'degradee', 'commit': '895309cf7c498845c2300975e9e8b52314dcf223', 'tags': ['green']});
    expect(e, isNotNull);
    expect((e!.id, e.name, e.author), ('pack-duckscape', 'duckscape', 'degradee'));
    expect(e.tags, ['green']);
    expect(ResourcePacks.archiveOf(e), 'https://github.com/melkypie/resource-packs/archive/895309cf7c498845c2300975e9e8b52314dcf223.zip');
    expect(PackEntry.from(e.toJson())!.commit, e.commit, reason: 'kept and read again as it was');
    // A name or a commit that would be anything else in an address or a file's name is no pack.
    for (final bad in [
      {'internalName': '../etc', 'commit': e.commit},
      {'internalName': 'pack/one', 'commit': e.commit},
      {'internalName': 'pack-one', 'commit': 'main'},
      {'internalName': 'pack-one', 'commit': '${e.commit}/../x'},
      {'internalName': '', 'commit': e.commit},
      'pack-one',
    ]) {
      expect(PackEntry.from(bad), isNull, reason: '$bad');
    }
  });

  test('a pack is read as pictures alone: the ones the look draws with, its colours off them, its box put together', () async {
    final pack = await ResourcePack.read(good, madePack());
    // What the look draws with, and nothing else of the archive (a script in it is not read, let alone run).
    expect(pack.sprites.keys, containsAll(['chatbox/button', 'chatbox/button_selected', 'chatbox/background', 'dialog/background', 'other/window_close_button', 'other/minimap_orb_frame_small']));
    expect(pack.sprites.keys.every((k) => k == 'button/frame' || k == 'chatbox/ground' || ResourcePack.wanted.contains(k)), isTrue);
    // The parchment inside the chatbox's frame as a picture of its own, to lay side by side: 60 by 40 less 8 each side.
    expect((pack['chatbox/ground']!.width, pack['chatbox/ground']!.height), (44, 24));
    expect(pack['chatbox/button']!.width, 56);
    // The game's nine pieces of a box as one picture: corners 6 across, 12 between.
    expect((pack['button/frame']!.width, pack['button/frame']!.height), (24, 24));
    // Its colours, read off its pictures: the window's face, a well's, the parchment and how wide its frame is.
    expect(pack.colours.window.toARGB32(), 0xFF342E33);
    expect(pack.colours.panel.toARGB32(), 0xFF221F23);
    expect(pack.colours.parchment.toARGB32(), 0xFFD8CEC2);
    expect(pack.parchmentEdge, 5);
  });

  test('what is not a pack is refused, and one too large is not opened', () async {
    final none = Archive()..addFile(ArchiveFile.bytes('folder/README.md', utf8.encode('not a pack')));
    await expectLater(ResourcePack.read(good, Uint8List.fromList(ZipEncoder().encode(none))), throwsFormatException);
    await expectLater(ResourcePack.read(good, Uint8List.fromList(utf8.encode('not an archive at all'))), throwsFormatException);
    await expectLater(ResourcePack.read(good, Uint8List(ResourcePack.mostArchive + 1)), throwsFormatException);
  });

  test('a pack\'s colours are laid over Runestone\'s own, and what is written on its parchment reads on it', () async {
    final light = (await ResourcePack.read(good, madePack())).css;
    expect(light, contains("[data-theme-preset='runestone']"));
    expect(light, contains('--app-chrome: #342e33;'));
    expect(light, contains('--glacier-gray-1: #221f23;'));
    expect(light, contains('--app-paper: #d8cec2;'));
    expect(light, isNot(contains('--app-line-mine')), reason: 'a light parchment keeps the stylesheet\'s dark inks');
    // A pack whose chatbox is dark: the look's light words again, over their shadow.
    final dark = (await ResourcePack.read(good, madePack(parchment: 0x1E1A1C))).css;
    expect(dark, contains('--app-line-mine: #9090FF;'));
    expect(dark, contains('--app-ink: #FFFFFF;'));
    expect(dark, contains('--glacier-text-shadow: 1px 1px 0 #000000;'));
  });

  test('a pack is fetched from the hub at the commit its list names, kept, used, and taken off again', () async {
    // The test binding answers every request itself (400); the stand-in below is asked for real, on this machine.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final zip = madePack();
    final asked = <String>[];
    final hub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => hub.close(force: true));
    hub.listen((request) async {
      asked.add(request.uri.path);
      if (request.uri.path == '/manifest.js') {
        request.response.write(jsonEncode([good.toJson(), {'internalName': '../bad', 'commit': 'x'}, {'internalName': 'pack-gone', 'displayName': 'Gone', 'author': '', 'commit': 'f' * 40}]));
      } else if (request.uri.path == '/archive/${good.commit}.zip') {
        request.response.add(zip);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final root = Directory.systemTemp.createTempSync('ghost-packs-test-');
    addTearDown(() => root.deleteSync(recursive: true));
    final at = 'http://127.0.0.1:${hub.port}';
    final packs = ResourcePacks(root: root, listUrl: '$at/manifest.js', archiveUrl: (e) => '$at/archive/${e.commit}.zip');
    final app = AppState()..setLook(Look.runestone);

    final list = await packs.hub();
    expect([for (final e in list) e.id], ['pack-gone', 'pack-made-here'], reason: 'by name, without what is no pack');
    expect(packs.installed(), isEmpty);
    expect(packs.usedBy(app), isNull);

    await packs.install(app, list.last);
    expect(asked, ['/manifest.js', '/archive/${good.commit}.zip']);
    expect(app.choice(ResourcePacks.pref, ''), good.id);
    expect(packs.usedBy(app)!.entry.name, 'Made here');
    expect([for (final e in packs.installed()) (e.id, e.commit)], [(good.id, good.commit)]);
    expect(root.listSync().map((f) => f.uri.pathSegments.last).toSet(), {'${good.id}.zip', '${good.id}.json'}, reason: 'the archive whole and what it is, and nothing unpacked');
    // Only Runestone draws with it.
    expect(packs.usedBy(AppState()..setLook(Look.dialup)), isNull);

    // One that is not there: what was in use stays in use.
    await expectLater(packs.install(app, list.first), throwsA(isA<HttpException>()));
    expect(packs.usedBy(app)!.entry.id, good.id);

    // Read again as the app starts: a new holder of the same folder.
    final again = ResourcePacks(root: root);
    await again.start(app);
    expect(again.current!.entry.id, good.id);

    await packs.use(app, '');
    expect(packs.current, isNull);
    expect(app.choice(ResourcePacks.pref, 'x'), '');
    await packs.use(app, good.id);
    expect(packs.current!.entry.id, good.id);
    await packs.remove(app, good.id);
    expect(packs.installed(), isEmpty);
    expect(packs.current, isNull);
    expect(app.choice(ResourcePacks.pref, 'x'), '');
  });

  testWidgets('Runestone draws its buttons, wells and headings from the pack; Dial-Up and a look without one draw as they did', (tester) async {
    final accents = (await tester.runAsync(AccentSheets.load))!;
    final app = AppState()..setLook(Look.runestone);
    Tokens tokens() => Tokens.root(accents.of(app), attrs: ghostAttrs(app, 'mobile'));
    expect(packOf(tokens()), isNull, reason: 'none fetched: flat stone');
    final flat = tokens().color('app-chrome');
    expect(PackBevel.of(tokens(), style: BevelStyle.raised, kind: BevelKind.button, small: false, ground: true, toggled: false), isNull);

    await tester.runAsync(() => ResourcePacks.instance.debugUse(good, madePack()));
    final t = tokens();
    expect(packOf(t)!.entry.id, good.id);
    expect(t.color('app-chrome').toARGB32(), 0xFF342E33, reason: 'the pack\'s window colour over the look\'s own');
    expect(t.color('app-chrome'), isNot(flat));
    expect(t.child(classes: {'parchment'}).color('app-paper').toARGB32(), 0xFFD8CEC2);
    // Each piece its own picture: a button, a held one, a window, a well's ground, the chat's parchment and a field's.
    final pack = ResourcePacks.instance.current!;
    PackBevel? piece(Tokens at, BevelStyle style, BevelKind kind, {bool small = false, bool toggled = false}) => PackBevel.of(at, style: style, kind: kind, small: small, ground: true, toggled: toggled);
    expect(piece(t, BevelStyle.raised, BevelKind.button)!.image, pack['chatbox/button']);
    expect(piece(t, BevelStyle.pressed, BevelKind.button)!.image, pack['chatbox/button_selected']);
    expect(piece(t, BevelStyle.raised, BevelKind.button, toggled: true)!.image, pack['chatbox/button_selected']);
    expect(piece(t, BevelStyle.raised, BevelKind.panel)!.image, pack['button/frame']);
    expect(piece(t, BevelStyle.sunken, BevelKind.panel)!.tile, pack['resizeable_mode/side_panel_background']);
    expect(piece(t.child(classes: {'parchment'}), BevelStyle.sunken, BevelKind.panel)!.tile, pack['chatbox/ground']);
    final well = t.child(classes: {'parchment'});
    expect(piece(well, BevelStyle.sunken, BevelKind.panel)!.image, pack['chatbox/background']);
    expect(piece(well, BevelStyle.sunken, BevelKind.panel)!.edge, 5 * packScale(t), reason: 'what is written starts inside the frame');
    expect(piece(well, BevelStyle.sunken, BevelKind.panel, small: true)!.edge, 5 * packScale(t) / 2, reason: 'a field\'s frame at half the size');

    // Drawn, on a page: nothing throws, and a profile's face is inside the pack's orb.
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: GlacierTheme(
        sheet: accents.of(app),
        attrs: ghostAttrs(app, 'mobile'),
        child: Column(children: [
          const TitleBar(title: 'Chat List'),
          TitleBar(title: 'A chat', onClose: () {}),
          RetroButton(onPressed: () {}, label: 'Send'),
          RetroButton(onPressed: () {}, label: 'Held', toggled: true),
          const Bevel(child: SizedBox(width: 120, height: 60)),
          const Sunken(child: SizedBox(width: 120, height: 60)),
          const GlacierScope(classes: {'parchment'}, child: Sunken(child: SizedBox(width: 160, height: 80))),
          const DialupWell(child: SizedBox(width: 160, height: 36)),
          const DialupFace(size: 44, child: SizedBox()),
          const PackOrb(size: 44, child: SizedBox()),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is OrbPainter), findsNWidgets(2));

    // Dial-Up with the same pack on the device: its own silver, and no picture asked for.
    final dial = AppState()..setLook(Look.dialup);
    final d = Tokens.root(accents.of(dial), attrs: ghostAttrs(dial, 'mobile'));
    expect(packOf(d), isNull);
    expect(d.color('app-chrome').toARGB32(), 0xFFC0C0C0);
  });

  test('the look\'s letters and icons are in the app, each with its licence beside it', () {
    for (final file in ['assets/fonts/Runestone-Regular.ttf', 'assets/fonts/Runestone-Bold.ttf']) {
      expect(File(file).lengthSync(), inInclusiveRange(10000, 40000), reason: file);
    }
    expect(File('assets/fonts/CC0-Runestone.txt').readAsStringSync(), allOf(contains('CC0 1.0 Universal'), contains('RuneStar/fonts'), contains('trademarks of Jagex')));
    expect(File('pubspec.yaml').readAsStringSync(), allOf(contains('- family: Runestone'), contains('assets/fonts/Runestone-Bold.ttf')));
    // Every icon the app names is drawn in pixels too, so nothing in the look is smooth.
    final named = (jsonDecode(File('tool/phosphor-map.json').readAsStringSync()) as Map).keys.toSet();
    expect(pixelIcons.keys.toSet(), named);
    expect(pixelIcons.values.every((d) => d.startsWith('M') && !d.contains('NaN')), isTrue);
    expect(File('lib/art/PIXELARTICONS_LICENSE').readAsStringSync(), allOf(contains('MIT License'), contains('Gerrit Halfmann')));
    // No pack's pictures are in the app or its source: they are fetched to the device (lib/packs/resource_pack.dart).
    expect(Directory('assets').listSync(recursive: true).whereType<File>().where((f) => f.path.contains('resource-pack') || f.path.contains('duckscape') || f.path.contains('vanilla')), isEmpty);
  });
}

/// A pack as the hub serves one: an archive of one folder, the game's file names in it, each a flat picture.
/// [parchment] is the chatbox's ground, cream unless said.
Uint8List madePack({int parchment = 0xD8CEC2}) {
  final archive = Archive();
  void put(String name, img.Image image) => archive.addFile(ArchiveFile.bytes('resource-packs-0123/$name.png', img.encodePng(image)));
  img.Image flat(int w, int h, int rgb, {int frame = 0, int frameRgb = 0x000000}) {
    final image = img.Image(width: w, height: h, numChannels: 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final edge = x < frame || y < frame || x >= w - frame || y >= h - frame;
        final c = edge ? frameRgb : rgb;
        image.setPixelRgba(x, y, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, 255);
      }
    }
    return image;
  }

  put('chatbox/button', flat(56, 22, 0x3A3038, frame: 1));
  put('chatbox/button_hovered', flat(56, 22, 0x4A4048, frame: 1));
  put('chatbox/button_selected', flat(56, 22, 0x5E6A5C, frame: 1));
  put('chatbox/button_new_messages', flat(56, 22, 0x6A3030, frame: 1));
  put('chatbox/background', flat(60, 40, parchment, frame: 5, frameRgb: 0x2A2428));
  put('chatbox/buttons_background_stones', flat(32, 23, 0x2C262A));
  put('dialog/background', flat(8, 8, 0x342E33));
  put('resizeable_mode/side_panel_background', flat(8, 8, 0x221F23));
  for (final corner in ['top_left', 'top_right', 'bottom_left', 'bottom_right']) {
    put('button/corner_$corner', flat(6, 6, 0x3A3038));
  }
  put('button/edge_top', flat(12, 6, 0x3A3038));
  put('button/edge_bottom', flat(12, 6, 0x3A3038));
  put('button/edge_left', flat(6, 12, 0x3A3038));
  put('button/edge_right', flat(6, 12, 0x3A3038));
  put('button/middle', flat(12, 12, 0x3A3038));
  put('other/window_close_button', flat(26, 23, 0x3A3038, frame: 1));
  put('other/window_close_button_hovered', flat(26, 23, 0x4A4048, frame: 1));
  put('other/minimap_orb_frame_small', flat(34, 34, 0x000000, frame: 4, frameRgb: 0x3A3038));
  // Not pictures the look draws with, and not pictures at all: left where they are.
  put('tab/inventory', flat(20, 20, 0xFF00FF));
  archive.addFile(ArchiveFile.bytes('resource-packs-0123/run-me.sh', utf8.encode('#!/bin/sh\nexit 1\n')));
  archive.addFile(ArchiveFile.bytes('resource-packs-0123/pack.properties', utf8.encode('displayName=Made here\n')));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
