/// The organizations on the home page: a card for each one joined, in its colour, with how many are in it, how many
/// notes are filed in its workspace, and who is in the app now and what they are editing, or that nobody is, so every
/// card is the same three lines tall. A tap opens its dashboard. A port of `src/app/home/HomeOrganizations.tsx` and
/// HomeOrganizations.module.css. Nothing is drawn for an account in no organization.
///
/// What differs: the web reads the organizations from the account (`core/orgs/orgs.ts`) and who is here from the live
/// service (`core/live/presence.ts`); neither is ported (stage 7), so both are handed in as [HomeOrg]s. The page
/// draws the block for whatever it is given, and nothing for an empty list.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/note.dart';
import '../core/workspaces.dart';
import 'home_icons.dart';
import 'home_text.dart';
import 'marks.dart' show OrgMark;

/// Someone in an organization's notes now (`Presence`, the part the home page says).
@immutable
class OrgPresence {
  const OrgPresence({required this.client, required this.handle, this.hue, this.editingNote, this.editingTitle, this.editingCanvas = false, this.editingPlace = false});

  /// The device they are on: one person on two devices is here once.
  final String client;
  final String handle;
  final String? hue;

  /// The note they are editing, by id, and its title; null where they are only here.
  final String? editingNote;
  final String? editingTitle;

  /// Whether what they are editing is a canvas (`at.kind === 'canvas'`), and whether the room knows where in it
  /// they are: their caret, or their pointer on a canvas (`at.cursor ?? at.pointer`).
  final bool editingCanvas;
  final bool editingPlace;

  @override
  bool operator ==(Object other) =>
      other is OrgPresence &&
      other.client == client &&
      other.handle == handle &&
      other.hue == hue &&
      other.editingNote == editingNote &&
      other.editingTitle == editingTitle &&
      other.editingCanvas == editingCanvas &&
      other.editingPlace == editingPlace;

  @override
  int get hashCode => Object.hash(client, handle, hue, editingNote, editingTitle, editingCanvas, editingPlace);
}

/// An organization this account has joined (`OrgRow` with `state: 'member'`), and who is in it now.
@immutable
class HomeOrg {
  const HomeOrg({required this.id, required this.name, this.hue, required this.members, this.here = const []});
  final String id;
  final String name;

  /// A workspace hue, or null for the app's own ink.
  final String? hue;

  /// How many have joined.
  final int members;
  final List<OrgPresence> here;

  /// The same organization, said the same: whoever hands the home page its organizations makes the list anew at
  /// every build, and the page asks whether anything in it moved before it draws them again.
  @override
  bool operator ==(Object other) => other is HomeOrg && other.id == id && other.name == name && other.hue == hue && other.members == members && listEquals(other.here, here);

  @override
  int get hashCode => Object.hash(id, name, hue, members, Object.hashAll(here));
}

/// The section heading the organizations and an organization's events share with the page's own
/// (HomeLayouts.module.css `.heading`): a mark, the words, how many.
class HomeHeading extends StatelessWidget {
  const HomeHeading({super.key, this.mark, required this.words, this.count});

  final Widget? mark;
  final String words;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return Semantics(
      header: true,
      label: count == null ? words : '$words, $count',
      excludeSemantics: true,
      child: Row(
        children: [
          if (mark != null) ...[mark!, SizedBox(width: t.space(2))],
          // `.heading` is a line of `line-height: normal`: 43 device pixels for its 13.47px words on a phone at
          // 2.625 (16.38px), where the engine's whole pixel is 16 and every section's notes stood a device pixel high.
          ExactLines.of(Text(words, style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2'))), normal: true, dpr: t.css.lineDpr),
          if (count != null) ...[
            SizedBox(width: t.space(2)),
            ExactLines.of(Text('$count', style: tabular(pageText(t, sm, color: t.color('app-ink-3')))), normal: true, dpr: t.css.lineDpr),
          ],
        ],
      ),
    );
  }
}

/// The organizations, under one heading, as a grid of small tiles two across: each its mark, its name, and how many
/// notes and members it has; a tap opens it. The port's own since 2026-10-16 (Matt: "the organization cards at the top
/// of the notes are a bit confusing and large, change it to just say organizations with the header and then simple
/// 2x2 grids of a smaller version of the card"): the web's cards (`src/app/home/HomeOrganizations.tsx`) were as wide
/// as the page and said who was in the app now, which the organization's own page still says.
class HomeOrganizations extends StatelessWidget {
  const HomeOrganizations({super.key, required this.orgs, required this.notes, required this.filed, required this.onOpen});

