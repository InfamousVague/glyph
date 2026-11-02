/// Note decay alerts' page in Settings (note_decay.dart; docs/NOTE_DECAY.md §2): Check with AI, then GitHub and
/// Figma's lookups and how long a docs page may go unedited, then the pages that may be out of date now.
///
/// In Simple (`Preferences.simple`) the page is the one switch and the list; the lookups and the months wait behind a
/// More row that opens in place, as Simple's rule is.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/preferences.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/settings_host.dart' show SettingsHost;
import '../host.dart' show onPluginStorage;
import '../types.dart' show PluginHost;
import 'decay.dart';
import 'decay_list.dart';
import 'manifest.dart';

class NoteDecayPane extends StatefulWidget {
  const NoteDecayPane({super.key, this.prefs, this.host, this.decay});

  /// The preferences Simple and Local only are read from: the app's unless given.
  final PreferencesStore? prefs;

  /// Where the switches are kept: the plugin's own host unless given.
  final PluginHost? host;

  /// The note decay the list reads: the app's unless given.
  final NoteDecay? decay;

  @override
  State<NoteDecayPane> createState() => _NoteDecayPaneState();
}

class _NoteDecayPaneState extends State<NoteDecayPane> {
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
    final decay = widget.decay ?? noteDecay;
    final localOnly = _prefs.value.localOnly;
    if (!_more && settingsSought(context, const ['Ask GitHub and Figma', 'Docs pages unedited for'])) _more = true;
    final open = !_prefs.value.simple || _more;
    final model = decay?.model;
    final who = model == null || !model.ready ? null : model.name;
    final months = decayMonths(via);
    return PaneBody(
      children: [
        PaneSection(
          title: 'Marks',
          description: const Text('A line whose links, tickets, pull requests or dates have changed since it was written gets a quiet “May be out of date” mark. Nothing is written into the note.'),
          children: [
            SettingRow(
              label: 'Check with AI',
              hint: Text(who == null
                  ? 'Connect an AI in Settings › AI, or get a model for the phone, to have flagged pages read for what is out of date.'
                  : localOnly
                      ? 'Local only: flagged pages are read by the phone’s own model, and nothing leaves it.'
                      : 'Flagged pages, and docs pages a month old, are read by $who for which lines are out of date.'),
              control: GlacierSwitch(ariaLabel: 'Check with AI', checked: decayAiOn(via), disabled: who == null, onCheckedChange: (on) => setDecayAi(on, via)),
            ),
            if (!open)
              SettingRow(
                label: 'More',
                hint: const Text('GitHub and Figma’s lookups, and how long a docs page may go unedited.'),
                control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
              ),
          ],
        ),
        if (open)
          PaneSection(
            title: 'What is checked',
            children: [
              SettingRow(
                label: 'Ask GitHub and Figma',
                hint: Text(localOnly ? 'Off with Local only: nothing is asked outside the phone.' : 'Whether a linked pull request was merged or an issue closed, and whether a linked Figma frame is still there, with those plugins connected.'),
                control: GlacierSwitch(ariaLabel: 'Ask GitHub and Figma', checked: !localOnly && decayLookupsOn(via), disabled: localOnly, onCheckedChange: (on) => setDecayLookups(on, via)),
              ),
              SettingRow(
                label: 'Docs pages unedited for',
                hint: const Text('A docs page this long unedited, while pages it links to changed, is marked at its head.'),
                layout: SettingRowLayout.stacked,
                control: GlacierSegmentedControl(
                  ariaLabel: 'Docs pages unedited for',
                  fullWidth: true,
                  size: GlacierSegmentedSize.sm,
                  options: [for (final each in const [1, 3, 6, 12]) GlacierSegmentedOption(value: '$each', label: Text(each == 1 ? '1 month' : '$each months'))],
                  value: '$months',
                  onValueChange: (value) => setDecayMonths(int.parse(value), via),
                ),
              ),
            ],
          ),
        if (decay != null)
          PaneSection(
            title: 'Pages',
            children: [
              DecayPagesSection(decay: decay, where: (_) => true, onOpen: switch (SettingsHost.maybeOf(context)?.onOpenNote) { final open? => (note) => open(note.id), null => null }, emptyWords: 'Nothing looks out of date.'),
              SettingRow(label: 'Check again', hint: const Text('Asks GitHub, Figma and the AI again the next time each page opens.'), control: RowAction(onPress: decay.forget, child: const Text('Check'))),
            ],
          ),
      ],
    );
  }
}
