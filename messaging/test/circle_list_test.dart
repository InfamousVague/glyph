// A circle's list, the one way a circle is drawn (Matt, 2026-11-17: "Lets remove the other views and focus on the list
// view / layout it's the most practical of them all so far"): it draws a busy made-up circle without overflowing on a
// small phone (360 wide), as a wide window's sidebar and across a whole 1180-wide window, in every look and brightness;
// each space says what is going on in it (who is talking, how many files, the newest message); a press opens a space;
// New space ends the list for whoever may add one; and nothing offers a choice of layout any more.
//
// With THEME_SHOTS=1 each is also kept as a picture at build/themes/circle-list/<look>-<theme>[-wide].png.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/looks.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides, ghostTypography;
import 'package:ghost_messaging/ui/circles/circle_list.dart';
import 'package:ghost_messaging/ui/circles/circle_view.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:glacier/glacier.dart';

import 'circle_sample.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final shots = Platform.environment['THEME_SHOTS'] == '1';
  late TokenSheet sheet;

  setUpAll(() async {
    await _fonts();
    sheet = await loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css']);
    installSettingsStyles(sheet);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('ghost/voicefx'), (call) async => null);
  });

  /// [child] in [look] and [theme] in a window of [size].
  Future<void> draw(WidgetTester tester, Widget child, {required Size size, Look look = Look.ghost, String theme = 'light', AppState? state}) async {
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
    addTearDown(tester.view.reset);
    final app = (state ?? AppState())
      ..setTheme(theme)
      ..setLook(look);
    await tester.pumpWidget(AppScope(
      state: app,
      child: WidgetsApp(
        key: ValueKey('${look.name}-$theme-$size-${child.hashCode}'),
        color: const Color(0xFF4F5BD5),
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
        builder: (context, child) => ListenableBuilder(
          listenable: app,
          builder: (context, _) => GlacierTheme(sheet: sheet, attrs: ghostAttrs(app, 'mobile'), typography: ghostTypography('noto'), child: InkOverrides(child: child!)),
        ),
        home: child,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> keep(WidgetTester tester, String name) async {
    final element = find.byType(WidgetsApp).evaluate().single;
    await tester.runAsync(() async {
      final image = await captureImage(element);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('build/themes/circle-list/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  for (final look in Look.values) {
    testWidgets('the list draws in ${look.name} on a phone, as a sidebar and across a whole window', (tester) async {
      for (final theme in [if (look.light) 'light', if (look.dark) 'dark']) {
        await draw(tester, CircleList(view: sampleCircleView()), size: const Size(360, 780), look: look, theme: theme);
        expect(tester.takeException(), isNull, reason: '360 in ${look.name} $theme');
        if (shots) await keep(tester, '${look.name}-$theme');
        await draw(tester, CircleList(view: sampleCircleView(wide: true, selected: sampleCircle.spaces.first.seed)), size: const Size(320, 860), look: look, theme: theme);
        expect(tester.takeException(), isNull, reason: 'a 320 sidebar in ${look.name} $theme');
        if (shots) await keep(tester, '${look.name}-$theme-wide');
        await draw(tester, CircleList(view: sampleCircleView(wide: true)), size: const Size(1180, 860), look: look, theme: theme);
        expect(tester.takeException(), isNull, reason: '1180 in ${look.name} $theme');
      }
    });
  }

  testWidgets('a banner is behind the header, taller, with the back arrow, face and name drawn on it', (tester) async {
    // Matt, 2026-11-19: "the background image for the header of circles needs to be taller and the back arrow and
    // other header content should render inside the background image not above it".
    final png = await tester.runAsync(() async {
      final r = ui.PictureRecorder();
      final canvas = Canvas(r);
      const size = Size(240, 80);
      canvas.drawRect(Offset.zero & size, Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(240, 80), [const Color(0xFF2E7D6B), const Color(0xFFE0A84A)]));
      for (var i = 0; i < 12; i++) {
        canvas.drawCircle(Offset(16.0 + i * 20, 24.0 + (i % 3) * 16), 7, Paint()..color = const Color(0x55FFFFFF));
      }
      final img = await r.endRecording().toImage(240, 80);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      return base64Encode(bytes!.buffer.asUint8List());
    });
    final m = sampleCircle.manifest;
    expect(png!.length, lessThan(26000), reason: 'small enough for a manifest');
    final c = sampleCircle.copyWith(manifest: m.next(extra: {...m.extra, 'bn': png}));
    for (final theme in ['light', 'dark']) {
      await draw(tester, CircleList(view: sampleCircleView(circle: c, onBack: () {})), size: const Size(412, 892), theme: theme);
      expect(tester.takeException(), isNull);
      final banner = tester.getRect(find.byKey(const ValueKey('circle-banner-strip')));
      final back = tester.getRect(find.bySemanticsLabel('Back'));
      final name = tester.getRect(find.text('Night Owls').first);
      // Set in a little from the screen's edges, rounded (Matt, 2026-11-19: "add just a bit of margin around the sidebar
      // banner header and add some border radius to them so it's not edge to edge").
      expect(banner.top, inInclusiveRange(4, 16), reason: 'a little below the top of the screen');
      expect(banner.left, inInclusiveRange(4, 16), reason: 'in from the left');
      expect(412 - banner.right, inInclusiveRange(4, 16), reason: 'in from the right');
      expect(find.ancestor(of: find.byKey(const ValueKey('circle-banner-strip')), matching: find.byType(ClipRRect)), findsWidgets, reason: 'rounded');
      expect(banner.height, greaterThan(135), reason: 'taller, less its margin');
      expect(banner.contains(back.center) && banner.contains(name.center), isTrue, reason: 'the header is inside it');
      await keep(tester, 'banner-$theme');
    }
  });

  testWidgets('each space says what is going on in it, under its heading, and New space ends the list', (tester) async {
    String? under = 'unset';
    await draw(tester, CircleList(view: sampleCircleView(onNewSpace: ({String? section}) => under = section)), size: const Size(412, 1200));
    expect(find.text('ROOMS'), findsOneWidget);
    expect(find.text('SHARING'), findsOneWidget);
    expect(find.text('3 talking · Maya, Theo, Sam'), findsOneWidget, reason: 'who is in the voice space\'s call');
    expect(find.text('48 files'), findsOneWidget, reason: 'a quiet Files space counts its files');
    expect(find.text('Sam: Added flashcards.zip'), findsOneWidget, reason: 'one with something new says it');
    expect(find.text('Maya: Popcorn is on me'), findsOneWidget);
    expect(find.text('3'), findsWidgets, reason: 'General\'s unread count');
    final add = find.byKey(const ValueKey('circle-new-space'));
    expect(add, findsOneWidget);
    await tester.ensureVisible(add);
    await tester.pump();
    await tester.tap(add);
    expect(under, isNull, reason: 'New space at the foot is under no heading');
  });

  testWidgets('whoever may not change the circle has no New space', (tester) async {
    await draw(tester, CircleList(view: sampleCircleView(canEdit: false)), size: const Size(412, 1200));
    expect(find.byKey(const ValueKey('circle-new-space')), findsNothing);
  });

  testWidgets('a press on a space opens it', (tester) async {
    final lounge = sampleCircle.spaces[1].seed;
    CircleSpaceView? opened;
    await draw(tester, CircleList(view: sampleCircleView(onOpen: (s) => opened = s)), size: const Size(412, 892));
    await tester.tap(find.byKey(ValueKey('circle-space-$lounge')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened?.seed, lounge);
  });

  testWidgets('Settings › Appearance offers no circle layout', (tester) async {
    await draw(tester, const SettingsSectionScreen('appearance'), size: const Size(412, 4000));
    expect(find.textContaining(RegExp('circle layout', caseSensitive: false), findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a space\'s line: talking, then files, then the newest message', () {
    final v = sampleCircleView();
    String? line(String name) => circleSpaceLine(v.spaces.firstWhere((s) => s.name == name));
    expect(line('Lounge'), '3 talking · Maya, Theo, Sam');
    expect(line('Photos'), '48 files');
    expect(line('Drop box'), 'Sam: Added flashcards.zip');
    expect(line('Study room'), isNull);
  });
}

/// The app's fonts, so the pictures show words.
Future<void> _fonts() async {
  Future<void> family(String name, String file) async {
    final loader = FontLoader(name)..addFont(File(file).readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
    await loader.load();
  }

  await family('Inter Variable', 'assets/fonts/InterVariable-latin.ttf');
  await family('JetBrains Mono Variable', 'assets/fonts/JetBrainsMonoVariable-latin.ttf');
  await family('Arimo', 'assets/fonts/ArimoVariable.ttf');
  await family('Ghost Emoji Noto', 'assets/emoji/NotoColor.ttf');
}
