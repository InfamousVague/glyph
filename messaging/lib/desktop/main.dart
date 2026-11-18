import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../accent.dart';
import '../app_state.dart';
import '../kit/settings_css.dart';
import '../looks.dart';
import '../main.dart' show InkOverrides, ghostTypography;
import '../sounds.dart';
import '../sms.dart';
import '../ui/files_space/share_in.dart';
import '../ui/window_chrome.dart';
import '../ui/settings_panes.dart' show appVersion;
import 'desk.dart';
import 'link/link.dart';
import 'platform.dart';
import 'remote.dart';
import '../voice/channels.dart';
import '../voice/discord.dart';
import '../voice/space_groups.dart';
import 'store.dart';
import 'ui/shell.dart';
import '../ui/update_banner.dart';
import 'ui/wizard.dart';
import '../inbox/inbox.dart';
import '../ui/inbox_ui.dart';
import '../circles/circles.dart';
import '../files/files_store.dart';
import 'gm_web.dart';
import 'updates.dart';
import '../people.dart';
import '../me/me.dart';
import '../standalone/standalone.dart';
import '../standalone/welcome.dart';
import 'ui/link_offer.dart';

/// Ghost Messaging on a computer (Matt, 2026-11-13: "a companion desktop app that can proxy messages encrypted from
/// my phone to my desktop and then send back to the phone to send again"; docs/desktop.md). The phone's screens,
/// with the link to the phone where the phone has Android: paired by a QR code, sealed between the two, over the
/// local network first and a relay when that fails.
///
/// Started with `GHOST_DESK_PEERS=host:port[,host:port]` it tries those addresses for the phone before any it finds
/// (an emulator's forwarded port; a network that hides the two from each other), `GHOST_DESK_DIR` keeps what it
/// keeps in another folder, and `GHOST_DESK_BONJOUR=off` leaves the local network unsearched.
///
/// [peers], [folder] and [bonjour] are the same three, for a test that starts the app itself
/// (integration_test/desk_live_test.dart). The app looks for a newer version of itself (updates.dart) unless
/// `GHOST_DESK_UPDATES=off` or [updates] is false, as it is for a test.
Future<void> desktopMain({List<Peer>? peers, String? folder, bool? bonjour, bool updates = true}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final dir = folder ?? env['GHOST_DESK_DIR'];
  // The Keychain holds the key in a release build. A build signed to run on this Mac alone loses its Keychain
  // items' trust each time it is rebuilt, so those keep the key in the app's own folder.
  final store = DeskStore(dir == null || dir.isEmpty ? DeskStore.defaultDir() : Directory(dir), keychain: const bool.fromEnvironment('GHOST_DESK_KEYCHAIN', defaultValue: kReleaseMode));
  final envPeers = peers ?? [for (final p in (env['GHOST_DESK_PEERS'] ?? '').split(',')) ?Peer.parse(p)];
  final prefs = await store.prefs();
  final link = PhoneLink(
    store: store,
    name: await MacPlatform.computerName(),
    app: appVersion,
    // Bonjour is the Mac's and the iPhone's (DeskChannels.swift); on Windows the phone is found by its address or the relay.
    finder: !(bonjour ?? (env['GHOST_DESK_BONJOUR'] != 'off' && (Platform.isMacOS || Platform.isIOS))) ? null : BonjourFinder(),
    given: [...envPeers, ?Peer.parse(prefs['peer'] ?? '')],
  );
  final calls = LinkCalls(link, store);
  await calls.init();
  // With no phone linked, the computer is Ghost Messaging of its own, as an iPhone is (lib/standalone; Matt, 2026-11-18:
  // "a user can use the app without linking the phone since some people may be joining just to enter circles or use
  // telegram and signal but not SMS"): friends by username, circles, Telegram and Signal, answered here. Linking a
  // phone later is a step of its own, and the app opens again on its link (restartApp).
  final alone = await store.load() == null;
  if (alone) {
    final own = StandaloneCalls(Directory('${store.dir.path}/standalone'), keychain: const bool.fromEnvironment('GHOST_DESK_KEYCHAIN', defaultValue: kReleaseMode));
    await own.load();
    Sms.calls = own;
    Sms.standalone = true;
  }
  // Where a voice message the Mac is playing has got to, told to the screens as the phone tells its own.
  MacPlatform.listenToVoice((m) => Sms.instance.voice.add(VoicePlayback.from(m)));
  if (!alone) Sms.calls = calls;
  // Google Messages on this computer (gm_web.dart): its helper started where this copy carries it, and what changes
  // there told to the screens as the phone's changes are.
  GmWeb.instance.changed.stream.listen(Sms.instance.changes.add);
  unawaited(GmWeb.instance.start(store.dir));
  final state = AppState();
  final loaded = await Future.wait<Object?>([AccentSheets.load(), state.load()]);
  final accents = loaded[0]! as AccentSheets;
  final sheet = accents.base;
  installSettingsStyles(sheet);
  await link.start();
  // Voice channels (lib/voice): the computer's own connection to the hub, made once it has a channel.
  // The interface sounds (lib/sounds.dart) read the person's choices from here.
  Sounds.instance.start(state);
  // And the circles, whose rooms ride Voice's connection (lib/circles/circles.dart).
  // On its own it runs the app's network itself, as the phone does: the routes, friends, groups, then voice and circles
  // (lib/people.dart). Paired, those are the phone's, asked across the link.
  if (alone) {
    startPeople(state);
  } else {
    unawaited(Voice.instance.start(state).then((_) => Circles.instance.start(state)));
  }
  // Files spaces' files (lib/files/files_store.dart): what was going up when the app closed goes on. And files dropped
  // on the window with no Files space showing are offered to one (lib/ui/files_space/share_in.dart; Matt, 2026-11-17:
  // "Finish the missing pieces that went unfinished").
  unawaited(FilesStore.instance.start());
  FilesShareIn.attach();
  SpaceGroups.instance.start(state);
  DiscordServers.instance.start(state);
  // Telegram's and Bluesky's chats (lib/inbox): the computer signs in to them itself, as their own apps do.
  addInboxSettings();
  unawaited(Inbox.instance.start(state));
  // The app's own updates: asked of the Mac's half, looked for now and every few hours. Never awaited: the app
  // opens whether or not the site answers.
  // A Mac swaps in the Mac's zip; Windows runs the new installer from gogho.st, silently, on Restart to update.
  final macUpdates = updates && (Platform.isMacOS || Platform.isWindows) ? MacUpdates.fromEnvironment(env, windows: Platform.isWindows) : null;
  if (macUpdates != null) {
    // Told to the phone's screens too, so its banner and its words are the computer's (remote.dart).
    calls.attachUpdates(macUpdates);
    unawaited(macUpdates.start());
  }
  runApp(DesktopApp(sheet: sheet, state: state, link: link, calls: calls, store: store, envPeers: envPeers, updates: macUpdates, accents: accents));
}

