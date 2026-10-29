/// The Keyboard modes plugin's page in Settings (keymaps.dart): the choice of Off, Vim or Emacs, and with Vim its
/// two switches, Start notes in Normal mode and jk to leave Insert. With Emacs there is nothing more to set; the page
/// says which keys it takes.
///
/// In Simple (`Preferences.simple`) the page is the choice alone, and the rest waits behind a More row that opens in
/// place, as Simple's rule is; in Advanced it is drawn under the choice.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/preferences.dart';
import '../../settings/kit/settings_kit.dart';
import '../host.dart' show onPluginStorage;
import '../types.dart' show PluginHost;
import 'keymaps.dart';

class KeymapsPane extends StatefulWidget {
  const KeymapsPane({super.key, this.prefs, this.host});

  /// The preferences Simple is read from: the app's unless given.
  final PreferencesStore? prefs;

  /// Where the choices are kept: the plugin's own host unless given.
  final PluginHost? host;

  @override
  State<KeymapsPane> createState() => _KeymapsPaneState();
}

class _KeymapsPaneState extends State<KeymapsPane> {
  /// Simple's More has been opened.
  bool _more = false;
  late VoidCallback _stop;

  PreferencesStore get _prefs => widget.prefs ?? preferences;

  @override
  void initState() {
    super.initState();
    _stop = onPluginStorage(_redraw);
    _prefs.addListener(_redraw);
  }

  @override
  void dispose() {
    _stop();
    _prefs.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final via = widget.host;
    final mode = keyboardModeChosen(via);
    // A row behind More looked for by name opens it.
    if (!_more && settingsSought(context, const ['Start notes in Normal mode', 'jk to leave Insert'])) _more = true;
    final open = !_prefs.value.simple || _more;
    final choice = PaneSection(
      title: 'Keys',
      description: const Text('From a hardware keyboard only: the screen’s keyboard types as it always has.'),
      children: [
        SettingRow(
          label: 'Type like',
          hint: Text(switch (mode) {
            KeyboardMode.off => 'Your notes take keys as they always have.',
            KeyboardMode.vim => 'Vim: Normal, Insert and Visual, and a command line. The mode is at the note’s foot.',
            KeyboardMode.emacs => 'Emacs: Control and Meta keys, with no modes. The mark and a search show at the note’s foot.',
          }),
          layout: SettingRowLayout.stacked,
          control: GlacierSegmentedControl(
            ariaLabel: 'Type like',
            fullWidth: true,
            size: GlacierSegmentedSize.sm,
            options: [for (final each in KeyboardMode.values) GlacierSegmentedOption(value: each.name, label: Text(each.label))],
            value: mode.name,
            onValueChange: (value) => setKeyboardMode(KeyboardMode.values.byName(value), via),
          ),
        ),
        if (!open && mode != KeyboardMode.off)
          SettingRow(
            label: 'More',
            hint: Text(mode == KeyboardMode.vim ? 'Whether notes open in Normal mode, and jk to leave Insert.' : 'The keys Emacs takes.'),
            control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
          ),
      ],
    );
    return PaneBody(
      children: [
        choice,
        if (open && mode == KeyboardMode.vim)
          PaneSection(
            title: 'Vim',
            description: const Text('Esc or Ctrl-[ goes back to Normal. :w saves, :q closes the note, :wq does both. Cmd and Ctrl shortcuts work in Insert as they always do.'),
            children: [
              SettingRow(
                label: 'Start notes in Normal mode',
                hint: const Text('Off, a note opens in Insert, ready to type.'),
                control: GlacierSwitch(ariaLabel: 'Start notes in Normal mode', checked: vimStartsNormal(via), onCheckedChange: (on) => setVimStartsNormal(on, via)),
              ),
              SettingRow(
                label: 'jk to leave Insert',
                hint: const Text('j then k, typed within a second, goes back to Normal, and the j is taken out.'),
                control: GlacierSwitch(ariaLabel: 'jk to leave Insert', checked: vimJk(via), onCheckedChange: (on) => setVimJk(on, via)),
              ),
            ],
          ),
        if (open && mode == KeyboardMode.emacs)
          const PaneSection(
            title: 'Emacs',
            children: [
              SettingRow(label: 'Moving', hint: Text('C-f C-b C-n C-p, M-f M-b, C-a C-e, M-< M->.')),
              SettingRow(label: 'Killing and yanking', hint: Text('C-k, M-d, M-Backspace, C-w and M-w, each run of kills one kill; C-y yanks it back.')),
              SettingRow(label: 'The mark', hint: Text('C-Space sets it and the motions select from it; C-g lets it go.')),
              SettingRow(label: 'And', hint: Text('C-s and C-r search as you type, C-/ undoes, C-t transposes, C-o opens a line, C-x C-s saves.')),
            ],
          ),
      ],
    );
  }
}
