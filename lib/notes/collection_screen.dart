/// Notes gathered by what they say, not where they are filed (the port's own, 2026-10-16; lib/shell/screen.dart
/// [ScreenCollection]): three pages behind one bar, the way home and the page's name in it.
///
/// - **Tags**: every tag in the library with how many notes carry it (lib/core/tag_index.dart), a tag inside another
///   (`#work/clients`) folded under it, the most used first or by name. A tap opens the tag's notes.
/// - **A tag**: its notes, a row each in the home page's row style (lib/home/home_rows.dart), newest first, and the
///   tags inside it to go on to. Rename gives it a new name in every note that has it, after a sheet that says how
///   many notes that changes; each changed note is written as a save from outside it is (the root's `writeNote`), and
///   the one being read through its own screen.
/// - **A smart notebook**: the notes its search finds now (lib/core/smart_notebooks.dart), in the search's order,
///   with what the search asks said under the bar, and its sheet (rename, its search, its place, Delete) from the bar.
///
/// What a page shows is the archive left out, as a search leaves it out, unless a smart notebook's search says
/// `is:archived`.
library;

import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/book.dart';
import '../core/note.dart';
import '../core/note_marks.dart';
import '../core/search_hits.dart';
import '../core/search_query.dart';
import '../core/smart_notebooks.dart';
import '../core/stored.dart';
import '../core/tag_index.dart';
import '../core/workspaces.dart';
import '../home/home_rows.dart';
import '../home/home_text.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import '../shell/header_pane.dart';
import '../shell/screen.dart' show CollectionKind;

/// How the Tags page was last ordered, on this device.
const String tagsSortKey = 'glyph-tags-sort';

