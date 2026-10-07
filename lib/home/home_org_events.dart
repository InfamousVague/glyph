/// What has happened lately in the organization the home page is filtered to: who is editing what right now, the
/// notes of its workspace as they change, and the team's news, in one list, newest first. Docked to the right of the
/// notes on a wide page, and over them on a narrow one. A note's line opens the note; the foot opens the
/// organization's dashboard. A port of `src/app/home/HomeOrgEvents.tsx` and the card's part of
/// HomeOrgEvents.module.css (the split beside the notes is the page's, `home_screen.dart`).
///
/// What differs: who is here and the team's news come from the live service and the notifications' feed on the web
/// (`core/live/presence.ts`, `core/notifications/feed.ts`), which are stage 7; here they are handed in, the news as
/// [OrgNews] already said in words. A piece of news wears its kind's colour as a dot, where the web draws the kind's
/// own mark (`notes/orgNews.tsx`).
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/widgets.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/workspaces.dart';
import '../notes/when.dart';
import 'home_icons.dart';
import 'home_organizations.dart';
import 'home_text.dart';

/// A piece of an organization's news, as its sentence (`sentenceOf`): who joined, left, a new role, a rename.
@immutable
class OrgNews {
  const OrgNews({required this.id, required this.at, required this.words, this.hue});
  final String id;
  final int at;
  final String words;

  /// The colour its kind wears (`KIND_HUES`).
  final String? hue;
}

/// How many lines the card shows (`MOST`).
const int orgEventsMost = 8;

/// The card of what has happened lately in an organization (`src/app/home/HomeOrgEvents.tsx`), from who is here and
/// the news it is handed: the web reads both from services that are not ported. It does not stick as the page
/// scrolls, and a piece of news wears a dot of its kind's colour where the web draws the kind's own mark.
class HomeOrgEvents extends StatelessWidget {
  const HomeOrgEvents({
    super.key,
    required this.orgId,
    required this.name,
    required this.notes,
    required this.filed,
    this.here = const [],
    this.news = const [],
    required this.onOpenNote,
    required this.onOpen,
    this.now,
  });

  final String orgId;
  final String name;
  final List<Note> notes;
  final Map<String, String> filed;
  final List<OrgPresence> here;
  final List<OrgNews> news;
  final ValueChanged<String> onOpenNote;
  final ValueChanged<String> onOpen;
  final int? now;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final workspace = orgWorkspaceId(orgId);
    final ink3 = t.color('app-ink-3');
    final editing = <_Line>[
      for (final each in here)
        if (each.editingNote != null)
          _Line(
            key: 'live-${each.client}',
            at: 0,
            words: '${each.handle} is editing ${each.editingTitle == null || each.editingTitle!.isEmpty ? 'a note' : each.editingTitle}',
            note: each.editingNote,
            live: true,
            dot: each.hue ?? 'ink',
          ),
    ];
    final rest = <_Line>[
      for (final note in notes)
        if (filed[note.id] == workspace && note.archivedAt == null)
          _Line(key: 'note-${note.id}', at: note.updatedAt, words: '${noteTitle(note.body).isEmpty ? 'An untitled note' : noteTitle(note.body)} changed', note: note.id),
      for (final each in news) _Line(key: 'news-${each.id}', at: each.at, words: each.words, dot: each.hue),
    ];
    final ordered = rest.indexed.toList()
      ..sort((a, b) {
        final by = b.$2.at.compareTo(a.$2.at);
        return by != 0 ? by : a.$1.compareTo(b.$1);
      });
    final lines = [...editing, for (final (_, line) in ordered) line].take(orgEventsMost).toList();
    final hairline = t.len('glacier-hairline');

    return Semantics(
      container: true,
      label: 'Recent in $name',
      explicitChildNodes: true,
      child: Container(
        padding: EdgeInsets.all(t.space(4)),
        decoration: BoxDecoration(
          color: t.colorOf('color-mix(in oklch, var(--app-ink) 3%, transparent)'),
          border: Border.all(color: t.color('app-rule'), width: hairline),
          borderRadius: BorderRadius.circular(t.radius('lg')),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            HomeHeading(mark: HomeIcon(HomeGlyph.activity, size: 15, color: t.color('app-ink-2')), words: 'Recent in $name'),
            SizedBox(height: t.space(2)),
            if (lines.isEmpty)
              Text('Nothing has happened here yet.', style: pageText(t, sm, color: ink3))
            else
              for (final (at, line) in lines.indexed)
                Container(
                  padding: EdgeInsets.symmetric(vertical: t.space(2)),
                  decoration: BoxDecoration(border: at == lines.length - 1 ? null : Border(bottom: BorderSide(color: t.color('app-rule'), width: hairline))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: t.lenOf('1.1rem'),
                        child: Center(
                          child: line.dot != null
                              ? GlacierScope(
                                  attrs: {'hue': line.dot!},
                                  child: Builder(
                                    builder: (context) => Container(
                                      width: t.lenOf('0.5rem'),
                                      height: t.lenOf('0.5rem'),
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: context.tokens.colorOf('var(--app-space, var(--app-ink))')),
                                    ),
                                  ),
                                )
                              : HomeIcon(HomeGlyph.note, size: 15, color: ink3),
                        ),
                      ),
                      SizedBox(width: t.space(2)),
                      Expanded(
                        child: line.note == null
                            ? Text(line.words, style: pageText(t, sm, weight: line.live ? 'medium' : 'regular', color: line.live ? t.color('app-ink') : t.color('app-ink-2')))
                            : GlacierPressable(
                                onPressed: () => onOpenNote(line.note!),
                                semanticLabel: line.words,
                                builder: (context, state) => GlacierFocusRing(
                                  visible: state.focused,
                                  radius: 0,
                                  color: t.color('app-ink'),
                                  child: ExcludeSemantics(
                                    child: Text(
                                      line.words,
                                      style: pageText(t, sm, weight: line.live ? 'medium' : 'regular', color: line.live ? t.color('app-ink') : t.color('app-ink-2'))
                                          .copyWith(decoration: state.hovered ? TextDecoration.underline : TextDecoration.none),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      SizedBox(width: t.space(2)),
                      Text(line.live ? 'now' : when(line.at, now), softWrap: false, style: pageText(t, t.fontSize('xs'), color: ink3)),
                    ],
                  ),
                ),
            SizedBox(height: t.space(2)),
            Align(alignment: AlignmentDirectional.centerStart, child: AppWord(onPressed: () => onOpen(orgId), child: Text('Open $name'))),
          ],
        ),
      ),
    );
  }
}

class _Line {
  const _Line({required this.key, required this.at, required this.words, this.note, this.live = false, this.dot});
  final String key;
  final int at;
  final String words;
  final String? note;
  final bool live;

  /// A hue for a dot in place of the page's mark: who is editing, or a piece of news in its kind's colour.
  final String? dot;
}
