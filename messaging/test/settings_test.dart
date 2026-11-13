import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/backgrounds.dart';
import 'package:ghost_messaging/kit/settings_css.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:ghost_messaging/ui/settings_panes.dart';
import 'package:glacier/glacier.dart';

/// Settings without a screen: what Updates says, what the search finds, and the chat background's choices.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Android is not there: every call is answered with nothing, as a phone that knows nothing would.
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async => null));

  group('updates', () {
    UpdateState failed(String error) => UpdateState(phase: 'failed', error: error, source: 'https://ghost-sms.com');

    test('a site that is not there to ask is said plainly, not as Java said it', () {
      const said = 'ghost-sms.com isn\'t serving updates yet.';
      // What Updater.kt says from 0.4.0, and what a TLS, DNS, connection or 404 failure reads as without it.
      for (final error in [
        'notServing',
        'java.security.cert.CertPathValidatorException: Trust anchor for certification path not found.',
        'Handshake failed',
        'Read error: ssl=0x7b1c: Failure in SSL library, usually a protocol error',
        'Unable to resolve host "ghost-sms.com": No address associated with hostname',
        'Failed to connect to ghost-sms.com/149.248.47.151:443',
        'The update server answered 404.',
      ]) {
        expect(updateLine(failed(error)), said, reason: error);
        expect(updateSummary(failed(error)), 'ghost-sms.com isn\'t serving updates yet', reason: error);
      }
    });

    test('other failures keep their own words', () {
      expect(updateLine(failed('offline')), startsWith('This phone is offline.'));
      expect(updateLine(failed('The download does not match the release\'s hash.')), 'Couldn\'t update: The download does not match the release\'s hash.');
      expect(updateLine(failed('The update server answered 500.')), 'Couldn\'t update: The update server answered 500.');
      expect(updateLine(failed('The download is not signed by this app\'s key.')), contains('Install the release from ghost-sms.com once'));
      expect(updateLine(const UpdateState(phase: 'upToDate')), 'Up to date.');
    });
  });

  group('search', () {
    test('every word typed starts a word of what is found, in any order', () {
      expect(settingsMatch('read rec', 'Read receipts On picture and group messages.'), isTrue);
      expect(settingsMatch('receipts read', 'Read receipts'), isTrue);
      expect(settingsMatch('eceipts', 'Read receipts'), isFalse);
      expect(settingsMatch('', 'Read receipts'), isFalse);
    });

    testWidgets('finds sections by name and settings on their pages', (tester) async {
      // The pages are read under the app's theme, as Settings reads them.
      final sheet = (await tester.runAsync(() => loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css'])))!;
      installSettingsStyles(sheet);
      late BuildContext context;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: GlacierTheme(
          sheet: sheet,
          attrs: const {'platform': 'mobile', 'theme': 'light'},
          child: Builder(builder: (c) {
            context = c;
            return const SizedBox.shrink();
          }),
        ),
      ));
      final model = SettingsModel(AppState());
      addTearDown(model.dispose);
      List<String> find(String q) => [for (final h in searchSettings(context, model, settingsSections, q)) h.setting == null ? h.section.label : '${h.section.label} › ${h.setting}'];

      expect(find('encryption').first, 'Encryption');
      expect(find('enter'), contains('Messages › Enter sends'));
      expect(find('preview'), contains('Notifications › Message previews'));
      expect(find('new key'), contains('Encryption › New key for this phone'));
      expect(find('text size'), contains('Appearance › Text size'));
      expect(find('confetti'), contains('Effects › Confetti'));
      expect(find('background').first, 'Chat background');
      expect(find('keyboard codes'), contains('Ghost Keyboard › Offer sign-in codes to Ghost Keyboard'));
      expect(find('zzzz'), isEmpty);
    });

    test('every section has an id of its own, and the ones the handoff asked for are there', () {
      final ids = [for (final s in settingsSections) s.id];
      expect(ids.toSet().length, ids.length);
      expect(ids, containsAll(['appearance', 'emoji', 'effects', 'messages', 'receipts', 'notifications', 'encryption', 'blocked', 'archived', 'number', 'android', 'keyboard', 'updates', 'about']));
    });
  });

  group('chat backgrounds', () {
    test('a choice is read back as it was kept', () {
      for (final raw in ['none', 'wallpaper', 'preset:dusk', 'color:#DCE8FB', 'image:/data/user/0/app/files/backgrounds/all-1.jpg', 'wash:#EEF2F7,#DCE5F0,#0F141B,#172230']) {
        expect(ChatBackground.parse(raw).raw, raw);
      }
      // What is not one of them is none, never an error: a preset since removed, a colour mistyped.
      for (final raw in [null, '', 'preset:gone', 'color:blue', 'image:', 'nonsense', 'wash:#EEF2F7,#DCE5F0', 'wash:a,b,c,d']) {
        expect(ChatBackground.parse(raw).isNone, isTrue, reason: '$raw');
      }
    });

    test('a conversation wears its own, else every chat\'s', () {
      final app = AppState();
      expect(ChatBackground.of(app, 4).isNone, isTrue);
      app.set('chat_bg', 'preset:mint');
      expect(ChatBackground.of(app, 4).raw, 'preset:mint');
      expect(ChatBackground.own(app, 4), isNull);
      app.set(ChatBackground.threadKey(4), 'color:#1B2433');
      expect(ChatBackground.of(app, 4).raw, 'color:#1B2433');
      expect(ChatBackground.of(app, 5).raw, 'preset:mint');
      // "Same as every chat" is kept as nothing.
      app.set(ChatBackground.threadKey(4), '');
      expect(ChatBackground.of(app, 4).raw, 'preset:mint');
      // None, chosen for one conversation, is its own: it does not fall back to every chat's.
      app.set(ChatBackground.threadKey(4), 'none');
      expect(ChatBackground.of(app, 4).isNone, isTrue);
    });

    test('what goes to the other phone is what it can wear', () {
      // Someone else's "Match my wallpaper" arrives as its four colours: light's two, then dark's.
      final wash = ChatBackground.parse('wash:#EEF2F7,#DCE5F0,#0F141B,#172230');
      expect(wash.colors(false), (const Color(0xFFEEF2F7), const Color(0xFFDCE5F0)));
      expect(wash.colors(true), (const Color(0xFF0F141B), const Color(0xFF172230)));
      expect(wash.label, 'Shared colours');
      // Everything but the wallpaper's colours goes as it is; those go as a wash, and not at all from a phone that
      // has none (before Android 12, and here).
      for (final raw in ['none', 'preset:dusk', 'color:#DCE8FB', 'image:/x.jpg']) {
        expect(ChatBackground.parse(raw).shareable?.raw, raw);
      }
      PhonePalette.current = null;
      expect(ChatBackground.wallpaper.shareable, isNull);
    });

    test('only a picture or a colour of the person\'s puts small words on a pill', () {
      expect(ChatBackground.parse('image:/x.jpg').busy, isTrue);
      expect(ChatBackground.parse('color:#123456').busy, isTrue);
      expect(ChatBackground.parse('preset:dusk').busy, isFalse);
      expect(ChatBackground.wallpaper.busy, isFalse);
      expect(ChatBackground.none.busy, isFalse);
    });

    test('a bubble\'s words read on its colour, and a conversation\'s own colour comes first', () {
      // White and grey are among them, as asked.
      expect(bubbleColors.map((b) => b.id), containsAll(['ghost', 'ink', 'white', 'gray']));
      expect(bubbleColors.map((b) => b.id).toSet().length, bubbleColors.length);
      for (final b in bubbleColors.where((b) => b.color != null)) {
        final ink = inkOn(b.color!);
        final contrast = (b.color!.computeLuminance() + 0.05) / (ink.computeLuminance() + 0.05);
        expect(contrast > 3 || 1 / contrast > 3, isTrue, reason: '${b.name}: ${contrast.toStringAsFixed(2)}');
      }
      expect(inkOn(const Color(0xFFFFFFFF)), const Color(0xFF16181D));
      expect(inkOn(const Color(0xFF3A3D42)), const Color(0xFFFFFFFF));
      // A white bubble on a white page needs a line round it; a blue one does not.
      expect(bubbleNeedsRim(const Color(0xFFFFFFFF), const Color(0xFFFDFDFD)), isTrue);
      expect(bubbleNeedsRim(const Color(0xFF0A84FF), const Color(0xFFFDFDFD)), isFalse);
      final app = AppState();
      expect(bubbleChoice(app, 4), 'ghost');
      app.setBubble('gray');
      expect(bubbleChoice(app, 4), 'gray');
      app.set('bubble_4', 'white');
      expect(bubbleChoice(app, 4), 'white');
      expect(bubbleChoice(app, 5), 'gray');
      // "Same as everywhere" is kept as nothing.
      app.set('bubble_4', '');
      expect(bubbleChoice(app, 4), 'gray');
    });

    test('every wash has a pale light pair and a deep dark pair', () {
      double light(Color c) => c.computeLuminance();
      for (final p in chatPresets) {
        expect(light(p.lightTop), greaterThan(0.75), reason: p.name);
        expect(light(p.lightBottom), greaterThan(0.7), reason: p.name);
        expect(light(p.darkTop), lessThan(0.03), reason: p.name);
        expect(light(p.darkBottom), lessThan(0.04), reason: p.name);
      }
    });
  });
}
