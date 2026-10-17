/// Asking the phone for the location a place reminder needs, in Android's order (docs/INTEGRATIONS.md §3): the
/// precise location while the app is in use first, then "Allow all the time", which Android only offers to an app that
/// has the first, and only after the app has said why. A geofence rings with the app closed, so without the second it
/// never rings at all.
///
/// - **Allowed all the time**: nothing is asked.
/// - **Never asked** (or asked and dismissed): Android's own prompt for the location while in use, then on.
/// - **Approximate only**: the same prompt, which Android shows as the switch to Precise; a geofence needs it.
/// - **Precise while in use**: the app's own sheet first ([PlaceAccessFlow.explain], which says why and what to pick),
///   and only on its Continue Android's "Allow all the time" (from Android 11 a page of the phone's settings).
/// - **Refused for good**: nothing is asked; the chip warns, and Settings › Notifications › Reminders says how.
///
/// Each step is [placeStepFor], pure, so every state is a test (test/reminders/place_access_test.dart).
library;

import 'place_host.dart';

/// What comes next for an access.
enum PlaceStep {
  /// Allowed all the time: nothing to ask.
  done,

  /// Android's prompt for the precise location while the app is in use.
  askForeground,

  /// The app's sheet saying why, then Android's "Allow all the time".
  explainBackground,

  /// Refused for good: only the phone's settings can allow it.
  settings,
}

/// The step after [access].
PlaceStep placeStepFor(PlaceAccess access) => switch (access) {
  PlaceAccess.always => PlaceStep.done,
  PlaceAccess.ask || PlaceAccess.approximate => PlaceStep.askForeground,
  PlaceAccess.whileUsing => PlaceStep.explainBackground,
  PlaceAccess.blocked => PlaceStep.settings,
};

/// Whether a place reminder warns with [access]: anything but all the time, where the phone could say.
bool placeAccessWarns(PlaceAccess? access) => access != null && access != PlaceAccess.always;

/// What Settings and the chip say for an access that keeps place reminders from ringing; null where none does.
String? placeAccessWords(PlaceAccess? access) => switch (access) {
  null || PlaceAccess.always => null,
  PlaceAccess.whileUsing => 'Android only lets Ghost.md know where you are while it is open, so it can’t tell when you arrive. Allow location all the time below.',
  PlaceAccess.approximate => 'Android only gives Ghost.md your approximate location, and a place reminder needs the precise one. Allow precise location below.',
  PlaceAccess.ask => 'Ghost.md hasn’t been allowed your location yet, so it can’t tell when you arrive. Allow it below.',
  PlaceAccess.blocked => 'Location is turned off for Ghost.md. In the phone’s settings, open Permissions › Location and choose Allow all the time.',
};

/// The steps, run against the phone.
class PlaceAccessFlow {
  PlaceAccessFlow({required this.host, required this.explain});

  final PlaceHost host;

  /// The app's own sheet before "Allow all the time": true for Continue, false where it was put away.
  final Future<bool> Function() explain;

  /// Asks what is still to be asked, once each, and answers the access as it stands at the end; null where there is
  /// no phone half. [placeWarning] follows it.
  Future<PlaceAccess?> run() async {
    var access = await host.access();
    if (access == null) return null;
    var askedForeground = false;
    for (;;) {
      final step = placeStepFor(access!);
      if (step == PlaceStep.askForeground && !askedForeground) {
        askedForeground = true;
        access = await host.askForeground();
        continue;
      }
      if (step == PlaceStep.explainBackground) {
        if (await explain()) access = await host.askBackground();
      }
      break;
    }
    placeWarning.value = placeAccessWarns(access);
    return access;
  }
}
