/// The workspaces, in a row under a list's bar, once there is one. A port of `src/app/notes/WorkspaceBar.tsx` with
/// WorkspaceBar.module.css.
///
/// Each by name, then + for another. A tap chooses one and the list shows its notes; a tap on the one already chosen
/// goes back to every note (there is no All since 2026-10-19). Held, a pill opens its workspace to rename or remove
/// (lib/notes/workspace_sheet.dart), where its colour is chosen too, or, for an organization's workspace, which wears
/// a small mark before its name, the organization's own screen.
/// Nothing at all while there are no workspaces, so a list that never uses them looks as it always did.
///
/// Outlined words a step smaller than the rows, so the row reads as a filter and not as more notes; the chosen one is
/// solid, in its own colour. The row scrolls sideways past the gutter rather than wrapping, so it stays one line
/// however many there are.
///
/// What differs:
/// - The row's `margin: 0 0 var(--glacier-space-5)` is [WorkspaceBar.marginBelow], for the page that lays it out to
///   put under it: on the page that margin collapses with the next block's own, which only the page can know.
/// - The workspaces are a [WorkspaceStore] handed in, where the page's hook read the app's own.
/// - A wheel turned over the row (`scrollSideways`) scrolls it as any Flutter scroller does under a mouse.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/workspaces.dart';
import '../home/home_parts.dart';
import '../home/marks.dart';
import 'folder_drag.dart';

/// The workspaces as a row of pills (`src/app/notes/WorkspaceBar.tsx`). The row's bottom margin is the caller's
/// ([marginBelow]) and the workspaces are handed in; nothing else differs.
class WorkspaceBar extends StatelessWidget {
  const WorkspaceBar({super.key, required this.store, required this.onManage, this.onOrganization});

  final WorkspaceStore store;

  /// A workspace's pill held, to rename or remove it; null for the +, a new one.
  final ValueChanged<Workspace?> onManage;

  /// An organization's own pill held: its own screen. Absent, its sheet, as any workspace's.
  final ValueChanged<String>? onOrganization;

  /// `margin: 0 0 var(--glacier-space-5)`: the air under the row.
  static double marginBelow(Tokens t) => t.space(5);

