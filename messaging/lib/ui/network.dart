import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../net/carrier.dart';
import '../net/net.dart';
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
        footer: const Text('A route over the local network and a peer-to-peer one, with no server, are being made: they will be listed here, and the relay server can then be switched off.'),
        children: [
          for (final c in board.carriers)
            SettingRow(
              icon: icon(switch (c.id) { 'hub' => Lucide.globe, 'sms' => Lucide.messageSquare, 'lan' => Lucide.wifi, _ => Lucide.network }),
              label: c.name,
              hint: Text('${_routeLine(c, on: net.on, anyone: anyone, off: board.off.contains(c.id))}\n${c.about}'),
              control: GlacierSwitch(checked: !board.off.contains(c.id), onCheckedChange: (v) => net.setRoute(c.id, v), ariaLabel: c.name),
            ),
        ],
      ),
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
              label: p.name ?? p.address ?? p.id.substring(0, 8),
              hint: Text(board == null ? '' : 'By ${board.routes(p, metered: true).map((c) => c.name).join(', ').ifEmpty('no route now')}'),
              onPress: () => showChoices(context, title: 'Test the way to ${p.name ?? p.address ?? 'them'}', choices: [
                Choice('Send a test', Lucide.send, () => test(p)),
                if (board?.carrier('hub') != null) Choice('By the relay server only', Lucide.globe, () => test(p, only: 'hub')),
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

  /// A test's stand-in for opening the WebSocket.
  final RelayConnect? connect;

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
