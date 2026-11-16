import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/accent.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/backgrounds.dart';
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/kit/semantic_colors.dart';
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/looks.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides, ghostTypography;
import 'package:ghost_messaging/net/crypto.dart' show NetKeys, NetCrypto;
import 'package:ghost_messaging/net/hub_carrier.dart' show RoomEvent, KeysSigner;
import 'package:ghost_messaging/sms.dart' show Person, Sms;
import 'package:ghost_messaging/ui/compose.dart';
import 'package:ghost_messaging/ui/dialup/dialup.dart';
import 'package:ghost_messaging/ui/hangout_screen.dart';
import 'package:ghost_messaging/ui/inbox_ui.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:ghost_messaging/ui/shell.dart';
import 'package:ghost_messaging/ui/thread.dart';
import 'package:ghost_messaging/voice/channels.dart';
import 'package:ghost_messaging/voice/hangout.dart';
import 'package:ghost_messaging/voice/roles.dart';
import 'package:ghost_messaging/voice/voice.dart';
import 'package:glacier/glacier.dart';

/// The looks (lib/looks.dart; Matt, 2026-11-16: "spend some time making a few themes for ghost, base one of them
/// heavily on the old AOL chatrooms").
///
/// Every run checks that each look, in each brightness it has, gives every colour the app's Dart reads (a look's
/// rules that loop or leave a grey out make a colour come out empty, which would stop the app drawing at all), that
/// its ink reads on its paper and your bubble's words on your bubble, and that Ghost's own look is as it was.
///
/// It also builds a few screens in every look ([themeScreens]), failing on an exception. With THEME_SHOTS=1 in the
/// environment (or `flutter test --update-goldens test/themes_test.dart`) it keeps their pictures at
/// `build/themes/<look>-<brightness>-<screen>.png`, for looking at side by side. Those are never compared and never
/// kept in git (test/shots is for the app's own pictures). Add a screen to [themeScreens].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TokenSheet sheet;

  setUpAll(() async {
    sheet = await _loadSheet();
  });

  group('every look gives every colour the app reads', () {
    for (final look in Look.values) {
      for (final b in brightnessesOf(look)) {
        test('${look.name} $b', () {
          final t = Tokens.root(sheet, attrs: look.attrs(platform: 'mobile', theme: b));
          expect(t.attrs['theme'], b);
          for (final name in colourTokens) {
            expect(() => t.color(name), returnsNormally, reason: '--$name under ${look.name} $b');
          }
          // The page's words on the page, and your bubble's words on your bubble (WCAG AA, 4.5:1).
          expect(_contrast(t.color('app-ink'), t.color('app-paper')), greaterThanOrEqualTo(4.5), reason: 'ink on paper, ${look.name} $b');
          final (mine, onMine) = bubbleOf(t, 'theme');
          expect(_contrast(onMine, mine), greaterThanOrEqualTo(4.5), reason: 'words on your bubble, ${look.name} $b');
          expect(_contrast(t.color('app-on-bubble-mine'), t.color('app-bubble-mine')), greaterThanOrEqualTo(4.5));
          // The accent the look's own bubbles leave in place reads too.
          expect(_contrast(t.color('app-on-accent'), t.color('app-accent')), greaterThanOrEqualTo(4.5), reason: 'words on the accent, ${look.name} $b');
          // A look's brightness is the page's: Dart's isDark, the system bars and the bubble greys go by it.
          expect(t.isDark, b == 'dark');
        });
      }
    }
  });

  test('a look stamps its preset and its fixed brightness; Ghost stamps neither, and follows Theme', () {
    _answerChannel();
    final app = AppState();
    expect(ghostAttrs(app, 'mobile'), {'platform': 'mobile'}, reason: 'Ghost on System: exactly what the app stamped before looks');
    app.setTheme('dark');
    expect(ghostAttrs(app, 'desktop'), {'platform': 'desktop', 'theme': 'dark'});
    app.setLook(Look.mist);
    expect(ghostAttrs(app, 'mobile'), {'platform': 'mobile', 'theme': 'light', 'theme-preset': 'mist'}, reason: 'Mist is always light');
    app.setLook(Look.sharp);
    expect(ghostAttrs(app, 'mobile')['theme'], 'dark', reason: 'Sharp has both halves, so Theme says');
    app.setLook(Look.dialup);
    expect(ghostAttrs(app, 'mobile')['rounding'], 'square');
  });

  test('choosing a look makes your bubbles its own; Ghost again puts them back, unless a colour was chosen since', () {
    _answerChannel();
    final app = AppState();
    expect(app.bubble, 'white');
    app.setLook(Look.lamplight);
    expect(app.bubble, 'theme');
    expect(app.choice('theme_bubble', ''), 'orange', reason: 'the keyboard is told the nearest of its own colours');
    app.setLook(Look.ghost);
    expect(app.bubble, 'white');
    app.setLook(Look.phosphor);
    app.setBubble('blue');
    app.setLook(Look.ghost);
    expect(app.bubble, 'blue', reason: 'a colour chosen after the look stays');
    for (final look in Look.values) {
      expect(bubbleColors.map((b) => b.id), contains(look.keyboard), reason: 'a colour Ghost Keyboard knows');
    }
  });

  test('a look\'s own bubbles leave its accent alone; a colour chosen still wins over it', () {
    expect(accentPair('theme').light, isNull);
    expect(accentPair('theme').dark, isNull);
    expect(accentCss('theme'), isNull);
    // Chosen on Mist's page, blue is the accent; white would not be seen on it, so it is not.
    final mist = Tokens.root(sheet, attrs: Look.mist.attrs(platform: 'mobile'));
    final page = mist.color('app-paper');
    expect(accentPair('blue', lightPage: page).light, isNotNull);
    expect(accentPair('white', lightPage: page).light, isNull);
  });

  test('Ghost is drawn as it was: the colours that were hex in the Dart, the scrims, and the accent check', () {
    for (final b in ['light', 'dark']) {
      final t = Tokens.root(sheet, attrs: Look.ghost.attrs(platform: 'mobile', theme: b));
      int argb(Color c) => c.toARGB32();
      expect(argb(t.danger), argb(t.colorOf('#dd3a30')));
      expect(argb(t.unread), argb(t.colorOf('#4f5bd5')));
      expect(argb(t.chosen), argb(t.colorOf('#4f5bd5')));
      expect(argb(t.info), argb(t.colorOf('#4f5bd5')));
      expect(argb(t.online), argb(t.colorOf('#2fb35a')));
      expect(argb(t.warn), argb(t.colorOf('#c27c00')));
      expect(argb(t.pinned), argb(t.colorOf('#d38b00')));
      expect(argb(t.chosenWash), argb(t.colorOf('color-mix(in srgb, #4f5bd5 22%, transparent)')));
      expect(argb(t.textSelection), argb(t.colorOf('color-mix(in srgb, #4f5bd5 30%, transparent)')));
      expect(argb(t.failedGround), argb(t.colorOf('color-mix(in srgb, #dd3a30 18%, var(--app-paper-2))')));
      expect(argb(t.sheetScrim), 0x66000000);
      expect(argb(t.menuScrim), 0x73000000);
      expect(t.raw('app-bubble-theirs'), isNull, reason: 'their bubbles are the paper\'s, as before');
      expect(t.raw('app-bubble-rim'), isNull);
    }
    // The accent's check against Ghost's own papers, read from its rules, decides as the fixed near white and near
    // black did, for every colour.
    final light = Tokens.root(sheet, attrs: const {'platform': 'mobile', 'theme': 'light'}).color('app-paper');
    final dark = Tokens.root(sheet, attrs: const {'platform': 'mobile', 'theme': 'dark'}).color('app-paper');
    for (final b in bubbleColors) {
      expect(accentCss(b.id, lightPage: light, darkPage: dark), accentCss(b.id), reason: b.id);
    }
  });

  group('Dial-Up', () {
    for (final b in brightnessesOf(Look.dialup)) {
      test('$b: its chrome, its names and its title bar read', () {
        final t = Tokens.root(sheet, attrs: Look.dialup.attrs(platform: 'mobile', theme: b));
        for (final name in dialupTokens) {
          expect(() => t.color(name), returnsNormally, reason: '--$name under Dial-Up $b');
        }
        expect(isBevelChrome(t), isTrue);
        double on(String a, String b) => _contrast(t.color(a), t.color(b));
        final paper = t.color('app-paper');
        // Names on the transcript's white (or black) page, yours, theirs and each of a room's six.
        for (final n in ['app-name-mine', 'app-name-theirs', for (var i = 1; i <= 6; i++) 'app-name-$i']) {
          expect(_contrast(t.color(n), paper), greaterThanOrEqualTo(4.5), reason: '$n on the page, $b');
        }
        expect(on('app-titlebar-ink', 'app-titlebar'), greaterThanOrEqualTo(4.5), reason: 'the title on its band');
        expect(on('app-on-chrome', 'app-chrome'), greaterThanOrEqualTo(4.5), reason: 'a button\'s words on silver');
        expect(on('app-ink-3', 'app-chrome'), greaterThanOrEqualTo(4.5), reason: 'secondary words (Host lines) on silver');
        expect(on('app-ink-3', 'app-paper'), greaterThanOrEqualTo(4.5), reason: 'secondary words on the page');
        expect(on('app-on-tooltip', 'app-tooltip'), greaterThanOrEqualTo(4.5), reason: 'a hover tip');
        expect(on('app-on-highlight', 'app-highlight'), greaterThanOrEqualTo(4.5), reason: 'a chosen row');
        expect(_contrast(t.danger, paper), greaterThanOrEqualTo(4.5), reason: 'a failure\'s words');
        expect(_contrast(t.unread, paper), greaterThanOrEqualTo(4.5), reason: 'an unread count');
        // Square everything, a pill too; nothing moves; no tracking; and the face is Arimo, with the emoji set behind.
        expect(t.radius('md'), 0);
        expect(t.len('glacier-radius-full'), 0);
        expect(t.duration('glacier-duration-normal').inMilliseconds, 0);
        expect(t.attrs['font'], 'arimo');
        expect(t.families('glacier-font-sans').first, 'Arimo');
        expect(DialupColors.of(t).nameFor('+15551230001'), DialupColors.of(t).nameFor('+1 (555) 123-0001'), reason: 'one colour per person');
      });
    }

    test('no other look is drawn as a chat room', () {
      for (final look in Look.values.where((l) => l != Look.dialup)) {
        for (final b in brightnessesOf(look)) {
          expect(isBevelChrome(Tokens.root(sheet, attrs: look.attrs(platform: 'mobile', theme: b))), isFalse, reason: '${look.name} $b');
        }
      }
      expect(isBevelChrome(Tokens.root(sheet, attrs: const {'platform': 'mobile'})), isFalse);
    });

    testWidgets('its pieces draw', (tester) async {
      _answerChannel();
      final shots = Platform.environment['THEME_SHOTS'] == '1' || autoUpdateGoldenFiles;
      await tester.runAsync(_fonts);
      final sheet = (await tester.runAsync(_loadSheet))!;
      for (final b in brightnessesOf(Look.dialup)) {
        await shootLook(tester, sheet, Look.dialup, b, ThemeScreen('chrome', () => const _DialupPieces()), write: shots);
        expect(find.bySemanticsLabel('Back'), findsWidgets);
      }
    });

    // The window's chrome on a small phone (360 wide, as the design asks it be checked at): the Chat List and its
    // taskbar, a conversation's title bar and composer, a page with a way back. An overflow is an exception, which
    // fails here. Then words in the composer, where Send comes with its word on it.
    testWidgets('its chrome holds at 360 wide', (tester) async {
      _answerChannel();
      final shots = Platform.environment['THEME_SHOTS'] == '1' || autoUpdateGoldenFiles;
      await tester.runAsync(_fonts);
      Inbox.instance = Inbox.of([_telegram()]);
      addTearDown(() => Inbox.instance = null);
      final sheet = (await tester.runAsync(_loadSheet))!;
      const small = Size(360, 740);
      Widget maya() => const ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')]);
      for (final b in brightnessesOf(Look.dialup)) {
        for (final screen in [
          ThemeScreen('conversations-360', () => const AppShell(), size: small),
          ThemeScreen('thread-360', maya, size: small),
          ThemeScreen('compose-360', () => const ComposeScreen(), size: small),
          ThemeScreen('settings-360', () => const SettingsSectionScreen('appearance'), size: small),
        ]) {
          await shootLook(tester, sheet, Look.dialup, b, screen, write: shots);
        }
        expect(find.bySemanticsLabel('Back'), findsWidgets);
        await shootLook(tester, sheet, Look.dialup, b, ThemeScreen('typing-360', maya, size: small), write: false);
        await tester.enterText(find.byType(EditableText).first, 'on my way, ten minutes');
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        expect(find.text('Send'), findsOneWidget);
        if (shots) await _capture(tester, 'dialup-$b-typing-360');
      }
    });
  });

  group('screens in every look', () {
    final shots = Platform.environment['THEME_SHOTS'] == '1' || autoUpdateGoldenFiles;
    setUpAll(_fonts);
    tearDown(() {
      Inbox.instance = null;
      Voice.instance.own = [];
      Voice.instance.clearHangouts();
    });
    for (final look in Look.values) {
      testWidgets(look.name, (tester) async {
        _answerChannel();
        // Telegram signed in and the space kept, for every screen alike: the list shows the same rows in every look.
        Inbox.instance = Inbox.of([_telegram()]);
        Voice.instance.own = [_space().channel];
        Voice.instance.putHangout(_space());
        final sheet = (await tester.runAsync(_loadSheet))!;
        for (final b in brightnessesOf(look)) {
          for (final screen in themeScreens) {
            await shootLook(tester, sheet, look, b, screen, write: shots);
          }
        }
      });
    }
  });
}

