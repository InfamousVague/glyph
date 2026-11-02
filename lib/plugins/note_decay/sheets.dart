/// What a decay mark opens (docs/NOTE_DECAY.md §2; Matt, 2026-11-02, the "'may be out of date' mark with the
/// reason"): the reason, then **Update with AI**, which shows the AI's edits as a diff to accept or reject and changes
/// nothing until accepted, and **Still right**, which keeps the mark away until its source changes again
/// (dismissals.dart). Every change goes through the open editor as one step its Undo takes back.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../editor/editor.dart';
import '../../editor/tickets/ticket_work.dart' show showWorkSheet;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import 'ai.dart';
import 'decay.dart';
import 'dismissals.dart';
import 'marks.dart' show decayRedraw;
import 'signals.dart';

/// The user event a decay change is made under.
const String decayUserEvent = 'input.decay';

/// What the reason's sheet was answered with.
enum DecayAnswer { update, stillRight }

/// [view]'s page made [next], as one change from where the two first differ to where they last do.
void replacePage(EditorViewLike view, String next) {
  final doc = view.state.doc.toString();
  if (doc == next) return;
  var start = 0;
  while (start < doc.length && start < next.length && doc.codeUnitAt(start) == next.codeUnitAt(start)) {
    start += 1;
  }
  var end = 0;
  while (end < doc.length - start && end < next.length - start && doc.codeUnitAt(doc.length - 1 - end) == next.codeUnitAt(next.length - 1 - end)) {
    end += 1;
  }
  view.dispatch(TransactionSpec(changes: ChangeSpec(from: start, to: doc.length - end, insert: next.substring(start, next.length - end)), effects: decayRedraw(), userEvent: decayUserEvent));
}

/// A mark tapped: its reasons, and what the person chooses (see the header).
Future<void> openDecay(BuildContext context, {required NoteDecay decay, required String noteId, required List<DecaySignal> signals, required EditorViewLike view}) async {
  final model = decay.model;
  final answer = await showWorkSheet<DecayAnswer>(context, (done) => DecayReasonSheet(signals: signals, aiName: model.ready ? model.name : null, onAnswer: done));
  if (answer == DecayAnswer.stillRight) {
    var body = view.state.doc.toString();
    for (final signal in signals) {
      body = withStillRight(body, signal);
    }
    replacePage(view, body);
    return;
  }
  if (answer != DecayAnswer.update || !context.mounted) return;
  final asked = decay.propose(noteId, view.state.doc.toString(), signals);
  final accepted = await showWorkSheet<List<DecayEdit>>(context, (done) => DecayDiffSheet(edits: asked, by: model.name, onAnswer: done));
  if (accepted == null || accepted.isEmpty) return;
  replacePage(view, applyEdits(view.state.doc.toString(), accepted));
}

/// The reasons, Update with AI and Still right.
class DecayReasonSheet extends StatelessWidget {
  const DecayReasonSheet({super.key, required this.signals, required this.aiName, required this.onAnswer});

  final List<DecaySignal> signals;

  /// Who Update with AI asks; null where no AI can be asked, and the row says so.
  final String? aiName;
  final ValueChanged<DecayAnswer?> onAnswer;

  @override
  Widget build(BuildContext context) => Sheet(
        key: const ValueKey('decay-reason'),
        label: 'May be out of date',
        onClose: () => onAnswer(null),
        children: [
          SheetTitle.text('May be out of date'),
          for (final signal in signals) SheetNote(signal.reason),
          SheetGroup(
            children: [
              SheetRow(
                key: const ValueKey('decay-update'),
                label: 'Update with AI',
                hint: aiName == null ? 'Connect an AI in Settings › AI first' : 'Asks $aiName for the edit; nothing changes until you accept it',
                disabled: aiName == null,
                onPress: aiName == null ? null : () => onAnswer(DecayAnswer.update),
              ),
              SheetRow(key: const ValueKey('decay-still-right'), label: 'Still right', hint: 'Keeps this away until it changes again', onPress: () => onAnswer(DecayAnswer.stillRight)),
            ],
          ),
        ],
      );
}

