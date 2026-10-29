/// The Place reminders plugin's page in Settings (places.dart): how a place reminder is made and what arriving does,
/// then whether Android lets the app know where the phone is all the time, which a geofence needs, and the way to
/// allow it: Android's own prompts in their order, or the phone's settings once they will not ask again
/// (lib/reminders/place_access.dart). Read as the page opens and again every second while something is kept from it,
/// as Settings › Notifications › Reminders reads its own, so coming back from the phone's settings shows the change.
///
/// Where the phone has no geofences (a Mac, an iPhone for now: docs/INTEGRATIONS.md §3) the page says so: a place
/// written on a to-do is still drawn and kept there, and reminds on an Android phone.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../reminders/place_access.dart';
import '../../reminders/place_host.dart';
import '../../reminders/reminder_settings.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/pane_parts.dart';
import '../onboarding/setup_card.dart';
import '../onboarding/setup_flow.dart' show PluginSetup;
import 'places_setup.dart';

class PlacesPane extends StatefulWidget {
  const PlacesPane({super.key, this.places, this.reminders});

  /// The phone's geofences: [phonePlaces] unless given.
  final PlaceHost? places;

  /// Settings › Notifications › Reminders: the app's own unless given.
  final ReminderSettingsStore? reminders;

  @override
  State<PlacesPane> createState() => _PlacesPaneState();
}

class _PlacesPaneState extends State<PlacesPane> {
  PlaceAccess? _access;
  bool _read = false;
  Timer? _again;

  PlaceHost? get _places => widget.places ?? phonePlaces.value;
  ReminderSettingsStore get _reminders => widget.reminders ?? reminderSettings;
  late final PluginSetup _setup = placesSetup(places: widget.places == null ? null : () => widget.places);

  @override
  void initState() {
    super.initState();
    unawaited(_look());
  }

  @override
  void dispose() {
    _again?.cancel();
    super.dispose();
  }

  Future<void> _look() async {
    final places = _places;
    final access = places == null ? null : await places.access();
    if (!mounted) return;
    setState(() {
      _access = access;
      _read = true;
    });
    // The setup's card follows what the page read.
    if (places != null) placesSetupAccess.value = access;
    final warns = places != null && placeAccessWarns(access);
    placeWarning.value = warns && _reminders.value.on && placeRemindersOn.value;
    if (!warns) {
      _again?.cancel();
      _again = null;
    } else {
      _again ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_look()));
    }
  }

  /// Android's prompts in their order; the words above the button have said why.
  Future<void> _allow() async {
    final places = _places;
    if (places == null) return;
    if (_access == PlaceAccess.blocked) {
      await places.openSettings();
    } else {
      await PlaceAccessFlow(host: places, explain: () async => true).run();
    }
    await _look();
  }

  @override
  Widget build(BuildContext context) {
    final places = _places;
    final access = _access;
    final kept = placeAccessWords(access);
    return PaneBody(
      children: [
        PluginSetupCard(setup: _setup),
        const PaneSection(
          title: 'How it works',
          description: Text('Hold a to-do and choose Remind me at a place: search for one, pick a place the note already has, or use where you are. When your phone comes within about 150 metres of it, the to-do reminds you, with Done to tick it. Ticked, it stops.'),
          children: [
            SettingRow(label: 'In the note', hint: Text('The place is written on the to-do as a pin and a link, 📍 [Target](geo:…), so other apps show it too.')),
            SettingRow(label: 'Search', hint: Text('A place you search for by name is looked up on OpenStreetMap. Off while Local only is on; a place already in the note, or where you are, still works.')),
          ],
        ),
        PaneSection(
          title: 'Location',
          description: const Text('A place reminder rings while Ghost.md is closed, so Android has to let it know where your phone is all the time. Where you are stays on the phone.'),
          children: [
            if (places == null)
              const SettingRow(label: 'Not on this device', hint: Text('Place reminders ring on an Android phone. Here a place on a to-do is shown and kept, and reminds on your phone.'))
            else if (!_read)
              const SettingRow(label: 'Location', hint: Text('Asking the phone…'))
            else
              SettingRow(
                label: kept == null ? 'Allowed all the time' : 'Not allowed all the time',
                hint: Text(kept ?? 'Your phone tells Ghost.md when it arrives at a place on one of your to-dos.'),
              ),
          ],
        ),
        if (places != null && _read && kept != null)
          PaneActions(
            children: [
              RowAction(
                onPress: () => unawaited(_allow()),
                child: Text(access == PlaceAccess.blocked ? 'Open the phone’s settings' : (access == PlaceAccess.whileUsing ? 'Allow location all the time' : 'Allow location')),
              ),
            ],
          ),
      ],
    );
  }
}
