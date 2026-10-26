// Pictures of the Market's themes and faces (Matt, 2026-10-26: "Make the plugins a dedicated "Market" section in the
// app, include some more themes, fonts ..."), for the eye: written only by `flutter test --update-goldens
// test/settings/market_looks_shots_test.dart`, into build/feature-shots/market-looks/ (not committed). The theme cards
// and the type cards, light and dark, on a phone and a wide window; and Appearance worn in each new theme, with the
// new faces chosen, so each face is seen drawn by the page's own tokens as well as by its card.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/settings/theme_cards.dart';
import 'package:ghost_md/settings/typeface_cards.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

const Size _wide = Size(760, 1300);
const Size _phoneTall = Size(390, 1900);

Future<void> _picture(WidgetTester tester, String name) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/market-looks/$name.png'));
}

/// [child] on the page's paper, padded as a card's insides are.
Widget _onPaper(Widget child) => Builder(
      builder: (context) => ColoredBox(
        color: context.tokens.color('app-paper'),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 52, 16, 16), child: child),
      ),
    );

Widget _type() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TypefaceCards(label: 'Note font', kind: TypefaceKind.note, faces: typefaces, value: 'lora', onValueChange: (_) {}),
        const SizedBox(height: 24),
        TypefaceCards(label: 'Interface font', kind: TypefaceKind.interface, faces: interfaceFaces, value: 'atkinson', onValueChange: (_) {}),
      ],
    );

void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    for (final (size, where) in [(_wide, 'wide'), (_phoneTall, 'phone')]) {
      testWidgets('the theme cards, $where, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        await pumpSettings(tester, _onPaper(ThemeCards(value: theme == 'light' ? 'sakura' : 'tide', onValueChange: (_) {})), size: size, prefs: Preferences(theme: theme));
        await _picture(tester, 'themes-$where-$theme');
        await endSettings(tester);
      });

      testWidgets('the type cards, $where, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        await pumpSettings(tester, _onPaper(_type()), size: size, prefs: Preferences(theme: theme));
        await _picture(tester, 'type-$where-$theme');
        await endSettings(tester);
      });
    }
  }

  // Each new theme worn, with one of the new faces for the note and Atkinson for the interface where it fits.
  for (final (theme, note, ui) in [('sakura', 'lora', 'atkinson'), ('meadow', 'atkinson', 'atkinson'), ('tide', 'jetbrains', 'inter'), ('dusk', 'lora', 'atkinson')]) {
    testWidgets('Appearance in $theme', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      await pumpSettings(
        tester,
        SettingsSheet(open: true, onClose: () {}, toPage: const SettingsTarget('theme', nonce: 1)),
        size: const Size(390, 844),
        prefs: Preferences(theme: theme, accent: themePresets[theme]!.accent, noteFace: note, typeface: ui, experience: 'advanced', experienceChosen: true),
      );
      await _picture(tester, 'worn-$theme');
      await endSettings(tester);
    });
  }
}
