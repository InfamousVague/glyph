import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../friends/buddies.dart';
import '../friends/groups.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../net/carrier.dart';
import '../net/hub_link.dart';
import '../net/ledger.dart';
import '../net/name_watch.dart';
import '../net/net.dart';
import '../net/p2p/node.dart';
import 'name_watch_words.dart';
import '../net/p2p/p2p.dart';
import '../net/relay_choice.dart';
import 'common.dart';
import 'compose.dart';
import 'settings.dart';
import 'shell.dart';

/// What one of the people the routes reach is called in Settings › Network: their name, else their address, else (no
/// address of theirs being known here: a member of a group, say, or someone who asked to be a friend) the group they are
/// in, else the start of their install's name. An address that is empty is none (found in review, 2026-11-23: their
/// row was blank).
String peerLabel(Peer p, {Iterable<Group>? groups}) {
  final name = p.name?.trim() ?? '', address = p.address?.trim() ?? '';
  if (name.isNotEmpty) return name;
  if (address.isNotEmpty) return address;
  final group = (groups ?? Groups.instance.all).where((g) => !g.gone && g.member(p.id) != null).firstOrNull;
  if (group != null) return 'A member of ${group.title}';
  return p.id.length > 8 ? p.id.substring(0, 8) : p.id;
}

/// How the network stands, in a line: Settings' row for it.
String networkSummary() {
  final net = Net.instance;
  if (net.error != null) return 'Not set up';
  if (!net.on) return 'Off';
  final people = net.people.length;
  if (people == 0) return 'Nobody to reach yet';
  final up = net.board?.carriers.where((c) => c.state.value == CarrierState.up).length ?? 0;
  return '${people == 1 ? '1 person' : '$people people'} · ${up == 1 ? '1 route' : '$up routes'} ready';
}

/// What an invitation says: where to get the app, in words a person would send. When they have it and the two
/// phones text each other, the app offers to exchange keys, and that is what makes them reachable by the routes.
const inviteText = 'Join me on Ghost Messaging: calls and private chats straight between our phones. Get it at https://gogho.st';

String _routeLine(Carrier c, {required bool on, required bool anyone, required bool off}) {
  if (off || !on) return 'Off';
  if (!anyone) return 'Waiting until there is someone to reach';
  return switch (c.state.value) {
    CarrierState.up => 'Ready',
    CarrierState.connecting => 'Connecting…',
    CarrierState.down => c.problem ?? 'Not working now',
    CarrierState.off => 'Off',
  };
}

/// How many devices the direct route knows of, in words (Settings › Routes › Direct).
String directKnownWords(int friends) => switch (friends) {
      0 => 'No friend\'s device known yet',
      1 => 'Knows 1 friend\'s device',
      _ => 'Knows $friends friends\' devices',
    };

/// Under [directKnownWords]: this account's own other devices, and how a device comes to be known.
String directKnownHint(int own) =>
    '${own == 0 ? '' : own == 1 ? 'And 1 other device of your own. ' : 'And $own other devices of your own. '}A device is known once it and this one have told each other they are here, which they do through the relay server.';

/// How many devices are linked now, in words, and under it whether each link is straight or through a link helper.
String directLinkedWords(int linked) => switch (linked) {
      0 => 'Not linked to any now',
      1 => 'Linked to 1 device now',
      _ => 'Linked to $linked devices now',
    };

String directLinkedHint(Iterable<P2pPathKind> links) {
  final straight = links.where((k) => k == P2pPathKind.direct).length, helped = links.where((k) => k == P2pPathKind.helper).length;
  if (links.isEmpty) return 'A link is made when the relay server can\'t carry something, and let go when nothing has been said on it for a while.';
  final parts = [if (straight > 0) '$straight straight', if (helped > 0) '$helped through a link helper'];
  return parts.isEmpty ? 'Finding the way.' : '${parts.join(', ')}.';
}

/// What "Only through link helpers" means, under its switch.
const directHelpersOnlyHint = 'Friends\' devices then see the link helper\'s address and not this device\'s. It is slower.';

