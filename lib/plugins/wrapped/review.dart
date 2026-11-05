/// Wrapped's review, after the story (docs/WRAPPED.md, "The review"; Matt, 2026-11-05: "unfinished items which we can
/// chose to check off or remove from the list, suggested reorginizations and more"): a list for each kind of thing
/// found, every item with its own buttons, and nothing changed but by a press. Each press says what it did with Undo
/// (actions.dart).
///
/// - **Unfinished to-dos**, the oldest note's first, each its line as written and its note: Check off, Remove, Keep,
///   Open. Ticked together they go as one (advanced, or behind More in Simple).
/// - **Stale notes**: Archive, Trash, Later, Keep.
/// - **Tidying**: moves into folders, new folders, merges of near-duplicates, each saying what it would do: Apply,
///   Dismiss.
/// - **Links to add**: Link, Dismiss.
/// - **What may be out of date**: the contradiction finder's own findings with its own Mark superseded and Not a
///   conflict, where that plugin is on.
///
/// In Simple (`Preferences.simple`) the to-dos and stale notes show, and the rest waits behind More, which opens in
/// place.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/note_text.dart' show noteTitle;
import '../../core/preferences.dart' show preferences;
import '../../core/workspaces.dart' show workspacePathName;
import '../../settings/kit/settings_kit.dart';
import '../contradictions/manifest.dart' as contradictions;
import '../registry.dart' show plugins;
import 'actions.dart';
import 'service.dart';
import 'state.dart';
import 'todos.dart' show lineOfTodo;

/// How the app opens a note at a line (from 0): the root's. Null where nothing can (a test).
void Function(String noteId, int? line)? wrappedOpenNote;

/// How many of a list are shown before Show all.
const int reviewShown = 12;

class WrappedReview extends StatefulWidget {
  const WrappedReview({super.key, required this.service, this.simple, this.openNote});

  final WrappedService service;

  /// Simple mode, the preference's unless a test says.
  final bool? simple;

  /// Opens a note, [wrappedOpenNote] unless given.
  final void Function(String noteId, int? line)? openNote;

  @override
  State<WrappedReview> createState() => _WrappedReviewState();
}

class _WrappedReviewState extends State<WrappedReview> {
  bool _more = false;
  final Set<String> _all = {};
  final Set<String> _ticked = {};
  String? _said;
  String? _undo;
  bool _busy = false;

  WrappedService get _service => widget.service;

