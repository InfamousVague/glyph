/// The organizations on the home page: a card for each one joined, in its colour, with how many are in it, how many
/// notes are filed in its workspace, and who is in the app now and what they are editing, or that nobody is, so every
/// card is the same three lines tall. A tap opens its dashboard. A port of `src/app/home/HomeOrganizations.tsx` and
/// HomeOrganizations.module.css. Nothing is drawn for an account in no organization.
///
/// What differs: the web reads the organizations from the account (`core/orgs/orgs.ts`) and who is here from the live
/// service (`core/live/presence.ts`); neither is ported (stage 7), so both are handed in as [HomeOrg]s. The page
/// draws the block for whatever it is given, and nothing for an empty list.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/note.dart';
import '../core/workspaces.dart';
import 'home_icons.dart';
import 'home_text.dart';

/// Someone in an organization's notes now (`Presence`, the part the home page says).
@immutable
class OrgPresence {
  const OrgPresence({required this.client, required this.handle, this.hue, this.editingNote, this.editingTitle});

  /// The device they are on: one person on two devices is here once.
  final String client;
  final String handle;
  final String? hue;

  /// The note they are editing, by id, and its title; null where they are only here.
  final String? editingNote;
  final String? editingTitle;
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
          Text(words, style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2'))),
          if (count != null) ...[SizedBox(width: t.space(2)), Text('$count', style: tabular(pageText(t, sm, color: t.color('app-ink-3'))))],
        ],
      ),
    );
  }
}

/// The organizations' cards (`src/app/home/HomeOrganizations.tsx`), for the [HomeOrg]s it is handed: the web reads
/// them from the account and the live service, which are not ported.
class HomeOrganizations extends StatelessWidget {
  const HomeOrganizations({super.key, required this.orgs, required this.notes, required this.filed, required this.onOpen});

  final List<HomeOrg> orgs;
  final List<Note> notes;

  /// Which workspace each filed note is in, by note id (`Workspaces.of`).
  final Map<String, String> filed;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (orgs.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    final gap = t.space(3);
    return Padding(
      // `.section { margin-block-start: var(--glacier-space-3) }`.
      padding: EdgeInsets.only(top: t.space(3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeHeading(mark: HomeIcon(HomeGlyph.people, size: 15, color: t.color('app-ink-2')), words: 'Organizations', count: orgs.length),
          SizedBox(height: t.space(2)),
          LayoutBuilder(
            builder: (context, box) {
              // `grid-template-columns: repeat(auto-fill, minmax(min(100%, 16rem), 1fr))`.
              final track = box.maxWidth < t.lenOf('16rem') ? box.maxWidth : t.lenOf('16rem');
              final columns = track <= 0 ? 1 : (((box.maxWidth + gap) / (track + gap)).floor()).clamp(1, 99);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row * columns < orgs.length; row += 1) ...[
                    if (row > 0) SizedBox(height: gap),
                    // A card fills its cell, so two in a row are one height even where a long name wraps in one.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var column = 0; column < columns; column += 1) ...[
                            if (column > 0) SizedBox(width: gap),
                            Expanded(child: row * columns + column < orgs.length ? _OrgCard(org: orgs[row * columns + column], notes: notes, filed: filed, onOpen: onOpen) : const SizedBox.shrink()),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OrgCard extends StatelessWidget {
  const _OrgCard({required this.org, required this.notes, required this.filed, required this.onOpen});

  final HomeOrg org;
  final List<Note> notes;
  final Map<String, String> filed;
  final ValueChanged<String> onOpen;

  /// One line for who is here: someone editing, by name, before a plain count.
  String? get _here {
    final handles = {for (final each in org.here) each.handle}.toList();
    OrgPresence? editing;
    for (final each in org.here) {
      if (each.editingNote != null) {
        editing = each;
        break;
      }
    }
    if (editing != null) {
      final title = editing.editingTitle == null || editing.editingTitle!.isEmpty ? 'a note' : editing.editingTitle!;
      return '${editing.handle} is editing $title${handles.length > 1 ? ', ${handles.length - 1} more here' : ''}';
    }
    if (handles.length == 1) return '${handles[0]} is here now';
    if (handles.length > 1) return '${handles.length} here now';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final workspace = orgWorkspaceId(org.id);
    final count = notes.where((note) => filed[note.id] == workspace && note.archivedAt == null).length;
    final here = _here;
    final meta = '${org.members == 1 ? '1 member' : '${org.members} members'} · ${count == 1 ? '1 note' : '$count notes'}';
    return GlacierScope(
      attrs: {'hue': org.hue ?? 'ink'},
      child: Builder(
        builder: (context) {
          final t = context.tokens;
          final md = t.fontSize('md'), sm = t.fontSize('sm');
          final space = t.color('app-space');
          final rem = t.lenOf('1rem');
          return GlacierPressable(
            onPressed: () => onOpen(org.id),
            semanticLabel: '${org.name}, $meta, ${here ?? 'Nobody here now'}',
            builder: (context, state) => GlacierFocusRing(
              visible: state.focused,
              offset: 3,
              radius: t.radius('lg'),
              color: t.color('app-ink'),
              child: Container(
                padding: EdgeInsets.all(t.space(4)),
                decoration: BoxDecoration(
                  // Mixed with nothing, not with the rule's grey: green mixed toward a grey came out brown.
                  color: t.colorOf('color-mix(in oklch, var(--app-space) ${state.hovered ? 10 : 6}%, transparent)'),
                  border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-space) 45%, transparent)'), width: t.len('glacier-hairline')),
                  borderRadius: BorderRadius.circular(t.radius('lg')),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 0.3 * 16),
                        child: Container(width: 0.8 * rem, height: 0.8 * rem, decoration: BoxDecoration(color: space, shape: BoxShape.circle)),
                      ),
                      SizedBox(width: t.space(3)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(org.name, style: pageText(t, md, weight: 'semibold', color: t.color('app-ink'))),
                            SizedBox(height: 0.2 * 16),
                            Text(meta, style: pageText(t, sm, color: t.color('app-ink-3'))),
                            SizedBox(height: 0.2 * 16),
                            // Always a line, said quietly when nobody is in.
                            Row(
                              children: [
                                Container(
                                  width: 0.5 * rem,
                                  height: 0.5 * rem,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: here == null ? null : space,
                                    border: here == null ? Border.all(color: t.color('app-ink-4'), width: 1.5) : null,
                                  ),
                                ),
                                SizedBox(width: 0.45 * sm),
                                Expanded(
                                  child: Text(here ?? 'Nobody here now', style: pageText(t, sm, weight: here == null ? 'regular' : 'medium', color: here == null ? t.color('app-ink-4') : space)),
                                ),
                              ],
                            ),
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