/// Settings › Routes › Direct (docs/OPEN_NETWORK.md, section 2; Matt, 2026-11-22: "p2p delivery with the relay as a
/// primary source but have p2p as a secondary back up"): what the direct route knows and holds now, and its one
/// choice. The route's own row, with its switch, is with the other routes above.
PaneSection directSection(BuildContext context, P2p p2p) {
  Widget icon(LucideIcon i) => AppIcon(i, size: 18);
  final links = p2p.carrier.links;
  // One device, however many streams or names it is linked under.
  final kinds = {for (final l in links) l.nodeId: l.kind}.values;
  return PaneSection(
    title: 'Direct',
    description: const Text('Straight between devices when the relay server can\'t carry something. A device links only with your own devices and your friends\', and only they are told where it is.'),
    footer: const Text('A link helper is a server that helps two devices find each other and passes their sealed packets along where no straight path can be made. It sees which devices link and how much they send, never who they are or what is said.'),
    children: [
      SettingRow(
        key: const ValueKey('direct-known'),
        icon: icon(Lucide.users),
        label: directKnownWords(p2p.friendsDevices),
        hint: Text(directKnownHint(p2p.ownDevices)),
      ),
      SettingRow(
        key: const ValueKey('direct-linked'),
        icon: icon(Lucide.link),
        label: directLinkedWords(kinds.length),
        hint: Text(directLinkedHint(kinds)),
      ),
      SettingRow(
        key: const ValueKey('direct-helpers-only'),
        icon: icon(Lucide.eyeOff),
        label: 'Only through link helpers',
        hint: const Text(directHelpersOnlyHint),
        control: GlacierSwitch(checked: p2p.helpersOnly, onCheckedChange: p2p.setHelpersOnly, ariaLabel: 'Only through link helpers'),
      ),
      if (p2p.helpers.isEmpty)
        SettingRow(
          key: const ValueKey('direct-no-helpers'),
          icon: icon(Lucide.info),
          label: 'No link helpers yet',
          hint: Text(p2p.helpersOnly ? 'So nothing links while "Only through link helpers" is on.' : 'Direct links work on your own network for now.'),
        ),
    ],
  );
}

String _ago(DateTime at) {
  final s = DateTime.now().difference(at).inSeconds;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60} min ago';
  return '${s ~/ 3600} h ago';
}

// --- Checking the relay (docs/OPEN_NETWORK.md, section 3) -----------------------------------------------------------

/// How long ago [at] was from [now] (both ms), in words.
String agoWords(int at, int now) {
  final s = (now - at) ~/ 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60} min ago';
  if (s < 2 * 86400) return '${s ~/ 3600} h ago';
  return '${s ~/ 86400} days ago';
}

/// The day [ms] fell on, as a row says it: "21 Nov".
String dayWords(int ms) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${months[d.month - 1]}';
}

/// When the relay was last checked over direct links, and with how many friends' devices.
String relayCheckedWords(int at, int devices, {required int now}) =>
    at <= 0 ? 'Not checked yet' : 'Last checked ${agoWords(at, now)}, with ${devices == 1 ? '1 device' : '$devices devices'}';

/// How many messages both ends agreed on this week.
String relayMatchedWords(int matched) => '${matched == 1 ? '1 message' : '$matched messages'} matched this week';

/// How many had to come straight with the relay not at fault.
/// How many came straight after the relay didn't bring them, and of those how many were lost when it started again: only
/// what did come straight is counted (the review, D7).
String relayMadeUpWords(int madeUp, {int restarts = 0}) => madeUp == 0
    ? 'None had to come straight.'
    : '${madeUp == 1 ? '1 came' : '$madeUp came'} straight after the relay didn\'t bring ${madeUp == 1 ? 'it' : 'them'}${restarts == 0 ? '' : restarts == madeUp ? ', lost when it started again' : ' ($restarts lost when it started again)'}.';

/// One thing the relay got wrong, said as whose word it is (the review, D5): what the relay told the friend [who]'s
/// device, held to what happened here, put down only once the message came straight.
String relayWrongWords(LedgerWrong w, String who) => switch (w.kind) {
      LedgerWrongKind.passed => '$who\'s device says the relay passed on a message to you, and it never came by the relay',
      LedgerWrongKind.kept => '$who\'s device says the relay kept a message for you, and it never handed it over',
      LedgerWrongKind.away => '$who\'s device says the relay told it you were away while you were connected',
      LedgerWrongKind.gone => 'The relay said $who was gone while their device said it was connected',
    };

/// What the name watch does, in a line, and when it last asked.
String nameWatchWords(int friends) => friends == 0 ? 'No friends added by username yet' : 'Asks the relay about ${friends == 1 ? '1 friend\'s username' : '$friends friends\' usernames'} each day';

