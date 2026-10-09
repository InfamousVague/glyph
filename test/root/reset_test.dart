import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/reset.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/slack/manifest.dart' show webhookPrefix;
import 'package:ghost_md/root/reset_wiring.dart';

/// Starting over in the app put together (lib/root/reset_wiring.dart): the plugins' secrets forgotten by name,
/// Slack's webhooks among them, the device's memory cleared, and the app told to start again.
void main() {
  late MemoryStored kept;
  late MemorySecureStore secrets;

  setUp(() {
    preferences.startWithoutStorage();
    kept = MemoryStored();
    secrets = MemorySecureStore();
    usePluginGround(PluginGround(stored: () => kept, secrets: secrets));
    installBuiltInPlugins();
  });

  tearDown(() {
    usePlugins(createRegistry(const []));
    usePluginGround(PluginGround());
  });

  test('Slack\'s webhooks are named one to a channel, from the channels kept now', () {
    expect(slackSecretNames(), isEmpty);
    kept.write('glyph-slack-channels', [
      {'id': '00112233445566778899aabbccddeeff', 'name': 'general'},
      {'id': 'ffeeddccbbaa99887766554433221100', 'name': 'ops'},
    ]);
    expect(slackSecretNames(), ['${webhookPrefix}00112233445566778899aabbccddeeff', '${webhookPrefix}ffeeddccbbaa99887766554433221100']);
    expect(secretsUnder(webhookPrefix), slackSecretNames());
    expect(secretsUnder('another:'), isEmpty);
    // What the phone's secure store takes for a name: letters, digits, `-`, `_` and `:`, sixty-four at most.
    for (final name in slackSecretNames()) {
      expect(RegExp(r'^[A-Za-z0-9_:-]{1,64}$').hasMatch(name), isTrue, reason: name);
    }
  });

  test('a reset forgets every plugin\'s secret by name, clears the device\'s memory but what is spared, and starts again', () async {
    final id = '00112233445566778899aabbccddeeff';
    kept.write('glyph-slack-channels', [
      {'id': id, 'name': 'general'},
    ]);
    kept.write('glyph-entry-drafts', {'a': 1});
    kept.write('glyph-developer', true);
    kept.write('someone-elses', 'kept');
    await secrets.write('$webhookPrefix$id', 'https://hooks.slack.com/services/T/B/x');
    for (final name in plugins.secretNames().where((name) => !name.endsWith(':'))) {
      await secrets.write(name, 'a token');
    }
    var restarts = 0;
    await resetLocalData(resetGroundFor(kept: () => kept, restart: () => restarts += 1), models: false);
    expect(secrets.held, isEmpty);
    expect(kept.keys().toSet(), {'glyph-developer', 'someone-elses'});
    expect(restarts, 1);
  });

  test('a reset is refused while a meeting is being recorded, with nothing touched', () async {
    kept.write('glyph-entry-drafts', {'a': 1});
    var restarts = 0;
    final ground = resetGroundFor(invoke: (command, [args = const {}]) async => fail('the core was asked for $command'), recordingNow: () => true, kept: () => kept, restart: () => restarts += 1);
    await expectLater(resetLocalData(ground, models: false), throwsA(isA<StateError>().having((e) => e.message, 'message', stopTheMeeting)));
    expect(kept.keys(), contains('glyph-entry-drafts'));
    expect(restarts, 0);
  });
}
