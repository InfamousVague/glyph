/// Light or dark, asked up front, because in an app that is almost all type the ground behind the words is most of
/// the look. A port of `src/app/guide/pages/Theme.tsx`, with the `.swatch[data-swatch]` rules of `Guide.module.css`.
///
/// Each choice applies the moment it is tapped, the guide itself changing colour under the thumb, so the person
/// decides by seeing, not by imagining. Changeable any time in Settings. Nothing puts the old theme back if the
/// person skips on: the choice is the preference, and there is no preview to undo. The page stays still until a
/// choice is tapped.
///
/// What differs: the preferences are a store the page is given ([preferences] unless a test brings its own), where
/// the page's are a module. Settings' own theme cards (lib/settings/theme_cards.dart) draw a small scene of each
/// theme and the named ones too; this page keeps the web's three rows and their "Aa".
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/preferences.dart';
import 'parts.dart';

/// `THEME_CHOICES`.
const List<({String value, String label, String hint})> themeChoices = [
  (value: 'dark', label: 'Dark', hint: 'Light words on black. Easier on the eyes at night.'),
  (value: 'light', label: 'Light', hint: 'Dark words on white, like paper.'),
  (value: 'system', label: 'Match the phone', hint: 'Follows your phone’s dark mode.'),
];

class GuideTheme extends StatelessWidget {
  const GuideTheme({super.key, this.store});

  /// The preferences to read and set; the app's own when null.
  final ValueNotifier<Preferences>? store;

  @override
  Widget build(BuildContext context) {
    final prefs = store ?? preferences;
    return ValueListenableBuilder<Preferences>(
      valueListenable: prefs,
      builder: (context, now, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const GuideTitle('Light or dark?'),
          const GuideLead('Pick one to see it. You can change it later in Settings.'),
          GuideChoices(
            label: 'Theme',
            children: [
              for (final choice in themeChoices)
                GuideChoice(
                  label: choice.label,
                  hint: choice.hint,
                  on: now.theme == choice.value,
                  onPick: () => prefs.value = prefs.value.copyWith(theme: choice.value),
                  swatch: (context) => _swatch(context.tokens, choice.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The swatch is the choice, shown: literal colours rather than tokens, the ink theme's own paper and ink, because
/// each one has to look like its theme whichever theme is on screen around it.
Widget _swatch(Tokens t, String theme) {
  Color grey(double lightness) => t.colorOf('oklch($lightness 0 0)');
  return switch (theme) {
    'dark' => GuideSwatch(text: 'Aa', style: guideSwatchStyle(t, grey(0.965)), color: grey(0.11), border: grey(0.34)),
    'light' => GuideSwatch(text: 'Aa', style: guideSwatchStyle(t, grey(0.16)), color: grey(0.995), border: grey(0.86)),
    // `linear-gradient(135deg, light 0 50%, dark 50% 100%)`.
    _ => GuideSwatch(
      text: 'Aa',
      style: guideSwatchStyle(t, grey(0.56)),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [grey(0.995), grey(0.995), grey(0.11), grey(0.11)], stops: const [0, 0.5, 0.5, 1]),
      border: grey(0.56),
    ),
  };
}
