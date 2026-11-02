/// The review of a cleanup's plan (docs/CLEANUP.md, "The review"; Matt, 2026-11-02): every suggestion grouped by pass,
/// each with its own tick, a move as `Work › Inbox → Work › Clients`, a title as `Old → New`, a merge with what goes to
/// the Trash and what the kept note gains, an edit as a line diff. Apply N applies the ticked; Apply all is the quieter
/// word beside it and never the default; Discard changes nothing.
///
/// Drawn in the settings kit's cards, on the plugin's page (cleanup_pane.dart).
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/versions_diff.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/kit/settings_type.dart' show pageText;
import 'plan.dart';

/// Each pass's glyph on the review and the page.
LucideIcon passIcon(CleanupPass pass) => switch (pass) {
      CleanupPass.sort => Lucide.folderInput,
      CleanupPass.titles => Lucide.heading,
      CleanupPass.duplicates => Lucide.copy,
      CleanupPass.tidy => Lucide.brushCleaning,
      CleanupPass.links => Lucide.tag,
      CleanupPass.stale => Lucide.archive,
    };

/// A note as the review names it.
String reviewTitle(String title) => title.trim().isEmpty ? 'Untitled' : title.trim();

/// The review (see the library doc).
class CleanupReview extends StatelessWidget {
  const CleanupReview({
    super.key,
    required this.plan,
    required this.ticked,
    required this.aiName,
    required this.onTick,
    required this.onTickPass,
    required this.onApply,
    required this.onApplyAll,
    required this.onDiscard,
    this.busy = false,
  });

  final CleanupPlan plan;
  final Set<String> ticked;
  final String aiName;
  final void Function(String id, bool on) onTick;
  final void Function(CleanupPass pass, bool on) onTickPass;
  final VoidCallback onApply;
  final VoidCallback onApplyAll;
  final VoidCallback onDiscard;

  /// Applying now: the words are greyed.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scope = plan.scope;
    final count = plan.items.length;
    final chosen = plan.items.where((i) => ticked.contains(i.id)).length;
    final big = count > CleanupPlan.bigPlan;
    final passes = [for (final pass in CleanupPass.values) if (plan.of(pass).isNotEmpty) pass];
    return Column(
      key: const ValueKey('cleanup-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: context.tokens.space(4),
      children: [
        SettingsCallout(
          key: const ValueKey('cleanup-review-head'),
          icon: const AppIcon(Lucide.listChecks, size: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: context.tokens.space(1),
            children: [
              Text(count == 0
                  ? '$aiName found nothing to change in ${scope.root.path}.'
                  : '$count ${count == 1 ? 'suggestion' : 'suggestions'} for ${scope.root.path} from $aiName. Nothing changes until you apply${big ? '; on a plan this size the edits and merges start unticked' : ''}.'),
              if (plan.stopped) const Text('Stopped before every note was read: these are what the finished asks found.'),
              if (plan.failures.isNotEmpty) Text('${plan.failures.length} of ${plan.asks} ${plan.asks == 1 ? 'ask' : 'asks'} failed: ${plan.failures.first}'),
              if (plan.dropped.isNotEmpty) Text('${plan.dropped.length} ${plan.dropped.length == 1 ? 'suggestion was' : 'suggestions were'} left out: ${plan.dropped.take(3).join('; ')}${plan.dropped.length > 3 ? '; …' : ''}.'),
            ],
          ),
        ),
        for (final pass in passes) _PassCard(plan: plan, pass: pass, ticked: ticked, onTick: onTick, onTickPass: onTickPass, busy: busy),
        PaneSection(
          children: [
            SettingRow(
              key: const ValueKey('cleanup-apply'),
              icon: const AppIcon(Lucide.check, size: 16),
              label: chosen == 0 ? 'Nothing ticked' : 'Apply $chosen ${chosen == 1 ? 'change' : 'changes'}',
              hint: const Text('Moves, titles and edits as ticked. Copies go to the Trash, stale notes to the Archive; nothing is deleted, and Undo takes the whole run back.'),
              value: RowAction(onPress: onApply, disabled: busy || chosen == 0, child: Text(busy ? 'Applying…' : 'Apply')),
            ),
            if (count > 1)
              SettingRow(
                key: const ValueKey('cleanup-apply-all'),
                label: 'Apply all $count',
                hint: Text(big ? 'Every suggestion, ticked or not. Read them first on a plan this size.' : 'Every suggestion, ticked or not.'),
                value: RowAction(onPress: onApplyAll, disabled: busy, child: const Text('Apply all')),
              ),
            SettingRow(
              key: const ValueKey('cleanup-discard'),
              icon: const AppIcon(Lucide.x, size: 16),
              label: 'Discard',
              hint: const Text('Put the plan away. Nothing changes.'),
              value: RowAction(onPress: onDiscard, disabled: busy, child: const Text('Discard')),
            ),
          ],
        ),
      ],
    );
  }
}

