import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'account/crypto.dart';
import 'app/ghost_app.dart';
import 'core/native/core.dart';
import 'core/native/device_paths.dart';
import 'core/native/ghost_core.dart';
import 'core/open_link.dart';
import 'core/phone_links.dart';
import 'core/preferences.dart';
import 'core/stored.dart';
import 'core/stored_device.dart';
import 'root/account_wiring.dart';
import 'root/ghost_root.dart';
import 'root/voice_wiring.dart';

/// The stylesheets the token engine reads after the kit's own, in the order the web app's page loads them
/// (tool/sync-design.sh copies them from ../glyph).
const appStyleSheets = ['assets/css/ink.css', 'assets/css/app.css', 'assets/css/typefaces.css'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge to edge, as the web app's page is under Android's bars: the page pads itself by the safe areas.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final sheet = await loadTokenSheet(more: appStyleSheets);
  // What this device chose and how it left things, before anything is drawn. Storage that will not answer is not
  // waited for: the app opens on its defaults and remembers nothing this run.
  try {
    await preferences.load().timeout(const Duration(seconds: 2));
    useStored(await DeviceStored.open().timeout(const Duration(seconds: 2)));
  } catch (_) {
    // Refused (core/stored.dart): a device that cannot remember, not an error.
  }
  // The notes library: the web app's own Rust, asked across FFI (lib/core/native). A phone where it will not load
  // still opens, on the invented library, rather than on nothing.
  CoreInvoke? core;
  AccountMaking? account;
  VoiceMaking? voice;
  try {
    final native = await GhostCore.open();
    final dirs = await DevicePaths.find();
    await native.init(dataDir: dirs.dataDir, cacheDir: dirs.cacheDir);
    core = native.invoke;
    // The account, only in a build told where its service is (`--dart-define=GHOST_API=http://…`), and never the
    // real service from a debug build (docs/STAGE7.md). With none, nothing of the account is made at all.
    final base = accountBase(ghostApiDefine);
    if (base != null) {
      account = AccountMaking(base: base, crypto: await CoreCrypto.withLane(native), dataDir: dirs.dataDir);
      debugPrint('[ghost] this build has an account service: $base');
    } else if (ghostApiDefine.isNotEmpty) {
      debugPrint('[ghost] GHOST_API was refused: a development build never talks to the real service, and a base must be an http address.');
    }
    // Voice: the phone's meeting service attached and what this launch was for read, before the first frame. A
    // model is only ever fetched from where this build was told (`--dart-define=GHOST_MODELS=http://…`), and never
    // from the real mirrors by a build that is not a release. No microphone is opened here, or by anything but a
    // recorder's screen.
    try {
      voice = await VoiceMaking.attach(native, dataDir: dirs.dataDir, mirrors: voiceMirrors(ghostModelsDefine)).timeout(const Duration(seconds: 3));
    } catch (failure) {
      debugPrint('[ghost] voice is off for this run: $failure');
    }
  } catch (failure) {
    debugPrint('[ghost] the library would not open: $failure');
  }
  // One PhoneLinks for the life of the app: it holds the channel the activity says `arrived` on.
  runApp(GhostApp(sheet: sheet, home: GhostRoot(core: core, account: account, voiceMaking: voice, links: PhoneLinks(), openLink: openLink)));
}
