import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/note.dart';
import '../core/note_text.dart';
import '../notes/tabs/bar_parts.dart';
import 'header_pane.dart';

// What the shell draws where a screen of the web app is not ported yet. Each says that it is a stand-in and for
// what, and does the one thing the shell needs of it so the frame can be walked on a phone: a list of titles to tap,
// a note's own words, a way back. None of them is a port of anything, and each goes when its screen arrives
// (shell/app_shell.dart takes a builder for each).

/// The words every stand-in begins with, so no one takes it for the screen it stands for.
class _StandsFor extends StatelessWidget {
  const _StandsFor(this.what);
  final String what;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('xs');
    return Text(
      'PLACEHOLDER · $what',
      style: t.textAt(
        size,
        weight: 'bold',
        color: t.color('app-ink-3'),
        tracking: t.len('app-tracking-caps', em: size),
      ),
    );
  }
}

/// A row that is a word to press.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.onPressed, this.detail});
  final String label;
  final String? detail;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('sm'),
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(12)),
          padding: EdgeInsets.symmetric(vertical: t.space(2)),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: t.color('app-rule'), width: t.len('glacier-hairline')),
            ),
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textAt(t.len('app-action'), weight: 'medium', color: state.pressed || state.hovered ? t.color('glacier-text') : t.color('app-ink-2')),
                  ),
                ),
                if (detail != null) Text(detail!, style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A page that scrolls under the bar's glass, padded as every screen is: by `--app-safe-top` above, the page's
/// gutters at its sides and the home indicator below.
class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      fit: StackFit.expand,
      children: [
        ListView(padding: EdgeInsets.fromLTRB(t.len('app-gutter-start'), t.len('app-safe-top') + t.space(4), t.len('app-gutter-end'), t.len('app-safe-bottom') + t.space(6)), children: children),
        const HeaderPane(),
      ],
    );
  }
}

String _titleOf(Note note) {
  final title = noteTitle(note.body);
  return title.isEmpty ? 'Untitled' : title;
}

/// Stands in for the home page (home/HomeScreen.tsx): the notes' titles, each a way into its note, and the way to
/// the All notes grid.
class HomePlaceholder extends StatelessWidget {
  const HomePlaceholder({super.key, required this.notes, required this.onOpen, required this.onAllNotes});

  final List<Note> notes;
  final ValueChanged<String> onOpen;
  final VoidCallback onAllNotes;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Page(
      children: [
        const _StandsFor('the home page'),
        SizedBox(height: t.space(3)),
        if (notes.isEmpty) Text('No notes yet.', style: t.textAt(t.len('app-body'), color: t.color('app-ink-3'))),
        for (final note in notes) _Row(label: _titleOf(note), onPressed: () => onOpen(note.id)),
        _Row(label: 'All notes', detail: '${notes.length}', onPressed: onAllNotes),
      ],
    );
  }
}

/// Stands in for the All notes grid (notes/AllNotesScreen.tsx): every title, and with [tapes] only the notes with a
/// recording.
class AllNotesPlaceholder extends StatelessWidget {
  const AllNotesPlaceholder({super.key, required this.notes, required this.tapes, required this.onOpen});

  final List<Note> notes;
  final bool tapes;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = tapes
        ? [
            for (final note in notes)
              if (hasTape(note)) note,
          ]
        : notes;
    return _Page(
      children: [
        _StandsFor(tapes ? 'all notes, the tapes' : 'all notes'),
        SizedBox(height: t.space(3)),
        for (final note in shown) _Row(label: _titleOf(note), onPressed: () => onOpen(note.id)),
      ],
    );
  }
}

/// Stands in for a note's screen (editor/NoteScreen.tsx): the note's title, and its Markdown as it is written.
class NotePlaceholder extends StatelessWidget {
  const NotePlaceholder({super.key, required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Page(
      children: [
        const _StandsFor('a note, unformatted'),
        SizedBox(height: t.space(3)),
        Text(
          _titleOf(note),
          style: t.textAt(
            t.len('app-h1'),
            weight: 'bold',
            tracking: t.len('app-tracking-title', em: t.len('app-h1')),
          ),
        ),
        SizedBox(height: t.space(4)),
        Text(note.body, style: t.textAt(t.len('app-body'), mono: true, height: 1.6, color: t.color('app-ink-2'))),
      ],
    );
  }
}

/// Stands in for an organization's dashboard (notes/OrganizationScreen.tsx), or with [log] its audit log
/// (notes/OrganizationLog.tsx).
class OrganizationPlaceholder extends StatelessWidget {
  const OrganizationPlaceholder({super.key, required this.name, required this.log, required this.onLog});

