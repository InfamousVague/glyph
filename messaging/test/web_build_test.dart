import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/files/files_model.dart' show SpaceFile;
import 'package:ghost_messaging/plugins/list.dart' show ListPlugins;
import 'package:ghost_messaging/plugins/plugin.dart' show MessageFacts;
import 'package:ghost_messaging/plugins/spam.dart' show isNetworkChat;
import 'package:ghost_messaging/standalone/overlay.dart' show UsernameOverlay;

/// The app's build for a browser (lib/web/main.dart, web/; Matt: "the full web client"). The build itself is
/// `node tool/build-web.mjs` (flutter build web -t lib/web/main.dart) and is not run here; these keep what it rests on.
/// The app in a page, as far as it can be held without a browser, is test/web_start_test.dart.
void main() {
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
    // The picture the page shows where it can't be the app (lib/web/app.dart: WebNotice) is one of its assets.
    expect(File('assets/art/ghost-mark.png').existsSync(), isTrue);
  });

  // Nothing is fetched from anyone else (Matt: "the full web client"; docs/OPEN_NETWORK.md, part 6): the page says so
  // to the browser, and what is written into the build beside the app names no other address. That the page as built
  // asks no other address is seen in real engines by tool/web/e2e.mjs.
  test('the page tells the browser it may speak to its own address alone', () {
    final page = File('web/index.html').readAsStringSync();
    final policy = RegExp(r'<meta http-equiv="Content-Security-Policy" content="([^"]+)">').firstMatch(page)?.group(1);
    expect(policy, isNotNull, reason: 'web/index.html has no policy');
    final said = {for (final part in policy!.split(';')) part.trim().split(' ').first: part.trim().split(' ').skip(1).toList()};
    expect(said, {
      'default-src': ["'none'"],
      // Its own scripts, and Flutter's engine compiled from WebAssembly: no script written into the page, none made
      // from text (`flutter build web --csp`), none from anywhere else.
      'script-src': ["'self'", "'wasm-unsafe-eval'"],
      'worker-src': ["'self'"],
      // Flutter's engine writes its styles into the page.
      'style-src': ["'self'", "'unsafe-inline'"],
      'img-src': ["'self'", 'data:', 'blob:'],
      'font-src': ["'self'"],
      'media-src': ["'self'", 'data:', 'blob:'],
      // The relay it came from, which is its hub too: the one address it speaks to.
      'connect-src': ["'self'"],
      'manifest-src': ["'self'"],
      'base-uri': ["'self'"],
      'form-action': ["'none'"],
      'frame-src': ["'none'"],
      'object-src': ["'none'"],
    });
    expect(page, contains('<meta name="referrer" content="no-referrer">'));
    // No script in the page but the loader, and nothing written into it to run.
    expect(RegExp(r'<script\b').allMatches(page), hasLength(1));
    expect(page, isNot(contains(RegExp(r'\son[a-z]+\s*=', caseSensitive: false))));
    // No other address is named by anything that is copied into the build as it is, comments apart (the worker's
    // first lines say whose work it is and where that is from).
    final other = RegExp(r'(?:https?:)?//[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
    for (final file in ['web/index.html', 'web/manifest.json', 'web/flutter_bootstrap.js', 'web/argon2id.js']) {
      final code = File(file).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('*') && !l.trimLeft().startsWith('/*')).join('\n');
      expect(other.allMatches(code).map((m) => m.group(0)), isEmpty, reason: file);
    }
  });

  test('the loader asks for missing letters\' fonts beside the page, and sets up no service worker', () {
    final loader = File('web/flutter_bootstrap.js').readAsStringSync();
    // Filled in by `flutter build web`: Flutter's own loader, and what it built.
    expect(loader, contains('{{flutter_js}}'));
    expect(loader, contains('{{flutter_build_config}}'));
    // Flutter asks fonts.gstatic.com for these unless told otherwise.
    expect(loader, contains("fontFallbackBaseUrl: 'fallback-fonts/'"));
    final code = loader.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    expect(code, isNot(contains('serviceWorker')));
    expect(code, isNot(contains('gstatic')));
  });

  // Signing in stretches the password with Argon2id. In a browser that is web/argon2id.js, run as a worker
  // (lib/account/argon2_browser_web.dart): built by tool/web/build-argon2.mjs from the browser extension's own pinned
  // copy of @noble/hashes, held to test/vectors/argon2id.json as it is built, and committed. That it is what the
  // script builds is `node tool/web/build-argon2.mjs --check` (tool/build-web.mjs runs it); what is held here is that
  // the file says where it came from, and that it is still the extension's pin.
  test('the Argon2id the page carries is the extension\'s pinned one, and says so', () {
    final worker = File('web/argon2id.js').readAsStringSync();
    final pin = ((jsonDecode(File('extension/package.json').readAsStringSync()) as Map)['dependencies'] as Map)['@noble/hashes'] as String;
    final lock = ((jsonDecode(File('extension/package-lock.json').readAsStringSync()) as Map)['packages'] as Map)['node_modules/@noble/hashes'] as Map;
    expect(pin, matches(RegExp(r'^\d+\.\d+\.\d+$')), reason: 'one version, not a range');
    expect(lock['version'], pin);
    expect(worker, startsWith('/* Argon2id for Ghost Messaging in a browser'));
    expect(worker, contains('Written by tool/web/build-argon2.mjs'));
    expect(worker, contains('From @noble/hashes $pin (${lock['integrity']})'));
    expect(worker, contains('MIT licensed'));
    // One file, with nothing to fetch: no other file brought in, no address asked.
    expect(worker, isNot(contains('importScripts')));
    expect(worker, isNot(contains('fetch(')));
    expect(worker, isNot(contains('XMLHttpRequest')));
    expect(worker.length, lessThan(40000));
    // The page starts it by this name, beside itself.
    expect(File('lib/account/argon2_browser_web.dart').readAsStringSync(), contains("const _script = 'argon2id.js';"));
  });

  // A file that can't be compiled for a browser, or would be wrong in one, has a half for each (lib/platform_info.dart,
  // lib/aside.dart, lib/net/fast_gcm.dart, …), chosen by a file that exports one or the other, or imports one or the
  // other under a name (lib/net/hub_link.dart, lib/web/browser.dart). Naming a half from anywhere else takes the
  // choice away: fast_gcm_64.dart in a browser seals bytes nothing else can open, and td_json_io.dart stops the build.
  test('a half is reached only through the file that chooses it, and a browser gets the one for a browser', () {
    final chooses = RegExp(r"^(?:export|import)\s+'([^']+)'\s+if\s+\(dart\.library\.js_interop\)\s+'([^']+)'(?:\s+as\s+\w+)?(?:\s+(?:show|hide)\s+[\w\s,]+)?;", multiLine: true);
    final conditional = RegExp(r"^(?:export|import)\s+'[^']+'\s+if\s*\(([^)]*)\)", multiLine: true);
    final directive = RegExp(r'''^\s*(?:import|export)\s+'([^']+)'(?:\s+if\s+\([^)]*\)\s+'([^']+)')?''', multiLine: true);
    final files = [for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) if (f.path.endsWith('.dart')) f.path.replaceAll('\\', '/')];
    expect(files.length, greaterThan(300));
    String resolve(String from, String uri) => uri.startsWith('package:ghost_messaging/') ? 'lib/${uri.substring('package:ghost_messaging/'.length)}' : File(from).parent.uri.resolve(uri).path.replaceFirst(RegExp(r'^.*?(?=lib/)'), '');

    // Each half, and the file that chooses it.
    final halves = <String, String>{};
    final choosers = <String>{};
    for (final path in files) {
      final text = File(path).readAsStringSync();
      // Every choice in lib/ is this one, written this way: for a browser or not. Another condition, or another
      // spelling, would be a choice this test does not see.
      for (final m in conditional.allMatches(text)) {
        expect(m.group(1), 'dart.library.js_interop', reason: '$path chooses by something else');
      }
      expect(conditional.allMatches(text).length, chooses.allMatches(text).length, reason: '$path has a conditional import or export this test does not read');
      for (final m in chooses.allMatches(text)) {
        choosers.add(path);
        final other = resolve(path, m.group(1)!), browsers = resolve(path, m.group(2)!);
        for (final at in [other, browsers]) {
          expect(File(at).existsSync(), isTrue, reason: '$path chooses $at, which is not there');
          expect(halves.containsKey(at), isFalse, reason: '$at is chosen twice');
          halves[at] = path;
        }
        // Which way round: the half after `if (dart.library.js_interop)` is the browser's, and is named so. Turned
        // round, a pair that names no dart:ffi or JavaScript of its own compiles everywhere and is wrong everywhere.
        expect(browsers, endsWith('_web.dart'), reason: '$path: the half a browser gets is the one named _web.dart');
        expect(other, isNot(endsWith('_web.dart')), reason: '$path: the half for a phone or a computer is not the one named _web.dart');
      }
    }
    expect(choosers, {
      'lib/platform_info.dart',
      'lib/aside.dart',
      'lib/net/fast_gcm.dart',
      'lib/net/hub_link.dart',
      'lib/account/gzip.dart',
      'lib/account/argon2_browser.dart',
      'lib/inbox/td_json.dart',
      'lib/files/apple_sha.dart',
      'lib/voice/mpv_property.dart',
      'lib/web/browser.dart',
    });
    expect(halves.keys, containsAll(['lib/platform_info_io.dart', 'lib/platform_info_web.dart', 'lib/aside_io.dart', 'lib/aside_web.dart', 'lib/net/fast_gcm_64.dart', 'lib/net/fast_gcm_web.dart', 'lib/account/gzip_io.dart', 'lib/account/gzip_web.dart', 'lib/inbox/td_json_io.dart', 'lib/inbox/td_json_web.dart', 'lib/files/apple_sha_io.dart', 'lib/files/apple_sha_web.dart', 'lib/net/hub_link_io.dart', 'lib/net/hub_link_web.dart', 'lib/voice/mpv_property_io.dart', 'lib/voice/mpv_property_web.dart', 'lib/account/argon2_browser_none.dart', 'lib/account/argon2_browser_web.dart', 'lib/web/browser_none.dart', 'lib/web/browser_web.dart']));

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

    // And JavaScript is spoken to only from a browser's half: anywhere else it stops every other build.
    final speaks = RegExp(r"^\s*import\s+'(?:dart:js_interop|dart:js_interop_unsafe|dart:html|dart:js|package:web/)", multiLine: true);
    final speaking = [for (final path in files) if (speaks.hasMatch(File(path).readAsStringSync())) path];
    expect(speaking, isNotEmpty);
    for (final path in speaking) {
      expect(halves[path], isNotNull, reason: '$path speaks to JavaScript and is no half of a pair');
      expect(path, endsWith('_web.dart'), reason: path);
    }
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
