import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/types.dart';

import 'support.dart';

/// A plugin's host (lib/plugins/host.dart): the "a plugin's host" cases of `src/app/plugins/registry.test.ts` and
/// all of `src/app/plugins/host.test.ts`, then what the port's host has that the page's did not (its secrets, its
/// requests, its ground).
///
/// What differs from the web's cases:
/// - "calls only the native commands its manifest lists": there is no native command to call here, so a listed
///   command is refused too, as something the plugin does itself now, and an unlisted one is still a permission
///   error.
/// - "opens an address in the phone's browser in the app, and in a new tab in a browser": there is one way to open
///   an address, the ground's.
/// - "says the binary is ready only when it is the generation the manifest asks for, or newer": the comparison is
///   the ground's `hasNativeGeneration` (the page's core/nativeGeneration.ts), so the case holds that the host asks
///   it for the manifest's generation and answers what it says.

final Matcher refused = throwsA(isA<PluginPermissionError>());
Matcher refusedSaying(String words) => throwsA(isA<PluginPermissionError>().having((e) => e.toString(), 'words', contains(words)));

void main() {
  late TestGround on;
  setUp(() {
    on = TestGround();
    usePluginGround(on.ground);
  });
  tearDown(() => usePluginGround(PluginGround()));

  group('a plugin’s host', () {
    test('calls only the native commands its manifest lists', () async {
      final host = createHost(manifestOf('n', permissions: [Permission.native], native: const PluginNative(generation: 1, commands: ['allowed'])));
      await expectLater(host.invoke<Object?>('allowed'), throwsA(isA<UnsupportedError>()));
      await expectLater(host.invoke<Object?>('reset_local_data'), refusedSaying('the native command “reset_local_data”'));
    });

    test('refuses native calls without the native permission, even for a listed command', () async {
      final host = createHost(manifestOf('n', native: const PluginNative(generation: 1, commands: ['allowed'])));
      await expectLater(host.invoke<Object?>('allowed'), refusedSaying('the “native” permission'));
    });

    test('reads and writes only its own storage keys', () {
      final host = createHost(manifestOf('s', storage: ['glyph-mine']));
      host.storage.set('glyph-mine', {'a': 1});
      expect(host.storage.get<Object?>('glyph-mine', null), {'a': 1});
      expect(() => host.storage.get<Object?>('glyph-notes', null), refused);
      expect(() => host.storage.set('glyph-preferences', const <String, Object?>{}), refused);
      expect(() => host.storage.remove('glyph-preferences'), refused);
      host.storage.remove('glyph-mine');
      expect(host.storage.get('glyph-mine', 'gone'), 'gone');
    });

    test('tells what draws from a plugin’s storage once a change is made, a removal as much as a write', () {
      final host = createHost(manifestOf('t', storage: ['glyph-told']));
      final heard = <Object?>[];
      final stop = onPluginStorage(() => heard.add(host.storage.get<Object?>('glyph-told', 'gone')));
      host.storage.set('glyph-told', {'a': 1});
      host.storage.remove('glyph-told');
      stop();
      host.storage.set('glyph-told', 2);
      expect(heard, [
        {'a': 1},
        'gone',
      ], reason: 'each listener reads what the change left, not what was there before it');
    });

    test('parses a key once for as long as its stored text is the same, and again as soon as anything changes it', () {
      final host = createHost(manifestOf('c', storage: ['glyph-cached']));
      host.storage.set('glyph-cached', {
        'links': {'n1': 'b1'},
      });
      final first = host.storage.get<Map<String, Object?>>('glyph-cached', const {'links': <String, Object?>{}});
      // The same text: the same parsed value, not a fresh parse.
      expect(identical(host.storage.get<Object?>('glyph-cached', null), first), isTrue);
      // Written behind the host's back (a reset, another device's settings): the text differs, so it is read again.
      on.kept.writeText('glyph-cached', '{"links":{"n2":"b2"}}');
      expect(host.storage.get<Object?>('glyph-cached', null), {
        'links': {'n2': 'b2'},
      });
      // Written through the host: the next read is the new value.
      host.storage.set('glyph-cached', {'links': <String, Object?>{}});
      expect(host.storage.get<Object?>('glyph-cached', null), {'links': <String, Object?>{}});
      host.storage.remove('glyph-cached');
      expect(host.storage.get('glyph-cached', 'gone'), 'gone');
    });

    test('asserts permissions it declared and refuses the rest', () {
      final host = createHost(manifestOf('p', name: 'P', permissions: [Permission.network]));
      expect(() => host.need(Permission.network), returnsNormally);
      expect(() => host.need(Permission.ai), refusedSaying("The P plugin didn't declare the “ai” permission."));
    });
  });

  group('a plugin’s host, on the phone and in a browser', () {
    test('opens an address in the phone’s browser in the app, and in a new tab in a browser', () async {
      await createHost(manifestOf('p', permissions: [Permission.network])).openUrl('https://www.notion.so/');
      expect(on.opened, ['https://www.notion.so/']);
    });

    test('opens nothing for a plugin that did not ask for the network', () async {
      final host = createHost(manifestOf('p', name: 'P'));
      await expectLater(host.openUrl('https://example.com/'), refusedSaying("didn't declare the “network” permission"));
      expect(on.opened, isEmpty);
    });

    test('says the binary is ready only when it is the generation the manifest asks for, or newer', () async {
      final wanted = <int>[];
      var has = 12;
      final ground = PluginGround(
        hasNativeGeneration: (generation) async {
          wanted.add(generation);
          return has >= generation;
        },
      );
      final host = createHost(manifestOf('p', permissions: [Permission.native], native: const PluginNative(generation: 12)), ground: ground);
      expect(await host.nativeReady(), isTrue);
      has = 11;
      expect(await host.nativeReady(), isFalse);
      expect(wanted, [12, 12]);
      // The ground a build starts with has everything a plugin needed of the binary, in Dart.
      expect(await createHost(manifestOf('p', native: const PluginNative(generation: 99)), ground: PluginGround()).nativeReady(), isTrue);
    });

    test('is never ready for a plugin that names no binary, which is "nothing asked for", not "nothing needed"', () async {
      expect(await createHost(manifestOf('p', permissions: [Permission.network])).nativeReady(), isFalse);
    });
  });

  // ---- not on the page ---------------------------------------------------------------------------------------------

  group('a plugin’s secrets', () {
    final manifest = manifestOf('k', name: 'K', storage: ['glyph-k'], secrets: ['glyph-k-token', 'glyph-k-webhook:']);

    test('are kept in the secure store, never in its storage, by the names its manifest lists', () async {
      final host = createHost(manifest);
      await host.secrets.write('glyph-k-token', 'secret');
      expect(on.secrets.held, {'glyph-k-token': 'secret'});
      expect(on.kept.keys(), isEmpty);
      expect(await host.secrets.read('glyph-k-token'), 'secret');
      await host.secrets.write('glyph-k-token', null);
      expect(on.secrets.held, isEmpty);
      expect(await host.secrets.read('glyph-k-token'), isNull);
    });

    test('take a name under a prefix that ends in a colon, and not the prefix alone or any other name', () async {
      final host = createHost(manifest);
      await host.secrets.write('glyph-k-webhook:general', 'https://hooks.example/1');
      expect(await host.secrets.read('glyph-k-webhook:general'), 'https://hooks.example/1');
      await expectLater(host.secrets.read('glyph-k-webhook:'), refusedSaying('the secret “glyph-k-webhook:”'));
      await expectLater(host.secrets.read('glyph-other-token'), refused);
      await expectLater(host.secrets.write('glyph-k-token-2', 'x'), refused);
      expect(() => host.secrets.held('glyph-account-keys'), refused);
      expect(on.secrets.held.keys, ['glyph-k-webhook:general']);
    });

    test('answer at once what was last read or written, and nothing before the first read', () async {
      on.secrets.held['glyph-k-token'] = 'kept';
      final host = createHost(manifest);
      expect(host.secrets.held('glyph-k-token'), isNull);
      await host.secrets.read('glyph-k-token');
      expect(host.secrets.held('glyph-k-token'), 'kept');
      await host.secrets.write('glyph-k-token', 'newer');
      expect(host.secrets.held('glyph-k-token'), 'newer');
      // One store, one memory of it: another host of the same manifest holds the same.
      expect(createHost(manifest).secrets.held('glyph-k-token'), 'newer');
    });

    test('are read once at launch, every exact name, and whatever draws from them is told if anything was there', () async {
      on.secrets.held['glyph-k-token'] = 'kept';
      on.secrets.held['glyph-k-webhook:general'] = 'hook';
      final host = createHost(manifest);
      var heard = 0;
      final stop = onPluginStorage(() => heard++);
      addTearDown(stop);
      await host.secrets.warm();
      expect(host.secrets.held('glyph-k-token'), 'kept');
      // A prefix names several; which ones is the plugin's own list to keep, and it reads them itself.
      expect(host.secrets.held('glyph-k-webhook:general'), isNull);
      expect(heard, 1);
      await host.secrets.warm();
      expect(heard, 1, reason: 'nothing new was read');
    });

    test('tell what draws from the plugin when one is written', () async {
      final host = createHost(manifest);
      final heard = <String?>[];
      final stop = onPluginStorage(() => heard.add(host.secrets.held('glyph-k-token')));
      await host.secrets.write('glyph-k-token', 'a');
      await host.secrets.write('glyph-k-token', null);
      stop();
      await host.secrets.write('glyph-k-token', 'b');
      expect(heard, ['a', null]);
    });

    test('read as nothing from a store that will not answer, and are held for this run when it will not keep them', () async {
      final host = createHost(manifest, ground: PluginGround(secrets: _RefusingStore()));
      expect(await host.secrets.read('glyph-k-token'), isNull);
      await host.secrets.write('glyph-k-token', 'held');
      expect(host.secrets.held('glyph-k-token'), 'held');
    });

    test('are forgotten by the hosts when another ground is put under them', () async {
      final host = createHost(manifest);
      await host.secrets.write('glyph-k-token', 'first ground');
      var heard = 0;
      final stop = onPluginStorage(() => heard++);
      addTearDown(stop);
      usePluginGround(TestGround().ground);
      expect(host.secrets.held('glyph-k-token'), isNull);
      expect(heard, 1);
      expect(await host.secrets.read('glyph-k-token'), isNull);
    });
  });

  group('a plugin’s requests', () {
    FetchRequest to(String url) => FetchRequest(method: 'GET', url: Uri.parse(url));

    test('reach only the hosts its manifest lists, or a name under one', () async {
      final host = createHost(manifestOf('g', name: 'G', permissions: [Permission.network], hosts: ['api.github.com', 'Example.org']));
      expect((await host.fetch(to('https://api.github.com/repos/o/r'))).status, 200);
      await host.fetch(to('https://uploads.api.github.com/x'));
      await host.fetch(to('https://EXAMPLE.org/x'));
      expect([for (final request in on.asked) request.url.host], ['api.github.com', 'uploads.api.github.com', 'example.org']);
      for (final url in ['https://github.com/o/r', 'https://evilapi.github.com.example/x', 'https://notapi.github.com/x', 'https://api.github.com.evil.test/x']) {
        await expectLater(host.fetch(to(url)), refusedSaying('the host “'), reason: url);
      }
      expect(on.asked, hasLength(3));
    });

    test('are refused without the network permission, as a failed request and not a throw', () async {
      final host = createHost(manifestOf('g', name: 'G', hosts: ['api.github.com']));
      late Future<FetchResponse> asked;
      expect(() => asked = host.fetch(to('https://api.github.com/')), returnsNormally);
      await expectLater(asked, refusedSaying("didn't declare the “network” permission"));
      expect(on.asked, isEmpty);
    });

    test('go nowhere on the ground a build starts with, which says so', () async {
      final host = createHost(manifestOf('g', permissions: [Permission.network], hosts: ['api.github.com']), ground: PluginGround());
      await expectLater(host.fetch(to('https://api.github.com/')), throwsStateError);
    });
  });

  group('the ground', () {
    test('is read when a host is used, not when it is made, so a host made as its file loads stands on the app’s', () {
      final host = createHost(manifestOf('s', storage: ['glyph-mine']));
      final later = TestGround();
      usePluginGround(later.ground);
      host.storage.set('glyph-mine', 1);
      expect(later.kept.readText('glyph-mine'), '1');
      expect(on.kept.readText('glyph-mine'), isNull);
      expect(identical(pluginGround, later.ground), isTrue);
    });

    test('reads a key kept in another shape as nothing kept', () {
      final host = createHost(manifestOf('s', storage: ['glyph-mine']));
      on.kept.writeText('glyph-mine', '"words"');
      expect(host.storage.get<Map<String, Object?>>('glyph-mine', const {}), isEmpty);
      on.kept.writeText('glyph-mine', 'not json');
      expect(host.storage.get<Object?>('glyph-mine', 'fallback'), 'fallback');
    });
  });
}

class _RefusingStore implements SecureStore {
  @override
  Future<String?> read(String name) => Future.error(StateError('locked'));

  @override
  Future<void> write(String name, String? value) => Future.error(StateError('locked'));
}
