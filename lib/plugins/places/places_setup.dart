/// The Place reminders plugin's setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the voiceover
/// onboarding for the rest of the plugins"). Nothing to sign in to and no key: what a place reminder needs is Android
/// letting the app know where the phone is all the time, asked by the same steps the plugin's page takes
/// (lib/reminders/place_access.dart [PlaceAccessFlow], places_pane.dart).
///
/// 1. **Reminders when you arrive**: what it does, and that where the phone is stays on it.
/// 2. **Allow your location**: Android's prompts in their order, the precise location while in use and then all the
///    time; refused for good, the phone's settings ([placesAllow]). Answered, the setup goes on by itself.
/// 3. **Check it worked**: the access as it stands ([placesSetupResult]), in the words the page and the chip say.
/// 4. **Try it**: hold a to-do, Remind me at a place.
///
/// Where the device has no geofences (a Mac, an iPhone for now) there is nothing to set up here: it is ready.
library;

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../art/lucide.g.dart';
import '../../reminders/place_access.dart';
import '../../reminders/place_host.dart';
import '../onboarding/setup_flow.dart';

/// What the phone last said of the location, as the setup read it: what [PluginSetup.ready] answers by.
final ValueNotifier<PlaceAccess?> placesSetupAccess = ValueNotifier<PlaceAccess?>(null);

/// Asks Android (see the header); what is still to do in a sentence, or null.
Future<String?> placesAllow(PlaceHost? places) async {
  if (places == null) return 'Place reminders ring on an Android phone. Here a place on a to-do is shown and kept.';
  if (await places.access() == PlaceAccess.blocked) {
    await places.openSettings();
    return 'In the phone’s settings, open Permissions › Location and choose Allow all the time, then come back and check.';
  }
  final access = placesSetupAccess.value = await PlaceAccessFlow(host: places, explain: () async => true).run();
  return access == PlaceAccess.blocked ? placeAccessWords(access) : null;
}

/// The check's answer (see the header).
Future<SetupResult> placesSetupResult(PlaceHost? places) async {
  if (places == null) return const SetupResult.ok('Nothing to allow on this device. Place reminders ring on your Android phone.');
  final access = placesSetupAccess.value = await places.access();
  final kept = placeAccessWords(access);
  if (kept == null) return const SetupResult.ok('Allowed all the time. Your phone tells Ghost.md when it arrives at a place on one of your to-dos.');
  return SetupResult.failed(kept, pasteAgain: true);
}

/// The setup (see the header). [places] is the phone's geofences; [phonePlaces] where null.
PluginSetup placesSetup({PlaceHost? Function()? places}) {
  PlaceHost? on() => places == null ? phonePlaces.value : places();
  return PluginSetup(
    id: 'place-reminders',
    name: 'Place reminders',
    hues: const ['green', 'mint', 'cyan'],
    tiles: const [Lucide.mapPin, Lucide.bell, Lucide.listChecks, Lucide.circleCheck],
    ready: () => on() == null || placesSetupAccess.value == PlaceAccess.always,
    watch: (listener) {
      placesSetupAccess.addListener(listener);
      return () => placesSetupAccess.removeListener(listener);
    },
    prepare: () async {
      final host = on();
      if (host != null) placesSetupAccess.value = await host.access();
    },
    about: 'Two short steps: allow your location all the time, and a check that it worked.',
    again: 'The steps from the start: allowing your location, and a check that it worked.',
    steps: [
      const SetupIntro(
        id: 'intro',
        title: 'Reminders when you arrive',
        icon: Lucide.mapPin,
        mark: false,
        points: [
          (Lucide.mapPin, 'Hold a to-do and choose Remind me at a place'),
          (Lucide.bell, 'It reminds you as your phone comes within about 150 metres, while the app is closed'),
          (Lucide.lock, 'Where you are stays on the phone'),
        ],
      ),
      SetupAct(id: 'allow', title: 'Allow your location', icon: Lucide.mapPin, label: 'Allow location', again: 'Allow again', onward: true, run: () => placesAllow(on())),
      SetupCheck(id: 'check', title: 'Check it worked', icon: Lucide.shieldCheck, checking: 'Asking the phone…', run: () => placesSetupResult(on())),
      const SetupDone(id: 'done', title: 'Try it', icon: Lucide.wandSparkles),
    ],
  );
}