  final String name;
  final bool log;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Page(
      children: [
        _StandsFor(log ? 'an organization’s activity' : 'an organization’s dashboard'),
        SizedBox(height: t.space(3)),
        Text(
          name,
          style: t.textAt(
            t.len('app-h1'),
            weight: 'bold',
            tracking: t.len('app-tracking-title', em: t.len('app-h1')),
          ),
        ),
        if (!log) _Row(label: 'Activity', onPressed: onLog),
      ],
    );
  }
}

/// Stands in for a screen that takes the whole window, with a way out of its own: a capture, a meeting being
/// recorded, the Academy.
class WholeScreenPlaceholder extends StatelessWidget {
  const WholeScreenPlaceholder({super.key, required this.what, required this.onDone});

  final String what;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.len('app-gutter-start'), t.len('app-inset-top') + t.space(6), t.len('app-gutter-end'), t.len('app-safe-bottom')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StandsFor(what),
              SizedBox(height: t.space(3)),
              _Row(label: 'Done', onPressed: onDone),
            ],
          ),
        ),
        const StatusScrim(),
      ],
    );
  }
}

/// Stands in for a pane of the split window: the docked notes tree (notes/NoteTree.tsx), or the aside
/// (aside/Aside.tsx).
class PanePlaceholder extends StatelessWidget {
  const PanePlaceholder({super.key, required this.what, this.notes = const [], this.onOpen});

  final String what;
  final List<Note> notes;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      padding: EdgeInsets.fromLTRB(t.space(4), t.len('app-safe-top') + t.space(4), t.space(4), t.len('app-safe-bottom') + t.space(4)),
      children: [
        _StandsFor(what),
        SizedBox(height: t.space(3)),
        if (onOpen != null)
          for (final note in notes) _Row(label: _titleOf(note), onPressed: () => onOpen!(note.id)),
      ],
    );
  }
}

/// Stands in for a card that floats over the screen under the bar: the notes' card at the start
/// (notes/NotesDrawer.tsx), the notifications' and the aside's at the end, Settings. It is where the web's floating
/// card is and the size it is (notes/FloatingCard.module.css `.card`), over a scrim a press on which closes it.
class CardPlaceholder extends StatelessWidget {
  const CardPlaceholder({super.key, required this.what, required this.onClose, this.atEnd = false, this.wide = false, this.children = const []});

  final String what;
  final VoidCallback onClose;

  /// `data-side="end"`: at the right, under the bell.
  final bool atEnd;

  /// `data-wide`: the notifications' card.
  final bool wide;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final top = t.len('app-safe-top') + t.space(2);
    final width = wide ? t.lenOf('min(26rem, calc(100vw - var(--app-safe-left) - var(--app-safe-right) - var(--glacier-space-6)))') : t.lenOf('min(20rem, calc(100vw - var(--glacier-space-10)))');
    final maxHeight = t.lenOf('calc(100vh - var(--app-inset-top) - var(--app-tabs) - var(--app-safe-bottom) - var(--glacier-space-2) - var(--glacier-space-3))');
    return Stack(
      fit: StackFit.expand,
      children: [
        // A press anywhere else on the screen closes it, and still does whatever it would have done. The bar is
        // left out: its own icon is the card's to close by.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: t.len('app-safe-top'),
          child: Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) => onClose()),
        ),
        Positioned(
          top: top,
          left: atEnd ? null : t.lenOf('calc(var(--app-safe-left) + var(--glacier-space-3))'),
          right: atEnd ? t.lenOf('calc(var(--app-safe-right) + var(--glacier-space-3))') : null,
          width: width,
          child: Semantics(
            container: true,
            label: what,
            // The card takes every press that lands in it.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: BarGlass(
                radius: t.radius('lg'),
                tint: t.colorOf('color-mix(in srgb, var(--glacier-bg) 88%, var(--glacier-text) 4%)'),
                border: BorderSide(color: t.color('glacier-border-subtle')),
                shadows: t.cssShadows('app-float-shadow'),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight < 0 ? 0 : maxHeight),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(t.space(4)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StandsFor(what),
                        SizedBox(height: t.space(2)),
                        ...children,
                        _Row(label: 'Close', onPressed: onClose),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A row of a stand-in card: a word to press.
class PlaceholderRow extends StatelessWidget {
  const PlaceholderRow({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _Row(label: label, onPressed: onPressed);
}