/// Which of the Tags page's tags are folded, on this device.
const String tagsClosedKey = 'glyph-tags-closed';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.kind,
    this.name = '',
    required this.notes,
    required this.workspaces,
    required this.smart,
    required this.onOpen,
    required this.onBack,
    required this.onTag,
    this.onRenameTag,
    this.onEditSmart,
    this.onNoteMenu,
    this.stored,
    this.clock,
  });

  final CollectionKind kind;

  /// The tag (lower case, without its `#`), or the smart notebook's id.
  final String name;

  /// Every note a screen shows, the archive with them.
  final List<Note> notes;
  final Workspaces workspaces;
  final SmartNotebookStore smart;
  final ValueChanged<String> onOpen;
  final VoidCallback onBack;

  /// A tag's own page, from the Tags page or from a tag inside the one shown.
  final ValueChanged<String> onTag;

  /// Renames a tag in every note that has it, and answers how many were changed.
  final Future<int> Function(String from, String to)? onRenameTag;

  /// A smart notebook's sheet.
  final ValueChanged<SmartNotebook>? onEditSmart;
  final void Function(String id, Offset at)? onNoteMenu;
  final Stored? stored;
  final int Function()? clock;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late TagSort _sort = (widget.stored ?? stored).readText(tagsSortKey) == 'name' ? TagSort.name : TagSort.count;
  late Set<String> _closed = {...(widget.stored ?? stored).read<List<String>>(tagsClosedKey, const [], (parsed) => parsed is List ? [...parsed.whereType<String>()] : null)};
  bool _renaming = false;

  @override
  void initState() {
    super.initState();
    widget.smart.addListener(_redraw);
  }

  @override
  void didUpdateWidget(CollectionScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.smart, widget.smart)) {
      old.smart.removeListener(_redraw);
      widget.smart.addListener(_redraw);
    }
    if (old.name != widget.name) _renaming = false;
  }

  @override
  void dispose() {
    widget.smart.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _setSort(TagSort sort) {
    (widget.stored ?? stored).writeText(tagsSortKey, sort == TagSort.name ? 'name' : 'count');
    setState(() => _sort = sort);
  }

  void _fold(String tag) {
    final next = {..._closed};
    if (!next.remove(tag)) next.add(tag);
    (widget.stored ?? stored).write(tagsClosedKey, [...next]);
    setState(() => _closed = next);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final safeTop = t.len('app-safe-top');
    final hairline = t.len('glacier-hairline');
    final bar = safeTop + t.space(2) * 2 + t.space(8) + hairline * 2;
    final top = bar.roundToDouble() + t.space(4);
    final foot = t.len('app-safe-bottom') + t.space(10);
    final gutterStart = t.len('app-gutter-start'), gutterEnd = t.len('app-gutter-end');

    final SmartNotebook? smart = widget.kind == CollectionKind.smart ? widget.smart.byId(widget.name) : null;
    final String title;
    final List<Widget> actions;
    final List<Widget> slivers;
    switch (widget.kind) {
      case CollectionKind.tags:
        title = 'Tags';
        actions = const [];
        slivers = _tags(t);
      case CollectionKind.tag:
        title = '#${widget.name}';
        actions = [if (widget.onRenameTag != null) _BarTool(key: const ValueKey('tag-rename'), label: 'Rename #${widget.name}', icon: Lucide.pencilLine, onPressed: () => setState(() => _renaming = true))];
        slivers = _tag(t);
      case CollectionKind.smart:
        title = smart?.name ?? 'Smart notebook';
        actions = [
          if (smart != null && widget.onEditSmart != null) _BarTool(key: const ValueKey('smart-edit'), label: 'Change ${smart.name}', icon: Lucide.ellipsis, onPressed: () => widget.onEditSmart!(smart)),
        ];
        slivers = _smart(t, smart);
    }

    return ColoredBox(
      color: t.color('glacier-bg'),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomScrollView(
                key: ValueKey('collection-scroll-${widget.kind.name}'),
                slivers: [
                  SliverPadding(padding: EdgeInsetsDirectional.fromSTEB(gutterStart, top, gutterEnd, foot), sliver: SliverMainAxisGroup(slivers: slivers)),
                ],
              ),
            ),
            HeaderPane(
              child: Padding(
                key: const ValueKey('collection-bar'),
                padding: EdgeInsetsDirectional.fromSTEB(gutterStart - t.space(2), t.space(2), gutterEnd, t.space(2)),
                child: Row(
                  spacing: t.space(2),
                  children: [
                    GlacierPressable(
                      key: const ValueKey('collection-back'),
                      onPressed: widget.onBack,
                      semanticLabel: widget.kind == CollectionKind.tags ? 'Back to home' : 'Back',
                      builder: (context, state) => GlacierFocusRing(
                        visible: state.focused,
                        child: SizedBox.square(dimension: t.space(8), child: Center(child: AppIcon(Lucide.arrowLeft, size: 20, color: t.color('app-ink')))),
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
            ),
            if (_renaming && widget.kind == CollectionKind.tag && widget.onRenameTag != null)
              TagRenameSheet(
                from: widget.name,
                notes: widget.notes,
                known: tagIndex(widget.notes).names.toSet(),
                onClose: () => setState(() => _renaming = false),
                onRename: (to) async {
                  setState(() => _renaming = false);
                  await widget.onRenameTag!(widget.name, to);
                  if (mounted) widget.onTag(to.toLowerCase());
                },
              ),
          ],
        ),
      ),
    );
  }

  /// A line of quiet words over a page's notes: how many, and what they are.
  Widget _tally(Tokens t, String words, {Widget? end}) => Padding(
        padding: EdgeInsets.only(bottom: t.space(3)),
        child: Row(
          children: [
            Expanded(child: Text(words, key: const ValueKey('collection-tally'), style: tabular(pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))))),
            ?end,
          ],
        ),
      );

  Widget _empty(Tokens t, String lead, String hint) => Padding(
        padding: EdgeInsets.only(top: t.space(6)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: t.space(1),
          children: [
            Text(lead, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
            Text(hint, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
          ],
        ),
      );

  /// The notes as rows, each with its notebook's name where it is a page of one.
  Widget _rows(List<Note> notes) {
    final inBooks = bookIndex(widget.notes);
    final now = widget.clock?.call();
    return SliverList.builder(
      itemCount: notes.length,
      itemBuilder: (context, i) {
        final note = notes[i];
        final place = placeOf(inBooks, note);
        return HomeRow(
          key: ValueKey('row-${note.id}'),
          note: note,
          index: i,
          onOpen: widget.onOpen,
          now: now,
          bookName: place?.title,
          notebook: place?.book.body,
          onMenu: widget.onNoteMenu,
        );
      },
    );
  }

  List<Widget> _tags(Tokens t) {
    final index = tagIndex(widget.notes);
    final tree = index.tree(_sort);
    if (tree.isEmpty) {
      return [SliverToBoxAdapter(child: _empty(t, 'No tags yet.', 'Write #tag in a note, on any line, and it is here. #work/clients puts one tag inside another.'))];
    }
    final rows = <({TagNode node, int depth})>[];
    void add(List<TagNode> level, int depth) {
      for (final node in level) {
        rows.add((node: node, depth: depth));
        if (node.children.isNotEmpty && !_closed.contains(node.name)) add(node.children, depth + 1);
      }
    }

    add(tree, 0);
    return [
      SliverToBoxAdapter(
        child: _tally(
          t,
          index.length == 1 ? '1 tag' : '${index.length} tags',
          end: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: t.space(1),
            children: [
              _Word(key: const ValueKey('tags-by-count'), label: 'Most used', on: _sort == TagSort.count, onPressed: () => _setSort(TagSort.count)),
              _Word(key: const ValueKey('tags-by-name'), label: 'A to Z', on: _sort == TagSort.name, onPressed: () => _setSort(TagSort.name)),
            ],
          ),
        ),
      ),
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final row = rows[i];
          return _TagRow(
            key: ValueKey('tag-row-${row.node.name}'),
            node: row.node,
            depth: row.depth,
            open: !_closed.contains(row.node.name),
            onFold: row.node.children.isEmpty ? null : () => _fold(row.node.name),
            onOpen: () => widget.onTag(row.node.name),
          );
        },
      ),
    ];
  }

  List<Widget> _tag(Tokens t) {
    final index = tagIndex(widget.notes);
    final notes = [...index.notesUnder(widget.name)]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final inside = [for (final name in index.names) if (name.startsWith('${widget.name}/') && !name.substring(widget.name.length + 1).contains('/')) name]..sort();
    return [
      SliverToBoxAdapter(child: _tally(t, notes.length == 1 ? '1 note' : '${notes.length} notes')),
      if (inside.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: t.space(3)),
            child: Wrap(
              spacing: t.space(2),
              runSpacing: t.space(2),
              children: [
                for (final name in inside) _TagChip(key: ValueKey('inside-$name'), tag: name, count: index.countOf(name), onPressed: () => widget.onTag(name)),
              ],
            ),
          ),
        ),
      if (notes.isEmpty)
        SliverToBoxAdapter(child: _empty(t, 'No notes have #${widget.name}.', 'A note tagged and archived is not counted here.'))
      else
        _rows(notes),
    ];
  }

  List<Widget> _smart(Tokens t, SmartNotebook? smart) {
    if (smart == null) return [SliverToBoxAdapter(child: _empty(t, 'This smart notebook is gone.', 'It was deleted, here or on another device.'))];
    final parsed = parseSearch(smart.query);
    final archive = parsed.archived;
    final pool = [for (final note in widget.notes) if (archive || note.archivedAt == null) note];
    final found = [for (final one in findNotes(pool, smart.query, scope: SearchScope(notes: widget.notes, workspaces: widget.workspaces))) one.note];
    final said = [for (final part in parsed.parts) part.label, if (parsed.words.isNotEmpty) 'with “${parsed.words.join(' ')}”'].join(' · ');
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(bottom: t.space(2)),
          child: Text(smart.query, key: const ValueKey('smart-query-line'), style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-2'))),
        ),
      ),
      SliverToBoxAdapter(child: _tally(t, '${found.length == 1 ? '1 note' : '${found.length} notes'}${said.isEmpty ? '' : ' · $said'}')),
      if (found.isEmpty) SliverToBoxAdapter(child: _empty(t, 'Nothing matches yet.', 'A note that comes to match is here at once.')) else _rows(found),
    ];
  }
}