class _PassCard extends StatelessWidget {
  const _PassCard({required this.plan, required this.pass, required this.ticked, required this.onTick, required this.onTickPass, required this.busy});

  final CleanupPlan plan;
  final CleanupPass pass;
  final Set<String> ticked;
  final void Function(String id, bool on) onTick;
  final void Function(CleanupPass pass, bool on) onTickPass;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final items = plan.of(pass);
    final all = items.every((i) => ticked.contains(i.id));
    return PaneSection(
      title: '${pass.label} · ${items.length}',
      children: [
        SettingRow(
          key: ValueKey('cleanup-pass-${pass.name}'),
          icon: AppIcon(passIcon(pass), size: 16),
          label: all ? 'All ticked' : '${items.where((i) => ticked.contains(i.id)).length} of ${items.length} ticked',
          hint: Text(pass.about),
          control: GlacierSwitch(ariaLabel: 'Tick every ${pass.label.toLowerCase()} suggestion', checked: all, disabled: busy, onCheckedChange: (on) => onTickPass(pass, on)),
        ),
        for (final item in items) _ItemRow(item: item, plan: plan, ticked: ticked.contains(item.id), onTick: busy ? null : (on) => onTick(item.id, on)),
      ],
    );
  }
}

/// One suggestion: its tick, what it is, what it does, and why.
class _ItemRow extends StatelessWidget implements PaneRow {
  const _ItemRow({required this.item, required this.plan, required this.ticked, required this.onTick});

  final CleanupItem item;
  final CleanupPlan plan;
  final bool ticked;
  final ValueChanged<bool>? onTick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = plan.scope;
    String titleOf(String id) => reviewTitle(scope.note(id)?.title ?? '');
    String folderOf(String id) {
      if (id.startsWith('folder:')) {
        final made = plan.byId(id);
        return made is NewFolderItem ? '${scope.pathOf(made.parentId)} › ${made.name} (new)' : id;
      }
      return scope.pathOf(id);
    }