  Future<void> _press(Future<WrappedDone> Function() run, String Function(int done) words) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final done = await run();
      if (!mounted) return;
      setState(() {
        _said = [words(done.done), if (done.skipped.isNotEmpty) 'Left as it was: ${done.skipped.join('; ')}.'].join(' ');
        _undo = done.record?.id;
        _ticked.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _quiet(VoidCallback run, String words) {
    run();
    setState(() {
      _said = words;
      _undo = null;
      _ticked.clear();
    });
  }

  Future<void> _undoLast() async {
    final id = _undo;
    if (id == null) return;
    final said = await _service.undo(id);
    if (mounted) {
      setState(() {
        _said = said;
        _undo = null;
      });
    }
  }

  void Function(String noteId, int? line)? get _open => widget.openNote ?? wrappedOpenNote;

  String _plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Listenable.merge([_service, preferences, plugins]), builder: (context, _) => _page(context));

  Widget _page(BuildContext context) {
    final simple = widget.simple ?? preferences.value.simple;
    final full = !simple || _more;
    final todos = _service.todos;
    final stale = _service.stale;
    final suggestions = _service.suggestions;
    final tidy = [for (final s in suggestions) if (s.kind != SuggestionKind.link) s];
    final links = [for (final s in suggestions) if (s.kind == SuggestionKind.link) s];
    final runner = plugins.isEnabled(contradictions.manifest.id) ? _service.contradictions : null;
    final findings = runner?.open ?? const [];
    final t = context.tokens;
    final picked = [for (final row in todos) if (_ticked.contains('todo:${row.todo.key}')) row.todo];
    final pickedNotes = [for (final row in stale) if (_ticked.contains('stale:${row.note.id}')) row.note.id];
    return PaneBody(
      children: [
        if (_said != null)
          SettingsCallout(
            key: const ValueKey('wrapped-said'),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: t.space(2),
              children: [Text(_said!), if (_undo != null) RowAction(key: const ValueKey('wrapped-undo'), onPress: () => unawaited(_undoLast()), child: const Text('Undo'))],
            ),
          ),
        PaneSection(
          key: const ValueKey('wrapped-todos'),
          title: 'Unfinished to-dos',
          description: Text(todos.isEmpty ? 'Every to-do in your notes is done.' : '${_plural(todos.length, 'open to-do')}, the oldest notes first.'),
          footer: full && picked.isNotEmpty
              ? Wrap(
                  spacing: t.space(2),
                  children: [
                    RowAction(key: const ValueKey('wrapped-todos-check-picked'), onPress: () => unawaited(_press(() => _service.checkOff(picked), (n) => '${_plural(n, 'to-do')} checked off.')), child: Text('Check off ${picked.length}')),
                    RowAction(key: const ValueKey('wrapped-todos-remove-picked'), onPress: () => unawaited(_press(() => _service.removeTodos(picked), (n) => '${_plural(n, 'to-do')} removed.')), child: Text('Remove ${picked.length}')),
                    RowAction(key: const ValueKey('wrapped-todos-keep-picked'), onPress: () => _quiet(() => _service.keepTodos(picked), 'Kept as they are.'), child: Text('Keep ${picked.length}')),
                  ],
                )
              : null,
          children: [
            if (todos.isEmpty) const SettingRow(key: ValueKey('wrapped-todos-none'), icon: AppIcon(Lucide.squareCheckBig, size: 18), label: 'Nothing unfinished'),
            for (final row in _all.contains('todos') ? todos : todos.take(reviewShown))
              SettingRow(
                key: ValueKey('wrapped-todo-${row.todo.key}'),
                icon: full
                    ? Pick(
                        checked: _ticked.contains('todo:${row.todo.key}'),
                        label: 'Choose this to-do',
                        onPress: () => setState(() => _ticked.contains('todo:${row.todo.key}') ? _ticked.remove('todo:${row.todo.key}') : _ticked.add('todo:${row.todo.key}')),
                      )
                    : const AppIcon(Lucide.square, size: 18),
                label: row.todo.words,
                layout: SettingRowLayout.stacked,
                hint: Text(_inNote(row), maxLines: 3, overflow: TextOverflow.ellipsis),
                control: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: t.space(2),
                  children: [
                    RowAction(key: const ValueKey('todo-check'), onPress: () => unawaited(_press(() => _service.checkOff([row.todo]), (_) => 'Checked off.')), child: const Text('Check off')),
                    RowAction(key: const ValueKey('todo-remove'), onPress: () => unawaited(_press(() => _service.removeTodos([row.todo]), (_) => 'Removed from its note.')), child: const Text('Remove')),
                    if (full) RowAction(key: const ValueKey('todo-keep'), onPress: () => _quiet(() => _service.keepTodos([row.todo]), 'Kept as it is.'), child: const Text('Keep')),
                    if (_open != null) RowAction(key: const ValueKey('todo-open'), onPress: () => _open!(row.todo.noteId, row.todo.line), child: const Text('Open')),
                  ],
                ),
              ),
            if (!_all.contains('todos') && todos.length > reviewShown)
              SettingRow(key: const ValueKey('wrapped-todos-all'), label: 'Show all ${todos.length}', onPress: () => setState(() => _all.add('todos'))),
          ],
        ),
        PaneSection(
          key: const ValueKey('wrapped-stale'),
          title: 'Stale notes',
          description: Text(stale.isEmpty ? 'Nothing looks stale.' : 'Archived or put in the Trash, each can be brought back.'),
          footer: full && pickedNotes.isNotEmpty
              ? Wrap(
                  spacing: t.space(2),
                  children: [
                    RowAction(key: const ValueKey('wrapped-stale-archive-picked'), onPress: () => unawaited(_press(() => _service.archive(pickedNotes), (n) => '${_plural(n, 'note')} archived.')), child: Text('Archive ${pickedNotes.length}')),
                    RowAction(key: const ValueKey('wrapped-stale-trash-picked'), onPress: () => unawaited(_press(() => _service.putInTrash(pickedNotes), (n) => '${_plural(n, 'note')} put in the Trash.')), child: Text('Trash ${pickedNotes.length}')),
                  ],
                )
              : null,
          children: [
            if (stale.isEmpty) const SettingRow(key: ValueKey('wrapped-stale-none'), icon: AppIcon(Lucide.archive, size: 18), label: 'Nothing stale'),
            for (final row in _all.contains('stale') ? stale : stale.take(reviewShown))
              SettingRow(
                key: ValueKey('wrapped-stale-${row.note.id}'),
                icon: full
                    ? Pick(
                        checked: _ticked.contains('stale:${row.note.id}'),
                        label: 'Choose this note',
                        onPress: () => setState(() => _ticked.contains('stale:${row.note.id}') ? _ticked.remove('stale:${row.note.id}') : _ticked.add('stale:${row.note.id}')),
                      )
                    : const AppIcon(Lucide.archive, size: 18),
                label: row.title.trim().isEmpty ? 'Untitled' : row.title.trim(),
                layout: SettingRowLayout.stacked,
                hint: Text(row.why),
                control: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: t.space(2),
                  children: [
                    RowAction(key: const ValueKey('stale-archive'), onPress: () => unawaited(_press(() => _service.archive([row.note.id]), (_) => 'Archived.')), child: const Text('Archive')),
                    RowAction(key: const ValueKey('stale-trash'), onPress: () => unawaited(_press(() => _service.putInTrash([row.note.id]), (_) => 'Put in the Trash.')), child: const Text('Trash')),
                    if (full) RowAction(key: const ValueKey('stale-later'), onPress: () => _quiet(() => _service.later([row.note.id]), 'Put off for a month; it is read again with your next Wrapped.'), child: const Text('Later')),
                    RowAction(key: const ValueKey('stale-keep'), onPress: () => _quiet(() => _service.keepNotes([row.note.id]), 'Kept as it is.'), child: const Text('Keep')),
                    if (_open != null) RowAction(key: const ValueKey('stale-open'), onPress: () => _open!(row.note.id, null), child: const Text('Open')),
                  ],
                ),
              ),
            if (!_all.contains('stale') && stale.length > reviewShown)
              SettingRow(key: const ValueKey('wrapped-stale-all'), label: 'Show all ${stale.length}', onPress: () => setState(() => _all.add('stale'))),
          ],
        ),
        if (full) ...[
          PaneSection(
            key: const ValueKey('wrapped-tidy'),
            title: 'Suggested tidying',
            description: Text(tidy.isEmpty ? (_service.state.made ? 'Nothing to tidy.' : 'Make your Wrapped to see what your AI suggests.') : 'Each says what it would do. Nothing changes until you press Apply, and each can be undone.'),
            children: [for (final s in tidy) _suggestionRow(context, s)],
          ),
          PaneSection(
            key: const ValueKey('wrapped-links'),
            title: 'Links to add',
            description: Text(links.isEmpty ? 'No links to suggest.' : 'Notes about the same thing that don’t link yet. Link adds a Related line to the first.'),
            children: [for (final s in links) _suggestionRow(context, s)],
          ),
          PaneSection(
            key: const ValueKey('wrapped-contradictions'),
            title: 'May be out of date',
            description: Text(runner == null ? 'Turn on Contradictions in Settings › Plugins to find older notes a newer one disagrees with.' : (findings.isEmpty ? 'No notes disagree.' : 'Where a newer note says otherwise, found by Contradictions.')),
            children: [
              for (final finding in findings)
                SettingRow(
                  key: ValueKey('wrapped-finding-${finding.key}'),
                  icon: const AppIcon(Lucide.replace, size: 18),
                  label: finding.olderTitle.isEmpty ? 'A note' : finding.olderTitle,
                  layout: SettingRowLayout.stacked,
                  hint: Text('“${finding.olderQuote}”. ${finding.newerTitle.isEmpty ? 'A newer note' : finding.newerTitle} says “${finding.newerQuote}”.'),
                  control: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: t.space(2),
                    children: [
                      if (_open != null) RowAction(onPress: () => _open!(finding.olderId, null), child: const Text('Open')),
                      RowAction(onPress: () => unawaited(_service.superseded(finding)), child: const Text('Mark superseded')),
                      RowAction(onPress: () => unawaited(_service.notConflict(finding)), child: const Text('Not a conflict')),
                    ],
                  ),
                ),
            ],
          ),
          if (_service.state.records.isNotEmpty)
            PaneSection(
              key: const ValueKey('wrapped-done'),
              title: 'Done from Wrapped',
              children: [
                for (final record in _service.state.records.take(8))
                  SettingRow(
                    key: ValueKey('wrapped-record-${record.id}'),
                    icon: const AppIcon(Lucide.undo2, size: 18),
                    label: record.folderPath,
                    hint: Text(record.undone ? '${record.summary} · undone' : record.summary),
                    control: record.undone
                        ? null
                        : RowAction(
                            onPress: () => unawaited(() async {
                              final said = await _service.undo(record.id);
                              if (mounted) setState(() => _said = said);
                            }()),
                            child: const Text('Undo'),
                          ),
                  ),
              ],
            ),
        ] else
          PaneSection(
            children: [
              SettingRow(
                key: const ValueKey('wrapped-more'),
                label: 'More',
                hint: Text('Suggested tidying${tidy.isEmpty ? '' : ' (${tidy.length})'}, links to add, notes that disagree, and choosing several at once.'),
                control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
              ),
            ],
          ),
      ],
    );
  }

  /// Where a to-do is: its note, the line over it where there is one, and the line as written.
  String _inNote(TodoRow row) {
    final lines = (_service.library.noteOf(row.todo.noteId)?.body ?? '').split('\n');
    String? over;
    for (var i = (lineOfTodo(lines.join('\n'), row.todo) ?? row.todo.line) - 1; i >= 0 && i < lines.length; i -= 1) {
      final line = lines[i].trim();
      if (line.isNotEmpty && line != '---') {
        over = line.replaceFirst(RegExp(r'^#+\s*'), '');
        break;
      }
    }
    final name = row.title.trim().isEmpty ? 'Untitled' : row.title.trim();
    final under = over == null || over == name ? '' : ', under “${over.length > 50 ? '${over.substring(0, 49)}…' : over}”';
    return 'In $name$under\n${row.todo.text.trim()}';
  }

  /// What [s] would do, in words, and its Apply and Dismiss.
  Widget _suggestionRow(BuildContext context, WrappedSuggestion s) {
    final t = context.tokens;
    final library = _service.library;
    final list = _service.workspaces.value.list;
    String title(String id) {
      final body = library.noteOf(id)?.body;
      final words = body == null ? '' : noteTitle(body).trim();
      return '“${words.isEmpty ? 'Untitled' : words}”';
    }

    String folder(String? id) => id == null ? 'your notes' : (list.any((w) => w.id == id) ? workspacePathName(list, id) : 'a folder');
    final names = s.notes.map(title).toList();
    final (icon, label) = switch (s.kind) {
      SuggestionKind.move => (Lucide.folderInput, 'Move ${names.first} to ${folder(s.folderId)}'),
      SuggestionKind.newFolder => (Lucide.folderPlus, 'New folder “${s.folderName}” in ${folder(s.parentId)} for ${names.length == 1 ? names.first : '${names.length} notes'}'),
      SuggestionKind.merge => (Lucide.copy, 'Merge ${names.skip(1).join(', ')} into ${names.first}'),
      SuggestionKind.link => (Lucide.link, 'Link ${names.first} to ${names.last}'),
    };
    final words = [
      if (s.why.isNotEmpty) s.why,
      if (s.kind == SuggestionKind.newFolder && names.length > 1) names.join(', '),
      if (s.kind == SuggestionKind.merge) 'The lines it lacks go into the first; the others go to the Trash.',
    ].join(' · ');
    return SettingRow(
      key: ValueKey('wrapped-suggestion-${s.id}'),
      icon: AppIcon(icon, size: 18),
      label: label,
      layout: SettingRowLayout.stacked,
      hint: words.isEmpty ? null : Text(words),
      control: Wrap(
        alignment: WrapAlignment.end,
        spacing: t.space(2),
        children: [
          RowAction(key: const ValueKey('suggestion-apply'), onPress: () => unawaited(_press(() => _service.apply(s), (n) => n == 0 ? 'Nothing needed changing.' : 'Done.')), child: Text(s.kind == SuggestionKind.link ? 'Link' : 'Apply')),
          RowAction(key: const ValueKey('suggestion-dismiss'), onPress: () => _quiet(() => _service.dismiss(s), 'Dismissed. It won’t be suggested again.'), child: const Text('Dismiss')),
        ],
      ),
    );
  }
}