String nameWatchHint(int lastAsked, {required int now}) => lastAsked <= 0
    ? 'Each is asked at a time of its own through the day, and the answer held against the key you added.'
    : 'Last asked ${agoWords(lastAsked, now)}. Each answer is held against the key you added; nothing the relay says changes who your friends are.';

/// Settings › Routes › Checking the relay (docs/OPEN_NETWORK.md, section 3; Matt, 2026-11-22: "p2p as a secondary back
/// up that validates everything our relay says"). Per relay, plainly: when it was last checked over direct links and
/// with how many devices, how many messages matched and how many were made up for, each thing it got wrong with its
/// day, and "Check now" (once a minute at most). Then the name watch, which needs no direct route. In a build with no
/// direct route ([ledger] null) it says the relay is checked only by the name watch, shows that alone, and dials
/// nothing.
PaneSection relayCheckSection(BuildContext context, {required Ledger? ledger, required LedgerCheck? check, required NameWatch? watch, required String relay, bool directOn = true, String Function(String id)? nameOf, int? now}) {
  Widget icon(LucideIcon i) => AppIcon(i, size: 18);
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  String who(String id) {
    final n = nameOf?.call(id);
    return n == null || n.isEmpty ? (id.length >= 6 ? id.substring(0, 6) : id) : n;
  }

  final compares = ledger != null && check != null;
  final rows = <Widget>[];
  if (compares) {
    final records = ledger.relays;
    final r = records[relay];
    rows.add(SettingRow(
      key: const ValueKey('relay-checked'),
      icon: icon(Lucide.shieldCheck),
      label: relayCheckedWords(r?.lastChecked ?? 0, r?.devices ?? 0, now: at),
      hint: Text('Of ${relayInUseWords(relay)}, over direct links with your friends\' devices.'),
    ));
    if (r != null && r.lastChecked > 0) {
      rows.add(SettingRow(
        key: const ValueKey('relay-matched'),
        icon: icon(Lucide.check),
        label: relayMatchedWords(r.matched(at)),
        hint: Text(relayMadeUpWords(r.madeUp(at), restarts: r.restarts(at))),
      ));
      final wrong = r.wrong.reversed.toList();
      if (wrong.isEmpty) {
        rows.add(SettingRow(key: const ValueKey('relay-wrong-none'), icon: icon(Lucide.circleCheck), label: 'It got nothing wrong'));
      }
      for (final (i, w) in wrong.indexed) {
        rows.add(SettingRow(key: ValueKey('relay-wrong-$i'), icon: icon(Lucide.circleAlert), label: relayWrongWords(w, who(w.friend)), hint: Text(dayWords(w.at))));
      }
    }
    // Relays this device used before, with what was found of them.
    for (final o in records.values.where((o) => o.url != relay)) {
      rows.add(SettingRow(
        key: ValueKey('relay-before-${o.url}'),
        icon: icon(Lucide.history),
        label: 'Before: ${relayInUseWords(o.url)}',
        hint: Text('${relayCheckedWords(o.lastChecked, o.devices, now: at)}. ${relayMatchedWords(o.matched(at))}; ${o.wrong.length == 1 ? '1 thing' : '${o.wrong.length} things'} wrong.'),
      ));
    }
    final may = directOn && check.canCheckNow;
    rows.add(SettingRow(
      key: const ValueKey('relay-check-now'),
      icon: icon(Lucide.refreshCw),
      label: 'Check now',
      hint: Text(!directOn
          ? 'Switch Direct on above to compare.'
          : may
              ? 'Dials the friends the relay says are here, and compares.'
              : 'Checked a moment ago. Again in a minute.'),
      disabled: !may,
      onPress: may
          ? () async {
              final n = await check.checkNow();
              if (!context.mounted) return;
              toast(context, n == 0 ? 'Nobody the relay says is here can be compared with now' : 'Comparing with ${n == 1 ? '1 friend' : '$n friends'}');
            }
          : null,
    ));
  }
  // The name watch: what needs no direct route.
  if (watch != null) {
    rows.add(SettingRow(
      key: const ValueKey('names-watched'),
      icon: icon(Lucide.atSign),
      label: nameWatchWords(watch.watching),
      hint: Text(nameWatchHint(watch.lastAsked, now: at)),
    ));
    // In the rows' own ink, with what usually causes each said (the review, M1 and M2).
    final own = watch.own;
    if (own != null) rows.add(SettingRow(key: const ValueKey('names-own'), icon: icon(Lucide.info), label: ownNameWords(own), hint: Text('${dayWords(own.at)}. ${ownNameHint(own)}')));
    for (final (i, t) in watch.toldMe.reversed.indexed) {
      rows.add(SettingRow(key: ValueKey('names-told-$i'), icon: icon(Lucide.info), label: toldWords(who(t.by ?? ''), t.username), hint: Text('${dayWords(t.at)}. $toldHint')));
    }
    for (final (i, c) in watch.changes.indexed) {
      rows.add(SettingRow(key: ValueKey('names-changed-$i'), icon: icon(Lucide.info), label: friendNameChangedLabel(c.change.username), hint: Text('${dayWords(c.change.at)}. ${friendNameChangedHint(who(c.friend))}')));
    }
  }
  return PaneSection(
    title: 'Checking the relay',
    description: Text(compares
        ? 'Your devices and your friends\' compare what went between them, over direct links, to find anything the relay dropped or kept back. Friends\' usernames are asked of it again each day.'
        : 'This device has no direct route, so the relay is checked only by the name watch: friends\' usernames are asked of it again each day, and your own each time you connect. Nothing is dialled.'),
    footer: Text(compares
        ? 'What is compared is which messages went and came, and when: never their words. It goes only to the friend it concerns, sealed, over a direct link.'
        : 'Only the relay you use is asked. A friend whose username it now gives to another account is told, sealed, through the relay.'),
    children: rows,
  );
}

