/// An organization's Tools: the project tools with a switch each, for the whole team (docs/PM_PLUGINS.md; Matt,
/// 2026-11-01). On the teamspace home and in the organization's settings sheet. A switch writes the organization's
/// `Home.md` `plugins:` through the suite; turning on a tool that needs Tickets turns Tickets on with it, and turning
/// Tickets off first says which tools go with it, with Turn off and Keep.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import 'suite.dart';
import 'tool_chip.dart' show toolIcon;

/// The suite's switches for [orgId], or for the person's own with none.
class ToolSwitches extends StatefulWidget {
  const ToolSwitches({super.key, this.orgId, this.canEdit = true});

  final String? orgId;

  /// Whether this account may change them; read only otherwise.
  final bool canEdit;

  /// One tool's row, by its id.
  static Key rowKey(String id) => ValueKey<String>('tool-switch:$id');
  static const Key warningKey = ValueKey<String>('tool-switch-warning');

  @override
  State<ToolSwitches> createState() => _ToolSwitchesState();
}

class _ToolSwitchesState extends State<ToolSwitches> {
  /// Tickets asked off while tools that need it are on: the warning is up.
  bool _askingTickets = false;

  void _set(String id, bool on) {
    final suite = projectSuite;
    final now = suite.onIn(orgId: widget.orgId);
    if (on) {
      setState(() => _askingTickets = false);
      suite.turnOn([id], orgId: widget.orgId);
      return;
    }
    if (id == ticketsTool && dependentsOf(now).isNotEmpty && !_askingTickets) {
      setState(() => _askingTickets = true);
      return;
    }
    setState(() => _askingTickets = false);
    suite.turnOff(id, orgId: widget.orgId);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectSuite,
      builder: (context, _) {
        final t = context.tokens;
        final sm = t.fontSize('sm');
        final md = t.fontSize('md');
        final on = projectSuite.onIn(orgId: widget.orgId);
        final going = [for (final id in dependentsOf(on)) toolShortName(id)];
        Widget row(String id) {
          final plugin = projectPlugin(id)!;
          final checked = on.contains(id);
          return Padding(
            key: ToolSwitches.rowKey(id),
            padding: EdgeInsets.symmetric(vertical: t.space(2)),
            child: Row(
              children: [
                ExcludeSemantics(child: AppIcon(toolIcon(id), size: md * 1.1, color: t.color('app-ink-2'))),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(plugin.manifest.name, style: t.textAt(md, weight: 'medium', color: t.color('app-ink'))),
                      Text(plugin.manifest.line, style: t.textAt(sm, color: t.color('app-ink-3'))),
                    ],
                  ),
                ),
                SizedBox(width: t.space(3)),
                GlacierSwitch(ariaLabel: plugin.manifest.name, checked: checked, disabled: !widget.canEdit, onCheckedChange: (value) => _set(id, value)),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final id in projectTools) row(id),
            if (_askingTickets && going.isNotEmpty)
              Container(
                key: ToolSwitches.warningKey,
                margin: EdgeInsets.only(top: t.space(2)),
                padding: EdgeInsets.all(t.space(3)),
                decoration: BoxDecoration(color: t.color('app-paper-2'), border: Border.all(color: t.color('app-rule')), borderRadius: BorderRadius.circular(t.radius('md'))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${going.join(going.length == 2 ? ' and ' : ', ')} ${going.length == 1 ? 'needs' : 'need'} Tickets, and ${going.length == 1 ? 'goes' : 'go'} off with it. Their markdown stays as it is.', style: t.textAt(sm, color: t.color('app-ink'))),
                    SizedBox(height: t.space(2)),
                    Row(
                      children: [
                        _Press(key: const ValueKey('tool-switch-turn-off'), words: 'Turn off', strong: true, onPress: () => _set(ticketsTool, false)),
                        SizedBox(width: t.space(2)),
                        _Press(key: const ValueKey('tool-switch-keep'), words: 'Keep', onPress: () => setState(() => _askingTickets = false)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A word to press: the warning's Turn off and Keep.
class _Press extends StatelessWidget {
  const _Press({super.key, required this.words, required this.onPress, this.strong = false});

  final String words;
  final VoidCallback onPress;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return Semantics(
      button: true,
      label: words,
      onTap: onPress,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPress,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: sm * 0.9, vertical: sm * 0.4),
            decoration: BoxDecoration(color: strong ? t.color('app-ink') : null, border: Border.all(color: t.color('app-rule')), borderRadius: BorderRadius.circular(sm)),
            child: Text(words, style: t.textAt(sm, weight: 'semibold', color: strong ? t.color('app-paper') : t.color('app-ink'))),
          ),
        ),
      ),
    );
  }
}
