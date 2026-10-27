/// Light or dark, asked before the first note, because in an app that is almost all type the ground behind the words
/// is most of the look. A port of `src/app/guide/pages/Theme.tsx`, with the `.swatch[data-swatch]` rules of `Guide.module.css`.
///
/// Each choice applies the moment it is tapped, the guide itself changing colour under the thumb, so the person
/// decides by seeing, not by imagining. Changeable any time in Settings. Nothing puts the old theme back if the
/// person skips on: the choice is the preference, and there is no preview to undo. The page stays still until a
/// choice is tapped.
///
/// What differs: the preferences are a store the page is given ([preferences] unless a test brings its own), where
/// the page's are a module. Settings' own theme cards (lib/settings/theme_cards.dart) draw a small scene of each
/// theme and the named ones too; this page keeps the web's three swatches and their "Aa", in a row on the last page
/// since 2026-10-27.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/preferences.dart';
import 'parts.dart';

/// `THEME_CHOICES`.
const List<({String value, String label, String hint})> themeChoices = [
  (value: 'dark', label: 'Dark', hint: 'Light words on black. Easier on the eyes at night.'),
  (value: 'light', label: 'Light', hint: 'Dark words on white, like paper.'),
  (value: 'system', label: 'Match device', hint: 'Follows your device’s dark mode.'),
];

/// Light or dark, as a row of three on the walkthrough's last page (since 2026-10-27, when the walkthrough became a
/// tour of the app and this question moved from its second page to its last): each swatch the choice shown, its
/// name under it, the chosen one ringed.
class GuideThemeChoices extends StatelessWidget {
  const GuideThemeChoices({super.key, this.store});

  /// The preferences to read and set; the app's own when null.
  final ValueNotifier<Preferences>? store;

  @override
  Widget build(BuildContext context) {
    final prefs = store ?? preferences;
    final t = context.tokens;
    return ValueListenableBuilder<Preferences>(
      valueListenable: prefs,
      builder: (context, now, _) => Padding(
        padding: EdgeInsets.only(top: t.space(6)),
        child: Semantics(
          container: true,
          label: 'Theme',
          child: Wrap(
            spacing: t.space(4),
            runSpacing: t.space(3),
            children: [
              for (final choice in themeChoices)
                _ThemeChip(label: choice.label, hint: choice.hint, on: now.theme == choice.value, onPick: () => prefs.value = prefs.value.copyWith(theme: choice.value), swatch: _swatch(t, choice.value)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({required this.label, required this.hint, required this.on, required this.onPick, required this.swatch});
  final String label;
  final String hint;
  final bool on;
  final VoidCallback onPick;
  final Widget swatch;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPick,
      button: false,
      excludeSemantics: true,
      builder: (context, state) => Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        button: true,
        label: '$label. $hint',
        onTap: onPick,
        child: GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('lg'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: t.reducedMotion ? Duration.zero : t.duration('glacier-duration-fast'),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.radius('lg') + 4),
                  border: Border.all(color: on ? t.color('glacier-text') : t.color('glacier-text').withValues(alpha: 0), width: 2),
                ),
                child: swatch,
              ),
              SizedBox(height: t.space(2)),
              Text(label, style: t.textAt(t.fontSize('sm'), weight: on ? 'semibold' : 'medium', color: t.color(on ? 'glacier-text' : 'glacier-text-muted'))),
            ],
          ),
        ),
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
