import 'links.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../games/game_activity.dart';
import '../accent.dart';
import '../account/account.dart';
import '../app_state.dart';
import '../kit/settings_css.dart';
import '../looks.dart';
import '../main.dart' show InkOverrides, ghostTypography;
import '../sounds.dart';
import '../keys.dart';
import '../net/net.dart';
import '../sms.dart';
import '../ui/files_space/share_in.dart';
import '../ui/window_chrome.dart';
import 'ui/desk_title_bar.dart';
import 'ui/launch_splash.dart';
import 'window_size.dart';
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
import '../plugins/pack/pack.dart' show InstalledPlugins;
import 'own_calls.dart';
import '../friends/buddies.dart';
import '../me/me.dart';
import '../standalone/standalone.dart';
import '../friends/handover.dart' show DeskHandover;
import '../standalone/welcome.dart';
import '../ui/account_screens.dart' show SignInScreen;
import '../ui/common.dart' show push;
import '../ui/recording_float.dart';
import 'ui/link_offer.dart';

/// How long a window's size stands still before the theme is worked out for it. Null in a test that sizes a window
/// and looks at once.
Duration? deskResizeSettle = const Duration(milliseconds: 120);

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
  // Paired, and the phone has handed over its identity (lib/desktop/own_calls.dart; Matt, 2026-11-18: "I want desktop
  // to be able to run standalone for internal friends and circles please fix that even if the desktop is linked"):
  // friends by username and the routes are this computer's own, texts the phone's.
  final ownDir = Directory('${store.dir.path}/own');
  const ownKeychain = bool.fromEnvironment('GHOST_DESK_KEYCHAIN', defaultValue: kReleaseMode);
  DeskOwnCalls? own;
  if (!alone && DeskOwnCalls.adoptedIn(ownDir)) {
    own = DeskOwnCalls(calls, ownDir, keychain: ownKeychain);
    await own.load();
  }
  if (!alone) Sms.calls = own ?? calls;
  // The look, for the launch splash (lib/desktop/ui/launch_splash.dart; Matt, 2026-11-20: "add a checking for updates
  // splash window that shows before the app launches and load the app on this screen too similar to how discord does on
  // launch"): it shows while the app looks for an update and loads, in the window the Mac's and Windows' halves have
  // made small for it. Read only now that what answers the screens is chosen (Sms.calls, above): read before, as 0.10.0
  // did, the choices came from nowhere and every launch started with none, a computer of its own back at the welcome
  // (Matt, 2026-11-20: "when signing in the app re launches and I have to login twice").
  final state = AppState();
  final loaded = await Future.wait<Object?>([AccentSheets.load(), state.load()]);
  final accents = loaded[0]! as AccentSheets;
  final sheet = accents.base;
  installSettingsStyles(sheet);
  final step = ValueNotifier<SplashStep>((words: 'Starting Ghost Messaging', progress: null));
  runApp(_SplashApp(sheet: accents.of(state), state: state, step: step));
  // The app's own updates, looked for before anything else, as Discord does: a version found is brought down and
  // restarted into from the splash. Offline, or with nothing new, the app opens as it is and goes on looking every few
  // hours. A Mac swaps in the Mac's zip; Windows runs the new installer from gogho.st, silently.
  final macUpdates = updates && (Platform.isMacOS || Platform.isWindows) ? MacUpdates.fromEnvironment(env, windows: Platform.isWindows) : null;
  if (macUpdates != null) await checkAtLaunch(macUpdates, step);
  step.value = (words: 'Starting Ghost Messaging', progress: null);
  // Google Messages on this computer (gm_web.dart): its helper started where this copy carries it, and what changes
  // there told to the screens as the phone's changes are.
  GmWeb.instance.changed.stream.listen(Sms.instance.changes.add);
  unawaited(GmWeb.instance.start(store.dir));
  await link.start();
  // Circles' invite links opened into the app (lib/desktop/links.dart).
  unawaited(DeskLinks.start());
  // Voice channels (lib/voice): the computer's own connection to the hub, made once it has a channel.
  // The interface sounds (lib/sounds.dart) read the person's choices from here.
  Sounds.instance.start(state);
  // The keyboard's commands and push to talk (lib/keys.dart).
  Keys.instance.start(state);
  // What game runs on this computer, told to friends and spaces while Game activity is added (lib/games).
  GamePresence.instance.start(state);
  // And the circles, whose rooms ride Voice's connection (lib/circles/circles.dart).
  // On its own it runs the app's network itself, as the phone does: the routes, friends, groups, then voice and circles
  // (lib/people.dart). Paired, those are the phone's, asked across the link.
  if (alone) {
    startPeople(state);
  } else {
    unawaited(Voice.instance.start(state).then((_) => Circles.instance.start(state)));
    if (own != null) {
      // Friends by username here, on this computer's own connection, phone or no phone.
      startOwnFriends(state);
    } else {
      // Until the phone hands over its identity: the phone's friends, listed and added through it (buddies.dart).
      unawaited(Buddies.instance.start());
    }
    _handover(link, calls, own, ownDir, ownKeychain, state);
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
  // The updates looked for at the splash, told to the phone's screens too, so its banner and its words are the
  // computer's (remote.dart).
  if (macUpdates != null) calls.attachUpdates(macUpdates);
  // Plugins from the Marketplace and in development (lib/plugins/pack; Matt, 2026-11-20: "I would like users to be able
  // to develop and submit their own plugins to our plugin marketplace"), read while the splash shows, from a plugins
  // folder beside everything else this computer keeps: GHOST_DESK_DIR's when it is set, as the store's is.
  InstalledPlugins.instance = InstalledPlugins(root: Directory('${store.dir.path}${Platform.pathSeparator}plugins'));
  await InstalledPlugins.instance.load(state, appVersion: appVersion);
  // Loaded: the window its own size again, and the app in it; on its own with no username yet, the small window for
  // signing up or in (lib/desktop/window_size.dart; Matt, 2026-11-20: "make the sign up / sign in window smaller").
  await leaveSplashWindow(compact: alone && state.choice('me_username', '').isEmpty);
  runApp(DesktopApp(sheet: sheet, state: state, link: link, calls: calls, store: store, envPeers: envPeers, updates: macUpdates, accents: accents));
}

