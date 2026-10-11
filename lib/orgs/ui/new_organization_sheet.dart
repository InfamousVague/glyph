/// A new organization from the home page's filters. A port of `src/app/home/NewOrganizationSheet.tsx`
/// (docs/TEAMS.md): a name, in the workspace sheet's own look, made on the service and opened at once. The maker
/// owns it and can invite people by handle from its screen; its workspace is made here as it is made.
///
/// What differs from the web original: the organizations are the [AccountServices]' own; with none, Create cannot
/// be pressed.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../account/ui_state.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';

/// The sheet (`NewOrganizationSheet`); nothing while [open] is false.
class NewOrganizationSheet extends StatefulWidget {
  const NewOrganizationSheet({super.key, required this.services, required this.open, required this.onClose, required this.onMade});

  final AccountServices? services;
  final bool open;
  final VoidCallback onClose;
  final ValueChanged<String> onMade;

  @override
  State<NewOrganizationSheet> createState() => _NewOrganizationSheetState();
}

class _NewOrganizationSheetState extends State<NewOrganizationSheet> {
  String _name = '';
  bool _busy = false;
  String? _problem;

  Future<void> _submit() async {
    final clean = _name.trim();
    final orgs = widget.services?.orgs;
    if (clean.isEmpty || _busy || orgs == null) return;
    final close = widget.onClose, made = widget.onMade;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final org = await orgs.createOrg(clean);
      if (mounted) setState(() => _name = '');
      close();
      made(org.id);
    } catch (failure) {
      if (mounted) setState(() => _problem = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final ready = _name.trim().isNotEmpty && !_busy && widget.services?.orgs != null;
    return Sheet(
      label: 'New organization',
      onClose: widget.onClose,
      children: [
        SheetTitle.text('New organization'),
        const SheetNote('A team by name. You own it, can invite people by their handle, and each member gets its workspace.'),
        SheetGroup(
          children: [
            SheetField(
              label: 'Name',
              value: _name,
              onChange: (text) => setState(() => _name = text),
              autoFocus: true,
              autoCapitalize: TextCapitalization.words,
              maxLength: 60,
              enterKeyHint: TextInputAction.done,
              onSubmitted: (_) => unawaited(_submit()),
            ),
            SheetRow(label: _busy ? 'One moment…' : 'Create', hint: _problem, onPress: () => unawaited(_submit()), disabled: !ready),
          ],
        ),
      ],
    );
  }
}