/// Settings › Network: the app's routes (Matt, 2026-11-14: "implement a full relay system for the app that's
/// replacable and swappable ... The goal will be to have multiple sources to feed data to eachother from wifi
/// locally, p2p, internet, sms, etc"). Each route with how it stands and a switch, the relay server's address, the
/// people the routes reach with a test to each, and what the routes last did.
List<Widget> networkPane(BuildContext context, SettingsModel m) {
  final net = Net.instance;
  final board = net.board;
  Widget icon(LucideIcon i) => AppIcon(i, size: 18);
  final anyone = net.people.isNotEmpty;

  Future<void> test(Peer p, {String? only}) async {
    final r = await net.test(p, only: only);
    if (!context.mounted) return;
    final d = r.delivery;
    final by = board?.carrier(d.via ?? '')?.name ?? d.via;
    toast(
      context,
      !d.sent
          ? 'Couldn\'t send it: ${d.tried.join('; ')}'
          : d.acked
              ? 'Reached them by $by in ${r.took.inMilliseconds} ms'
              : d.handed == Handed.held
                  ? 'They are away: the relay server is keeping it for them'
                  : 'Sent by $by. Their phone shows it under Settings › Routes.',
      tone: d.sent ? GlacierToastTone.neutral : GlacierToastTone.danger,
    );
  }

  return [
    PaneSection(
      footer: const Text('It works with the people encryption is on with: exchanging keys by text is what introduces two phones. Nothing is sent anywhere until there is one. Everything that crosses is sealed between the two phones.'),
      children: [
        SettingRow(
          icon: icon(Lucide.network),
          label: 'Reach other phones with the app directly',
          hint: const Text('For calls, and for what a text cannot carry.'),
          control: GlacierSwitch(checked: net.on, onCheckedChange: net.setOn, ariaLabel: 'Reach other phones with the app directly'),
        ),
      ],
    ),
    if (net.error != null)
      PaneSection(title: 'Not set up', children: [
        SettingRow(icon: icon(Lucide.circleAlert), label: 'The routes could not be set up', hint: Text(net.error!)),
      ]),
    if (board != null)
      PaneSection(
        title: 'Routes',
        description: const Text('The ways this phone reaches another, tried from the top. One that fails or gets no answer gives way to the next.'),
        footer: Text(net.p2p == null && net.directProblem == null
            ? 'A route over the local network and a peer-to-peer one, with no server, are being made: they will be listed here, and the relay server can then be switched off.'
            : 'A route over the local network is being made: it will be listed here.'),
        children: [
          for (final c in board.carriers)
            SettingRow(
              key: ValueKey('route-${c.id}'),
              icon: icon(switch (c.id) { 'hub' => Lucide.globe, 'sms' => Lucide.messageSquare, 'lan' => Lucide.wifi, 'p2p' => Lucide.link2, _ => Lucide.network }),
              label: c.name,
              hint: Text('${_routeLine(c, on: net.on, anyone: anyone, off: board.off.contains(c.id))}\n${c.about}'),
              control: GlacierSwitch(checked: !board.off.contains(c.id), onCheckedChange: (v) => net.setRoute(c.id, v), ariaLabel: c.name),
            ),
        ],
      ),
    if (board != null && net.p2p != null) directSection(context, net.p2p!),
    // A build with the direct route whose core could not be started (a library missing, or built for another machine):
    // the other routes go on, and this says why there is no Direct among them.
    if (board != null && net.p2p == null && net.directProblem != null)
      PaneSection(title: 'Direct', children: [
        SettingRow(key: const ValueKey('direct-problem'), icon: icon(Lucide.circleAlert), label: 'Direct isn\'t working on this device', hint: Text(net.directProblem!)),
      ]),
    // Checking the relay: what comparing over direct links found, and the name watch, which needs no direct route.
    if (board != null) relayCheckSection(context, ledger: net.ledger, check: net.check, watch: NameWatch.instance, relay: net.hubUrl, directOn: net.p2p?.on ?? false, nameOf: _friendName),
    if (board != null && net.hub != null)
      PaneSection(
        title: 'Relay server',
        description: const Text('It sees which installs talk and when, never what they say. You can run your own and use it here instead of ours.'),
        footer: const Text(relayLimitsWords),
        children: [
          SettingRow(
            key: const ValueKey('relay-in-use'),
            icon: icon(Lucide.globe),
            label: relayInUseWords(net.hubUrl),
            hint: Text('In use · ${_hubLine(net)}'),
          ),
          if (!net.onDefaultHub)
            SettingRow(
              key: const ValueKey('relay-use-default'),
              icon: icon(Lucide.undo2),
              label: 'Go back to Ghost Messaging\'s relay',
              hint: const Text('gogho.st, where everyone else is.'),
              onPress: () async {
                await net.useRelay('');
                if (context.mounted) toast(context, 'Using Ghost Messaging\'s relay again');
              },
            ),
          SettingRowBox(child: RelayAddressField(net: net)),
        ],
      ),
    PaneSection(
      title: 'Invite',
      footer: const Text('Once they have the app and you text each other, it offers to turn encryption on between you. From then they are someone the routes reach.'),
      children: [
        SettingRow(
          icon: icon(Lucide.userPlus),
          label: 'Invite someone by text',
          hint: const Text('Opens a new chat with an invitation written. Choose who, change the words if you like, and send it as any text.'),
          onPress: () {
            // In the app's frame a new chat opens in the pane, the invitation already in its message field.
            final shell = AppShell.maybeOf(context);
            if (shell != null) {
              shell.compose(body: inviteText);
            } else {
              push<void>(context, (_) => const ComposeScreen(body: inviteText));
            }
          },
        ),
      ],
    ),
    if (anyone)
      PaneSection(
        title: 'People you can reach',
        description: const Text('Press one to send a test and see which route carries it.'),
        children: [
          for (final p in net.people)
            SettingRow(
              icon: icon(Lucide.userRound),
              label: peerLabel(p),
              hint: Text(board == null ? '' : 'By ${board.routes(p, metered: true).map((c) => c.name).join(', ').ifEmpty('no route now')}'),
              onPress: () => showChoices(context, title: 'Test the way to ${peerLabel(p)}', choices: [
                Choice('Send a test', Lucide.send, () => test(p)),
                if (board?.carrier('hub') != null) Choice('By the relay server only', Lucide.globe, () => test(p, only: 'hub')),
                if (board?.carrier('p2p') != null) Choice('By a direct link only', Lucide.link2, () => test(p, only: 'p2p')),
                if (board?.carrier('sms') != null) Choice('By SMS only (one text on your plan)', Lucide.messageSquare, () => test(p, only: 'sms')),
              ]),
            ),
        ],
      ),
    if (net.recent.isNotEmpty)
      PaneSection(
        title: 'Lately',
        children: [
          for (final e in net.recent.take(8))
            SettingRow(
              icon: icon(Lucide.clock),
              label: e.words,
              hint: Text('${e.via == null ? '' : '${board?.carrier(e.via!)?.name ?? e.via} · '}${_ago(e.at)}'),
            ),
        ],
      ),
    if (net.id != null)
      PaneSection(
        title: 'This phone',
        footer: const Text('A name made from this phone\'s encryption key. A relay server and the other phones know this phone by it, and learn no number or name from it.'),
        children: [
          SettingRow(icon: icon(Lucide.keyRound), label: '${net.id!.substring(0, 8)} ${net.id!.substring(8, 16)}'),
        ],
      ),
  ];
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// A friend's name as Settings says it: their name or username as friends by username keep it, else as the routes know
/// them.
String _friendName(String id) {
  final b = Buddies.instance.byId(id);
  if (b != null) return b.shown;
  final p = Net.instance.byId(id);
  return p?.name ?? p?.address ?? '';
}

/// What a relay of one's own does and doesn't reach, in Settings › Routes (GMFB-25; docs/SELF_HOSTING.md).
const relayLimitsWords =
    'Relays don\'t connect to each other. On your own relay you reach only people using the same relay: friends, usernames, your account backup, circles, spaces and invite words are kept on each relay apart, and people on Ghost Messaging\'s relay can\'t reach you through it. Texts (SMS) still reach anyone. The Marketplace always comes from gogho.st. How to run one: gogho.st/docs/routes.';

/// How the relay's route stands, in a few words.
String _hubLine(Net net) {
  final hub = net.hub;
  if (hub == null) return 'not set up';
  if (net.board?.off.contains('hub') ?? false) return 'switched off above';
  return switch (hub.state.value) {
    CarrierState.up => 'connected',
    CarrierState.connecting => 'connecting…',
    CarrierState.down => hub.problem ?? 'not reachable now',
    CarrierState.off => 'connects when something needs it',
  };
}

/// Another relay's address, typed, checked and only then used (GMFB-25): a Ghost Messaging relay has to answer at it
/// ([Net.useRelay]), and the person is told what moving there means before anything changes.
class RelayAddressField extends StatefulWidget {
  const RelayAddressField({super.key, required this.net, this.connect});
  final Net net;

  /// A test's stand-in for dialling the relay.
  final HubDial? connect;

  @override
  State<RelayAddressField> createState() => _RelayAddressFieldState();
}

class _RelayAddressFieldState extends State<RelayAddressField> {
  late final _address = TextEditingController(text: _inUse);
  bool _checking = false;
  String? _problem;

  /// The address the field shows for the relay in use: empty for ours.
  String get _inUse => widget.net.onDefaultHub ? '' : widget.net.hubUrl;
  late String _shown = _inUse;

  @override
  void initState() {
    super.initState();
    widget.net.addListener(_moved);
  }

  /// The relay changed elsewhere (Go back to Ghost Messaging's relay): the field follows, unless something else was
  /// typed in it meanwhile.
  void _moved() {
    final now = _inUse;
    if (now == _shown) return;
    if (_address.text.trim() == _shown) _address.text = now;
    _shown = now;
  }

  @override
  void dispose() {
    widget.net.removeListener(_moved);
    _address.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String url) async {
    var yes = false;
    await showChoices(
      context,
      title: 'Use ${relayInUseWords(url).replaceFirst('Your own relay: ', '')}?',
      header: const Text(relayLimitsWords),
      choices: [Choice('Use this relay', Lucide.check, () => yes = true, hint: 'It answered as a Ghost Messaging relay.')],
    );
    return yes;
  }

  Future<void> _use() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _problem = null;
    });
    final r = await widget.net.useRelay(_address.text, connect: widget.connect, confirm: _confirm);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _problem = r.problem;
    });
    if (r.problem != null || r.declined) return;
    _address.text = _shown = _inUse;
    toast(context, widget.net.onDefaultHub ? 'Using Ghost Messaging\'s relay' : 'Using ${relayInUseWords(widget.net.hubUrl)}');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      GlacierInput(
        key: const ValueKey('relay-address'),
        controller: _address,
        placeholder: 'relay.example.com',
        ariaLabel: 'Another relay server\'s address',
        inputMode: TextInputType.url,
        size: GlacierFieldSize.md,
        onSubmitted: (_) => _use(),
      ),
      if (_problem != null)
        Padding(
          padding: EdgeInsets.only(top: t.space(2)),
          child: Text(_problem!, key: const ValueKey('relay-problem'), style: pageText(t, t.fontSize('sm'), color: t.color('app-danger'))),
        ),
      SizedBox(height: t.space(2)),
      SettingRow(
        key: const ValueKey('relay-check-and-use'),
        icon: _checking ? const GhostSpinner(size: 18) : const AppIcon(Lucide.check, size: 18),
        label: _checking ? 'Checking it answers…' : 'Check it and use it',
        hint: const Text('Nothing changes unless a Ghost Messaging relay answers there.'),
        onPress: _checking ? null : _use,
      ),
    ]);
  }
}
