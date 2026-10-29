// Handing an address to the phone: the last case of core/linkPreview.test.ts ("opens in the phone's browser through
// the app"), the rule the opener is held to (src-tauri/capabilities/default.json), and what happens when the phone
// has no half, refuses, or has nothing to open it.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/link_preview.dart' show LinkOpener;
import 'package:ghost_md/core/location.dart';
import 'package:ghost_md/core/open_link.dart';

const String urlA = 'https://www.airbnb.com/rooms/1234';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// The phone's half: every call it was handed, answered by [answer].
  List<MethodCall> phone([Object? Function(MethodCall call)? answer]) {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(openLinkChannel, (call) async {
      calls.add(call);
      return answer == null ? true : answer(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(openLinkChannel, null));
    return calls;
  }

  test('opens in the phone’s browser through the app', () async {
    final calls = phone();
    await openLink(urlA);
    expect(calls.single.method, 'open');
    expect(calls.single.arguments, <String, Object?>{'url': urlA});
    expect(openLinkChannel.name, 'ghost_md/open');
  });

  // Matt, 2026-10-29: links in a note tapped on the Fold must open their own app through Android's App Links (a
  // verified hello.trade opens HelloTrade Staging), not a page in a browser inside Ghost. The phone is handed the
  // address alone, as `open {url}`: its half starts a plain ACTION_VIEW with no app named (OpenLink.kt), which
  // the phone's own resolver sends to the app verified for the address, or to the default browser. Nothing here
  // asks for an in-app browser or a Custom Tab, which would skip App Links.
  test('hands an App Link and a LAN address to the phone as written, and asks for nothing but `open`', () async {
    final calls = phone();
    const hello = 'https://hello.trade/waitlist?ref=EXU6LYUP5K', lan = 'http://192.168.18.21:3120';
    await openLink(hello);
    await openLink(lan);
    expect(calls.map((call) => call.method), <String>['open', 'open']);
    expect(calls.map((call) => call.arguments), <Object?>[
      <String, Object?>{'url': hello},
      <String, Object?>{'url': lan},
    ]);
  });

  test('is a LinkOpener, and opens a tapped map in the phone’s maps', () async {
    final calls = phone();
    const LinkOpener opener = openLink;
    await openPlace(const GeoTag(lat: 38.7057, lon: -9.1446, place: 'Cais do Sodré, Lisbon'), opener, MapsApp.androidGeo);
    expect(calls.single.arguments, <String, Object?>{'url': 'geo:38.7057,-9.1446?q=38.7057,-9.1446(Cais%20do%20Sodr%C3%A9%2C%20Lisbon)'});
  });

  test('hands over web pages, mail, a number to ring and a place, as written', () async {
    final calls = phone();
    const open = <String>[
      'http://example.com',
      'https://example.com/a?b=c#d',
      'HTTPS://Example.com/Path',
      'mailto:report@ghostmarkdown.com?subject=Report%20an%20organization&body=Its%20id',
      'tel:+441234567890',
      'geo:51.5074,-0.1278?q=51.5074,-0.1278',
      'https://www.openstreetmap.org/?mlat=51.5074&mlon=-0.1278#map=15/51.5074/-0.1278',
    ];
    for (final url in open) {
      expect(canOpenLink(url), isTrue, reason: url);
      await openLink(url);
    }
    expect(calls.map((call) => (call.arguments as Map)['url']), open);
  });

  test('never hands the phone anything else', () async {
    final calls = phone();
    const refused = <String>[
      'javascript:alert(1)',
      'JavaScript:alert(1)',
      'file:///sdcard/Download/notes.md',
      'content://com.android.contacts/contacts/1',
      'intent://scan/#Intent;scheme=zxing;package=com.google.zxing.client.android;end',
      'intent:#Intent;action=android.intent.action.CALL;end',
      'data:text/html,<script>alert(1)</script>',
      'blob:https://example.com/1',
      'about:blank',
      'market://details?id=x',
      'sms:+441234567890',
      'ftp://example.com/x',
      'app://settings',
      'android-app://com.example/http/x',
      'vbscript:x',
      // not an address at all
      '',
      'example.com',
      '/rooms/1234',
      'just words',
      '//example.com/x',
      'https://',
      'http:///path',
      'mailto:',
      'tel:',
      'geo:',
      // something hidden in front of, or inside, the scheme
      ' javascript:alert(1)',
      '\tjavascript:alert(1)',
      'java\nscript:alert(1)',
      ' https://example.com',
      'https://example.com/a b',
      'https://example.com/\u0000',
    ];
    for (final url in refused) {
      expect(canOpenLink(url), isFalse, reason: url);
      await openLink(url);
    }
    expect(calls, isEmpty);
  });

  test('fails quietly where no phone is listening, the phone refuses, or nothing can open it', () async {
    // No handler at all: a desktop run, a test.
    await openLink(urlA);
    final calls = phone((call) => false); // nothing there opens it
    await openLink('tel:+441234567890');
    expect(calls.length, 1);
    phone((call) => throw PlatformException(code: 'refused', message: 'That address is not one the phone opens.'));
    await openLink(urlA);
    phone((call) => throw MissingPluginException());
    await openLink(urlA);
  });
}
