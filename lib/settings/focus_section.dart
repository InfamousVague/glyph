/// Settings › Appearance › Focus: focus mode's switch and its typewriter scroll (Matt, 2026-10-27: "build ... focus
/// mode"; lib/editor/focus/focus_mode.dart).
///
/// In both modes, it being one switch whose doing is plain to see. In Simple (`Preferences.simple`, GHST-103) the
/// typewriter scroll waits behind a More row that opens in place, as Simple's rule is; in Advanced it is drawn under
/// the switch. It is focus mode's own half, so it is drawn as off while focus mode is.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/preferences.dart';
import 'kit/settings_kit.dart';

/// The section, writing [store].
class FocusSection extends StatefulWidget {
  const FocusSection({super.key, required this.store});

  final PreferencesStore store;

  @override
  State<FocusSection> createState() => _FocusSectionState();
}

class _FocusSectionState extends State<FocusSection> {
  /// Simple's More has been opened.
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final prefs = store.value;
    final open = !prefs.simple || _more;
    return PaneSection(
      title: 'Focus',
      description: const Text('While you write, every paragraph but the one you are in fades back.'),
      children: [
        SettingRow(
          label: 'Focus mode',
          hint: const Text('Dims every paragraph but the one you are writing. Also in a note’s More, and in the command bar.'),
          control: GlacierSwitch(ariaLabel: 'Focus mode', checked: prefs.focusMode, onCheckedChange: (on) => store.update((now) => now.copyWith(focusMode: on))),
        ),
        if (open)
          SettingRow(
            label: 'Typewriter scroll',
            hint: const Text('Keeps the line you are writing in the middle of the page, above the keyboard.'),
            disabled: !prefs.focusMode,
            control: GlacierSwitch(
              ariaLabel: 'Typewriter scroll',
              checked: prefs.focusMode && prefs.focusTypewriter,
              disabled: !prefs.focusMode,
              onCheckedChange: (on) => store.update((now) => now.copyWith(focusTypewriter: on)),
            ),
          )
        else
          SettingRow(
            label: 'More',
            hint: const Text('Whether the line you are writing stays in the middle of the page.'),
            control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
          ),
      ],
    );
  }
}
