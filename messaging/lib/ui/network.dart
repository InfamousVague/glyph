import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../net/carrier.dart';
import '../net/hub_link.dart';
import '../net/net.dart';
import '../net/hub_carrier.dart' show HubRelay;
import '../net/p2p/node.dart';
import '../net/p2p/p2p.dart';
import '../net/relay_choice.dart';
import 'common.dart';
import 'compose.dart';
import 'settings.dart';
import 'shell.dart';

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
        footer: Text(net.p2p == null
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
          // Whether this relay passes messages to other relays, as it said itself the last time the app signed in.
          if (net.hub!.state.value == CarrierState.up)
            SettingRow(
              key: const ValueKey('relay-talks'),
              icon: icon(Lucide.network),
              label: relayTalksWords(net.hub!.relay).$1,
              hint: Text(relayTalksWords(net.hub!.relay).$2),
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
              label: p.name ?? p.address ?? p.id.substring(0, 8),
              hint: Text(board == null ? '' : 'By ${board.routes(p, metered: true).map((c) => c.name).join(', ').ifEmpty('no route now')}'),
              onPress: () => showChoices(context, title: 'Test the way to ${p.name ?? p.address ?? 'them'}', choices: [
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

/// What a relay of one's own does and doesn't reach, in Settings › Routes (GMFB-25; docs/SELF_HOSTING.md). Since
/// relays talk to each other (docs/OPEN_NETWORK.md, section 4; Matt, 2026-11-22), friends cross relays; the rest is
/// still each relay's own.
const relayLimitsWords =
    'Relays can pass messages to each other. Add a friend on another relay as @name@their.relay, and what you write to each other goes through your relay to theirs, where both relays allow it. Everything else is still kept on each relay apart: usernames, your account backup, circles, spaces, calls, who is online and invite words reach only people using the same relay. Texts (SMS) still reach anyone. The Marketplace always comes from gogho.st. How to run one: gogho.st/docs/routes.';

/// Whether the relay in use passes messages to other relays, as a row's label and the line under it: by what the
/// relay said of itself in its hello ([relay]; null from a relay from before relays talked).
(String, String) relayTalksWords(HubRelay? relay) => relay == null
    ? ('Doesn\'t pass messages to other relays', 'This relay is from before relays talked to each other. You reach only people who use it.')
    : relay.fed
        ? ('Passes messages to other relays', 'A friend on another relay, added as @name@their.relay, is reached through this one.')
        : ('Doesn\'t pass messages to other relays', 'Whoever runs it hasn\'t switched that on. You reach only people who use this relay.');

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
