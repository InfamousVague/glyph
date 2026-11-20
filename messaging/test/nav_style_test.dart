import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/circles/circles.dart';
import 'package:ghost_messaging/ui/nav_style.dart';
import 'package:ghost_messaging/ui/shell.dart';
import 'package:ghost_messaging/voice/voice.dart' show SpaceKind;

import 'support/list_harness.dart';

/// One navigation on every page (Matt, 2026-11-19: "work on a unified navigation across the whole app instead of it
/// changing navigations on every page ... including a navigation rail version of the app. It should include the
/// circles icons like discord and slack does ... give me a setting in developer settings to switch between the
/// different views"). Each style is pictured on a phone and a wide window, on the conversations and inside a circle,
/// at build/themes/nav-style/<style>-<size>-<where>.png.
Future<void> _fonts() async {
  final loader = FontLoader('Inter Variable')..addFont(File('assets/fonts/InterVariable-latin.ttf').readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  await loader.load();
}

Circle _circle(String n, String name, String hue, String icon, {String? picture}) => Circle(
      seed: n * 64,
      owner: '',
      manifest: CircleManifest(owner: '', version: 1, name: name, hue: hue, icon: icon, picture: picture, spaces: [
        CircleSpace(seed: '${n}a' * 32, name: 'General', kind: SpaceKind.text),
        CircleSpace(seed: '${n}b' * 32, name: 'Lounge', order: 1),
      ]),
    );

final _owls = _circle('7', 'Night Owls', 'indigo', 'sparkles');
// With a picture of its own: a square one, a dark ground to its edges, which the rail's round must fill with none of
// the circle's colour round its rim (Matt, 2026-11-19: "the icons inside the sidebar rail for the circles bleed around
// the edges since they're square and not zoomed to fit").
final _alpha = _circle('8', 'Alpha Testers', 'teal', 'flask-conical', picture: base64.encode(File('test/fixtures/circle-face.png').readAsBytesSync()));

Future<void> _keep(WidgetTester tester, String name) async {
  final element = find.byType(WidgetsApp).evaluate().single;
  await tester.runAsync(() async {
    final image = await captureImage(element);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('build/themes/nav-style/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);
  setUp(() => ListPhone([
        ListPhone.conversation(1, '+15551230001', 'See you at 7', name: 'Maya Chen'),
        ListPhone.conversation(2, '+15551230002', 'The build is out', name: 'Sam Ortiz'),
      ]).install());
  tearDown(() async => Circles.instance.clear());

  for (final (size, at) in [('phone', const Size(412, 892)), ('wide', const Size(1000, 760))]) {
    for (final style in NavStyle.values) {
      testWidgets('${style.name} on a $size: the conversations and a circle', (tester) async {
        Circles.instance.join(_owls);
        Circles.instance.join(_alpha);
        final state = AppState()..set(NavStyle.pref, style.name);
        final sheet = await loadSheet(tester);
        await pumpScreen(tester, sheet, const AppShell(), state, size: at);
        await settle(tester);
        await _keep(tester, '${style.name}-$size-home');

        AppShellState.live!.openCircle(_owls);
        await settle(tester);
        await _keep(tester, '${style.name}-$size-circle');

        switch (style) {
          case NavStyle.classic:
            // The circle's own dock in place of the app's.
            expect(_key('nav-home'), findsOneWidget);
            expect(_key('nav-messages'), findsNothing);
          case NavStyle.dock:
            // The app's rings stay, inside the circle too.
            expect(_key('nav-home'), findsNothing);
            for (final id in ['new', 'messages', 'contacts', 'archive', 'settings']) {
              expect(_key('nav-$id'), findsOneWidget, reason: id);
            }
          case NavStyle.rail:
            // No pill: the rail, its circles by their faces, and Home taking the circle away.
            expect(_key('nav-messages'), findsNothing);
            // Share feedback is the rail's, one ring above Settings, not beside the search (Matt, 2026-11-20).
            expect(_key('share-feedback'), findsOneWidget);
            expect(tester.getCenter(_key('share-feedback')).dy, lessThan(tester.getCenter(_key('rail-settings')).dy));
            expect(tester.getCenter(_key('share-feedback')).dy, greaterThan(tester.getCenter(_key('rail-archive')).dy));
            expect(_key('rail-circle-${_owls.seed}'), findsOneWidget);
            expect(_key('rail-circle-${_alpha.seed}'), findsOneWidget);
            await tester.tap(_key('rail-circle-${_alpha.seed}'));
            await settle(tester);
            expect(AppShellState.live!.openCircleSeed, _alpha.seed);
            await tester.tap(_key('rail-home'));
            await settle(tester);
            expect(AppShellState.live!.circleOpen, isFalse);
        }

        // Settings: the same navigation stays where it is unified, on a phone too.
        AppShellState.live!.settings();
        await settle(tester);
        await _keep(tester, '${style.name}-$size-settings');
        if (style == NavStyle.rail) expect(_key('rail-settings'), findsOneWidget);
      });
    }
  }
}