/// The AI's edits as a diff: each line as it reads struck through, what it would read under it, each chosen to be
/// accepted or not; Accept makes the chosen ones, Reject none.
class DecayDiffSheet extends StatefulWidget {
  const DecayDiffSheet({super.key, required this.edits, required this.by, required this.onAnswer});

  final Future<List<DecayEdit>> edits;
  final String by;
  final ValueChanged<List<DecayEdit>?> onAnswer;

  @override
  State<DecayDiffSheet> createState() => _DecayDiffSheetState();
}

class _DecayDiffSheetState extends State<DecayDiffSheet> {
  List<DecayEdit>? _edits;
  Object? _failed;
  final Set<int> _chosen = {};

  @override
  void initState() {
    super.initState();
    unawaited(widget.edits.then((edits) {
      if (!mounted) return;
      setState(() {
        _edits = edits;
        _chosen.addAll([for (var i = 0; i < edits.length; i++) i]);
      });
    }, onError: (Object error) {
      if (mounted) setState(() => _failed = error);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final edits = _edits;
    final chosen = [
      if (edits != null)
        for (var i = 0; i < edits.length; i++)
          if (_chosen.contains(i)) edits[i],
    ];
    return Sheet(
      key: const ValueKey('decay-diff'),
      label: 'Update with AI',
      onClose: () => widget.onAnswer(null),
      children: [
        SheetTitle.text('Update with AI'),
        if (_failed != null)
          SheetNote('${widget.by} could not suggest an edit: $_failed')
        else if (edits == null)
          SheetNote('Asking ${widget.by}…')
        else if (edits.isEmpty)
          SheetNote('${widget.by} suggests no change. The page may still be right.')
        else ...[
          SheetNote('${widget.by} suggests ${edits.length == 1 ? 'this edit' : 'these ${edits.length} edits'}. Nothing changes until you accept.'),
          for (var i = 0; i < edits.length; i++) DecayEditRow(edit: edits[i], chosen: _chosen.contains(i), onToggle: () => setState(() => _chosen.contains(i) ? _chosen.remove(i) : _chosen.add(i))),
        ],
        SheetGroup(
          children: [
            SheetRow(
              key: const ValueKey('decay-accept'),
              label: chosen.length <= 1 ? 'Accept' : 'Accept ${chosen.length} edits',
              disabled: chosen.isEmpty,
              onPress: chosen.isEmpty ? null : () => widget.onAnswer(chosen),
            ),
            SheetRow(key: const ValueKey('decay-reject'), label: 'Reject', onPress: () => widget.onAnswer(const [])),
          ],
        ),
      ],
    );
  }
}

/// One edit: the line struck through in the muted ink, its new words in the ink, and why; a tap chooses it or not.
class DecayEditRow extends StatelessWidget {
  const DecayEditRow({super.key, required this.edit, required this.chosen, required this.onToggle});

  final DecayEdit edit;
  final bool chosen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final base = DefaultTextStyle.of(context).style;
    final muted = t.color('glacier-text-muted');
    final ink = t.color('app-ink');
    final ground = t.colorOf('color-mix(in oklch, currentColor ${chosen ? 7 : 3}%, transparent)', current: ink);
    return Semantics(
      button: true,
      toggled: chosen,
      label: 'Edit: ${edit.before.trim()} becomes ${edit.after.isEmpty ? 'nothing' : edit.after.trim()}',
      onTap: onToggle,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: ValueKey<String>('decay-edit-${edit.line}'),
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Container(
            margin: EdgeInsets.symmetric(vertical: t.space(1)),
            padding: EdgeInsets.all(t.space(3)),
            decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(t.space(2))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(edit.before.trim(), style: base.copyWith(color: muted, decoration: TextDecoration.lineThrough, decorationColor: muted)),
                      SizedBox(height: t.space(1)),
                      Text(edit.after.isEmpty ? '(line removed)' : edit.after.trim(), style: base.copyWith(color: ink)),
                      if (edit.why.isNotEmpty) ...[SizedBox(height: t.space(1)), Text(edit.why, style: base.copyWith(color: muted, fontSize: (base.fontSize ?? 15) * 0.85))],
                    ],
                  ),
                ),
                SizedBox(width: t.space(2)),
                AppIcon(chosen ? Lucide.circleCheck : Lucide.circle, size: (base.fontSize ?? 15) * 1.2, color: chosen ? ink : muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
