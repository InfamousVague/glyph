import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/preferences.dart';
import 'accent_swatch.dart';
import 'kit/settings_kit.dart';
import 'kit/settings_type.dart';
import 'layout_cards.dart';
import 'scale_cards.dart';
import 'settings_screen.dart' show settingsSplitFits;
import 'settings_search.dart';
import 'theme_cards.dart';
import 'top_bar_cards.dart';
import 'typeface_cards.dart';
import 'words.dart';

/// What Settings' search finds on Appearance (`findable`, src/app/settings/AppearancePane.findable.ts), by the names
/// the page draws, in its order. Type, Motion and Touch were pages of their own until docs/DESIGN.md §138: each
/// page's words are its card's now, so looking for "type" or "animations" still lands.
///
/// Two rows are drawn only where they do something, and listed only there: the sidebar's choice on a window wide
/// enough for the sidebar, and the haptics where there is a motor.
List<SettingsFindable> appearanceFindable({required bool wide, required bool haptics}) => [
      const SettingsFindable('Page', 'theme light dark system dawn boreal ember'),
      const SettingsFindable('Home page', 'dashboard layout home cards list timeline spotlight grid'),
      const SettingsFindable('Top bar', 'header toolbar tabs bar ledger strip masthead islands thumb classic capsules'),
      const SettingsFindable('Accent', 'colour color highlight'),
      const SettingsFindable('Type', 'text font'),
      const SettingsFindable('Note font', 'font typeface body note editor maple fira mono monospace code coding ligatures inter noto plex'),
      const SettingsFindable('Interface font', 'font typeface ui app tabs menus inter noto plex'),
      const SettingsFindable('Text size', 'font bigger smaller larger'),
      const SettingsFindable('Scale', 'size zoom interface ui bigger smaller'),
      const SettingsFindable('Spacing', 'density compact padding roomy tight'),
      const SettingsFindable('Corners', 'rounding radius round square'),
      const SettingsFindable('Code', 'syntax highlighting colours colors'),
      if (wide) const SettingsFindable('Sidebar', 'dock column popover notes list'),
      const SettingsFindable('Motion', 'movement animations'),
      const SettingsFindable('Animation speed', 'motion fast slow'),
      const SettingsFindable('Ghostly typing', 'wisp letters'),
      const SettingsFindable('Smoke at the edges', 'wisp fade scroll'),
      const SettingsFindable('Ripples while recording', 'waves voice'),
      if (haptics) const SettingsFindable('Haptics', 'vibrate vibration buzz touch'),
    ];

/// A map of a preference's words as the options a segmented control takes, in the map's own order (`optionsOf`).
List<GlacierSegmentedOption> _options(Map<String, String> words) => [
      for (final entry in words.entries) GlacierSegmentedOption(value: entry.key, label: Text(entry.value)),
    ];

/// Port of `AppearancePane` (src/app/settings/AppearancePane.tsx): how the app looks, moves and feels. The page
/// first, then how the home page is laid out and how the top bar is, each as cards that are the thing drawn small,
/// then its one colour, then the type, how much air it gives itself and how round its corners are, then the colours
/// of code, then how it moves and how it answers a touch.
///
/// Every control writes the app's preferences ([store], the app's own unless a test brings one), and the app's theme
/// is built from them, so each choice is seen at once. The sidebar's choice is drawn only on a window wide enough
/// for the sidebar, and Touch only where there is a motor.
///
/// What differs from the web original:
/// - Controls whose feature has no Flutter port yet still write their preference and change nothing more: the home
///   page's layout and the top bar's style until those screens read them, the code colours, the sidebar's style,
///   the three Motion switches, and the note's face until there is a note to set in it.
/// - The faces Fira Code, Noto and Plex are not shipped yet, so choosing one draws in the fallback face.
/// - Scale reaches the app as a magnification of the whole window (lib/app/ghost_app.dart), where the page set the
///   root's font size; and the pace reaches the kit's duration tokens through the app's theme rather than inline.
class AppearancePane extends StatelessWidget {
  const AppearancePane({super.key, this.store, this.haptics, this.wide, this.hasMotor});

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;

  /// The haptics switch's flag; the app's own when null.
  final DeviceFlag? haptics;

  /// Whether the window has room for the sidebar; asked of the window when null.
  final bool? wide;

