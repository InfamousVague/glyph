/// What the app draws where a project tool is off but the words use it (docs/PM_PLUGINS.md §5 and §6; Matt,
/// 2026-11-01: "When a plugin is required for an org show a banner at the top with iconography asking the user to
/// enable them for the org").
///
/// - [ToolChip]: a small chip under the words that need the tool, its mark and "Turn on Gantt", or "Turn on Gantt for
///   HelloTrade" in an organization's space. The words above it are drawn as they are written; nothing is rewritten.
/// - [ToolBanner]: the band at the top of an organization's space, and of any of its notes that uses a tool its list
///   lacks: each missing tool's mark and name, one button, "Turn on for HelloTrade", and a way to put it away (kept per
///   device by the suite). In Simple mode one line: the marks, the words and the button.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../more/more_tools.dart' show moreToolPlugin;
import '../registry.dart' show plugins;
import 'suite.dart';

/// A tool's mark, by its plugin's icon name: a project tool's, or one of the more tools' (docs/PM_PLUGINS.md §10), or
/// any other plugin's (the Academy's chip for the Marks plugin).
LucideIcon toolIcon(String id) => Lucide.all[(projectPlugin(id) ?? moreToolPlugin(id) ?? plugins.byId(id))?.icon ?? ''] ?? Lucide.puzzle;

/// A chip asking for [tools] to be turned on [where] (" for HelloTrade", or nothing for the person's own); quiet and
/// pressing nothing where [onPress] is null (an organization this device cannot write to).
class ToolChip extends StatelessWidget {
  const ToolChip({super.key, required this.tools, this.where = '', this.onPress, this.size});

  /// The tools, in the suite's order; the chip names the first and says how many more.
  final List<String> tools;
  final String where;
  final VoidCallback? onPress;

  /// The words' size; the body's where unsaid.
  final double? size;

  String get words {
    final first = toolShortName(tools.first);
    final rest = tools.length - 1;
    return 'Turn on $first${rest > 0 ? ' and ${rest == 1 ? toolShortName(tools[1]) : '$rest more'}' : ''}$where';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final em = size ?? t.len('app-body');
    final text = (em * 0.82).roundToDouble();
    final ink = onPress == null ? t.color('app-ink-3') : t.color('app-ink-2');
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: text * 0.75, vertical: text * 0.3),
      decoration: BoxDecoration(color: t.color('app-paper-2'), border: Border.all(color: t.color('app-rule')), borderRadius: BorderRadius.circular(text)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(toolIcon(tools.first), size: text * 1.05, color: ink),
          SizedBox(width: text * 0.45),
          Flexible(child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textAt(text).copyWith(color: ink, fontWeight: FontWeight.w500))),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: onPress != null,
      label: words,
      onTap: onPress,
      child: ExcludeSemantics(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: GestureDetector(key: ValueKey('tool-chip:${tools.join(',')}'), behavior: HitTestBehavior.opaque, onTap: onPress, child: chip),
        ),
      ),
    );
  }
}

/// The banner over an organization's space asking for the [tools] its notes use and its list lacks.
class ToolBanner extends StatelessWidget {
  const ToolBanner({super.key, required this.tools, required this.orgName, required this.onTurnOn, this.onPutAway, this.simple = false});

  final List<String> tools;
  final String orgName;
  final VoidCallback? onTurnOn;
  final VoidCallback? onPutAway;

  /// Simple mode: one line.
  final bool simple;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final em = t.len('app-body');
    final small = (em * 0.86).roundToDouble();
    final names = [for (final id in tools) toolShortName(id)];
    final said = names.length == 1 ? names.single : '${names.take(names.length - 1).join(', ')} and ${names.last}';
    final ink = t.color('app-ink'), quiet = t.color('app-ink-3');
    final button = Semantics(
      button: true,
      enabled: onTurnOn != null,
      label: 'Turn on for $orgName',
      onTap: onTurnOn,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const ValueKey('tool-banner-turn-on'),
          behavior: HitTestBehavior.opaque,
          onTap: onTurnOn,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: small * 0.9, vertical: small * 0.4),
            decoration: BoxDecoration(color: onTurnOn == null ? t.color('app-paper-2') : ink, borderRadius: BorderRadius.circular(small)),
            child: Text('Turn on for $orgName', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textAt(small).copyWith(color: onTurnOn == null ? quiet : t.color('app-paper'), fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
    final putAway = onPutAway == null
        ? null
        : Semantics(
            button: true,
            label: 'Not now',
            onTap: onPutAway,
            child: ExcludeSemantics(
              child: GestureDetector(
                key: const ValueKey('tool-banner-put-away'),
                behavior: HitTestBehavior.opaque,
                onTap: onPutAway,
                child: Padding(padding: EdgeInsets.all(small * 0.4), child: AppIcon(Lucide.x, size: small * 1.1, color: quiet)),
              ),
            ),
          );
    final marks = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, id) in tools.indexed) ...[if (index > 0) SizedBox(width: small * 0.35), AppIcon(toolIcon(id), size: small * 1.2, color: ink)],
      ],
    );
    final ground = BoxDecoration(color: t.color('app-paper-2'), border: Border.all(color: t.color('app-rule')), borderRadius: BorderRadius.circular(t.radius('lg')));
    if (simple) {
      return Semantics(
        container: true,
        label: 'Tools this space uses',
        child: Container(
          key: const ValueKey('tool-banner'),
          padding: EdgeInsets.symmetric(horizontal: small, vertical: small * 0.5),
          decoration: ground,
          child: Row(
            children: [
              marks,
              SizedBox(width: small * 0.6),
              Expanded(child: Text('Uses $said', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textAt(small).copyWith(color: ink))),
              SizedBox(width: small * 0.6),
              button,
              ?putAway,
            ],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: 'Tools this space uses',
      child: Container(
        key: const ValueKey('tool-banner'),
        padding: EdgeInsets.all(small),
        decoration: ground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: small * 0.9,
                    runSpacing: small * 0.4,
                    children: [
                      for (final id in tools)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(toolIcon(id), size: small * 1.2, color: ink),
                            SizedBox(width: small * 0.35),
                            Text(projectPlugin(id)?.manifest.name ?? id, style: t.textAt(small).copyWith(color: ink, fontWeight: FontWeight.w600)),
                          ],
                        ),
                    ],
                  ),
                ),
                ?putAway,
              ],
            ),
            SizedBox(height: small * 0.4),
            Text('$orgName’s notes use ${tools.length == 1 ? 'a tool' : 'tools'} the team hasn’t turned on: $said. Until then they show as plain text.', style: t.textAt(small).copyWith(color: quiet, height: 1.35)),
            SizedBox(height: small * 0.6),
            button,
          ],
        ),
      ),
    );
  }
}