  /// A pill's height: `min-block-size: 2rem`, or its word's line and the ring of `0.6em` round it where that is more.
  static double pillHeight(Tokens t) => math.max(t.lenOf('2rem'), 2.2 * t.fontSize('sm') + 2);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Workspaces>(
      valueListenable: store,
      builder: (context, spaces, _) {
        if (spaces.list.isEmpty) return const SizedBox.shrink();
        final t = context.tokens;
        final start = t.len('app-gutter-start'), end = t.len('app-gutter-end');
        final current = spaces.current;
        final row = SingleChildScrollView(
          key: const ValueKey('workspace-bar'),
          scrollDirection: Axis.horizontal,
          // `padding-block: 2px; padding-inline: var(--app-gutter-start) var(--app-gutter-end)`
          padding: EdgeInsetsDirectional.fromSTEB(start, 2, end, 2),
          child: Row(
            // `align-items: center; gap: var(--glacier-space-2)`: each pill at its own height.
            spacing: t.space(2),
            children: [
              // No All (Matt, 2026-10-19: "remove the "all" option just use list or icon"): with none chosen the page is
              // every note, and the chosen pill tapped again goes back to that.
              for (final workspace in spaces.list)
                GlacierScope(
                  // Its hue, if it has one: the pill is drawn in it (ink.css `[data-hue]`).
                  attrs: {'hue': workspace.hue ?? 'ink'},
                  // A note or a folder carried onto the pill goes into that workspace, as onto its folder
                  // (lib/notes/folder_drag.dart). The pill is not carried itself: holding it opens its sheet.
                  child: FolderDropZone(
                    key: ValueKey('drop-space-${workspace.id}'),
                    store: store,
                    target: workspace.id,
                    decorate: true,
                    radius: t.radius('full'),
                    builder: (context, _) => _Pill(
                      key: ValueKey('space-${workspace.id}'),
                      label: workspace.name,
                      // Marked as the team's in an organization's own workspace and in every folder under it (GHST-107).
                      org: orgOfWorkspace(spaces.list, workspace.id) != null,
                      pressed: current?.id == workspace.id,
                      onPressed: () => store.chooseWorkspace(current?.id == workspace.id ? null : workspace.id),
                      // Held: the organization's own pill opens the organization; any other its sheet, to rename,
                      // recolour or remove it (a second tap did this while there was an All to go back by).
                      onLongPress: () {
                        final org = orgIdOf(workspace.id);
                        final toOrg = onOrganization;
                        if (org != null && toOrg != null) return toOrg(org);
                        onManage(workspace);
                      },
                    ),
                  ),
                ),
              _Pill(key: const ValueKey('space-add'), add: true, said: 'New workspace', onPressed: () => onManage(null)),
            ],
          ),
        );
        // Out to the edge of the column it scrolls in, both ends:
        // `margin-inline: calc(-1 * var(--app-gutter-start)) calc(-1 * var(--app-gutter-end))`.
        return Semantics(
          container: true,
          label: 'Workspaces',
          child: SizedBox(
            height: pillHeight(t) + 4,
            child: LayoutBuilder(
              builder: (context, box) => OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                minWidth: box.maxWidth + start + end,
                maxWidth: box.maxWidth + start + end,
                child: Transform.translate(offset: Offset(Directionality.of(context) == TextDirection.rtl ? start : -start, 0), child: row),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Inter's ascent and descent, as a share of its size (hhea: 1984 and 494 of 2048), as lib/home/home_text.dart has
/// them.
const double _interAscent = 1984 / 2048, _interDescent = 494 / 2048;

/// Where a line of Inter's baseline falls in a line box exactly its font size tall (`line-height: 1`), as Chromium
/// lays it: the face's ascent and descent each rounded to a whole pixel, and the half of the leading above the
/// baseline (negative here, the line being shorter than the face) rounded down. Flutter puts the same line's
/// baseline a pixel and a half lower (measured on the pills: the page's "All" stands at 132 to 141.5, Flutter's own
/// at 133.5 to 143).
double _baselineInLine(double size) {
  final ascent = (_interAscent * size).roundToDouble(), descent = (_interDescent * size).roundToDouble();
  return ascent + ((size - ascent - descent) / 2).floorToDouble();
}

/// `.space`: one pill, and `.spaceAdd`, the + for another.
class _Pill extends StatelessWidget {
  const _Pill({super.key, this.label = '', this.said, this.pressed, this.org = false, this.add = false, required this.onPressed, this.onLongPress});

  final String label;
  final String? said;

  /// `aria-pressed`; null for the +, which is not a choice.
  final bool? pressed;
  final bool org;
  final bool add;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = pressed ?? false;
    // `.spaceAdd { font-size: var(--glacier-font-size-md) }`, else `font-size: var(--glacier-font-size-sm)`.
    final size = add ? t.fontSize('md') : t.fontSize('sm');
    return GlacierPressable(
      onPressed: onPressed,
      onLongPress: onLongPress,
      toggled: pressed,
      haptic: HapticKind.selection,
      semanticLabel: said,
      builder: (context, state) {
        // `color: var(--app-space, var(--app-ink-2))`; `.space:active { color: var(--app-ink) }`;
        // `[aria-pressed='true'] { color: var(--app-paper) }`.
        final color = on ? t.color('app-paper') : (state.pressed ? t.color('app-ink') : t.colorOf('var(--app-space, var(--app-ink-2))'));
        return GlacierFocusRing(
          visible: state.focused,
          child: Container(
            // `min-block-size: 2rem`; the + is `inline-size: 2rem; padding: 0`, a round button the size of a pill.
            constraints: BoxConstraints(minHeight: t.lenOf('2rem'), minWidth: add ? t.lenOf('2rem') : 0, maxWidth: add ? t.lenOf('2rem') : double.infinity),
            // An even ring of space round the word, in ems so it holds at every text size: `padding: 0.6em`.
            padding: add ? EdgeInsets.zero : EdgeInsets.all(0.6 * size),
            decoration: BoxDecoration(
              // `[aria-pressed='true'] { background: var(--app-space, var(--app-ink)) }`
              color: on ? t.colorOf('var(--app-space, var(--app-ink))') : null,
              // `border: 1px solid color-mix(in oklch, var(--app-space, var(--app-ink-3)) 55%, transparent)`
              border: Border.all(color: on ? t.colorOf('var(--app-space, var(--app-ink))') : t.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink-3)) 55%, transparent)'), width: 1),
              borderRadius: BorderRadius.circular(t.radius('full')),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (add)
                  DrawnIconView(AppIcons.plus, size: size, color: color)
                else ...[
                  if (org) OrgMark(em: size, color: color),
                  // `font-weight: medium; line-height: 1; white-space: nowrap`: the line box pinned to the words.
                  CssLines(
                    lineHeight: size,
                    above: _baselineInLine(size),
                    child: Text(label, maxLines: 1, softWrap: false, style: t.textAt(size, weight: 'medium', color: color, height: 1)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
