import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/preferences.dart';
import '../../guide/pages/mode.dart' show experienceChoices;
import '../choice_card.dart';
import '../kit/settings_icons.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../settings_search.dart';

/// What Settings' search finds on Simple or advanced: the one card, by the name it draws.
const List<SettingsFindable> experienceFindable = [SettingsFindable('Mode', 'simple advanced beginner everything hide more fewer')];

/// The row's line: the mode the app is in. Before the choice is ever made the app is advanced ([Preferences.experience]
/// reads so), and the line says that rather than nothing: it is true, and it is what a tap on the row would show lit.
String experienceSummary(Preferences prefs) => prefs.simple ? 'Simple' : 'Advanced';

/// Settings › Simple or advanced (GHST-103): the same choice the walkthrough asks on its "How much of it?" page, for
/// anyone who wants to change it later. Matt, 2026-10-17: "allow selecting between simple and advanced mode where
/// simple mode has a much more approachable UI with fancy features hidden behind more". Two cards, as Appearance
/// chooses a theme, with the walkthrough's own words under each ([experienceChoices]), and a line under the card
/// saying what Simple puts away, so nobody fears losing their boards by tapping it.
///
/// A tap is the choice, with nothing to confirm, and writes it the one way every place does
/// ([Preferences.choosing]): the mode, that it was chosen, and for Simple the notes opened formatted. Settings
/// itself answers at once, since its list is read from the preferences: the sections Simple hides leave the list
/// under the person's finger.
///
/// Nothing of the web app's to port: the choice is new with the Flutter app.
class ExperiencePane extends StatelessWidget {
  const ExperiencePane({super.key, this.store});

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? preferences;
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) => PaneBody(
        children: [
          PaneSection(
            title: 'Mode',
            description: const Text('Start simple and grow into the rest, or have it all from the first day.'),
            // Matt's worry for a new person is the opposite of an old hand's: the first needs less, the second needs to
            // know that less is not loss.
            footer: const Text('Boards, databases, canvases, AI, teams and most settings wait behind Advanced. Nothing is lost: switch back any time.'),
            children: [
              // Unlike the walkthrough, which lights Simple for a new person, this lights what the app is: advanced
              // until the choice is made, which is what every section on the list behind this page is answering to.
              SettingRowBox(child: ExperienceCards(value: prefs.experience, onValueChange: (mode) => store.update((now) => now.choosing(mode)))),
            ],
          ),
        ],
      ),
    );
  }
}

/// The two modes as choice cards (choice_card.dart), in the pattern of the theme cards: a picture over its words and
/// a tick. The picture is the walkthrough's sign for each, a feather for Simple and a grid of everything for
/// Advanced, drawn in the page's own ink rather than any colour, since the choice is not about colour.
class ExperienceCards extends StatelessWidget {
  const ExperienceCards({super.key, required this.value, required this.onValueChange});

  /// One of [experienceIds].
  final String value;
  final ValueChanged<String> onValueChange;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final byValue = {for (final choice in experienceChoices) choice.value: choice};
    return ChoiceCards<String>(
      label: 'Mode',
      values: [for (final choice in experienceChoices) choice.value],
      value: value,
      onValueChange: onValueChange,
      nameOf: (value) => byValue[value]!.label,
      radius: t.radius('lg'),
      // Side by side, the pair: neither leads, as System does among the themes.
      layout: (context, cards) => ChoiceGrid(columns: 2, gap: t.space(3), children: cards),
      card: (context, value, selected) {
        final choice = byValue[value]!;
        return ChoiceCardBody(
          // The sign on a plain ground with its hairline under it, as the theme cards' miniatures have theirs.
          picture: Container(
            height: t.lenOf('4.5rem'),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.color('glacier-surface'),
              border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline'))),
            ),
            child: AppIcon(value == 'simple' ? Lucide.feather : Lucide.layoutGrid, size: 28, strokeWidth: 1.8, color: t.color('glacier-text')),
          ),
          words: Padding(
            padding: EdgeInsets.all(t.space(3)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExactLines.of(
                        Text(
                          choice.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: pageText(t, t.fontSize('sm'), weight: 'semibold', height: t.len('glacier-leading-sm')),
                        ),
                      ),
                      const SizedBox(height: 1),
                      // The walkthrough's hint, which may run to three lines in a card half a phone wide: the grid
                      // gives both cards the taller one's height.
                      ExactLines.of(
                        Text(
                          choice.hint,
                          style: pageText(t, t.fontSize('xs'), height: t.len('glacier-leading-sm'), color: t.color('glacier-text-muted')),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: t.space(2)),
                ChoiceTick(
                  selected: selected,
                  size: t.lenOf('1.25rem'),
                  border: t.color('glacier-border'),
                  borderWidth: t.len('glacier-hairline'),
                  tick: t.color('glacier-accent-contrast'),
                  child: const SettingsIcon(SettingsGlyph.check, size: 12, strokeWidth: 2.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
