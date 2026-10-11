import '../core/preferences.dart';

export '../core/preferences.dart';

/// The preferences under the name they had while this file was a stand-in for them. They are
/// lib/core/preferences.dart now, a port of the web app's src/app/core/preferences.ts: [Preferences], and the store
/// `preferences`, which this file hands on. New code imports that file and says [Preferences].
///
/// What changed for code written against the stand-in: the defaults are the web's (the theme is `dark`, not
/// `system`; the text size `large` and the rounding `round`, not `default`), and the haptics switch is no longer a
/// preference but this device's own flag, `hapticsPref`.
typedef AppPreferences = Preferences;
