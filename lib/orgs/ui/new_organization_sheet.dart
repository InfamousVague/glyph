/// A new organization from the home page's filters. A port of `src/app/home/NewOrganizationSheet.tsx`
/// (docs/TEAMS.md): a name, in the workspace sheet's own look, made on the service and opened at once. The maker
/// owns it and can invite people by handle from its screen; its workspace is made here as it is made.
///
/// Then the team's tools (docs/PM_PLUGINS.md; Matt, 2026-11-01: "when starting an org it asks you which of the org
/// based plugins you'd like to enable for gantts project managment and more"): after the name, a second step, "Which
/// tools does this team use?", the project tools with their marks and a line each, all unchecked; checking one that
/// stands on Tickets checks Tickets. Create makes the organization and hands its id and the tools chosen to
/// [NewOrganizationSheet.onTools], whose holder writes the organization's `Home.md` with them there and then. The step
/// is the same in Simple mode and Advanced.
///
/// What differs from the web original: the organizations are the [AccountServices]' own; with none, Create cannot
/// be pressed.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../account/ui_state.dart';
import '../../art/app_icon.dart';
import '../../plugins/projects/suite.dart';
import '../../plugins/projects/tool_chip.dart' show toolIcon;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';

/// The sheet (`NewOrganizationSheet`); nothing while [open] is false.
class NewOrganizationSheet extends StatefulWidget {
  const NewOrganizationSheet({super.key, required this.services, required this.open, required this.onClose, required this.onMade, this.onTools});

  final AccountServices? services;
  final bool open;
  final VoidCallback onClose;
  final ValueChanged<String> onMade;

  /// The organization made and the tools chosen for it, in the suite's order with what they need: its home page is
  /// written with them (lib/root/root_teamspaces.dart). Told before [onMade].
  final FutureOr<void> Function(String orgId, List<String> tools)? onTools;

  @override
  State<NewOrganizationSheet> createState() => _NewOrganizationSheetState();
}

class _NewOrganizationSheetState extends State<NewOrganizationSheet> {
  String _name = '';
  bool _busy = false;
  String? _problem;

  /// Whether the name is given and the tools are being chosen.
  bool _tools = false;
  Set<String> _chosen = const {};

  void _next() {
    if (_name.trim().isEmpty) return;
    setState(() => _tools = true);
  }

  /// [id] checked or not: one that needs Tickets brings it; Tickets unchecked takes what needs it.
  void _choose(String id) {
    final next = {..._chosen};
    if (next.contains(id)) {
      next.remove(id);
      if (id == ticketsTool) next.removeAll(needTickets);
    } else {
      next.add(id);
    }
    setState(() => _chosen = withNeeds(next).toSet());
  }

  Future<void> _submit() async {
    final clean = _name.trim();
    final orgs = widget.services?.orgs;
    if (clean.isEmpty || _busy || orgs == null) return;
    final close = widget.onClose, made = widget.onMade, tools = widget.onTools;
    final chosen = withNeeds(_chosen);
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final org = await orgs.createOrg(clean);
      if (mounted) {
        setState(() {
          _name = '';
          _tools = false;
          _chosen = const {};
        });
      }
      await tools?.call(org.id, chosen);
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
    final named = _name.trim().isNotEmpty;
    final ready = named && !_busy && widget.services?.orgs != null;
    if (_tools) {
      return Sheet(
        label: 'New organization',
        onClose: widget.onClose,
        children: [
          SheetTitle.text('Which tools does this team use?'),
          SheetNote('Turn on what ${_name.trim()} plans its work with. Each can be switched later in its Tools, for the whole team. Left off, their markdown stays as plain text.'),
          SheetGroup(
            children: [
              for (final plugin in projectPlugins)
                SheetRow(
                  key: ValueKey('new-org-tool:${plugin.manifest.id}'),
                  icon: AppIcon(toolIcon(plugin.manifest.id), size: 18),
                  label: plugin.manifest.name,
                  hint: plugin.manifest.line,
                  chosen: _chosen.contains(plugin.manifest.id),
                  onPress: () => _choose(plugin.manifest.id),
                ),
            ],
          ),
          SheetGroup(
            children: [
              SheetRow(label: _busy ? 'One moment…' : 'Create', hint: _problem, onPress: () => unawaited(_submit()), disabled: !ready),
              SheetRow(label: 'Back', onPress: _busy ? null : () => setState(() => _tools = false), disabled: _busy),
            ],
          ),
        ],
      );
    }
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
              enterKeyHint: TextInputAction.next,
              onSubmitted: (_) => _next(),
            ),
            SheetRow(label: 'Next', onPress: _next, disabled: !named || widget.services?.orgs == null),
          ],
        ),
      ],
    );
  }
}
