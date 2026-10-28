/// Version 5 of the header toolbar, **Labelled** (lib/shell/header_toolbar.dart): only what the screen in front of
/// you is for, and on a wide window each with its word beside its glyph, so nothing has to be guessed from a shape.
///
/// - **On a note**: Home, the sidebar's toggle and Back at the start; at the end the view (its word, Formatted or
///   Markdown, on a wide window), Share (or the note's first action where it has no Share), and More, whose menu has
///   the rest of the note's, More for this note, and the way around (Forward, the side panel, a new note).
/// - **At home**: Home and the sidebar's toggle; Search (the command palette), New, and Browse (every note), then More
///   with Back, Forward and the side panel.
/// - **Anywhere else**: Home, the sidebar's toggle and Back, whatever the screen handed the bar, and More.
///
/// Home is at the start on every screen and at every width (Matt, 2026-10-28: "Also always show the home button on
/// the top bar").
///
/// The app's own - the bell, the organizations, Settings - are behind the round button for you at the row's end, and
/// the bell is a dot on it while something is new. (What was asked had them move to the sidebar and the dock;
/// Settings is on the home page's dock already, and the sidebar is the notes' own, so they stay one press away in
/// the bar instead, behind the button, rather than reaching into either.)
///
/// Iconography: the chosen pack's **Filled** style, a size up from the other versions', in the page's ink; what is
/// on, and New, wear the accent's soft ground.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/icon_packs.dart' show IconStyle;
import '../header_toolbar.dart';
import 'grouped_row.dart' show fallbackTools;
import 'header_kit.dart';

HeaderRow labelledRow(BuildContext context, HeaderParts parts) {
  Widget filled(Widget child) => styled(context, IconStyle.filled, child);
  final wide = parts.wide;
  final List<HeaderAct> lead;
  final List<HeaderAct> shown;
  final List<HeaderAct> others;
  if (parts.onNote) {
    final second = parts.actions.where((act) => act.id == 'share').firstOrNull ?? parts.actions.firstOrNull;
    // Home first at every width, on every screen (Matt, 2026-10-28: "Also always show the home button on the top bar").
    lead = [?parts.home, ?parts.sidebar, ?parts.back];
    shown = [?parts.view, ?second];
    others = [...notShown(parts.actions, [?second]), ?parts.more, ?parts.forward, ?parts.aside, ?parts.newNote];
  } else if (parts.atHome) {
    lead = [?parts.home, ?parts.sidebar];
    shown = [?parts.search, ?parts.newNote, ?parts.allNotes];
    others = [?parts.back, ?parts.forward, ?parts.aside];
  } else {
    lead = [?parts.home, ?parts.sidebar, ?parts.back];
    shown = const [];
    others = [?parts.forward, ?parts.aside, ?parts.search, ?parts.newNote, ?parts.allNotes];
  }
  final ink = context.tokens.color('glacier-text');
  Widget glyph(HeaderAct act) => HeaderGlyph(act, size: 16, color: ink);
  return HeaderRow(
    lead: [
      filled(Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [for (final act in lead) _Labelled(act: act, fine: parts.fine, word: wide && act.id == 'back')])),
    ],
    trail: [
      ?parts.presence,
      if (!parts.onNote) ...fallbackTools(parts),
      filled(
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final act in shown) _Labelled(act: act, fine: parts.fine, word: wide, accent: act.id == 'new'),
            if (others.isNotEmpty)
              HeaderMenuButton(
                act: moreAct(),
                fine: parts.fine,
                entries: [for (final act in others) HeaderMenuAct(act, icon: glyph(act))],
                face: (context, state, open) => _LabelledFace(act: moreAct(), state: state, on: open, word: wide),
              ),
          ],
        ),
      ),
      if (parts.you.isNotEmpty) filled(_You(parts: parts)),
    ],
  );
}

/// A control with its glyph, and with [word] its word beside it.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.act, required this.fine, required this.word, this.accent = false});
  final HeaderAct act;
  final bool fine;
  final bool word;
  final bool accent;

  @override
  Widget build(BuildContext context) => HeaderPress(act: act, fine: fine, radius: 10, face: (context, state) => _LabelledFace(act: act, state: state, on: act.on, word: word, accent: accent));
}

class _LabelledFace extends StatelessWidget {
  const _LabelledFace({required this.act, required this.state, required this.on, required this.word, this.accent = false});
  final HeaderAct act;
  final PressState state;
  final bool on;
  final bool word;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    final lit = (state.hovered || state.pressed) && !state.disabled;
    final strong = on || accent;
    final color = strong ? t.color('glacier-accent-text') : (lit ? t.color('glacier-text') : t.color('glacier-text-muted'));
    final ground = strong ? t.color(lit ? 'glacier-accent-soft-hover' : 'glacier-accent-soft') : (lit ? t.color('app-paper-2') : null);
    final glyph = HeaderGlyph(act, size: 18, color: color, strokeWidth: 2);
    return withMarks(
      act,
      Container(
        height: ring,
        constraints: BoxConstraints(minWidth: ring),
        padding: word ? EdgeInsetsDirectional.only(start: t.space(2), end: t.space(3)) : EdgeInsets.zero,
        decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(10)),
        child: word
            ? Row(
                mainAxisSize: MainAxisSize.min,
                spacing: t.space(1) * 1.5,
                children: [glyph, ExcludeSemantics(child: Text(act.word.replaceAll('…', ''), style: t.text('sm', weight: 'medium', color: color)))],
              )
            : Center(child: glyph),
      ),
      rim: t.color('glacier-bg'),
      ink: t.color('glacier-text'),
      paper: t.color('app-paper'),
    );
  }
}

/// The round button for you, with the bell as its dot.
class _You extends StatelessWidget {
  const _You({required this.parts});
  final HeaderParts parts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    final act = youAct(parts);
    final ink = t.color('glacier-text');
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: HeaderMenuButton(
        act: act,
        fine: parts.fine,
        radius: 999,
        entries: youEntries(parts, icon: (act) => HeaderGlyph(act, size: 16, color: ink)),
        menuLabel: 'Notifications, organizations and Settings',
        face: (context, state, open) {
          final lit = state.hovered || state.pressed || open;
          return withMarks(
            act,
            Container(
              width: ring,
              height: ring,
              decoration: BoxDecoration(shape: BoxShape.circle, color: t.color(lit ? 'glacier-accent-soft-hover' : 'glacier-accent-soft')),
              child: Center(child: HeaderGlyph(act, size: 18, color: t.color('glacier-accent-text'))),
            ),
            rim: t.color('glacier-bg'),
            ink: ink,
            paper: t.color('app-paper'),
          );
        },
      ),
    );
  }
}
