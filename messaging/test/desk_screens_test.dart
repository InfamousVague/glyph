import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/desktop/link/crypto.dart';
import 'package:ghost_messaging/desktop/link/link.dart';
import 'package:ghost_messaging/desktop/main.dart';
import 'package:ghost_messaging/desktop/remote.dart';
import 'package:ghost_messaging/desktop/store.dart';
import 'package:ghost_messaging/desktop/updates.dart';
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/ui/common.dart';
import 'package:glacier/glacier.dart';

/// The Mac's screens, drawn at a window's size in light and dark and written to test/shots/mac-* (run with
/// `flutter test --update-goldens test/desk_screens_test.dart`): the wizard's steps, the conversations with one
/// open, and Settings. There is no phone here: the conversations are made up and answered below, where the app asks
/// the phone over the link (test/desk_link_test.dart is that).
final _now = DateTime.now();
int _ago({int days = 0, int hours = 0, int minutes = 0}) => _now.subtract(Duration(days: days, hours: hours, minutes: minutes)).millisecondsSinceEpoch;
Map<String, Object?> _p(String address, [String? name]) => {'address': address, 'name': name, 'photo': null};

final _conversations = <Map<String, Object?>>[
  {'id': 1, 'date': _ago(minutes: 4), 'people': [_p('+15551230001', 'Maya Chen')], 'snippet': 'Sounds good, see you at 7! Bring the projector cable if you still have it', 'unread': true, 'error': false, 'archived': false},
  {'id': 2, 'date': _ago(minutes: 52), 'people': [_p('+15551230002', 'Jordan Park'), _p('+15551230003', 'Sam Rivera')], 'snippet': 'Saturday works for me', 'unread': false, 'error': false, 'archived': false},
  {'id': 3, 'date': _ago(hours: 5), 'people': [_p('+15551230005', 'Dad')], 'snippet': 'Call me when you land', 'unread': false, 'error': false, 'archived': false, 'pinned': true},
  {'id': 4, 'date': _ago(days: 1, hours: 2), 'people': [_p('28849')], 'snippet': 'Your verification code is 482913.', 'unread': false, 'error': false, 'archived': false, 'muted': true},
  {'id': 8, 'date': _ago(days: 2), 'people': [_p('+15551230011', 'Riley Fox')], 'snippet': 'Only our two phones can read this now', 'unread': false, 'error': false, 'archived': false, 'encrypted': true},
  {'id': 7, 'date': _ago(days: 40), 'people': [_p('+15551230008', 'Old Thread')], 'snippet': 'ok', 'unread': false, 'error': false, 'archived': true},
];

final _messages = <Map<String, Object?>>[
  {'id': 12, 'kind': 'waiting', 'address': '', 'body': 'Leaving in ten', 'date': _ago(minutes: 1), 'outgoing': true, 'state': 'waiting', 'parts': const []},
  {'id': 6, 'kind': 'sms', 'address': '+15551230001', 'body': 'Sounds good, see you at 7! Bring the projector cable if you still have it', 'date': _ago(minutes: 4), 'outgoing': false, 'state': 'received'},
  {'id': 8, 'kind': 'sms', 'address': '+15551230001', 'body': '❤️ to “Dinner at mine first?”', 'date': _ago(minutes: 20), 'outgoing': false, 'state': 'received'},
  {'id': 5, 'kind': 'sms', 'address': '+15551230001', 'body': 'Dinner at mine first?', 'date': _ago(minutes: 30), 'outgoing': true, 'state': 'delivered'},
  {'id': 4, 'kind': 'sms', 'address': '+15551230001', 'body': 'Movie night is still on for tonight right?', 'date': _ago(minutes: 31), 'outgoing': true, 'state': 'delivered'},
  {'id': 3, 'kind': 'sms', 'address': '+15551230001', 'body': 'Here\'s the link https://example.com/tickets', 'date': _ago(days: 1, hours: 1), 'outgoing': false, 'state': 'received'},
  {'id': 1, 'kind': 'sms', 'address': '+15551230001', 'body': 'Hey! Long time 👋', 'date': _ago(days: 1, hours: 3), 'outgoing': false, 'state': 'received'},
];

