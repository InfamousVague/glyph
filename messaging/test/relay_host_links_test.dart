import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/carrier.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/net/hub_link.dart';
import 'package:ghost_messaging/net/net.dart';
import 'package:ghost_messaging/net/relay_choice.dart';
import 'package:ghost_messaging/relay_host/address.dart';

import 'support/host_support.dart' show waitFor;

/// A relay's link and a hosted relay's address, as the second review found them (2026-11-23), each from its probe: a
/// link was followed (dialled) before the person was asked; a link could name any relay, a public one too; and the
/// relay named in a `ghost-relay://` address was never checked against the relay that answered.

/// A hub that says [hello] and nothing more.
class _FakeLink implements HubLink {
  _FakeLink(Map<String, Object?> hello) {
    scheduleMicrotask(() => _said.add(jsonEncode(hello)));
  }
  final _said = StreamController<Object>();
  final told = <Object>[];
  @override
  Stream<Object> get said => _said.stream;
  @override
  void say(Object message) => told.add(message);
  @override
  Future<void> close() async {
    if (!_said.isClosed) await _said.close();
  }
}

/// A relay's card for its hello: a real key, so its name is made from it.
Map<String, Object?> _card(NetKeys k) => {'id': k.id, 'key': base64Encode(k.public), 'fed': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a relay\'s link', () {
    final local = 'ghostmsg://relay?a=${Uri.encodeQueryComponent('ws://192.168.1.9:7787/hub')}';

    test('is asked about before the address it carries is dialled; no, and nothing is', () async {
      final order = <String>[];
      Future<HubLink> connect(String url) async {
        order.add('dialled $url');
        return _FakeLink({'hello': 'd' * 64, 'peek': true});
      }

      final no = await Net.instance.useRelay(local, connect: connect, askFirst: (url) async {
        order.add('asked $url');
        return false;
      }, decide: (url, check) async => (yes: false, pass: null));
      expect(no.declined, isTrue);
      expect(order, ['asked ws://192.168.1.9:7787/hub'], reason: 'nothing dialled on a no');
      order.clear();
      await Net.instance.useRelay(local, connect: connect, askFirst: (url) async {
        order.add('asked $url');
        return true;
      }, decide: (url, check) async {
        order.add('decided');
        return (yes: false, pass: null);
      });
      expect(order, ['asked ws://192.168.1.9:7787/hub', 'dialled ws://192.168.1.9:7787/hub', 'decided']);
    });

    test('names only a hosted relay or one on the local network: a public relay, or plain ws:// anywhere, only typed in', () {
      String link(String a) => 'ghostmsg://relay?a=${Uri.encodeQueryComponent(a)}';
      expect(relayFromLink(link('wss://evil.example/hub')), isNull);
      expect(relayFromLink(link('ws://203.0.113.9:80/hub')), isNull);
      expect(relayFromLink(link('ws://evil.example:7787/hub')), isNull);
      expect(relayFromLink(link('wss://192.168.1.9/hub')), isNull, reason: 'a local relay is plain ws://, as the door is');
      expect(tidyRelayAddress(link('wss://evil.example/hub')), isNull);
      for (final ok in ['ws://192.168.1.9:7787/hub', 'ws://10.0.0.5:7787/hub', 'ws://172.20.1.1:7787/hub', 'ws://127.0.0.1:7787/hub', 'ws://maya-mac.local:7787/hub', 'ws://[fd12:3456::1]:7787/hub']) {
        expect(relayFromLink(link(ok)), ok, reason: ok);
      }
      for (final no in ['ws://172.32.0.1:7787/hub', 'ws://192.169.0.1:7787/hub', 'ws://[2001:db8::1]:7787/hub', 'ws://.local:7787/hub']) {
        expect(relayFromLink(link(no)), isNull, reason: no);
      }
      final hosted = '${GhostRelayAddress(relay: 'ab' * 16, node: 'cd' * 32, via: 'wss://gogho.st/hub')}';
      expect(relayFromLink(link(hosted)), hosted);
      // Typed in, a public relay is taken as ever.
      expect(tidyRelayAddress('wss://relay.example.com/hub'), 'wss://relay.example.com/hub');
    });
  });

  group('a hosted relay\'s address names the relay', () {
    final real = NetKeys.generate(), other = NetKeys.generate();
    final url = '${GhostRelayAddress(relay: real.id, node: 'c' * 64)}';

    test('checking it, another relay answering there is refused; the one it names is taken', () async {
      final wrong = await checkRelay(url, connect: (_) async => _FakeLink({'hello': 'd' * 64, 'peek': true, 'relay': _card(other), 'hosted': true}));
      expect([wrong.ok, wrong.problem], [false, wrongRelayWords]);
      final none = await checkRelay(url, connect: (_) async => _FakeLink({'hello': 'd' * 64, 'peek': true, 'hosted': true}));
      expect(none.ok, isFalse, reason: 'one that says no name isn\'t it either');
      final right = await checkRelay(url, connect: (_) async => _FakeLink({'hello': 'd' * 64, 'peek': true, 'relay': _card(real), 'hosted': true}));
      expect(right.ok, isTrue);
      // An ordinary relay's address names none: anything that answers as a relay is one.
      expect((await checkRelay('wss://relay.example.com/hub', connect: (_) async => _FakeLink({'hello': 'd' * 64, 'relay': _card(other)}))).ok, isTrue);
    });

    test('the route doesn\'t sign in to another relay answering there', () async {
      final links = <_FakeLink>[];
      final c = HubCarrier(url: url, signer: KeysSigner(NetKeys.generate()), retry: const Duration(hours: 1), dial: (_) async {
        final l = _FakeLink({'hello': 'd' * 64, 'peek': true, 'relay': _card(other), 'hosted': true});
        links.add(l);
        return l;
      });
      await c.start();
      await waitFor(() => c.problem != null, 'never said anything');
      expect(c.problem, wrongRelayWords);
      expect(links.single.told, isEmpty, reason: 'no sign-in said to it');
      expect(c.state.value, CarrierState.down);
      await c.stop();
    });
  });
}