/// The brightnesses [look] has.
List<String> brightnessesOf(Look look) => [if (look.light) 'light', if (look.dark) 'dark'];

/// Every colour token the app's Dart reads by name (and the kit's components, the few that matter most), which every
/// look must give.
const colourTokens = [
  'app-ink', 'app-ink-2', 'app-ink-3', 'app-ink-4', //
  'app-paper', 'app-paper-2', 'app-paper-3', 'app-rule', //
  'glacier-bg', 'app-accent', 'app-on-accent', 'app-bubble-mine', 'app-on-bubble-mine', //
  'glacier-surface', 'glacier-text', 'glacier-border-subtle', 'glacier-text-muted', 'glacier-text-subtle', //
  'glacier-segment-track', 'glacier-segment-thumb', 'glacier-selection', 'glacier-overlay', //
  'app-danger', 'app-unread', 'app-chosen', 'app-info', 'app-online', 'app-warn', 'app-pinned', //
  'app-text-selection', 'app-sheet-scrim', 'app-menu-scrim',
];

/// The colours Dial-Up's own pieces read (lib/ui/dialup/), which its rules must give in both halves.
const dialupTokens = [
  'app-chrome', 'app-on-chrome', 'app-bevel-hi', 'app-bevel-lo', 'app-bevel-shadow', 'app-bevel-dark', //
  'app-titlebar', 'app-titlebar-end', 'app-titlebar-ink', 'app-titlebar-inactive', 'app-titlebar-inactive-ink', //
  'app-name-mine', 'app-name-theirs', 'app-name-1', 'app-name-2', 'app-name-3', 'app-name-4', 'app-name-5', 'app-name-6', //
  'app-desktop', 'app-tooltip', 'app-on-tooltip', 'app-highlight', 'app-on-highlight',
];

