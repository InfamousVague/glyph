/// Simple or advanced, asked up front (GHST-103). Matt, 2026-10-17: "right now the app can be quite intense and
/// cumbersome to new users during onboarding allow selecting between simple and advanced mode where simple mode has
/// a much more approachable UI with fancy features hidden behind more".
///
/// Like the theme page, each choice applies the moment it is tapped, and the page stays still until one is. Simple is
/// lit when the page opens: a new person is who the page is for, and the whole app is one tap away, here or in
/// Settings. Choosing Simple also takes the model page out of the walkthrough (pages.dart): a person who asked for
/// less is not asked to pick a language model next.
///
/// Nothing of the web app's to port: the choice is new with the Flutter app.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/preferences.dart';
import 'parts.dart';

/// The two modes, in the page's order, with the words Settings says too (lib/settings/panes/experience_pane.dart).
const List<({String value, String label, String hint})> experienceChoices = [
  (value: 'simple', label: 'Simple', hint: 'Notes, lists and to-dos. Everything else waits behind More.'),
  (value: 'advanced', label: 'Advanced', hint: 'The whole app: boards, databases, canvases, AI, teams.'),
];

class GuideMode extends StatelessWidget {
  const GuideMode({super.key, this.store});

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
          const GuideTitle('How much of it?'),
          const GuideLead('Start simple and grow into the rest, or have it all from the first day. You can change it any time in Settings.'),
          GuideChoices(
            label: 'Mode',
            children: [
              for (final choice in experienceChoices)
                GuideChoice(
                  label: choice.label,
                  hint: choice.hint,
                  // Simple is lit before anything is chosen: the page is for a new person.
                  on: now.experienceChosen ? now.experience == choice.value : choice.value == 'simple',
                  onPick: () => prefs.value = prefs.value.copyWith(experience: choice.value, experienceChosen: true),
                  swatch: (context) => _swatch(context.tokens, choice.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A feather for Simple, a grid of everything for Advanced: drawn in the ink of the theme around it rather than the
/// theme page's literal colours, since this choice is not about colour.
Widget _swatch(Tokens t, String mode) => GuideSwatch(
      text: '',
      style: guideSwatchStyle(t, t.color('glacier-text')),
      color: t.color('glacier-surface-raised'),
      border: t.color('glacier-border-strong'),
      child: AppIcon(mode == 'simple' ? Lucide.feather : Lucide.layoutGrid, size: 22, strokeWidth: 2.2, color: t.color('glacier-text')),
    );
