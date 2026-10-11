import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/widgets.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/guide_models.dart';
import 'package:ghost_md/guide/pages/model.dart';
import 'package:ghost_md/guide/pages/parts.dart';
import 'package:ghost_md/guide/pages/start.dart';
import 'package:ghost_md/guide/pages/theme.dart';
import 'package:ghost_md/guide/pages/welcome.dart';
import 'package:ghost_md/settings/panes/ai_pane.dart' show models;
import 'package:glacier/glacier.dart';

import 'support.dart';

/// `guide/pages/Model.test.tsx`, `Start.test.tsx` and `Theme.test.tsx`, case for case, each page drawn alone.
void main() {
  setUpAll(loadAppFonts);

  Future<void> show(WidgetTester tester, Widget page, {Preferences prefs = const Preferences(theme: 'light')}) =>
      pumpGuide(tester, SingleChildScrollView(padding: const EdgeInsets.all(20), child: page), prefs: prefs);

  /// A row's words as the page's `textContent` had them: the swatch, the label, the hint.
  String wordsOf(WidgetTester tester, Finder row) => tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text))).map((text) => text.data ?? '').join();
  List<String> rowWords(WidgetTester tester) => [for (var i = 0; i < find.byType(GuideChoice).evaluate().length; i++) wordsOf(tester, find.byType(GuideChoice).at(i))];
  Finder row(String label) => find.byWidgetPredicate((w) => w is GuideChoice && w.label == label);
  List<String> checked(WidgetTester tester) => [for (final choice in tester.widgetList<GuideChoice>(find.byType(GuideChoice))) if (choice.on) choice.label];

  /// Whether a row is printed in reverse (`app-inverse`): its own tokens say the reversed paper.
  bool reversed(WidgetTester tester, String label) => GlacierTheme.of(tester.element(find.descendant(of: row(label), matching: find.text(label)))).classes.contains('app-inverse');

  group('the guide’s model page', () {
    late ValueNotifier<Preferences> store;
    late FakeGuideModels phone;
    setUp(() {
      store = ValueNotifier(const Preferences(theme: 'light', formatModel: 'qwen3.5-4b'));
      phone = FakeGuideModels();
    });
    tearDown(() => store.dispose());

    /// The line under the rows, about the chosen model's download: its words, the button's among them.
    String? fine(WidgetTester tester) {
      final line = find.byWidgetPredicate((w) => w is Text && w.textSpan != null && w.textSpan!.toPlainText().isNotEmpty && find.ancestor(of: find.byWidget(w), matching: find.byType(GuideChoice)).evaluate().isEmpty && find.ancestor(of: find.byWidget(w), matching: find.byType(GuideWord)).evaluate().isEmpty);
      if (line.evaluate().isEmpty) return null;
      final words = tester.widget<Text>(line).textSpan!.toPlainText(includePlaceholders: false);
      return '$words${find.text('get it now').evaluate().isEmpty ? '' : 'get it now'}';
    }

    testWidgets('has a row per model with its size, and sets the preference the moment one is tapped', (tester) async {
      await show(tester, GuideModel(phone: phone, store: store));
      expect(find.byType(GuideChoice), findsNWidgets(models.length));
      expect(wordsOf(tester, row('Qwen3.5 9B')), '5.7 GBQwen3.5 9BThe most careful, and the slowest. Wants 12 GB of memory.');
      expect(checked(tester), ['Qwen3.5 4B']);
      await tester.tap(row('Qwen3.5 9B'));
      await tester.pump();
      expect(store.value.formatModel, 'qwen3.5-9b');
      expect(checked(tester), ['Qwen3.5 9B']);
      expect(reversed(tester, 'Qwen3.5 9B'), isTrue);
      expect(reversed(tester, 'Qwen3.5 4B'), isFalse);
      // Nothing is fetched for a tap: the bytes wait to be asked for.
      expect(phone.fetched, isEmpty);
      await away(tester);
    });

    testWidgets('offers to get the chosen model now when it is not on the phone', (tester) async {
      await show(tester, GuideModel(phone: phone, store: store));
      expect(fine(tester), 'Qwen3.5 4B is not on the phone yet. Get it later in Settings › Recording, or get it now');
      await tester.tap(find.text('get it now'));
      expect(phone.fetched, ['qwen3.5-4b']);
      await away(tester);
    });

    testWidgets('offers nothing to get on an iPhone, which runs no model and has no Recording page to point at', (tester) async {
      // An iPhone, or a build with no engine: either way the phone's models are not offered.
      await show(tester, GuideModel(phone: NoGuideModels(), store: store));
      expect(find.byType(GuideChoice), findsNWidgets(models.length));
      expect(fine(tester), isNull);
      expect(find.text('get it now'), findsNothing);
      await away(tester);
    });

    testWidgets('says how far a download has got, and that the model is here once it is', (tester) async {
      phone.download = const GuideDownload(id: 'qwen3.5-4b', received: 1000000000, total: 2740937888);
      await show(tester, GuideModel(phone: phone, store: store));
      expect(fine(tester), 'Getting Qwen3.5 4B, 1.0 GB of 2.7 GB. Keep Ghost.md open.');
      expect(find.text('get it now'), findsNothing);
      // The download lands: the page follows the phone.
      phone
        ..download = null
        ..here = {'qwen3.5-4b'}
        ..told();
      await tester.pump();
      expect(fine(tester), 'Qwen3.5 4B is on the phone.');
      expect(find.text('get it now'), findsNothing);
      await away(tester);
    });

    testWidgets('says what went wrong with a download, and still offers to try again', (tester) async {
      phone.problem = 'Not enough space on the phone.';
      await show(tester, GuideModel(phone: phone, store: store));
      expect(fine(tester), 'Not enough space on the phone.get it now');
      expect(find.text('get it now'), findsOneWidget);
      await away(tester);
    });

    testWidgets('says nothing of downloads in a browser, where a row still sets the preference', (tester) async {
      phone.offered = false;
      await show(tester, GuideModel(phone: phone, store: store));
      expect(fine(tester), isNull);
      await tester.tap(row('Gemma 4 E4B'));
      expect(store.value.formatModel, 'gemma-4-e4b');
      await away(tester);
    });
  });

  group('the guide’s last page', () {
    testWidgets('offers the Academy for the rest, and says the home page offers it too', (tester) async {
      var academy = 0;
      await show(tester, GuideStart(onAcademy: () => academy += 1));
      final words = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? '').join('\n');
      expect(words, contains('Learn it, or just start.'));
      expect(words, contains('find it on the home page'));
      await tester.tap(find.widgetWithText(AppPill, 'Take the Ghost.md Academy'));
      expect(academy, 1);
      // No side key, no habits: those pages are gone, and nothing here is a step to follow.
      expect(words, isNot(matches(RegExp('side key|habit', caseSensitive: false))));
      await away(tester);
    });
  });

  group('the guide’s theme page', () {
    testWidgets('offers Dark, Light and the phone’s own, each saying what it looks like', (tester) async {
      await show(tester, const GuideTheme(), prefs: const Preferences(theme: 'dark'));
      expect(rowWords(tester), ['AaDarkLight words on black. Easier on the eyes at night.', 'AaLightDark words on white, like paper.', 'AaMatch the phoneFollows your phone’s dark mode.']);
      await away(tester);
    });

    testWidgets('applies a row the moment it is tapped, and marks it as the one chosen', (tester) async {
      // The app's own preferences, so the page under the row is seen to change with it.
      await show(tester, const GuideTheme(), prefs: const Preferences(theme: 'dark'));
      String themeNow() => GlacierTheme.of(tester.element(find.byType(GuideTheme))).attrs['theme'] ?? '';
      expect(checked(tester), ['Dark']);
      expect(themeNow(), 'dark');
      await tester.tap(row('Light'));
      await tester.pump();
      await tester.pump();
      expect(preferences.value.theme, 'light');
      expect(themeNow(), 'light');
      expect(checked(tester), ['Light']);
      expect(reversed(tester, 'Light'), isTrue);
      expect(reversed(tester, 'Dark'), isFalse);
      // Another tap is another choice, kept at once: there is nothing to confirm and nothing puts the last one back.
      await tester.tap(row('Dark'));
      await tester.pump();
      expect(preferences.value.theme, 'dark');
      expect(checked(tester), ['Dark']);
      // And it is the preference from now on.
      await tester.tap(row('Match the phone'));
      await tester.pump();
      expect(preferences.value.theme, 'system');
      await away(tester);
    });
  });

  group('the guide’s first page', () {
    // Not cases of the page's tests (it has none for Welcome): what it promises, by whether the phone records.
    testWidgets('promises a voice where the phone records, and lists where it does not', (tester) async {
      expect([for (final point in welcomePoints(recordsVoice: true)) point.label], ['Say it or type it', 'Plain Markdown files', 'The same on every device']);
      expect(welcomePoints(recordsVoice: false).first.label, 'Lists, to-dos and boards');
      await show(tester, const GuideWelcome(recordsVoice: false));
      expect(find.textContaining('Notes you type. Plain Markdown'), findsOneWidget);
      await away(tester);
    });

    test('pops each promise in after the one before, and wiggles its icon now and then', () {
      expect(promiseInAt(419, 0), 0);
      expect(promiseInAt(420 + 420, 0), 1);
      expect(promiseInAt(540, 1), 0);
      expect(wiggleAt(1000, 0), 0);
      // 89% of the way round, 1.2 s in: the first lean.
      expect(wiggleAt(1200 + 3200 * 0.89, 0), closeTo(-14, 1e-6));
      expect(wiggleAt(1600 + 3200 * 0.92, 1), closeTo(12, 1e-6));
      expect(wiggleAt(1200 + 3200 * 0.5, 0), 0);
    });
  });
}
