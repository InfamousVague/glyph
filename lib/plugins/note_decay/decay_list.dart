/// "Pages that may be out of date" (docs/NOTE_DECAY.md §2; Matt, 2026-11-02, Note decay alerts): each page with its
/// first reason and how many more, a press opening it. Drawn on a teamspace's home (lib/orgs/ui/teamspace_home.dart),
/// on a docs notebook's index (lib/book/book_view.dart) and on the plugin's page. Nothing at all where the plugin is
/// off or no page is marked, unless [emptyWords] says what to say then (the plugin's page).
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/note.dart';
import '../../sheet/css.dart' show pageText;
import 'decay.dart';

/// The list (see the header), read from [decay], the app's where unsaid.
class DecayPagesSection extends StatelessWidget {
  const DecayPagesSection({super.key, required this.where, required this.onOpen, this.decay, this.emptyWords, this.top = 0, this.most = 8});

  /// Which pages the list is of: a teamspace's, a notebook's.
  final bool Function(Note note) where;
  /// Opens the page pressed.
  final ValueChanged<Note>? onOpen;
  final NoteDecay? decay;

  /// What is said where no page is marked; null draws nothing.
  final String? emptyWords;

  /// The room above it, where it is drawn.
  final double top;

  /// The most rows drawn; the rest counted.
  final int most;

  static const Key listKey = ValueKey<String>('decay-pages');
  static Key rowKey(String id) => ValueKey<String>('decay-page-$id');

  @override
  Widget build(BuildContext context) {
    final decay = this.decay ?? noteDecay;
    if (decay == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: decay,
      builder: (context, _) {
        final pages = decay.pages(where: where);
        if (pages.isEmpty && emptyWords == null) return const SizedBox.shrink();
        final t = context.tokens;
        final sm = t.fontSize('sm');
        final shown = pages.take(most).toList();
        return Padding(
          key: listKey,
          padding: EdgeInsets.only(top: top),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ExcludeSemantics(child: AppIcon(Lucide.clock, size: 15, color: t.color('app-ink-3'))),
                  SizedBox(width: t.space(2)),
                  Semantics(header: true, child: Text('Pages that may be out of date', style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2')))),
                ],
              ),
              SizedBox(height: t.space(2)),
              if (pages.isEmpty) Text(emptyWords!, style: pageText(t, sm, color: t.color('app-ink-3'))),
              for (final page in shown) _Row(page: page, onOpen: onOpen == null ? null : () => onOpen!(page.note)),
              if (pages.length > shown.length) Padding(padding: EdgeInsets.only(top: t.space(1)), child: Text('and ${pages.length - shown.length} more', style: pageText(t, sm, color: t.color('app-ink-3')))),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.page, required this.onOpen});
  final DecayPage page;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final title = page.title.trim().isEmpty ? 'Untitled' : page.title.trim();
    final more = page.signals.length - 1;
    final reason = more > 0 ? '${page.signals.first.reason} · $more more' : page.signals.first.reason;
    return GlacierPressable(
      key: DecayPagesSection.rowKey(page.note.id),
      onPressed: onOpen,
      semanticLabel: '$title may be out of date: $reason',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('md'),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(2)),
          decoration: BoxDecoration(color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)') : null, borderRadius: BorderRadius.circular(t.radius('md'))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink'))),
              Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, sm, color: t.color('app-ink-3'))),
            ],
          ),
        ),
      ),
    );
  }
}