  final List<HomeOrg> orgs;
  final List<Note> notes;

  /// Which workspace each filed note is in, by note id (`Workspaces.of`).
  final Map<String, String> filed;
  final ValueChanged<String> onOpen;

  /// Tiles in a row.
  static const int columns = 2;

  @override
  Widget build(BuildContext context) {
    if (orgs.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    final gap = t.space(2);
    return Padding(
      // `.section { margin-block-start: var(--glacier-space-3) }`.
      padding: EdgeInsets.only(top: t.space(3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeHeading(mark: HomeIcon(HomeGlyph.people, size: 15, color: t.color('app-ink-2')), words: 'Organizations'),
          SizedBox(height: t.space(2)),
          for (var row = 0; row * columns < orgs.length; row += 1) ...[
            if (row > 0) SizedBox(height: gap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < columns; column += 1) ...[
                  if (column > 0) SizedBox(width: gap),
                  Expanded(
                    child: row * columns + column < orgs.length
                        ? OrgTile(org: orgs[row * columns + column], notes: notes, filed: filed, onOpen: onOpen)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One organization's tile: its mark on a wash of its hue, its name on one line, and "12 notes · 3 members" under it.
class OrgTile extends StatelessWidget {
  const OrgTile({super.key, required this.org, required this.notes, required this.filed, required this.onOpen});

  final HomeOrg org;
  final List<Note> notes;
  final Map<String, String> filed;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final workspace = orgWorkspaceId(org.id);
    final count = notes.where((note) => filed[note.id] == workspace && note.archivedAt == null).length;
    final meta = '${count == 1 ? '1 note' : '$count notes'} · ${org.members == 1 ? '1 member' : '${org.members} members'}';
    return GlacierScope(
      attrs: {'hue': org.hue ?? 'ink'},
      child: Builder(
        builder: (context) {
          final t = context.tokens;
          final md = t.fontSize('md'), sm = t.fontSize('sm'), xs = t.fontSize('xs');
          final space = t.color('app-space');
          final markBox = 2 * sm;
          return GlacierPressable(
            onPressed: () => onOpen(org.id),
            semanticLabel: '${org.name}, $meta',
            builder: (context, state) => GlacierFocusRing(
              visible: state.focused,
              offset: 3,
              radius: t.radius('md'),
              color: t.color('app-ink'),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2) + 2),
                decoration: BoxDecoration(
                  // Mixed with nothing, not with the rule's grey: green mixed toward a grey came out brown.
                  color: t.colorOf('color-mix(in oklch, var(--app-space) ${state.hovered || state.pressed ? 10 : 5}%, transparent)'),
                  border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-space) 35%, transparent)'), width: t.len('glacier-hairline')),
                  borderRadius: BorderRadius.circular(t.radius('md')),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Container(
                        width: markBox,
                        height: markBox,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.colorOf('color-mix(in oklch, var(--app-space) 16%, transparent)'),
                          borderRadius: BorderRadius.circular(t.radius('sm')),
                        ),
                        child: OrgMark(em: sm, color: space),
                      ),
                      SizedBox(width: t.space(2) + 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(org.name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, md, weight: 'semibold', color: t.color('app-ink'))),
                            const SizedBox(height: 1),
                            Text(meta, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: tabular(pageText(t, xs, color: t.color('app-ink-3')))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
