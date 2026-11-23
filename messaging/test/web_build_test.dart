import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
