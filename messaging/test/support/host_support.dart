import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/net/hub_link.dart';
import 'package:ghost_messaging/net/net.dart';
import 'package:ghost_messaging/net/p2p/p2p.dart';
import 'package:ghost_messaging/relay_host/relay_host_io.dart';
import 'package:ghost_relay/federation.dart' show FedDial;

/// What the tests of a relay hosted from the app stand on (test/relay_host_test.dart and the rest): a host as the app
/// makes one, but for what it keeps and where, and installs on it in memory.

/// What the app keeps for the host: its choices and its secrets.
class Kept {
  final choices = <String, String>{};
  final secrets = <String, String>{};
  String get hubUrl => (choices['net_hub'] ?? '').isEmpty ? Net.defaultHub : choices['net_hub']!;
}

/// A host as the app makes one, but for what it keeps ([k]) and where: a folder of its own for the test ([folder]),
/// made and deleted with it where none is given, as the app always has one (its key, and so its name, outlives a stop).
/// The local network's door is shut unless [lan], and listens at [port] (0: any free one) on this machine alone.
RelayHost makeHost(Kept k, {Directory? folder, bool phone = false, Timer Function(Duration, void Function())? timer, P2p? Function()? p2p, int port = 0, bool lan = false, String? via, FedDial? viaDial, Set<int> viaPorts = const {}, bool viaPlain = false, Future<List<String>> Function()? addresses}) {
  k.choices[RelayHost.portKey] = '$port';
  if (!lan) k.choices[RelayHost.lanKey] = 'off';
  final dir = folder ?? Directory.systemTemp.createTempSync('relay-host-');
  if (folder == null) addTearDown(() => dir.deleteSync(recursive: true));
  return RelayHost(
    read: (key) => k.choices[key] ?? '',
    write: (key, v) => k.choices[key] = v,
    secretRead: (n) async => k.secrets[n],
    secretKeep: (n, v) async => k.secrets[n] = v,
    folder: () async => dir,
    p2p: p2p ?? () => null,
    phone: phone,
    timer: timer,
    via: via,
    viaDial: viaDial,
    viaPorts: viaPorts,
    viaPlain: viaPlain,
    addresses: addresses,
    hubUrl: () => k.hubUrl,
    useRelay: (url) async {
      k.choices['net_hub'] = url;
      return null;
    },
    moveBack: (url) async => k.choices['net_hub'] = url,
    forgetHub: (url) => k.choices['net_hub'] = url,
    passChanged: () {},
  );
}

/// Waits for [ok], however long the machine takes ([most] at most), not for a length of time.
Future<void> waitFor(bool Function() ok, String what, {Duration most = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(most);
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ok(), isTrue, reason: what);
}

/// An install on the relay this device hosts, in memory: its key and its route, dialled as the app dials its own.
class OnHost {
  OnHost(RelayHost host, {String? Function()? pass, HubDial? dial}) : keys = NetKeys.generate() {
    carrier = HubCarrier(url: host.ownUrl!, signer: KeysSigner(keys), retry: const Duration(milliseconds: 20), dial: (url) {
      dials++;
      return (dial ?? (_) => host.dialHere())(url);
    })
      ..pass = pass;
    carrier.arrived.listen(got.add);
  }
  final NetKeys keys;
  late final HubCarrier carrier;
  final got = <Arrived>[];
  int dials = 0;
  String get id => keys.id;
  Future<void> up() async {
    await carrier.start();
    await waitFor(() => carrier.state.value == CarrierState.up, 'never signed in: ${carrier.problem}');
  }
}