/// The phone's answers, made up. What is the Mac's own (its choices) is still the Mac's ([LinkCalls]).
class _Calls extends LinkCalls {
  _Calls(super.link, super.store);

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    final a = (arguments as Map?) ?? const {};
    final Object? answer = switch (method) {
      'conversations' => _conversations,
      'conversationsPage' => {'items': [for (final c in _conversations) if ((c['archived'] == true) == (a['archived'] == true)) c], 'next': null},
      'conversation' => _conversations.where((c) => c['id'] == a['thread']).firstOrNull,
      'archivedCount' => 1,
      'messages' => a['thread'] == 1 ? _messages : const [],
      'people' => _conversations.firstWhere((c) => c['id'] == a['thread'])['people'],
      'e2e' => {'address': a['address'], 'state': a['address'] == '+15551230011' ? 'on' : 'none'},
      'draft' || 'markRead' || 'setDraft' || 'photo' || 'part' => null,
      // The Mac's choices, kept here and not in a file: a test's clock does not wait on a disk.
      'prefs' => Map<String, String>.of(_prefs),
      'setPref' => _prefs['${a['key']}'] = '${a['value']}',
      'searchContacts' => [
          {'name': 'Maya Chen', 'address': '+1 555-123-0001', 'photo': null, 'label': 'Mobile'},
          {'name': 'Mom', 'address': '+1 555-123-0010', 'photo': null, 'label': 'Mobile'},
        ],
      _ => await super.invokeMethod<Object>(method, arguments),
    };
    return answer as T?;
  }

  final _prefs = <String, String>{'enter_sends': 'on'};

  @override
  int get waiting => 1;
}

/// The Mac's half of an update, standing in: it counts the restarts asked for.
class _Mac implements UpdateHost {
  int restarts = 0;
  @override
  Future<InstalledMac?> installed() async => null;
  @override
  Future<String> install(String path, {required String sha256, required int bytes}) async => 'ready';
  @override
  Future<String> restart() async {
    restarts++;
    return 'restarting';
  }
}

Finder _button(String label) => find.byWidgetPredicate((w) => w is IconTap && w.label == label);

class _Store implements LinkStore {
  PairedPhone? kept;
  @override
  Future<PairedPhone?> load() async => kept;
  @override
  Future<void> save(PairedPhone phone) async => kept = phone;
  @override
  Future<void> clear() async => kept = null;
}

