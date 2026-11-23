import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/files/files_model.dart' show SpaceFile;
import 'package:ghost_messaging/plugins/list.dart' show ListPlugins;
import 'package:ghost_messaging/plugins/plugin.dart' show MessageFacts;
import 'package:ghost_messaging/plugins/spam.dart' show isNetworkChat;
import 'package:ghost_messaging/standalone/overlay.dart' show UsernameOverlay;
import 'package:ghost_messaging/web/main.dart';

/// The app's build for a browser (lib/web/main.dart, web/; Matt: "the full web client"). The build itself is
/// `flutter build web -t lib/web/main.dart --release` and is not run here; these keep what it rests on.
void main() {
  testWidgets('for now the page says the app is being built, and starts nothing', (tester) async {
    await tester.pumpWidget(const BeingBuilt());
    expect(find.text('Ghost Messaging for the web is being built'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the app itself is started only by an address that ends in #app', () {
    expect(startsApp(Uri.parse('https://example.com/')), isFalse);
    expect(startsApp(Uri.parse('https://example.com/index.html')), isFalse);
    expect(startsApp(Uri.parse('https://example.com/?app')), isFalse);
    expect(startsApp(Uri.parse('https://example.com/#')), isFalse);
    expect(startsApp(Uri.parse('https://example.com/#apple')), isFalse);
    expect(startsApp(Uri.parse('https://example.com/#app')), isTrue);
    expect(startsApp(Uri.parse('http://localhost:8080/index.html#app')), isTrue);
  });

  test('the page names the app\'s icons, and they are there', () {
    final page = File('web/index.html').readAsStringSync();
    // What `flutter build web` fills in and writes: without either the built page loads nothing.
    expect(page, contains(r'<base href="$FLUTTER_BASE_HREF">'));
    expect(page, contains('<script src="flutter_bootstrap.js" async></script>'));
    expect(page, contains('<title>Ghost Messaging</title>'));
    final named = RegExp(r'href="([^"$]+\.(?:png|json))"').allMatches(page).map((m) => m.group(1)!).toList();
    expect(named, containsAll(['favicon.png', 'manifest.json', 'icons/Icon-192.png']));
    final manifest = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map;
    expect(manifest['name'], 'Ghost Messaging');
    final icons = [for (final i in manifest['icons'] as List) (i as Map)['src'] as String];
    expect(icons, hasLength(4));
    for (final file in [...named, ...icons]) {
      expect(File('web/$file').existsSync(), isTrue, reason: 'web/$file');
    }
    // The picture the app shows on that page is one of its assets.
    expect(File('assets/art/ghost-mark.png').existsSync(), isTrue);
  });

  // A file that can't be compiled for a browser, or would be wrong in one, has a half for each (lib/platform_info.dart,
  // lib/aside.dart, lib/net/fast_gcm.dart, …), chosen by a file that exports one or the other. Importing a half by
  // its own name takes the choice away: fast_gcm_64.dart in a browser seals bytes nothing else can open, and
  // td_json_io.dart stops the build.
  test('a half is reached only through the file that chooses it', () {
    final chooses = RegExp(r'''^export\s+'([^']+)'\s+if\s+\(dart\.library\.js_interop\)\s+'([^']+)';''', multiLine: true);
    final directive = RegExp(r'''^\s*(?:import|export)\s+'([^']+)'(?:\s+if\s+\([^)]*\)\s+'([^']+)')?''', multiLine: true);
    final files = [for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) if (f.path.endsWith('.dart')) f.path.replaceAll('\\', '/')];
    expect(files.length, greaterThan(300));
    String resolve(String from, String uri) => uri.startsWith('package:ghost_messaging/') ? 'lib/${uri.substring('package:ghost_messaging/'.length)}' : File(from).parent.uri.resolve(uri).path.replaceFirst(RegExp(r'^.*?(?=lib/)'), '');

    // Each half, and the file that chooses it.
    final halves = <String, String>{};
    for (final path in files) {
      for (final m in chooses.allMatches(File(path).readAsStringSync())) {
        for (final half in [m.group(1)!, m.group(2)!]) {
          final at = resolve(path, half);
          expect(File(at).existsSync(), isTrue, reason: '$path chooses $half, which is not there');
          expect(halves.containsKey(at), isFalse, reason: '$at is chosen twice');
          halves[at] = path;
        }
      }
    }
    expect(halves.keys, containsAll(['lib/platform_info_io.dart', 'lib/platform_info_web.dart', 'lib/aside_io.dart', 'lib/aside_web.dart', 'lib/net/fast_gcm_64.dart', 'lib/net/fast_gcm_web.dart', 'lib/account/gzip_io.dart', 'lib/account/gzip_web.dart', 'lib/inbox/td_json_io.dart', 'lib/inbox/td_json_web.dart', 'lib/files/apple_sha_io.dart', 'lib/files/apple_sha_web.dart']));

    final found = <String>[];
    for (final path in files) {
      for (final m in directive.allMatches(File(path).readAsStringSync())) {
        for (final uri in [m.group(1)!, ?m.group(2)]) {
          if (uri.startsWith('dart:') || (uri.startsWith('package:') && !uri.startsWith('package:ghost_messaging/'))) continue;
          final at = resolve(path, uri);
          final chooser = halves[at];
          if (chooser != null && chooser != path) found.add('$path names $at: name $chooser instead');
        }
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  // In a browser an integer is JavaScript's number, and `<<`, `>>` and `>>>` keep 32 bits of it: `1 << 40` is 0 there,
  // at run time and as a constant alike, with nothing to say so. (So a file's most size was 0, and every file over it.)
  // A number past 32 bits is written out (0x10000000000), which a browser holds exactly up to 2^53.
  test('nothing in lib/ shifts by 32 bits or more', () {
    // Where it may, and why.
    const allowed = {
      'lib/net/fast_gcm_64.dart': 'the half of lib/net/fast_gcm.dart for 64-bit integers; a browser gets fast_gcm_web.dart',
    };
    final shift = RegExp(r'(?:<<|>>>?)=?\s*\(?\s*(?:3[2-9]|[4-9][0-9]|[1-9][0-9]{2,})\b');
    final found = <String>[];
    var files = 0;
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final path = file.path.replaceAll('\\', '/');
      files++;
      final lines = file.readAsLinesSync();
      final here = [
        for (var i = 0; i < lines.length; i++)
          if (!lines[i].trimLeft().startsWith('//') && shift.hasMatch(lines[i])) '$path:${i + 1}: ${lines[i].trim().length > 120 ? '${lines[i].trim().substring(0, 120)}…' : lines[i].trim()}',
      ];
      if (allowed.containsKey(path)) {
        expect(here, isNotEmpty, reason: '$path is allowed such shifts and has none: take it off the list.');
      } else {
        found.addAll(here);
      }
    }
    expect(files, greaterThan(300));
    expect(found, isEmpty, reason: 'A shift keeps 32 bits in a browser: write the number out, or split the file as lib/net/fast_gcm.dart is.\n${found.join('\n')}');
    // And the four that were `1 << 40` are still 2^40 here.
    expect(SpaceFile.maxSize, 1099511627776);
    expect(UsernameOverlay.base, 1099511627776);
    expect(ListPlugins.chatThread('a'), lessThanOrEqualTo(-1099511627776));
    expect(ListPlugins.chatThread('a'), greaterThan(-1099511627776 - 0x40000000));
    expect(isNetworkChat(MessageFacts(thread: ListPlugins.chatThread('a'), senders: const [], text: '', contact: false)), isTrue);
    expect(isNetworkChat(const MessageFacts(thread: 7, senders: [], text: '', contact: false)), isFalse);
  });
}