/// Dial-Up's pieces on one page, for looking at: a window with its title bar, a well, and buttons up, held and off.
class _DialupPieces extends StatelessWidget {
  const _DialupPieces();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = DialupColors.of(t);
    final text = t.textAt(16, color: c.ink);
    // Bold through the face's weight axis: Arimo is variable, and textAt's `wght` would outvote a fontWeight.
    final bold = t.textAt(16, weight: 'bold');
    return ColoredBox(
      color: c.desktop,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 60, 12, 40),
        child: Bevel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitleBar(title: 'Maya Chen', subtitle: 'Telegram · People Here: 4', onClose: () {}),
              const SizedBox(height: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Sunken(
                    padding: const EdgeInsets.all(8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [TextSpan(text: 'Host: ', style: text.copyWith(color: c.inkSoft, fontStyle: FontStyle.italic)), TextSpan(text: '*** You are in "Lobby".', style: text.copyWith(color: c.inkSoft, fontStyle: FontStyle.italic))])),
                      const SizedBox(height: 4),
                      Text.rich(TextSpan(children: [TextSpan(text: 'Maya Chen: ', style: bold.copyWith(color: c.nameTheirs)), TextSpan(text: 'are you coming tonight?', style: text)])),
                      const SizedBox(height: 4),
                      Text.rich(TextSpan(children: [TextSpan(text: 'You: ', style: bold.copyWith(color: c.nameMine)), TextSpan(text: 'on my way, ten minutes', style: text)])),
                      const SizedBox(height: 4),
                      for (var i = 0; i < 6; i++) Text.rich(TextSpan(children: [TextSpan(text: 'Person ${i + 1}: ', style: bold.copyWith(color: c.names[i])), TextSpan(text: 'hello', style: text)])),
                      const SizedBox(height: 8),
                      Container(color: c.highlight, padding: const EdgeInsets.all(4), child: Text('A chosen row', style: text.copyWith(color: c.onHighlight))),
                      const SizedBox(height: 8),
                      Container(color: c.tooltip, padding: const EdgeInsets.all(4), child: Text('A hover tip', style: text.copyWith(color: c.onTooltip, fontSize: 14))),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(children: [
                  RetroButton(onPressed: () {}, label: '+', semanticLabel: 'More'),
                  const SizedBox(width: 6),
                  const Expanded(child: SizedBox(height: 40, child: Sunken(padding: EdgeInsets.symmetric(horizontal: 8)))),
                  const SizedBox(width: 6),
                  RetroButton(onPressed: () {}, label: 'Send', primary: true),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Row(children: [
                  RetroButton(onPressed: () {}, label: 'Held', toggled: true),
                  const SizedBox(width: 6),
                  const RetroButton(onPressed: null, label: 'Off'),
                  const SizedBox(width: 6),
                  TitleBarButton(glyph: TitleGlyph.help, label: 'Details', onPressed: () {}),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A screen drawn in every look by [shootLook]: its [name] in the file's name, how to make it, the window it is drawn
/// in, and anything to put in place before (a network signed in, a space's chat).
class ThemeScreen {
  const ThemeScreen(this.name, this.build, {this.size = phone, this.before});
  final String name;
  final Widget Function() build;
  final Size size;
  final void Function()? before;

  static const phone = Size(412, 892), wide = Size(750, 832);
}

/// The screens every look is drawn on. Add one here and it is drawn in every look and brightness.
final themeScreens = <ThemeScreen>[
  ThemeScreen('conversations', () => const AppShell()),
  ThemeScreen('thread', () => const ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')])),
  ThemeScreen('group', () => ThreadScreen(thread: 2, people: [for (final p in _conversations[1]['people'] as List) Person.from(p as Map)])),
  ThemeScreen('inbox', () => InboxChatScreen(network: _telegram(), chatId: '10')),
  ThemeScreen('settings-appearance', () => const SettingsSectionScreen('appearance')),
  ThemeScreen('space', () => HangoutScreen(channel: _space().channel)),
  ThemeScreen('frame-wide', () => const AppShell(), size: ThemeScreen.wide),
  // A group on a wide screen, and a space where people are coming and going (Dial-Up's Host lines and People Here).
  // The list and a conversation on a small phone (360 wide) in every look, not only Dial-Up's chrome check above.
  ThemeScreen('conversations-narrow', () => const AppShell(), size: const Size(360, 780)),
  ThemeScreen('thread-narrow', () => const ThreadScreen(thread: 1, people: [Person(address: '+15551230001', name: 'Maya Chen')]), size: const Size(360, 780)),
  ThemeScreen('group-narrow', () => ThreadScreen(thread: 2, people: [for (final p in _conversations[1]['people'] as List) Person.from(p as Map)]), size: const Size(360, 780)),
  ThemeScreen('group-wide', () => ThreadScreen(thread: 2, people: [for (final p in _conversations[1]['people'] as List) Person.from(p as Map)]), size: ThemeScreen.wide),
  ThemeScreen('space-room', () => HangoutScreen(channel: _busySpace('phone').channel), before: () => Voice.instance.putHangout(_busySpace('phone'))),
  ThemeScreen('space-room-wide', () => HangoutScreen(channel: _busySpace('wide').channel), size: ThemeScreen.wide, before: () => Voice.instance.putHangout(_busySpace('wide'))),
];

/// Draws [screen] in [look] at [brightness] as the app would, from the person's choices alone (lib/looks.dart's
/// ghostAttrs), and with [write] keeps its picture at `build/themes/<look>-<brightness>-<screen>.png`.
Future<void> shootLook(WidgetTester tester, TokenSheet sheet, Look look, String brightness, ThemeScreen screen, {bool write = true}) async {
  tester.view.physicalSize = screen.size * 2.0;
  tester.view.devicePixelRatio = 2.0;
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
  addTearDown(tester.view.reset);
  screen.before?.call();
  // Sms keeps a part's future, made in the test that first asked for it: in a later test its callbacks wait on that
  // test's fake zone, which has gone, so the group's sticker was blank in every look but the first. Each screen is
  // handed one made here, and the picture is decoded afresh.
  Sms.instance.holdPart(902, Future.value(File('assets/stickers/party/03.webp').readAsBytesSync()));
  PaintingBinding.instance.imageCache.clear();
  final state = AppState()
    ..setTheme(brightness)
    ..setLook(look);
  final name = '${look.name}-$brightness-${screen.name}';
  await tester.pumpWidget(AppScope(
    state: state,
    child: WidgetsApp(
      color: const Color(0xFF4F5BD5),
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
      builder: (context, child) => GlacierTheme(
        sheet: sheet,
        attrs: ghostAttrs(state, 'mobile'),
        typography: ghostTypography('noto'),
        child: InkOverrides(child: GlacierToastProvider(child: child!)),
      ),
      home: KeyedSubtree(key: ValueKey(name), child: screen.build()),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Pictures (a sticker, a face) decode on a real async gap and are drawn on the frame after: one short gap left the
  // group's sticker blank in some looks' pictures, so a few, each followed by a frame.
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 125));
  }
  expect(tester.takeException(), isNull, reason: name);
  if (!write) return;
  final element = find.byType(WidgetsApp).evaluate().single;
  await tester.runAsync(() async {
    final image = await captureImage(element);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('build/themes/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Keeps what is on the screen now at `build/themes/<name>.png`, for a screen changed after [shootLook] drew it.
Future<void> _capture(WidgetTester tester, String name) async {
  final element = find.byType(WidgetsApp).evaluate().single;
  await tester.runAsync(() async {
    final image = await captureImage(element);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('build/themes/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<TokenSheet> _loadSheet() async {
  final sheet = await loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css']);
  installSettingsStyles(sheet);
  return sheet;
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
}

/// The app's fonts (as test/screens_test.dart loads them), so the pictures show words.
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

// --- a made-up phone ------------------------------------------------------------------------------------------------

final _now = DateTime.now();
int _ago({int days = 0, int hours = 0, int minutes = 0}) => _now.subtract(Duration(days: days, hours: hours, minutes: minutes)).millisecondsSinceEpoch;
Map<String, Object?> _p(String address, [String? name]) => {'address': address, 'name': name, 'photo': null};

final _conversations = [
  {'id': 1, 'date': _ago(minutes: 4), 'people': [_p('+15551230001', 'Maya Chen')], 'snippet': 'Sounds good, see you at 7! Bring the projector cable if you still have it', 'unread': true, 'error': false, 'archived': false},
  {'id': 2, 'date': _ago(minutes: 52), 'people': [_p('+15551230002', 'Jordan Park'), _p('+15551230003', 'Sam Rivera'), _p('+15551230004', 'Alex Kim')], 'snippet': 'Picture', 'unread': true, 'error': false, 'archived': false},
  {'id': 3, 'date': _ago(hours: 5), 'people': [_p('+15551230005', 'Dad')], 'snippet': 'Call me when you land', 'unread': false, 'error': false, 'archived': false, 'pinned': true},
  {'id': 4, 'date': _ago(days: 1, hours: 2), 'people': [_p('28849')], 'snippet': 'Your verification code is 482913. Don\'t share it with anyone.', 'unread': false, 'error': false, 'archived': false, 'muted': true},
  {'id': 5, 'date': _ago(days: 3), 'people': [_p('+15551230006', 'Priya Natarajan')], 'snippet': 'haha yes 😂', 'unread': false, 'error': true, 'archived': false},
  {'id': 6, 'date': _ago(days: 12), 'people': [_p('+15551230007')], 'snippet': 'Your package was delivered', 'unread': false, 'error': false, 'archived': false, 'draft': 'Thanks, I\'ll pick it up tom'},
  {'id': 7, 'date': _ago(days: 40), 'people': [_p('+15551230008', 'Old Thread')], 'snippet': 'ok', 'unread': false, 'error': false, 'archived': true},
];

List<Map<String, Object?>> _messages(int thread) => switch (thread) {
      2 => [
          {'id': 16, 'kind': 'mms', 'address': '', 'body': 'Trailhead at 9', 'date': _ago(minutes: 47), 'outgoing': true, 'state': 'failed', 'read': true, 'parts': [], 'why': 'mobile data is off. Picture messages need it, even on Wi-Fi'},
          {'id': 15, 'kind': 'mms', 'address': '', 'body': '', 'date': _ago(minutes: 48), 'outgoing': true, 'state': 'sent', 'read': true, 'parts': [{'id': 902, 'type': 'image/png', 'name': 'ghost-sticker-party-03.png'}]},
          {'id': 13, 'kind': 'mms', 'address': '+15551230004', 'body': '👍 to "Hike this weekend?"', 'date': _ago(minutes: 50), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
          {'id': 11, 'kind': 'mms', 'address': '+15551230003', 'body': 'Look at this view 🏔️', 'date': _ago(minutes: 52), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
          {'id': 10, 'kind': 'mms', 'address': '', 'body': 'Saturday works for me', 'date': _ago(hours: 1), 'outgoing': true, 'state': 'read', 'read': true, 'parts': []},
          {'id': 9, 'kind': 'mms', 'address': '+15551230004', 'body': 'Same, any time after noon', 'date': _ago(hours: 1, minutes: 5), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
          {'id': 8, 'kind': 'mms', 'address': '+15551230002', 'body': 'Hike this weekend?', 'date': _ago(hours: 1, minutes: 8), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
          {'id': 7, 'kind': 'mms', 'address': '+15551230002', 'body': 'Who\'s around Saturday', 'date': _ago(hours: 1, minutes: 9), 'outgoing': false, 'state': 'received', 'read': true, 'parts': []},
        ],
      _ => [
          {'id': 10, 'kind': 'sms', 'address': '+15551230001', 'body': '🎉🍿', 'date': _ago(minutes: 1), 'outgoing': false, 'state': 'received', 'read': true},
          {'id': 6, 'kind': 'sms', 'address': '+15551230001', 'body': 'Sounds good, see you at 7! Bring the projector cable if you still have it', 'date': _ago(minutes: 4), 'outgoing': false, 'state': 'received', 'read': true},
          {'id': 8, 'kind': 'sms', 'address': '+15551230001', 'body': '❤️ to “Dinner at mine first?”', 'date': _ago(minutes: 20), 'outgoing': false, 'state': 'received', 'read': true},
          {'id': 5, 'kind': 'sms', 'address': '+15551230001', 'body': 'Dinner at mine first?', 'date': _ago(minutes: 30), 'outgoing': true, 'state': 'delivered', 'read': true},
          {'id': 4, 'kind': 'sms', 'address': '+15551230001', 'body': 'Movie night is still on for tonight right?', 'date': _ago(minutes: 31), 'outgoing': true, 'state': 'delivered', 'read': true},
          {'id': 3, 'kind': 'sms', 'address': '+15551230001', 'body': 'Here\'s the link https://example.com/tickets', 'date': _ago(days: 1, hours: 1), 'outgoing': false, 'state': 'received', 'read': true},
          {'id': 2, 'kind': 'sms', 'address': '+15551230001', 'body': 'Did you get the tickets?', 'date': _ago(days: 1, hours: 1, minutes: 2), 'outgoing': true, 'state': 'sent', 'read': true},
          {'id': 1, 'kind': 'sms', 'address': '+15551230001', 'body': 'Hey! Long time 👋', 'date': _ago(days: 1, hours: 3), 'outgoing': false, 'state': 'received', 'read': true},
        ],
    };

void _answerChannel() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  messenger.setMockMethodCallHandler(const MethodChannel('ghost/voicefx'), (call) async => null);
  messenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async {
    final args = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'status':
        return const {'isDefault': true, 'contacts': true, 'notifications': true, 'phone': true};
      case 'conversations':
        return _conversations;
      case 'conversationsPage':
        if (args['archived'] == true) return {'items': _conversations.where((c) => c['archived'] == true).toList(), 'next': null};
        return {'items': _conversations, 'next': null};
      case 'conversation':
        return _conversations.where((c) => c['id'] == args['thread']).firstOrNull;
      case 'archivedCount':
        return _conversations.where((c) => c['archived'] == true).length;
      case 'messages':
        return _messages((args['thread'] as num).toInt());
      case 'people':
        return _conversations.firstWhere((c) => c['id'] == args['thread'])['people'];
      case 'update':
        return {'phase': 'idle', 'current': '0.8.2', 'auto': true, 'canInstall': true, 'source': 'https://gogho.st'};
      case 'ownNumber':
        return '+15551239999';
      case 'contact':
        return _p(args['address'] as String);
      case 'e2e':
        return {'address': args['address'], 'state': 'none', 'verified': false, 'changed': false};
      case 'ghostPeers':
        return false;
      case 'keyboardHere':
        return true;
      case 'netSmsAvailable':
        return false;
      case 'netSmsDrain':
        return const <Object>[];
      case 'prefs':
        return <String, String>{};
      case 'part':
        return (args['id'] as num).toInt() == 902 ? File('assets/stickers/party/03.webp').readAsBytesSync() : null;
      default:
        return null;
    }
  });
}

/// A Telegram signed in, held in memory, with one chat (as test/inbox_screens_test.dart's).
InboxNetwork _telegram() => _tg ??= _FakeNetwork('telegram', 'Telegram', [
      InboxChat(network: 'telegram', id: '10', title: 'Jo Park', date: _now.subtract(const Duration(minutes: 2)), snippet: 'are you coming tonight?', unread: 2),
    ], {
      '10': [
        InboxMessage(id: '1', text: 'hey! long time', date: _now.subtract(const Duration(minutes: 30)), mine: false),
        InboxMessage(id: '2', text: 'I know, how have you been?', date: _now.subtract(const Duration(minutes: 28)), mine: true),
        InboxMessage(id: '3', text: 'good! there\'s a thing at the park later', date: _now.subtract(const Duration(minutes: 3)), mine: false),
        InboxMessage(id: '4', text: 'are you coming tonight?', date: _now.subtract(const Duration(minutes: 2)), mine: false),
        InboxMessage(id: '5', text: 'yes! save me a spot', date: _now.subtract(const Duration(minutes: 1)), mine: true),
      ],
    });
InboxNetwork? _tg;

class _FakeNetwork extends InboxNetwork {
  _FakeNetwork(this.id, this.name, this._chats, this._messages);
  @override
  final String id;
  @override
  final String name;
  final List<InboxChat> _chats;
  final Map<String, List<InboxMessage>> _messages;

  @override
  InboxState get state => InboxState.ready;
  @override
  String? get error => null;
  @override
  String? get account => '@matt';
  @override
  List<InboxChat> get chats => _chats;
  @override
  List<InboxMessage> messagesOf(String chatId) => _messages[chatId] ?? const [];
  @override
  Future<void> load(String chatId, {bool older = false}) async {}
  @override
  Future<void> send(String chatId, String text) async {}
  @override
  Future<void> markRead(String chatId) async {}
  @override
  set watching(String? chatId) {}
  @override
  Future<void> start(AppState app) async {}
  @override
  Future<void> signOut() async {}
}

/// A space's chat with a few messages, this device its owner, Maya a moderator (as test/support/space_call_harness's).
HangoutRoom _space() => _room ??= () {
      final keys = NetKeys.generate();
      final channel = VoiceChannel.make('Friday hang', owner: NetCrypto.hex(keys.public));
      final store = MemoryHangoutStore();
      final at = DateTime(2026, 11, 16, 19, 40).millisecondsSinceEpoch;
      store.keepMessages(channel.chatRoom, [
        HangoutMessage(id: '1', from: 'a', name: 'Maya Chen', text: 'Starting the movie in 10, hop in', at: at),
        HangoutMessage(id: '2', from: 'a', name: 'Maya Chen', text: 'Bring snacks 🍿', at: at + 20000),
        HangoutMessage(id: '3', from: 'c', name: 'Riley', text: 'On my way!', at: at + 60000),
        HangoutMessage(id: '4', from: keys.id, name: 'Me', text: 'Saving you a seat', at: at + 90000),
      ]);
      store.keepRoster(channel.chatRoom, Roster.first(channel.owner).next(assigned: {'a': Role.moderator}));
      return HangoutRoom(channel: channel, route: _NoRoute(keys.id), name: 'Me', signer: KeysSigner(keys), store: store);
    }();
HangoutRoom? _room;

/// A space with people in it: Maya (in voice) and Dana there on joining, then Riley comes in and Dana leaves, each
/// saying their name as the app does ('hi', sealed with the space's key). One per [screen], each joined afresh.
HangoutRoom _busySpace(String screen) => _busy[screen] ??= () {
      final keys = NetKeys.generate();
      final channel = VoiceChannel.make('Saturday hike', owner: NetCrypto.hex(keys.public));
      final store = MemoryHangoutStore();
      final at = _now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch;
      store.keepMessages(channel.chatRoom, [
        HangoutMessage(id: '1', from: 'a', name: 'Maya Chen', text: 'Meet at the north trailhead, 9 sharp', at: at),
        HangoutMessage(id: '2', from: 'b', name: 'Dana', text: 'I can drive two people', at: at + 60000),
        HangoutMessage(id: '3', from: keys.id, name: 'Me', text: 'Count me in for a seat, I\'ll bring coffee for everyone who wants it', at: at + 120000),
      ]);
      return HangoutRoom(channel: channel, route: _BusyRoute(keys.id, channel), name: 'Me', signer: KeysSigner(keys), store: store);
    }();
final _busy = <String, HangoutRoom>{};

class _BusyRoute extends _NoRoute {
  _BusyRoute(super.me, this.channel);
  final VoiceChannel channel;
  final _events = StreamController<RoomEvent>.broadcast();
  final _packets = StreamController<({String room, String from, Uint8List bytes})>.broadcast();

  void _hi(String from, String name, {bool voice = false}) =>
      _packets.add((room: channel.chatRoom, from: from, bytes: NetCrypto.seal(channel.key, utf8.encode(jsonEncode({'t': 'hi', 'n': name, 'a': voice})))));

  @override
  Future<List<String>> join(String room, String token) async {
    Timer(const Duration(milliseconds: 1), () {
      _hi('a', 'Maya Chen', voice: true);
      _hi('b', 'Dana');
    });
    Timer(const Duration(milliseconds: 60), () => _events.add(RoomEvent(channel.chatRoom, came: 'c')));
    Timer(const Duration(milliseconds: 110), () => _hi('c', 'Riley'));
    Timer(const Duration(milliseconds: 160), () => _events.add(RoomEvent(channel.chatRoom, went: 'b')));
    return const ['a', 'b'];
  }

  @override
  Stream<RoomEvent> get events => _events.stream;
  @override
  Stream<({String room, String from, Uint8List bytes})> get packets => _packets.stream;
}

class _NoRoute implements VoiceRoute {
  _NoRoute(this.me);
  @override
  final String me;
  @override
  Future<List<String>> join(String room, String token) async => const [];
  @override
  void leave(String room) {}
  @override
  void send(String room, Uint8List bytes) {}
  @override
  void look(String room, String token) {}
  @override
  void unlook(String room) {}
  @override
  Stream<RoomEvent> get events => const Stream.empty();
  @override
  Stream<({String room, String from, Uint8List bytes})> get packets => const Stream.empty();
  @override
  Stream<({String room, List<String> members})> get looks => const Stream.empty();
}