    final (String label, String change, Widget? more) = switch (item) {
      NewFolderItem(:final name, :final parentId) => ('New folder: $name', 'In ${scope.pathOf(parentId)} · ${plan.movesInto(item.id).length} ${plan.movesInto(item.id).length == 1 ? 'note goes' : 'notes go'} in', null),
      MoveItem(:final noteId, :final from, :final to) => (titleOf(noteId), '${folderOf(from)} → ${folderOf(to)}', null),
      TitleItem(:final from, :final to) => (reviewTitle(from), '→ $to', null),
      MergeItem(:final keepId, :final others) => (
          'Keep ${titleOf(keepId)}',
          '${others.length == 1 ? '${titleOf(others.single)} goes' : '${others.map(titleOf).join(', ')} go'} to the Trash; any line the kept note lacks is kept in it',
          _MergeLines(plan: plan, item: item as MergeItem),
        ),
      EditItem(:final noteId, :final before, :final after, :final tags, :final links) => (
          titleOf(noteId),
          [if (tags.isNotEmpty) 'Tags: ${tags.join(', ')}', if (links.isNotEmpty) 'Links: ${links.map((l) => '[[$l]]').join(' · ')}'].join(' · '),
          LineDiff(before: before, after: after),
        ),
      ArchiveItem(:final noteId) => (titleOf(noteId), 'Into the Archive', null),
    };
    final ink3 = t.color('app-ink-3');
    final small = pageText(t, t.fontSize('sm'), height: t.len('glacier-leading-sm'), color: t.color('app-ink-2'));
    return Semantics(
      checked: ticked,
      label: '$label${change.isEmpty ? '' : ', $change'}',
      onTap: onTick == null ? null : () => onTick!(!ticked),
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('cleanup-item-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTick == null ? null : () => onTick!(!ticked),
        child: Padding(
          padding: EdgeInsets.all(t.space(3)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: t.space(3),
            children: [
              Padding(padding: EdgeInsets.only(top: t.space(1) / 2), child: TickBox(ticked: ticked, disabled: onTick == null)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: t.space(1),
                  children: [
                    Text(label, style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink'))),
                    if (change.isNotEmpty) Text.rich(arrowed(change, small, t), style: small),
                    if (item.why.isNotEmpty) Text(item.why, style: small.copyWith(color: ink3)),
                    ?more,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [text] with each ` → ` drawn as an arrow glyph: the app's faces have no arrow of their own.
TextSpan arrowed(String text, TextStyle style, Tokens t) {
  final parts = text.split('→');
  final size = (style.fontSize ?? t.fontSize('sm')) * 0.95;
  return TextSpan(children: [
    for (var i = 0; i < parts.length; i += 1) ...[
      if (i > 0)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(padding: EdgeInsets.symmetric(horizontal: size * 0.15), child: AppIcon(Lucide.arrowRight, size: size, color: style.color)),
        ),
      TextSpan(text: parts[i].trim().isEmpty ? '' : (i > 0 ? parts[i].trimLeft() : parts[i].trimRight())),
    ],
  ]);
}

/// A tick in a box, in the ink: the review's checkbox.
class TickBox extends StatelessWidget {
  const TickBox({super.key, required this.ticked, this.disabled = false});

  final bool ticked;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.space(5);
    final ink = t.color(disabled ? 'app-ink-3' : 'app-ink');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: ticked ? ink : null,
        borderRadius: BorderRadius.circular(t.space(1) * 1.5),
        border: Border.all(color: ticked ? ink : t.color('app-ink-3'), width: 1.5),
      ),
      alignment: Alignment.center,
      child: ticked ? AppIcon(Lucide.check, size: side * 0.7, color: t.color('app-paper'), strokeWidth: 3) : null,
    );
  }
}

/// What a merge brings into the kept note: each copy's lines it lacks, the first few.
class _MergeLines extends StatelessWidget {
  const _MergeLines({required this.plan, required this.item});

  final CleanupPlan plan;
  final MergeItem item;

  @override
  Widget build(BuildContext context) {
    final keep = plan.scope.note(item.keepId);
    if (keep == null) return const SizedBox.shrink();
    final have = {for (final line in keep.body.split('\n')) if (line.trim().isNotEmpty) line.trim()};
    final gained = <String>[
      for (final id in item.others)
        for (final line in (plan.scope.note(id)?.body ?? '').split('\n').skip(1))
          if (line.trim().isNotEmpty && have.add(line.trim())) line,
    ];
    if (gained.isEmpty) return Text('The copies say nothing the kept note doesn’t.', style: pageText(context.tokens, context.tokens.fontSize('sm'), color: context.tokens.color('app-ink-3')));
    return LineDiff(before: '', after: gained.join('\n'), onlyAdded: true);
  }
}

/// A line diff of an edit (lib/core/versions_diff.dart `diffLines`): the lines taken out struck through, the lines
/// put in marked, a line of what stays round each change, at most [most] lines drawn.
class LineDiff extends StatelessWidget {
  const LineDiff({super.key, required this.before, required this.after, this.most = 14, this.onlyAdded = false});

  final String before;
  final String after;
  final int most;

  /// Only lines put in (a merge's): no context.
  final bool onlyAdded;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = diffRows(before, after, onlyAdded: onlyAdded);
    final shown = rows.take(most).toList();
    final mono = pageText(t, t.fontSize('xs'), mono: true, height: 1.45, color: t.color('app-ink-2'));
    return Container(
      key: const ValueKey('cleanup-diff'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(2)),
      decoration: BoxDecoration(color: t.color('app-paper'), borderRadius: BorderRadius.circular(t.radius('md')), border: Border.all(color: t.color('app-rule'), width: t.len('glacier-hairline'))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in shown)
            Text.rich(
              TextSpan(children: [
                TextSpan(text: switch (row.kind) { DiffRowKind.added => '+ ', DiffRowKind.removed => '− ', DiffRowKind.kept => '  ', DiffRowKind.gap => '' }),
                TextSpan(text: row.kind == DiffRowKind.gap ? '⋯' : (row.text.isEmpty ? ' ' : row.text)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: switch (row.kind) {
                DiffRowKind.added => mono.copyWith(color: t.color('app-ink'), fontWeight: t.weight('semibold'), backgroundColor: t.color('app-paper-3')),
                DiffRowKind.removed => mono.copyWith(color: t.color('app-ink-3'), decoration: TextDecoration.lineThrough),
                _ => mono.copyWith(color: t.color('app-ink-3')),
              },
            ),
          if (rows.length > shown.length) Text('… ${rows.length - shown.length} more lines', style: mono.copyWith(color: t.color('app-ink-3'))),
        ],
      ),
    );
  }
}

/// What a diff row is.
enum DiffRowKind { kept, added, removed, gap }

/// The rows of a diff as the review draws them: each change with one kept line round it, a gap where kept lines are
/// left out. [onlyAdded] draws only lines put in.
List<({DiffRowKind kind, String text})> diffRows(String before, String after, {bool onlyAdded = false}) {
  if (onlyAdded) return [for (final line in after.split('\n')) if (line.trim().isNotEmpty) (kind: DiffRowKind.added, text: line)];
  final steps = diffLines(linesOf(before), linesOf(after));
  final flat = <({DiffRowKind kind, String text})>[];
  var at = 0;
  final old = linesOf(before);
  for (final step in steps) {
    switch (step) {
      case Keep(:final count):
        for (var i = 0; i < count; i += 1) {
          flat.add((kind: DiffRowKind.kept, text: old[at + i]));
        }
        at += count;
      case Del(:final line):
        flat.add((kind: DiffRowKind.removed, text: line));
        at += 1;
      case Add(:final line):
        flat.add((kind: DiffRowKind.added, text: line));
    }
  }
  // Blank lines say nothing in a review: left out, changed or not.
  flat.removeWhere((row) => row.text.trim().isEmpty);
  // Keep one line of context either side of a change.
  final near = <int>{};
  for (var i = 0; i < flat.length; i += 1) {
    if (flat[i].kind != DiffRowKind.kept) near.addAll([i - 1, i, i + 1]);
  }
  final rows = <({DiffRowKind kind, String text})>[];
  var gap = false;
  for (var i = 0; i < flat.length; i += 1) {
    if (near.contains(i)) {
      rows.add(flat[i]);
      gap = false;
    } else if (!gap && rows.isNotEmpty) {
      rows.add((kind: DiffRowKind.gap, text: ''));
      gap = true;
    }
  }
  if (rows.isNotEmpty && rows.last.kind == DiffRowKind.gap) rows.removeLast();
  return rows;
}