Future<void> _fonts() async {
  Future<void> family(String name, String file) async {
    final loader = FontLoader(name)..addFont(File(file).readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
    await loader.load();
  }

  await family('Inter Variable', 'assets/fonts/InterVariable-latin.ttf');
  await family('JetBrains Mono Variable', 'assets/fonts/JetBrainsMonoVariable-latin.ttf');
  await family('Ghost Emoji Noto', 'assets/emoji/NotoColor.ttf');
}

void main() {
  setUpAll(_fonts);
  testWidgets('the Mac\'s screens', (tester) async {
    tester.view.physicalSize = const Size(1100 * 2.0, 740 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
    installSettingsStyles(sheet);
    final dir = Directory.systemTemp.createTempSync('ghost-desk-shots');
    addTearDown(() => dir.deleteSync(recursive: true));

    Future<void> shoot(String name, PhoneLink link, {required bool dark, Future<void> Function()? then, MacUpdates? updates}) async {
      final store = DeskStore(dir, keychain: false);
      final calls = _Calls(link, store);
      Sms.calls = calls;
      final state = AppState()
        ..setTheme(dark ? 'dark' : 'light')
        ..set('emoji', 'noto');
      await tester.pumpWidget(KeyedSubtree(key: ValueKey('$name$dark'), child: DesktopApp(sheet: sheet, state: state, link: link, calls: calls, store: store, updates: updates)));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      if (then != null) await then();
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      // Written, never compared: the conversations hold the time of day. A plain run builds every screen.
      if (autoUpdateGoldenFiles) await expectLater(find.byType(DesktopApp), matchesGoldenFile('shots/mac-$name-${dark ? 'dark' : 'light'}.png'));
    }

    PhoneLink fresh() => PhoneLink(store: _Store(), name: "Matt's MacBook Pro", app: '0.6.0');

    for (final dark in [false, true]) {
      // The wizard: how to connect, the code to scan, the six digits.
      await shoot('1-wizard', fresh(), dark: dark);
      final showing = fresh()..beginPairing(mode: 'both', relay: 'wss://ghost-sms.com/relay');
      // The code as the examples have it, so the picture is the same from one run to the next.
      await shoot('2-code', showing, dark: dark);
      expect(find.text('Scan this with your phone'), findsOneWidget);
      final comparing = fresh();
      comparing.beginPairing(mode: 'both', relay: 'wss://ghost-sms.com/relay')
        ..phase = 'code'
        ..code = '874151'
        ..phoneName = 'Galaxy Z Fold8';
      await shoot('3-digits', comparing, dark: dark);
      expect(find.text('874 151'), findsOneWidget);
      expect(find.text('They match'), findsOneWidget);

      // Paired: the conversations, one of them open, a text waiting for the phone.
      PhoneLink paired(String? via) => fresh()
        ..phone = PairedPhone(id: 'd387c0690aec58b7', name: 'Galaxy Z Fold8', key: DeskCrypto.randomBytes(32), mode: 'both', relay: 'wss://ghost-sms.com/relay', since: DateTime.now().subtract(const Duration(days: 9)))
        ..shownVia = via;
      await shoot('4-conversations', paired('local'), dark: dark, then: () async {
        await tester.tap(find.text('Maya Chen'));
      });
      expect(find.text('Waiting for your phone'), findsOneWidget); // under the text typed while it was away
      expect(find.textContaining('Connected over the local network'), findsOneWidget);
      // What only the phone does is not offered here.
      expect(_button('Send'), findsOneWidget);
      expect(_button('Call'), findsNothing);
      expect(_button('Stickers'), findsNothing);
      expect(_button('Add an attachment'), findsNothing);
      expect(_button('Conversation settings'), findsNothing);
      expect(_button('Back'), findsNothing);

      await shoot('5-settings', paired('relay'), dark: dark, then: () async {
        await tester.tap(_button('Settings'));
      });
      expect(find.text('Unpair this phone'), findsOneWidget);
      expect(find.textContaining('Connected through the relay'), findsWidgets);

      await shoot('6-waiting', paired(null), dark: dark);
      expect(find.textContaining('Waiting for your phone'), findsOneWidget);
      expect(find.text('Restart to update'), findsNothing);

      // A newer version is in place beside this one: a bar over the page says so, and Restart to update swaps it in.
      final mac = _Mac();
      final ready = MacUpdates.standing(
        installed: const InstalledMac(version: '0.6.2', build: 456601, dir: '/tmp/none'),
        phase: MacUpdatePhase.ready,
        release: MacRelease(version: '0.7.0', build: 470000, sha256: 'ab' * 32, bytes: 35000000, url: Uri.parse('https://ghost-sms.com/ghost-messaging-mac.zip')),
        host: mac,
      );
      await shoot('7-update-ready', paired('local'), dark: dark, updates: ready);
      expect(find.text('Ghost Messaging 0.7.0 is ready'), findsOneWidget);
      await tester.tap(find.text('Restart to update'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(mac.restarts, 1);
      expect(find.text('Restarting as Ghost Messaging 0.7.0…'), findsOneWidget);
      expect(find.text('Restart to update'), findsNothing);
      // And in Settings: where the updates stand, and a look for one when asked.
      final idle = MacUpdates.standing(installed: const InstalledMac(version: '0.6.2', build: 456601, dir: '/tmp/none'), phase: MacUpdatePhase.idle, host: mac);
      await shoot('8-settings-updates', paired('local'), dark: dark, updates: idle, then: () async {
        await tester.tap(_button('Settings'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.scrollUntilVisible(find.text('Look for an update'), 200, scrollable: find.byType(Scrollable).last);
      });
      expect(find.text('Look for an update'), findsOneWidget);
      expect(find.textContaining('Up to date. This is 0.6.2 (456601)'), findsOneWidget);
    }
    // Leave nothing running: the wizard's question to the relay, a toast.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
