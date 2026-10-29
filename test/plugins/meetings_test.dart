// Google Meet and Zoom, two plugins (lib/plugins/meetings/; Matt, 2026-10-26: "Make sure the Google Meet and the Zoom
// plugins are two different plugins", and the same day: "I want settings / meetings to be broken up into three plugins
// where each zoom, Google meets and discord handle their own meetings"). Two catalogue entries, each with its own
// switch, both on; a page each in Settings for an account with Ghost in meetings, kept in Simple as Meetings was; no
// Meetings section any more, and with both off nothing of meetings in Settings at all; a link to what was Meetings
// landing on a meeting plugin's page, or on Post to Slack's, or on the Market with neither on.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/meet/meet_kinds.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/meetings/meetings.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/settings/settings_screen.dart' show SettingsTarget;
import 'package:ghost_md/settings/settings_sections.dart';

import '../account_ui/support.dart';
import '../meet/support.dart';

const Preferences _simple = Preferences(theme: 'light', experience: 'simple', experienceChosen: true);
const Preferences _advanced = Preferences(theme: 'light', experience: 'advanced', experienceChosen: true);

void main() {
  late Registry registry;
  setUp(() {
    registry = createRegistry(builtIn, store: MemorySwitches());
    usePlugins(registry);
  });
  tearDown(() => usePlugins(createRegistry(const [])));

  /// A signed-in device whose service has Ghost in meetings.
  Future<Device> meeting() async {
    final meet = FakeMeet();
    final service = await FakeService.start(seed: seeded);
    final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher));
    await device.meetIn!.refresh();
    return device;
  }

  SettingsFacts facts(Preferences prefs, Device? device) => SettingsFacts(prefs: prefs, wide: false, haptics: true, android: true, ios: false, developer: false, services: device?.services);
  List<String> among(SettingsFacts facts) => [
        for (final spec in settingsSections)
          if (spec.where?.call(facts) ?? true) spec.id,
      ];

  test('are two entries of the catalogue, both on, each with its own words, page and plain icon', () {
    final meet = builtIn.singleWhere((p) => p.manifest.id == 'google-meet');
    final zoom = builtIn.singleWhere((p) => p.manifest.id == 'zoom');
    expect((meet.manifest.name, zoom.manifest.name), ('Google Meet', 'Zoom'));
    expect((meet.manifest.standard, zoom.manifest.standard), (true, true));
    expect((meet.manifest.category, zoom.manifest.category), (PluginCategory.connections, PluginCategory.connections));
    // Lucide's: the page of meetings' people, and Zoom's video camera (Matt, 2026-10-29: "change zoom"; Google Meet's mark
    // is drawn in white on its colour alone, lib/plugins/brands.dart).
    expect((meet.icon, zoom.icon), ('users', 'video'));
    expect(meet.manifest.description, isNot(zoom.manifest.description));
    expect((meet.settings!.simple, zoom.settings!.simple), (true, true));
    expect(registry.isEnabled('google-meet') && registry.isEnabled('zoom'), isTrue);
    // Each switch is its own.
    registry.setEnabled('zoom', false);
    expect((registry.isEnabled('google-meet'), registry.isEnabled('zoom')), (true, false));
    expect(meetKindsWanted(), {'meet': true, 'zoom': false});
  });

  test('each has a page in Settings for an account with Ghost in meetings, in Simple too, and there is no Meetings', () async {
    final device = await meeting();
    expect(meetingPluginOffered(device.services), isTrue);
    for (final prefs in [_simple, _advanced]) {
      final ids = among(facts(prefs, device));
      expect(ids, containsAll(['plugin:google-meet', 'plugin:zoom']), reason: prefs.experience);
      expect(ids, isNot(contains('meetings')));
    }
    // Simple keeps no other plugin's page.
    expect([for (final id in among(facts(_simple, device))) if (id.startsWith('plugin:')) id], ['plugin:google-meet', 'plugin:zoom']);
    // Each row reads its own kind's meetings.
    final meet = settingsSections.singleWhere((s) => s.id == 'plugin:google-meet');
    final zoom = settingsSections.singleWhere((s) => s.id == 'plugin:zoom');
    expect((meet.summary!(facts(_advanced, device)), zoom.summary!(facts(_advanced, device))), ('Invite Ghost to a Google Meet', 'Invite Ghost to a Zoom call'));
    expect((meet.hue, zoom.hue), ('orange', 'mint'));
    // Signed out, or a service without Ghost in meetings: neither page.
    expect(among(facts(_advanced, null)), isNot(anyOf(contains('plugin:google-meet'), contains('plugin:zoom'))));
  });

  test('with both off, nothing of meetings is in Settings, and a link to what was Meetings lands on the Market', () async {
    final device = await meeting();
    registry.setEnabled('google-meet', false);
    registry.setEnabled('zoom', false);
    for (final prefs in [_simple, _advanced]) {
      final ids = among(facts(prefs, device));
      expect(ids.where((id) => id == 'meetings' || id == 'plugin:google-meet' || id == 'plugin:zoom'), isEmpty);
    }
    expect(settingsLanding(const SettingsTarget('meetings', nonce: 1)).id, 'market');
  });

  test('a link to what was Meetings lands on a meeting plugin’s page, or Post to Slack’s on Slack’s', () {
    SettingsTarget land(String? setting) => settingsLanding(SettingsTarget('meetings', setting: setting, nonce: 1));
    expect(land(null).id, 'plugin:google-meet');
    registry.setEnabled('google-meet', false);
    expect(land(null).id, 'plugin:zoom', reason: 'Zoom alone on');
    registry.setEnabled('slack', true);
    expect((land('Post to Slack').id, land('Post to Slack').setting), ('plugin:slack', 'Post to Slack'));
    registry.setEnabled('discord', true);
    expect(land('Post to Discord').id, 'plugin:discord');
  });
}
