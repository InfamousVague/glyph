/// A project tool's words where the tool is off: drawn as they are written, with a chip under them that turns it on
/// (docs/PM_PLUGINS.md §5; Matt, 2026-11-01, of the suite: off is "plain text plus a turn-on chip").
///
/// The chip goes under the closing run of a ```gantt, ```board, ```rules or ```form fence whose tool is off, of a
/// ```query whose source or view needs one (the query itself is left as its lines: queries.dart `QueryOptions.held`),
/// and under a ticket's front matter (or a ticket notebook's) while Tickets is off. Nothing is written into the note:
/// with the tool on the editor draws what it always drew, and the chips are gone.
///
/// Plugins cannot add to the editor, so the note's screen adds this itself (lib/root/note_desk.dart), in the slot it
/// reconfigures as the tools are switched, fed through [ToolChipHooks].
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../../core/boards/fence.dart' show closesBoardFence;
import '../../core/front_matter.dart' show frontMatterSpan;
import '../../core/project_tools.dart';
import '../../plugins/projects/tool_chip.dart';
import '../editor.dart';
import '../view/blocks.dart';
import '../view/extended.dart' show frontMatter;
import '../view/line_facts.dart' show bareFenceFacts;

/// What the note's screen gives the chips.
class ToolChipHooks {
  const ToolChipHooks({required this.on, required this.turnOn, this.where = _nowhere, this.canTurnOn = _always});

  /// Whether a tool is on where the note is: read at each drawing.
  final bool Function(String tool) on;

  /// Turns [tools] on where the note is (with what they need).
  final void Function(List<String> tools) turnOn;

  /// " for HelloTrade" in an organization's space, nothing in the person's own.
  final String Function() where;

  /// Whether a chip can turn anything on here: an organization this device can write to.
  final bool Function() canTurnOn;

  static String _nowhere() => '';
  static bool _always() => true;
}

/// A fence's opening line and its word: the tools' fences and a query.
final RegExp _opening = RegExp(r'^\s*(`{3,}|~{3,})\s*(gantt|board|rules|form|query)\b', caseSensitive: false);

final LineFact<({String fence, String word})> _openings = LineFact<({String fence, String word})>((text) {
  if (!text.contains('```') && !text.contains('~~~')) return null;
  final match = _opening.firstMatch(text);
  return match == null ? null : (fence: match.group(1)!, word: match.group(2)!.toLowerCase());
});

/// One fence's tools, where it closes: the closing line's number.
typedef _Fence = ({int to, Set<String> tools});

final DocMemo<List<_Fence>> _fences = DocMemo<List<_Fence>>((doc) {
  final openings = _openings.of(doc);
  if (openings.isEmpty) return const <_Fence>[];
  final closers = bareFenceFacts.of(doc);
  final found = <_Fence>[];
  var after = 0, closer = 0;
  for (final open in openings) {
    if (open.number <= after) continue;
    while (closer < closers.length && closers[closer].number <= open.number) {
      closer += 1;
    }
    var end = -1;
    for (var at = closer; at < closers.length; at += 1) {
      if (closesBoardFence(closers[at].fact, open.fact.fence)) {
        end = closers[at].number;
        break;
      }
    }
    if (end < 0) break;
    final Set<String> tools = switch (open.fact.word) {
      'gantt' => const {ganttTool},
      'board' => const {boardsTool},
      'rules' => const {automationsTool},
      'form' => const {formsTool},
      _ => toolsOfQuery(end > open.number + 1 ? doc.sliceString(open.to + 1, doc.line(end - 1).to) : ''),
    };
    if (tools.isNotEmpty) found.add((to: end, tools: tools));
    after = end;
  }
  return found;
});

/// The tools the front matter says the note is (a ticket, a ticket notebook, a ticket's planning and time), and the
/// line it closes on; null for none.
({int to, Set<String> tools})? _frontTools(Doc doc) {
  final front = frontMatter(doc);
  if (front == null) return null;
  final head = doc.sliceString(0, doc.line(front.to).to);
  final tools = toolsUsedIn('$head\n', frontMatterSpan('$head\n'));
  return tools.isEmpty ? null : (to: front.to, tools: tools);
}

/// A row of one chip under words whose tools are off.
class ToolChipWidget extends EditorWidget implements ClassedBlockWidget {
  const ToolChipWidget({required this.tools, required this.where, required this.press});

  final List<String> tools;
  final String where;

  /// Turns them on; null where this device cannot.
  final VoidCallback? press;

  @override
  String get className => 'cm-toolChip';

  @override
  bool eq(ToolChipWidget other) => other.where == where && (other.press == null) == (press == null) && other.tools.join(',') == tools.join(',');

  @override
  double get estimatedHeight => 34;

  @override
  bool takesPointer(PointerEvent event) => true;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: ToolChip(tools: tools, where: where, onPress: press));
}

DecorationSet _decorate(EditorState state, ToolChipHooks hooks) {
  final ranges = <Range<Decoration>>[];
  final doc = state.doc;
  // Turning a tool on writes nothing of the note's own, so a chip presses in words drawn read only too.
  final can = hooks.canTurnOn();
  void chip(int line, Set<String> used) {
    final off = [for (final id in withNeeds(used)) if (!hooks.on(id)) id];
    if (off.isEmpty) return;
    final widget = ToolChipWidget(tools: off, where: hooks.where(), press: can ? () => hooks.turnOn(off) : null);
    // Before the line after, where there is one: the front matter's lines are folded into one block, and a widget at
    // that block's end is drawn by nothing.
    ranges.add(line < doc.lines ? Decoration.widget(widget: widget, block: true, side: -1).range(doc.line(line + 1).from) : Decoration.widget(widget: widget, block: true, side: 1).range(doc.line(line).to));
  }

  if (_frontTools(doc) case final front?) chip(front.to, front.tools);
  for (final fence in _fences.of(doc)) {
    chip(fence.to, fence.tools);
  }
  return ranges.isEmpty ? Decoration.none : Decoration.set(ranges, true);
}

/// The chips, drawn again as the words change and as the slot they are in is reconfigured (a tool switched).
Extension toolChips(ToolChipHooks hooks) {
  final field = StateField.define<DecorationSet>(
    create: (state) => _decorate(state, hooks),
    update: (value, tr) => tr.docChanged || tr.reconfigured ? _decorate(tr.state, hooks) : value,
    provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field, (value) => value),
  );
  return field;
}