class DesktopApp extends StatefulWidget {
  const DesktopApp({super.key, required this.sheet, required this.state, required this.link, required this.calls, required this.store, this.envPeers = const [], this.updates, this.accents, this.relaunch});
  final TokenSheet sheet;

  /// The stylesheets with the bubble colour chosen everywhere as the accent (lib/accent.dart); [sheet] alone where
  /// not given.
  final AccentSheets? accents;
  final AppState state;
  final PhoneLink link;
  final LinkCalls calls;
  final DeskStore store;
  final List<Peer> envPeers;
  final MacUpdates? updates;

  /// In place of opening the app again (restartApp), for a test.
  final Future<void> Function()? relaunch;

  @override
  State<DesktopApp> createState() => _DesktopAppState();
}

class _DesktopAppState extends State<DesktopApp> {
  /// This copy's navigator, its own: files dropped on the window are asked about on it (FilesShareIn). A key shared by
  /// every copy (a static one) carried one copy's pages, with the link they were made with, into the next mounted.
  final _navigator = GlobalKey<NavigatorState>(debugLabel: 'desk');

  @override
  void initState() {
    super.initState();
    FilesShareIn.navigateWith(_navigator);
  }

  @override
  Widget build(BuildContext context) {
    final DesktopApp(:relaunch, :link, :calls, :store, :envPeers, :updates, :state, :accents, :sheet) = widget;
    return DeskScope(
      relaunch: relaunch,
      link: link,
      calls: calls,
      store: store,
      envPeers: envPeers,
      updates: updates,
      child: AppScope(
        state: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => WidgetsApp(
            title: 'Ghost Messaging',
            color: const Color(0xFF4F5BD5),
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigator,
            pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
            // Each page that opens asks for a look for a newer version, as on the phone.
            navigatorObservers: [UpdateWatch()],
            builder: (context, child) => GlacierTheme(
              sheet: accents?.of(state) ?? sheet,
              attrs: ghostAttrs(state, 'desktop'),
              typography: ghostTypography(state.emoji),
              // A newer version says so with the card the phone has, at the top of the list (lib/ui/update_banner.dart).
              child: InkOverrides(child: GlacierToastProvider(child: child!)),
            ),
            home: const DeskHome(),
          ),
        ),
      ),
    );
  }
}

