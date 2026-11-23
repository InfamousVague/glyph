import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/looks.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides;
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/net.dart';
import 'package:ghost_messaging/net/p2p/node.dart';
import 'package:ghost_messaging/net/p2p/p2p.dart';
import 'package:ghost_messaging/net/packet.dart';
import 'package:ghost_messaging/ui/network.dart';
import 'package:ghost_messaging/ui/settings.dart' show SettingsModel;
import 'package:glacier/glacier.dart';

import 'support/direct_world.dart';
import 'support/fake_p2p.dart';

/// Settings › Routes and the direct route (lib/ui/network.dart): no Direct row at all in a build with no core; with
/// one, the route among the others with its switch, and under them what it knows, what it holds now, "Only through
/// link helpers", and a line where the relay has named no link helper.

const _helper = 'https://link.example';

/// Every piece of text drawn in the row keyed [key].
List<String> _words(WidgetTester tester, String key) => [for (final t in tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))) ?t.data];

Finder _switchIn(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(GlacierSwitch));

/// Lets what a press set off finish, however long the machine takes (two seconds at most), not for a length of time.
Future<void> _until(WidgetTester tester, bool Function() ok) async {
  for (var i = 0; i < 400 && !ok(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pump(WidgetTester tester, AppState state, Listenable listenable, List<Widget> Function(BuildContext) rows) async {
  tester.view.physicalSize = const Size(412, 3600) * 2.0;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
  installSettingsStyles(sheet);
  await tester.pumpWidget(AppScope(
    state: state,
    child: WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
      builder: (context, child) => GlacierTheme(sheet: sheet, attrs: ghostAttrs(state, 'mobile'), child: InkOverrides(child: GlacierToastProvider(child: child!))),
      home: ListenableBuilder(listenable: listenable, builder: (context, _) => ListView(children: rows(context))),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('what the rows say', () {
    expect([directKnownWords(0), directKnownWords(1), directKnownWords(4)], ['No friend\'s device known yet', 'Knows 1 friend\'s device', 'Knows 4 friends\' devices']);
    const how = 'A device is known once it and this one have told each other they are here, which they do through the relay server.';
    expect([directKnownHint(0), directKnownHint(1), directKnownHint(3)], [how, 'And 1 other device of your own. $how', 'And 3 other devices of your own. $how']);
    expect([directLinkedWords(0), directLinkedWords(1), directLinkedWords(2)], ['Not linked to any now', 'Linked to 1 device now', 'Linked to 2 devices now']);
    expect(directLinkedHint(const []), 'A link is made when the relay server can\'t carry something, and let go when nothing has been said on it for a while.');
    expect(directLinkedHint(const [P2pPathKind.direct]), '1 straight.');
    expect(directLinkedHint(const [P2pPathKind.helper, P2pPathKind.direct, P2pPathKind.helper]), '1 straight, 2 through a link helper.');
    expect(directLinkedHint(const [P2pPathKind.helper]), '1 through a link helper.');
    expect(directLinkedHint(const [P2pPathKind.none]), 'Finding the way.');
    expect(directHelpersOnlyHint, 'Friends\' devices then see the link helper\'s address and not this device\'s. It is slower.');
  });

  test('the settings pages are told to draw again when what the direct route knows or holds changes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async => null);
    final model = SettingsModel(AppState())..start();
    await pumpEventQueue();
    var drawn = 0;
    model.addListener(() => drawn++);
    Net.instance.direct.value++;
    expect(drawn, 1);
    model.dispose();
    Net.instance.direct.value++;
    expect(drawn, 1, reason: 'and no longer once the pages are gone');
  });

  group('Settings › Routes, as the app holds the routes', () {
    final me = NetKeys.generate(), sam = NetKeys.generate();
    late Map<String, String> secrets;

    setUp(() {
      secrets = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async {
        final a = call.arguments is Map ? call.arguments as Map : const {};
        switch (call.method) {
          case 'netIdentity':
            return {'id': me.id, 'key': base64Encode(me.public)};
          case 'netSign':
            return NetCrypto.sign(me, (a['message'] as List).cast<int>());
          case 'netPeers':
            return [
              {'id': sam.id, 'address': '@sam', 'key': NetCrypto.netKey(NetCrypto.conversationKey(me, sam.public)!)},
            ];
          case 'netSmsDrain':
            return const <Object>[];
          case 'secretKeep':
            final value = '${a['value'] ?? ''}';
            value.isEmpty ? secrets.remove('${a['name']}') : secrets['${a['name']}'] = value;
            return null;
          case 'secretRead':
            return secrets['${a['name']}'];
        }
        return null;
      });
    });
    tearDown(() async {
      await Net.instance.shutdown();
      Net.p2pNode = null;
    });

    Future<void> open(WidgetTester tester, AppState state) async {
      await tester.runAsync(() async {
        await Net.instance.start(state, carriers: [PlainCarrier('hub'), PlainCarrier('sms')]);
        final p2p = Net.instance.p2p;
        for (var i = 0; i < 400 && p2p != null && !(p2p.loaded && p2p.card != null); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      final model = SettingsModel(state);
      addTearDown(model.dispose);
      await _pump(tester, state, Listenable.merge([Net.instance, Net.instance.direct]), (context) => networkPane(context, model));
    }

    testWidgets('a build with no core shows no Direct row at all, and nothing of the direct route', (tester) async {
      await open(tester, AppState());
      expect(find.byKey(const ValueKey('route-hub')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-sms')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-p2p')), findsNothing);
      for (final key in ['direct-known', 'direct-linked', 'direct-helpers-only', 'direct-no-helpers']) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      expect(find.text('Direct'), findsNothing);
      expect(find.text('DIRECT'), findsNothing);
      expect(find.textContaining('a peer-to-peer one, with no server, are being made'), findsOneWidget, reason: 'still said to be on its way');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a core that could not be started: the other routes as ever, and a Direct line that says why', (tester) async {
      Net.p2pNode = FakeP2pMesh.broken(StateError('libghost_p2p.so could not be loaded'));
      await open(tester, AppState());
      expect(find.byKey(const ValueKey('route-hub')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-p2p')), findsNothing);
      expect(_words(tester, 'direct-problem'), ['Direct isn\'t working on this device', 'The direct route could not be started on this device (Bad state: libghost_p2p.so could not be loaded). The other routes work as before.']);
      for (final key in ['direct-known', 'direct-linked', 'direct-helpers-only']) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with a core the Direct route is among the others, switched off and on like them, with its lines and its switch under them', (tester) async {
      final mesh = FakeP2pMesh();
      Net.p2pNode = mesh.node;
      final state = AppState();
      await open(tester, state);
      // Among the routes, after the relay's: its name, how it stands, what it is.
      final routes = [for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('route-')).evaluate()) (e.widget.key as ValueKey<String>).value];
      expect(routes, ['route-hub', 'route-p2p', 'route-sms']);
      expect(_words(tester, 'route-p2p'), ['Direct', 'Ready\nStraight between your devices and your friends\', with no server in between. Their device sees your network address; nobody else does.']);
      expect(find.textContaining('a peer-to-peer one'), findsNothing);
      expect(find.text('A route over the local network is being made: it will be listed here.'), findsOneWidget);
      // Under them: what it knows, what it holds, the one choice, and that the relay has named no link helper.
      expect(_words(tester, 'direct-known'), ['No friend\'s device known yet', directKnownHint(0)]);
      expect(_words(tester, 'direct-linked'), ['Not linked to any now', directLinkedHint(const [])]);
      expect(_words(tester, 'direct-helpers-only'), ['Only through link helpers', directHelpersOnlyHint]);
      expect(_words(tester, 'direct-no-helpers'), ['No link helpers yet', 'Direct links work on your own network for now.']);
      expect(tester.widget<GlacierSwitch>(_switchIn('direct-helpers-only')).checked, isFalse);
      expect(tester.widget<GlacierSwitch>(_switchIn('route-p2p')).checked, isTrue);

      // "Only through link helpers": kept as the person's choice, and said to mean nothing links for now.
      await tester.tap(_switchIn('direct-helpers-only'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(Net.instance.p2p!.helpersOnly, isTrue);
      expect(state.choice(P2p.helpersOnlyName, ''), 'on');
      expect(tester.widget<GlacierSwitch>(_switchIn('direct-helpers-only')).checked, isTrue);
      expect(_words(tester, 'direct-no-helpers').last, 'So nothing links while "Only through link helpers" is on.');
      // The relay names a link helper: that line goes.
      Net.instance.p2p!.setHelpers(const [_helper]);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('direct-no-helpers')), findsNothing);

      // Switched off like any route: kept with the routes switched off, and the route says so.
      await tester.tap(_switchIn('route-p2p'));
      await _until(tester, () => Net.instance.board!.off.contains('p2p') && !Net.instance.p2p!.on);
      expect(Net.instance.board!.off, {'p2p'});
      expect(state.choice('net_off', ''), 'p2p');
      expect(Net.instance.p2p!.on, isFalse);
      expect(_words(tester, 'route-p2p').last, startsWith('Off\n'));
      expect(tester.widget<GlacierSwitch>(_switchIn('route-p2p')).checked, isFalse);
      await tester.tap(_switchIn('route-p2p'));
      await _until(tester, () => Net.instance.board!.off.isEmpty && Net.instance.p2p!.on);
      expect([Net.instance.board!.off, state.choice('net_off', 'x'), Net.instance.p2p!.on], [isEmpty, '', isTrue]);
      expect(_words(tester, 'route-p2p').last, startsWith('Ready\n'));
      // Everything that was started is stopped before the page goes.
      await tester.runAsync(() => Net.instance.shutdown());
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('the Direct section, over devices that know and link with each other', () {
    testWidgets('says how many friends\' devices are known and how many of your own, how many are linked and how, and draws again as that changes', (tester) async {
      final w = World(helpers: [_helper]);
      final maya = w.account('maya');
      late Install a, b, mine;
      await tester.runAsync(() async {
        a = w.install(maya, computer: true);
        mine = w.install(maya, computer: true);
        b = w.install(w.account('sam'), computer: true, network: 'elsewhere');
        w.friends(a, b);
        w.friends(mine, b);
        for (final i in [a, mine, b]) {
          await i.start();
        }
      });
      addTearDown(() => tester.runAsync(w.stop));
      final state = AppState();
      await _pump(tester, state, a.p2p, (context) => [directSection(context, a.p2p)]);
      expect(_words(tester, 'direct-known'), ['Knows 1 friend\'s device', directKnownHint(1)]);
      expect(_words(tester, 'direct-linked'), ['Not linked to any now', directLinkedHint(const [])]);
      expect(find.byKey(const ValueKey('direct-no-helpers')), findsNothing, reason: 'the relay named one');
      expect(find.text('DIRECT'), findsOneWidget);

      // The relay goes, and a text is sent: a link to the friend's device on another network, through the helper, and
      // one to this account's own other device, straight.
      await tester.runAsync(() async {
        await w.relayGone();
        await a.text(b.account, 'by the helper');
        await a.board.send(a.mine, _mine(), only: const {'p2p'});
        await w.settle();
      });
      await tester.pump(const Duration(milliseconds: 50));
      expect(_words(tester, 'direct-linked'), ['Linked to 2 devices now', '1 straight, 1 through a link helper.']);

      // "Only through link helpers": the node is started again with it, so the links go, and are made through the
      // helper when next used.
      await tester.tap(_switchIn('direct-helpers-only'));
      await tester.runAsync(w.settle);
      await tester.pump(const Duration(milliseconds: 50));
      expect([a.p2p.helpersOnly, a.node.config!.helpersOnly, a.plain.kept[P2p.helpersOnlyName]], [true, true, 'on']);
      expect(_words(tester, 'direct-linked').first, 'Not linked to any now');
      await tester.runAsync(() async {
        await a.board.send(a.mine, _mine(), only: const {'p2p'});
        await w.settle();
      });
      await tester.pump(const Duration(milliseconds: 50));
      expect(_words(tester, 'direct-linked'), ['Linked to 1 device now', '1 through a link helper.']);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

Envelope _mine() => Envelope(kind: 'mine', body: const {'t': 'to my other device'});
