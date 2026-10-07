import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/preferences.dart';
import 'kit/settings_icons.dart';
import 'settings_screen.dart';
import 'settings_sections.dart';

/// Whether the hidden pages are unlocked (settings/developerMode.ts, `glyph-developer`): this device's own switch,
/// flipped from About once that page is ported.
final DeviceFlag developerMode = DeviceFlag('glyph-developer');

/// Port of `SettingsSheet` (src/app/settings/SettingsSheet.tsx): Settings itself, the sections and their live
/// one-line readings, handed to the screen that lists them ([SettingsScreen]). The sections are the table in
/// settings_sections.dart; this reads the facts they depend on (the preferences, the window, the device) and
/// answers the links into Settings.
///
/// Put it over the app's screens, under the app's `BackScope`, and give it [open] and [onClose]. [toCheatSheet],
/// [toModel] and [toPage] are asked from outside to open at a page: each is the moment it was asked for, so asking
/// twice opens it twice, and 0 or null is not asked.
///
/// What differs from the web original:
/// - `updates`, and the callbacks that About's and Examples' rows run (`onGuide`, `onSample`, `onGuideBook`,
///   `onBoard`, `onCanvas`, `onHowCanvas`, `onAcademy`, `onOrganization`), are not parameters yet: the pages that
///   use them are not ported, and each comes back with its page.
/// - [split] is an addition, for a test or a shell that says the window's shape itself.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.open, required this.onClose, this.toCheatSheet = 0, this.toModel = 0, this.toPage, this.split});

  final bool open;
  final VoidCallback onClose;

  /// Asked from outside to open at the cheat sheet: the Academy's summary sends people there.
  final int toCheatSheet;

  /// Asked from outside to open at the AI section's Model card, lit: the home page's "Get a model".
  final int toModel;

  /// Asked from outside to open at a page, by its id, as a link into Settings does.
  final SettingsTarget? toPage;

  /// Whether to draw the split view; null asks the window.
  final bool? split;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  SettingsTarget? _goTo;

  @override
  void initState() {
    super.initState();
    _links(null);
  }

  @override
  void didUpdateWidget(SettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _links(oldWidget);
  }

  /// Each link once, when it is asked: the sheet comes up on that page rather than on the list of sections.
  void _links(SettingsSheet? was) {
    if (widget.toCheatSheet != 0 && widget.toCheatSheet != was?.toCheatSheet) _goTo = SettingsTarget('cheatsheet', nonce: widget.toCheatSheet);
    if (widget.toModel != 0 && widget.toModel != was?.toModel) _goTo = SettingsTarget('ai', setting: 'Model', nonce: widget.toModel);
    final page = widget.toPage;
    if (page != null && page.nonce != was?.toPage?.nonce) _goTo = SettingsTarget(page.id, setting: page.setting, nonce: page.nonce);
  }

  @override
  Widget build(BuildContext context) {
    final store = preferences;
    final wide = widget.split ?? settingsSplitFits(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, developerMode]),
      builder: (context, _) {
        final facts = SettingsFacts(
          prefs: store.value,
          wide: wide,
          haptics: hapticsAvailable(),
          android: defaultTargetPlatform == TargetPlatform.android,
          ios: defaultTargetPlatform == TargetPlatform.iOS,
          developer: developerMode.value,
        );
        final sections = [
          for (final spec in settingsSections)
            if (spec.where?.call(facts) ?? true)
              SettingsSection(
                id: spec.id,
                label: spec.label,
                words: spec.words,
                settings: spec.settings?.call(facts) ?? const [],
                icon: SettingsIcon(spec.glyph, size: 16),
                content: spec.pane ?? (context) => SettingsNotPorted(spec: spec),
                summary: spec.summary?.call(facts),
                group: spec.group,
                hue: spec.hue,
                listed: spec.listed,
                parent: spec.parent,
              ),
        ];
        return SettingsScreen(open: widget.open, onClose: widget.onClose, sections: sections, goTo: _goTo, split: widget.split);
      },
    );
  }
}
