/// Where one of the more tools would be drawn and it is off (docs/PM_PLUGINS.md §10): a line saying what is there, and
/// the chip that turns it on (lib/plugins/projects/tool_chip.dart [ToolChip], the project tools' own). A canvas note
/// opened while Canvas is off is this, in its cards' place; nothing of the note is read into it or written.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../projects/tool_chip.dart' show ToolChip;
import '../registry.dart' show Registry, plugins;

/// [words] over a chip that turns [tool] on in [registry] (the app's where unsaid).
class MoreToolOff extends StatelessWidget {
  const MoreToolOff({super.key, required this.tool, required this.words, this.registry});

  final String tool;
  final String words;
  final Registry? registry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.space(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            key: ValueKey('tool-off:$tool'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(words, textAlign: TextAlign.center, style: t.textAt(t.len('app-body')).copyWith(color: t.color('app-ink-2'), height: 1.4)),
              SizedBox(height: t.space(3)),
              Center(child: ToolChip(tools: [tool], onPress: () => (registry ?? plugins).setEnabled(tool, true))),
            ],
          ),
        ),
      ),
    );
  }
}
