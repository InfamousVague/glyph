import 'dart:async';

import 'package:flutter/widgets.dart';

import '../account/ui_state.dart';
import '../notes/workspace_swatch.dart';
import 'account_forms.dart';
import 'kit/settings_kit.dart';

/// Port of `ColourCard` (src/app/settings/ColourCard.tsx; docs/SHARED.md, S7): your colour, one of the app's seven
/// hues, worn in every organization - your cursor and your selections while you edit a team note, your comments,
/// and your row in the members - unless an organization gives you another there (organization_sheet.dart). Ink, the
/// app's own, is no colour. Kept on the service in the clear, as an organization's hue is.
///
/// What differs from the web original: the colour and the call that sets it are the [AccountServices]' organizations
/// (`useOrgs().colour`, `setAccountColour`); with none, the card draws ink and a press changes nothing.
class ColourCard extends StatefulWidget {
  const ColourCard({super.key, required this.services});
  final AccountServices services;

  @override
  State<ColourCard> createState() => _ColourCardState();
}

class _ColourCardState extends State<ColourCard> {
  String? _problem;

  Future<void> _choose(String hue) async {
    final orgs = widget.services.orgs;
    if (orgs == null) return;
    setState(() => _problem = null);
    try {
      await orgs.setAccountColour(hue == 'ink' ? null : hue);
    } catch (failure) {
      if (mounted) setState(() => _problem = accountFailureText(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return PaneSection(
      title: 'Your colour',
      footer: const Text("Worn by your cursor and your selections while you edit a team note, by your comments, and by your row in an organization's members. An organization can give you another colour there."),
      children: [
        CardSwatch(child: WorkspaceSwatch(hue: widget.services.orgState.colour ?? 'ink', onHue: (hue) => unawaited(_choose(hue)))),
        if (problem != null) SettingsFootnote(child: Text(problem)),
      ],
    );
  }
}
