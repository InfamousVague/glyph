import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../net/carrier.dart';
import '../net/net.dart';
import 'common.dart';
import 'settings.dart';

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
                  : 'Sent by $by. Their phone shows it under Settings › Network.',
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
        footer: const Text('Ours is used where this is empty. It sees which phones talk and when, never what they say. Anyone can run their own and put its address here; both phones need not use the same one for SMS or the local network, only for this route.'),
        children: [
          SettingRowBox(child: _HubField(net: net)),
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

/// The relay server's address, typed.
class _HubField extends StatefulWidget {
  const _HubField({required this.net});
  final Net net;

  @override
  State<_HubField> createState() => _HubFieldState();
}

class _HubFieldState extends State<_HubField> {
  late final _address = TextEditingController(text: widget.net.hubUrl == Net.defaultHub ? '' : widget.net.hubUrl);

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final typed = _address.text.trim();
    if ((typed.isEmpty ? Net.defaultHub : typed) == widget.net.hubUrl) return;
    if (typed.isNotEmpty && !typed.startsWith('wss://') && !typed.startsWith('ws://')) {
      toast(context, 'A relay server\'s address starts with wss://', tone: GlacierToastTone.danger);
      return;
    }
    await widget.net.setHub(typed);
    if (mounted) toast(context, typed.isEmpty ? 'Using ours' : 'Using $typed');
  }

  @override
  Widget build(BuildContext context) => GlacierInput(
        controller: _address,
        placeholder: Net.defaultHub,
        ariaLabel: 'Relay server address',
        inputMode: TextInputType.url,
        size: GlacierFieldSize.md,
        onSubmitted: (_) => _save(),
        onBlur: _save,
      );
}