/// While linked: the phone's identity asked for once (then the app opens again on it, with friends of its own), and
/// after that each side's friends by username taken in by the other each time the two connect (lib/friends/
/// handover.dart). A phone from before handovers is left as it is: the computer asks it for friends as before.
void _handover(PhoneLink link, LinkCalls calls, DeskOwnCalls? own, Directory ownDir, bool keychain, AppState state) {
  var busy = false;
  DateTime? synced;
  void say(String phase, [String? problem]) => DeskHandover.state.value = (phase: phase, problem: problem);
  Future<void> go({bool asked = false}) async {
    if (busy) return;
    if (!link.online) {
      if (own == null) say('waiting');
      return;
    }
    // A phone from before handovers: said, so Settings › Me can ask for it to be updated rather than wait silently.
    if (!calls.caps.contains('handover')) {
      if (own == null) say('old');
      return;
    }
    if (own != null && !asked && synced != null && DateTime.now().difference(synced!) < const Duration(minutes: 5)) return;
    busy = true;
    try {
      if (own == null) {
        say('asking');
        final h = await Sms.instance.handover(const {});
        if ('${h['scalar'] ?? ''}'.length != 64) {
          say('failed', 'Your phone didn\'t hand over who you are.');
          return;
        }
        await DeskOwnCalls.adopt(ownDir, h, keychain: keychain);
        // Who this is goes with the identity: the same username, name and line as the phone.
        _takeMe(state, h['me']);
        say('done');
        // Written before the app closes: they were lost with it, and this computer came back with no username.
        await Sms.instance.prefsWritten();
        await restartApp();
        return;
      }
      final r = await Sms.instance.handover({'only': 'buddies', 'buddies': own.buddyJson});
      final theirs = '${r['buddies'] ?? ''}';
      if (theirs.isNotEmpty) {
        own.takeBuddies(theirs);
        await Buddies.instance.takeAll(own.buddyJson);
      }
      // The phone's account, as it is now (a phone from before says nothing, and what was known stays).
      if (r.containsKey('account')) own.takePhoneAccount(r['account']);
      // And who this is, as the phone says it, where this computer has none: one lost here comes back, and a username
      // taken on the phone after the handover is this computer's too. One changed here is left as it is.
      // Only while this computer is still the phone's identity (not one signed in to another account here).
      final me = r['me'];
      if (me is Map && me['id'] != null && me['id'] == Net.instance.id) _takeMe(state, me, onlyMissing: true);
      synced = DateTime.now();
    } catch (e) {
      // Asked again as the link comes and goes, and every little while; why it failed is shown in Settings › Me
      // (DartAsk's words: most often "Open Ghost Messaging on your phone, then try again.").
      if (own == null) say('failed', '$e'.replaceFirst(RegExp(r'^[A-Za-z]*(Exception|Error)(\([^)]*\))?: ?'), ''));
    } finally {
      busy = false;
    }
  }

  if (own != null) say('done');
  DeskHandover.retry = () => unawaited(go(asked: true));
  link.addListener(() => unawaited(go()));
  Timer.periodic(const Duration(minutes: 1), (_) => unawaited(go()));
}