/// What a computer opens on. With a phone linked as it started: the conversations, or the wizard once it has been
/// unpaired. On its own (Sms.standalone): a username first, then linking a phone offered once and passed by as easily
/// (Matt, 2026-11-18: "make setting up SMS and such and linking to a phone an optional step"), then the conversations;
/// a phone linked later, from here or Settings › Your phone, opens the app again on it.
class DeskHome extends StatefulWidget {
  const DeskHome({super.key});

  @override
  State<DeskHome> createState() => _DeskHomeState();
}

class _DeskHomeState extends State<DeskHome> {
  /// Whether linking a phone has been offered and passed by; null until the choices are read.
  bool? _offered;

  /// The wizard, asked for from the offer.
  bool _linking = false;
  bool _restarting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_offered != null || !Sms.standalone) return;
    DeskScope.of(context).store.prefs().then((p) {
      if (mounted) setState(() => _offered = p['phone_offered'] == '1');
    });
  }

  /// Linking passed by: the app at once, and the choice kept so it is not offered again (Settings › Your phone has it).
  void _passBy() {
    final store = DeskScope.of(context).store;
    setState(() {
      _offered = true;
      _linking = false;
    });
    unawaited(store.prefs().then((p) => store.savePrefs({...p, 'phone_offered': '1'})));
  }

  /// Opens the app again on its new footing, once.
  void _restart() {
    if (_restarting) return;
    _restarting = true;
    final relaunch = DeskScope.of(context).relaunch;
    Future.delayed(const Duration(milliseconds: 900), () => restartApp(relaunch: relaunch));
  }

  Widget _wizard({String? skipLabel, VoidCallback? onSkip}) => Stack(children: [
        Positioned.fill(child: PairWizard(skipLabel: skipLabel, onSkip: onSkip)),
        Positioned(left: 0, right: 0, top: 0, height: 56, child: const WindowDragArea(child: SizedBox.expand())),
      ]);

  @override
  Widget build(BuildContext context) {
    final link = DeskScope.of(context).link;
    return ListenableBuilder(
      listenable: Listenable.merge([link, Me.instance]),
      builder: (context, _) {
        final a = link.attempt;
        // Paired a moment ago: the wizard's last step is the conversations themselves.
        if (a != null && a.phase == 'done') WidgetsBinding.instance.addPostFrameCallback((_) => link.pairingShown());
        final linked = link.phone != null && (a == null || a.phase == 'done');
        if (!Sms.standalone) {
          if (linked) return DeskShell(key: ValueKey(link.phone!.id));
          // Unpaired since it opened: the wizard, or the app of its own again.
          return _wizard(skipLabel: 'Use without a phone', onSkip: _restart);
        }
        // Linked from here or from Settings: the app opens again on the phone.
        if (linked) {
          _restart();
          return LinkRestarting(phone: link.phone!.name);
        }
        if (_linking) {
          return _wizard(
            skipLabel: 'Not now',
            onSkip: () {
              unawaited(link.cancelPairing());
              _passBy();
            },
          );
        }
        // The username is how anyone reaches someone here (lib/standalone/welcome.dart).
        if (Me.instance.username == null) {
          return Stack(children: [
            Positioned.fill(child: StandaloneWelcome(onDone: () => setState(() {}))),
            Positioned(left: 0, right: 0, top: 0, height: 56, child: const WindowDragArea(child: SizedBox.expand())),
          ]);
        }
        if (_offered == null) return ColoredBox(color: context.tokens.color('glacier-bg'));
        if (!_offered!) {
          return Stack(children: [
            Positioned.fill(child: LinkOffer(onLink: () => setState(() => _linking = true), onSkip: _passBy)),
            Positioned(left: 0, right: 0, top: 0, height: 56, child: const WindowDragArea(child: SizedBox.expand())),
          ]);
        }
        return const DeskShell(key: ValueKey('alone'));
      },
    );
  }
}