  /// Whether this device has a motor; asked of the platform when null.
  final bool? hasMotor;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? preferences;
    final haptics = this.haptics ?? hapticsPref;
    final wide = this.wide ?? settingsSplitFits(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, haptics]),
      builder: (context, _) {
        final t = context.tokens;
        final prefs = store.value;
        final faces = prefs.faces;
        void set(Preferences Function(Preferences now) change) => store.update(change);

        Widget segments(String label, Map<String, String> words, String value, ValueChanged<String> onChange) => GlacierSegmentedControl(
              ariaLabel: label,
              fullWidth: true,
              size: GlacierSegmentedSize.sm,
              options: _options(words),
              value: value,
              onValueChange: onChange,
            );
        final density = GlacierDensityMode.values.firstWhere((mode) => mode.token == prefs.density, orElse: () => GlacierDensityMode.comfortable);
        final sampleSize = t.len('app-h1');
        final noteFonts = t.families('app-note-font');

        return PaneBody(
          children: [
            PaneSection(
              title: 'Page',
              description: const Text('Ink on paper, paper on ink, or one of three tinted themes. System follows the phone.'),
              children: [
                // The kit's theme cards: each is the page painted small in that theme, System split light and dark.
                SettingRowBox(child: ThemeCards(value: prefs.theme, onValueChange: (value) => set((now) => themeChoice(value, now)))),
              ],
            ),
            // The home page's four layouts, each a card that is the page drawn small.
            PaneSection(
              title: 'Home page',
              description: const Text('How the home page lays out your notebooks and notes. The search and its filters stay on top whichever you pick.'),
              children: [
                SettingRowBox(child: LayoutCards(value: prefs.homeLayout, onValueChange: (homeLayout) => set((now) => now.copyWith(homeLayout: homeLayout, homeLayoutChosen: true)))),
              ],
            ),
            // The top bar's four ways, each a card that is the bar drawn small.
            PaneSection(
              title: 'Top bar',
              description: const Text("Where the controls and the open notes' tabs sit. The same on every screen, and on your other devices."),
              children: [
                SettingRowBox(child: TopBarCards(value: prefs.topBar, onValueChange: (topBar) => set((now) => now.copyWith(topBar: topBar)))),
              ],
            ),
            PaneSection(
              title: 'Accent',
              description: const Text("Colours the few things that mark a choice: a focus ring, a chosen segment. Ink is the app's own."),
              children: [AccentSwatch(accent: prefs.accent, onAccent: (accent) => set((now) => now.copyWith(accent: accent)))],
            ),
            PaneSection(
              title: 'Type',
              // The size shown rather than described, in the note's own face, so it changes with the choice under it.
              description: ExcludeSemantics(
                child: Text(
                  'Aa',
                  key: const ValueKey('settings-sample'),
                  style: pageText(t, sampleSize, weight: 'bold', height: 1, tracking: t.len('app-tracking-display', em: sampleSize), color: t.color('app-ink-3'), mono: true).copyWith(
                        fontFamily: noteFonts.isEmpty ? null : noteFonts.first,
                        fontFamilyFallback: [...noteFonts.skip(1), for (final family in noteFonts) ...?t.typography.fallbacks[family]],
                      ),
                ),
              ),
              children: [
                // Two faces: the note's, and the interface's.
                SettingRow(
                  label: 'Note font',
                  hint: const Text('The words of a note and its code. Maple Mono and Fira Code join pairs like -> and != into one sign.'),
                  layout: SettingRowLayout.stacked,
                  control: TypefaceCards(label: 'Note font', kind: TypefaceKind.note, faces: typefaces, value: faces.note, onValueChange: (noteFace) => set((now) => now.copyWith(noteFace: noteFace))),
                ),
                SettingRow(
                  label: 'Interface font',
                  hint: const Text('Tabs, lists, Settings and buttons.'),
                  layout: SettingRowLayout.stacked,
                  control: TypefaceCards(label: 'Interface font', kind: TypefaceKind.interface, faces: interfaceFaces, value: faces.ui, onValueChange: (typeface) => set((now) => now.copyWith(typeface: typeface))),
                ),
                SettingRow(
                  label: 'Text size',
                  hint: const Text('The note, the list and the headings.'),
                  layout: SettingRowLayout.stacked,
                  control: segments('Text size', sizeWords, prefs.textSize, (value) => set((now) => now.copyWith(textSize: value))),
                ),
                // A card per step, each the same row of the app drawn at that size.
                SettingRow(
                  label: 'Scale',
                  hint: const Text('Everything, buttons and bars as well as words. Stays with this device.'),
                  layout: SettingRowLayout.stacked,
                  control: ScaleCards(value: prefs.uiScale, onValueChange: (uiScale) => set((now) => now.copyWith(uiScale: uiScale))),
                ),
              ],
            ),
            PaneSection(
              title: 'Spacing',
              description: const Text('The padding and gaps of everything the app draws. The words keep their own size.'),
              children: [
                // The kit's own density picker: a card per step, each showing how tightly it packs, in Ghost.md's words.
                SettingRowBox(
                  child: GlacierDensitySelector(
                    ariaLabel: 'Spacing',
                    value: density,
                    onValueChange: (mode) => set((now) => now.copyWith(density: mode.token)),
                    labels: {for (final mode in GlacierDensityMode.values) mode: Text(densityWords[mode.token]!)},
                  ),
                ),
              ],
            ),
            PaneSection(
              title: 'Corners',
              children: [
                SettingRow(
                  label: 'Rounding',
                  hint: const Text('Cards, fields and buttons. Pills stay pills.'),
                  layout: SettingRowLayout.stacked,
                  control: segments('Rounding', roundingWords, prefs.rounding, (value) => set((now) => now.copyWith(rounding: value))),
                ),
              ],
            ),
            PaneSection(
              title: 'Code',
              description: const Text("The colours of code in a code block. Ink keeps code in the page's own ink."),
              children: [
                SettingRow(
                  label: 'On the light page',
                  layout: SettingRowLayout.stacked,
                  control: segments('Code colours on the light page', codeLightWords, prefs.codeLight, (value) => set((now) => now.copyWith(codeLight: value, codeChosen: true))),
                ),
                SettingRow(
                  label: 'On the dark page',
                  layout: SettingRowLayout.stacked,
                  control: segments('Code colours on the dark page', codeDarkWords, prefs.codeDark, (value) => set((now) => now.copyWith(codeDark: value, codeChosen: true))),
                ),
              ],
            ),
            if (wide)
              PaneSection(
                title: 'Sidebar',
                children: [
                  SettingRow(
                    label: 'Sidebar',
                    hint: const Text('Your notes over the note, or docked as a column beside it.'),
                    layout: SettingRowLayout.stacked,
                    control: segments('Sidebar', sidebarWords, prefs.sidebarStyle, (value) {
                      if (isSidebarStyle(value)) set((now) => now.copyWith(sidebarStyle: value));
                    }),
                  ),
                ],
              ),
            PaneSection(
              title: 'Motion',
              description: const Text("Your phone's own reduce motion setting comes first. With it on, Ghost.md holds still whatever is on here."),
              children: [
                SettingRow(
                  label: 'Animation speed',
                  hint: const Text('How quickly letters gather and screens and sheets move.'),
                  layout: SettingRowLayout.stacked,
                  control: segments('Animation speed', speedWords, prefs.motionSpeed, (value) => set((now) => now.copyWith(motionSpeed: value))),
                ),
                SettingRow(
                  label: 'Ghostly typing',
                  hint: const Text('Words you say arrive as smoke, and words you delete leave as smoke. What you type appears at once.'),
                  control: GlacierSwitch(ariaLabel: 'Ghostly typing', checked: prefs.wisp, onCheckedChange: (wisp) => set((now) => now.copyWith(wisp: wisp))),
                ),
                SettingRow(
                  label: 'Smoke at the edges',
                  hint: const Text('A page turns to smoke as it passes under the header or the dock.'),
                  control: GlacierSwitch(ariaLabel: 'Smoke at the edges', checked: prefs.wispEdge, onCheckedChange: (wispEdge) => set((now) => now.copyWith(wispEdge: wispEdge))),
                ),
                SettingRow(
                  label: 'Ripples while recording',
                  hint: const Text('The newest words move with your voice as the phone hears it.'),
                  control: GlacierSwitch(ariaLabel: 'Ripples while recording', checked: prefs.ripples, onCheckedChange: (ripples) => set((now) => now.copyWith(ripples: ripples))),
                ),
              ],
            ),
            if (hasMotor ?? hapticsAvailable())
              PaneSection(
                title: 'Touch',
                children: [
                  SettingRow(
                    label: 'Haptics',
                    hint: const Text('A small tap when a style or a cue kicks in.'),
                    control: GlacierSwitch(ariaLabel: 'Haptics', checked: haptics.value, onCheckedChange: haptics.set),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