/// The phone's username, name and line ([answerHandover]'s `me`) taken on here: each the phone has and this computer has
/// not the same, or with [onlyMissing] each this computer has none of.
///
/// What was taken is kept (`me_from_phone`): a field emptied here on purpose (a username given up) is not filled again
/// with the same the phone still says, only with something new from it.
void _takeMe(AppState state, Object? me, {bool onlyMissing = false}) {
  if (me is! Map) return;
  Map<String, dynamic> taken;
  try {
    taken = (jsonDecode(state.choice('me_from_phone', '{}')) as Map).cast<String, dynamic>();
  } catch (_) {
    taken = {};
  }
  var changed = false;
  for (final (key, said) in [('me_username', me['u']), ('me_display', me['n']), ('me_bio', me['b'])]) {
    final value = '${said ?? ''}';
    final have = state.choice(key, '');
    if (value.isEmpty || have == value) continue;
    if (onlyMissing && (have.isNotEmpty || taken[key] == value)) continue;
    state.set(key, value);
    taken[key] = value;
    changed = true;
  }
  if (changed) state.set('me_from_phone', jsonEncode(taken));
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

  /// [pages] with a call being recorded over them: its pill and tracks, over every page, the call's own among them
  /// (lib/ui/recording_float.dart).
  Widget _recorded(Widget pages) => Stack(children: [pages, Positioned.fill(child: RecordingFloat(navigator: _navigator))]);

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
              // A window being dragged larger or smaller keeps its tokens until it has stood still a moment: they,
              // and all that is drawn from them, were made anew at every frame of the drag
              // (docs/performance-audit.md, finding 8).
              resizeSettle: deskResizeSettle,
              // A newer version says so with the card the phone has, at the top of the list (lib/ui/update_banner.dart).
              // On the Mac, the window's own title strip over everything (lib/desktop/ui/desk_title_bar.dart).
              child: InkOverrides(
                child: GlacierToastProvider(
                  child: MacChrome.stripEnabled ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [DeskTitleBar(navigator: _navigator), Expanded(child: _recorded(child!))]) : _recorded(child!),
                ),
              ),
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

  /// Whether signing in to an account has been offered on this paired computer (AccountOffer); null until read.
  bool? _accountOffered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_accountOffered == null && Sms.paired && Sms.ownNetwork) {
      DeskScope.of(context).store.prefs().then((p) {
        if (mounted) setState(() => _accountOffered = p['account_offered'] == '1');
      });
    }
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

  /// Signing in passed by, or taken up: not offered again (Settings › Me has it).
  void _accountPassedBy() {
    final store = DeskScope.of(context).store;
    setState(() => _accountOffered = true);
    unawaited(store.prefs().then((p) => store.savePrefs({...p, 'account_offered': '1'})));
  }

  /// Opens the app again on its new footing, once.
  void _restart() {
    if (_restarting) return;
    _restarting = true;
    final relaunch = DeskScope.of(context).relaunch;
    Future.delayed(const Duration(milliseconds: 900), () async {
      await Sms.instance.prefsWritten();
      await restartApp(relaunch: relaunch);
    });
  }

  Widget _wizard({String? skipLabel, VoidCallback? onSkip}) => Stack(children: [
        Positioned.fill(child: PairWizard(skipLabel: skipLabel, onSkip: onSkip)),
        Positioned(left: 0, right: 0, top: 0, height: 56, child: const WindowDragArea(child: SizedBox.expand())),
      ]);

  /// The window small for signing up or in and the offers around it, its own size for the app and the pairing
  /// wizard (lib/desktop/window_size.dart).
  Widget _sized(bool compact, Widget child) {
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(DeskWindow.compact(compact)));
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final link = DeskScope.of(context).link;
    return ListenableBuilder(
      listenable: Listenable.merge([link, Me.instance, Account.instance]),
      builder: (context, _) {
        final a = link.attempt;
        // Paired a moment ago: the wizard's last step is the conversations themselves.
        if (a != null && a.phase == 'done') WidgetsBinding.instance.addPostFrameCallback((_) => link.pairingShown());
        final linked = link.phone != null && (a == null || a.phase == 'done');
        if (!Sms.standalone) {
          if (linked) {
            // Become the same you as the phone a moment ago, and in no account: signing in offered once.
            if (Sms.ownNetwork && _accountOffered == false && !Account.instance.signedIn) {
              final calls = Sms.calls;
              return _sized(true, Stack(children: [
                Positioned.fill(
                  child: AccountOffer(
                    phoneUsername: calls is DeskOwnCalls ? calls.phoneAccount?.username : null,
                    onSignIn: () {
                      _accountPassedBy();
                      final name = calls is DeskOwnCalls ? calls.phoneAccount?.username ?? '' : '';
                      push(context, (_) => SignInScreen(username: name));
                    },
                    onSkip: _accountPassedBy,
                  ),
                ),
                Positioned(left: 0, right: 0, top: 0, height: 56, child: const WindowDragArea(child: SizedBox.expand())),
              ]));
            }
            return _sized(false, DeskShell(key: ValueKey(link.phone!.id)));
          }
          // Unpaired since it opened: the wizard, or the app of its own again.
          return _sized(false, _wizard(skipLabel: 'Use without a phone', onSkip: _restart));
        }
        // Linked from here or from Settings: the app opens again on the phone.
        if (linked) {
          _restart();
          return LinkRestarting(phone: link.phone!.name);
        }
        if (_linking) {
          return _sized(false, _wizard(
            skipLabel: 'Not now',
            onSkip: () {
              unawaited(link.cancelPairing());
              _passBy();
            },
          ));
        }
        // The username is how anyone reaches someone here (lib/standalone/welcome.dart).
        if (Me.instance.username == null) {
          return _sized(true, Stack(children: [
            Positioned.fill(child: StandaloneWelcome(onDone: () => setState(() {}))),
            Positioned(left: 0, right: 0, top: 0, height: 56, child: const WindowDragArea(child: SizedBox.expand())),
          ]));
        }
        if (_offered == null) return ColoredBox(color: context.tokens.color('glacier-bg'));
        if (!_offered!) {
          return _sized(true, Stack(children: [
            Positioned.fill(child: LinkOffer(onLink: () => setState(() => _linking = true), onSkip: _passBy)),
            Positioned(left: 0, right: 0, top: 0, height: 56, child: const WindowDragArea(child: SizedBox.expand())),
          ]));
        }
        return _sized(false, const DeskShell(key: ValueKey('alone')));
      },
    );
  }
}

/// The launch splash in the app's look, before the app itself is there (lib/desktop/ui/launch_splash.dart).
class _SplashApp extends StatelessWidget {
  const _SplashApp({required this.sheet, required this.state, required this.step});

  final TokenSheet sheet;
  final AppState state;
  final ValueListenable<SplashStep> step;

  @override
  Widget build(BuildContext context) => WidgetsApp(
        title: 'Ghost Messaging',
        color: const Color(0xFF4F5BD5),
        debugShowCheckedModeBanner: false,
        builder: (context, _) => GlacierTheme(
          sheet: sheet,
          attrs: ghostAttrs(state, 'desktop'),
          typography: ghostTypography(state.emoji),
          child: LaunchSplash(step: step),
        ),
      );
}