/// A small bare tool at the bar's end.
class _BarTool extends StatelessWidget {
  const _BarTool({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final LucideIcon icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          width: t.space(8),
          height: t.space(8),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: state.hovered ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
          child: AppIcon(icon, size: 18, strokeWidth: 2.1, color: t.color('app-ink-2')),
        ),
      ),
    );
  }
}

/// One of two orders, as All notes draws its own (`.sorts`).
class _Word extends StatelessWidget {
  const _Word({super.key, required this.label, required this.on, required this.onPressed});

  final String label;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final color = on ? t.color('app-ink') : t.color('app-ink-2');
    return GlacierPressable(
      onPressed: onPressed,
      selected: on,
      haptic: HapticKind.selection,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: 1),
          decoration: BoxDecoration(
            color: on ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null,
            border: Border.all(color: on ? t.color('glacier-border-subtle') : const Color(0x00000000), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: Text(label, maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'medium', color: color)),
        ),
      ),
    );
  }
}

/// A tag on the Tags page: its fold where it has tags inside it, its mark, its name and its count.
class _TagRow extends StatelessWidget {
  const _TagRow({super.key, required this.node, required this.depth, required this.open, required this.onFold, required this.onOpen});

  final TagNode node;
  final int depth;
  final bool open;
  final VoidCallback? onFold;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    final ink3 = t.color('app-ink-3');
    final fold = onFold;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: depth * t.space(5)),
      child: Row(
        children: [
          SizedBox(
            width: t.space(8),
            height: t.space(12),
            child: fold == null
                ? null
                : GlacierPressable(
                    onPressed: fold,
                    semanticLabel: open ? 'Fold #${node.name}' : 'Open #${node.name}',
                    builder: (context, state) => GlacierFocusRing(
                      visible: state.focused,
                      child: Center(
                        child: AnimatedRotation(
                          turns: open ? 0.25 : 0,
                          duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 140),
                          curve: t.curve('glacier-ease-out'),
                          child: AppIcon(Lucide.chevronRight, size: 15, strokeWidth: 2.2, color: ink3),
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: GlacierPressable(
              onPressed: onOpen,
              semanticLabel: '#${node.name}, ${node.count == 1 ? '1 note' : '${node.count} notes'}',
              builder: (context, state) => GlacierFocusRing(
                visible: state.focused,
                radius: 0,
                child: Container(
                  constraints: BoxConstraints(minHeight: t.space(12)),
                  padding: EdgeInsets.symmetric(horizontal: t.space(1)),
                  color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)') : null,
                  child: ExcludeSemantics(
                    child: Row(
                      spacing: t.space(2),
                      children: [
                        AppIcon(Lucide.hash, size: 15, strokeWidth: 2.2, color: ink3),
                        Expanded(
                          child: Text(node.label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, md, weight: node.own > 0 || node.children.isEmpty ? 'semibold' : 'medium', color: t.color('app-ink'))),
                        ),
                        Text('${node.count}', style: tabular(pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-3')))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tag inside the one shown, to go on to.
class _TagChip extends StatelessWidget {
  const _TagChip({super.key, required this.tag, required this.count, required this.onPressed});

  final String tag;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: '#$tag, $count',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(7)),
          padding: EdgeInsets.symmetric(horizontal: t.space(3)),
          decoration: BoxDecoration(
            color: t.colorOf(state.hovered ? 'color-mix(in oklch, var(--app-ink) 10%, transparent)' : 'color-mix(in oklch, var(--app-ink) 6%, transparent)'),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 0.5 * sm,
              children: [
                Text('#${tag.substring(tag.lastIndexOf('/') + 1)}', style: pageText(t, sm, weight: 'medium', color: t.color('app-ink-2'))),
                Text('$count', style: tabular(pageText(t, sm, color: t.color('app-ink-3')))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tag's new name, after the sheet has said how many notes it changes.
class TagRenameSheet extends StatefulWidget {
  const TagRenameSheet({super.key, required this.from, required this.notes, required this.known, required this.onClose, required this.onRename});

  final String from;

  /// Every note, the archive's too: a rename reaches them all.
  final List<Note> notes;

  /// The tags there are, for saying when a new name is one already.
  final Set<String> known;
  final VoidCallback onClose;
  final Future<void> Function(String to) onRename;

  @override
  State<TagRenameSheet> createState() => _TagRenameSheetState();
}

class _TagRenameSheetState extends State<TagRenameSheet> {
  late String _name = widget.from;
  bool _busy = false;

  /// How many notes carry the tag or a tag under it, the archive's too: what a rename changes.
  late final int _changes = [for (final note in widget.notes) if (NoteMarks.of(note).tagged(widget.from)) note].length;

  @override
  Widget build(BuildContext context) {
    final to = tidyTagName(_name);
    final valid = isTagName(to) && to != widget.from;
    final joins = valid && widget.known.contains(to.toLowerCase()) && to.toLowerCase() != widget.from;
    final counted = _changes == 1 ? '1 note' : '$_changes notes';
    final String note;
    if (!isTagName(to)) {
      note = 'A tag starts with a letter, then letters, numbers, dashes, underscores or slashes, and has no spaces.';
    } else if (joins) {
      note = '#$to is a tag already: the two become one. This changes $counted.';
    } else {
      note = 'This changes $counted, and the tags inside it with it: #${widget.from}/… becomes #$to/…';
    }
    return Sheet(
      label: 'Rename #${widget.from}',
      onClose: widget.onClose,
      children: [
        SheetTitle.text('Rename #${widget.from}'),
        SheetNote(note),
        SheetGroup(
          children: [
            SheetField(
              key: const ValueKey('tag-new-name'),
              label: 'New name',
              value: _name,
              onChange: (text) => setState(() => _name = text),
              autoFocus: true,
              autoCapitalize: TextCapitalization.none,
              autoCorrect: false,
              enterKeyHint: TextInputAction.done,
              onSubmitted: (_) => _go(to, valid),
            ),
            SheetRow(key: const ValueKey('tag-rename-go'), label: _busy ? 'Renaming…' : 'Rename in $counted', onPress: () => _go(to, valid), disabled: !valid || _busy || _changes == 0),
            SheetRow(label: 'Cancel', onPress: widget.onClose),
          ],
        ),
      ],
    );
  }

  void _go(String to, bool valid) {
    if (!valid || _busy || _changes == 0) return;
    setState(() => _busy = true);
    unawaited(widget.onRename(to));
  }
}
