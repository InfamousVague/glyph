import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'account/crypto.dart';
import 'app/front_frames.dart';
import 'app/ghost_app.dart';
import 'core/native/core.dart';
import 'core/native/device_paths.dart';
import 'core/native/ghost_core.dart';
import 'core/locale_dates.dart';
import 'core/geocode.dart';
import 'core/keep_keyboard.dart';
import 'core/films.dart';
import 'core/open_link.dart';
import 'core/phone_films.dart';
import 'core/phone_day.dart';
import 'core/phone_pictures.dart';
import 'core/phone_position.dart';
import 'editor/media/map_tiles.dart';
import 'core/phone_links.dart';
import 'core/preferences.dart';
import 'core/stored.dart';
import 'core/stored_device.dart';
import 'core/updates.dart';
import 'root/account_wiring.dart';
import 'core/link_preview.dart' show linkPreviewFetch;
import 'root/ghost_root.dart';
import 'root/plugin_ground.dart';
import 'root/voice_wiring.dart';
import 'shell/desktop/desktop_commands.dart';
import 'shell/desktop/mac_tour.dart';
import 'shell/desktop/mac_window.dart';
import 'tapes/phone_player.dart';

/// The stylesheets the token engine reads after the kit's own, in the order the web app's page loads them
/// (tool/sync-design.sh copies them from ../glyph).
const appStyleSheets = ['assets/css/ink.css', 'assets/css/app.css', 'assets/css/typefaces.css'];

Future<void> main() async {
  // Flutter's binding, which draws nothing while Android is taking the app from the front (app/front_frames.dart).
  GhostBinding.ensureInitialized();
  // The keyboard that was up when the app was left is up again when it is come back to (core/keep_keyboard.dart).
  KeepKeyboard.install();
  // Every date in the phone's own words and order, as the page's Intl writes them (core/locale_dates.dart).
  useLocaleOf(PlatformDispatcher.instance.locale);
  // Edge to edge, as the web app's page is under Android's bars: the page pads itself by the safe areas.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // The Mac app's window (its menu bar, its three lights) and a desktop's keys: nothing on a phone.
  MacWindow.instance.attach();
  DesktopKeys.attach();
  final sheet = await loadTokenSheet(more: appStyleSheets);
  // What this device chose and how it left things, before anything is drawn. Storage that will not answer is not
  // waited for: the app opens on its defaults and remembers nothing this run.
  try {
    await preferences.load().timeout(const Duration(seconds: 2));
    useStored(await DeviceStored.open().timeout(const Duration(seconds: 2)));
  } catch (_) {
    // Refused (core/stored.dart): a device that cannot remember, not an error.
  }
  // The plugins that ship, on the phone's own memory, secure store and network (lib/root/plugin_ground.dart):
  // before the first screen, since Settings' rows, the editor's parser and the Academy's lessons read them.
  installPlugins();
  // The notes library: the web app's own Rust, asked across FFI (lib/core/native). A phone where it will not load
  // still opens, on the invented library, rather than on nothing.
  CoreInvoke? core;
  GhostCore? whole;
  AccountMaking? account;
  VoiceMaking? voice;
  try {
    final native = await GhostCore.open();
    final dirs = await DevicePaths.find();
    await native.init(dataDir: dirs.dataDir, cacheDir: dirs.cacheDir);
    core = native.invoke;
    whole = native;
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
  // The app's updates, only in a build told where its own releases are (`--dart-define=GHOST_UPDATES=https://…`)
  // and never in a debug build (lib/core/updates.dart): with none, nothing is asked of anywhere. One for the
  // process, as the core is; it begins to look once the root is up.
  final updates = core == null ? null : Updates.forBuild(invoke: core, localOnly: () => preferences.value.localOnly);
  if (updates != null) debugPrint('[ghost] this build looks for updates at ${updates.config.source}');
  // One PhoneLinks for the life of the app: it holds the channel the activity says `arrived` on.
  final links = PhoneLinks();
  // And one player of a note's recording, the phone's own.
  final tapes = PhoneTapePlayer();
  // A film in a note: the phone's picker, the core that keeps it and the phone's player (Android only, as the
  // page's was).
  Films? films;
  if (core != null && defaultTargetPlatform == TargetPlatform.android) {
    films = Films(device: PhoneFilmDevice(core), pick: phoneFilmPicker(core, kept: (video) => films?.kept(video)));
  }
  // Where the phone is, for a note keeping its place: asked only from a press, or for a new note with tagging on.
  // The place's name is OpenStreetMap's, asked once as the app itself; so are a tagged note's tiles.
  final locator = await PhoneLocator().attach();
  final placeLookup = geocodePlace(geocodeFetcher(), lang: () => PlatformDispatcher.instance.locale.toLanguageTag());
  final mapTiles = MapTiles().builder;
  runApp(GhostApp(
    sheet: sheet,
    home: _Runs(
      builder: (restart) => GhostRoot(core: core, native: whole, account: account, voiceMaking: voice, links: links, openLink: openLink, previewFetch: linkPreviewFetch(), restart: restart, tapePlayer: tapes, updates: updates, locator: locator, placeLookup: placeLookup, mapTiles: mapTiles, picturePicker: phonePicturePicker, films: films, dayPicker: defaultTargetPlatform == TargetPlatform.android ? phoneDayPicker : null),
    ),
  ));
  // A debug build of the Mac app started with a script walks itself (lib/shell/desktop/mac_tour.dart).
  unawaited(runMacTour());
}

/// The app, built anew each time it is started over (Developer's resets, lib/core/reset.dart): what
/// `window.location.reload()` was to the page. The core, the phone's halves and the links' channel are the
/// process's and stay; everything the root made from them is made again, on a library that is empty.
class _Runs extends StatefulWidget {
  const _Runs({required this.builder});
  final Widget Function(VoidCallback restart) builder;

  @override
  State<_Runs> createState() => _RunsState();
}

class _RunsState extends State<_Runs> {
  int _run = 0;

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: ValueKey<int>(_run), child: widget.builder(() => setState(() => _run += 1)));
}
