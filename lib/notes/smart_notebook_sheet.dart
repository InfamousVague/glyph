/// A smart notebook's sheet (lib/core/smart_notebooks.dart): a name for a search being kept, from the Save under a
/// search field; or, for one kept already, from its More in the sidebar or on its own page, its name and its search
/// to change, its place in the list, and Delete, which takes the search away and no note with it.
///
/// Built only while it is open, as every [Sheet] is.
library;

import 'package:flutter/services.dart' show TextCapitalization, TextInputAction;
import 'package:flutter/widgets.dart';

import '../core/search_query.dart';
import '../core/smart_notebooks.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';

/// A name proposed for a search: its first operator's words, or its words, as a person would call it.
String proposedName(String query) {
  final parsed = parseSearch(query);
  if (parsed.parts.isNotEmpty) {
    final first = parsed.parts.first.label.replaceAll('“', '').replaceAll('”', '');
    return parsed.words.isEmpty ? first : '$first, ${parsed.words.join(' ')}';
  }
  final words = query.trim();
  return words.isEmpty ? '' : '${words[0].toUpperCase()}${words.substring(1)}';
}

class SmartNotebookSheet extends StatefulWidget {
  const SmartNotebookSheet({super.key, required this.store, this.query, this.editing, required this.onClose, this.onMade});

  final SmartNotebookStore store;

  /// The search to keep, for a new one.
  final String? query;

  /// The one to change; null makes a new one from [query].
  final SmartNotebook? editing;
  final VoidCallback onClose;

  /// The one just made, for whoever would open it.
  final ValueChanged<SmartNotebook>? onMade;

  @override
  State<SmartNotebookSheet> createState() => _SmartNotebookSheetState();
}

class _SmartNotebookSheetState extends State<SmartNotebookSheet> {
  late String _name = widget.editing?.name ?? proposedName(widget.query ?? '');
  late String _query = widget.editing?.query ?? widget.query ?? '';
  bool _deleting = false;

  void _submit() {
    final editing = widget.editing;
    if (_name.trim().isEmpty || _query.trim().isEmpty) return;
    if (editing == null) {
      final made = widget.store.add(_name, _query);
      widget.onClose();
      if (made != null) widget.onMade?.call(made);
      return;
    }
    if (_name.trim() != editing.name) widget.store.rename(editing.id, _name);
    if (_query.trim() != editing.query) widget.store.setQuery(editing.id, _query);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final editing = widget.editing;
    if (editing != null && _deleting) {
      return Sheet(
        label: 'Delete ${editing.name}',
        onClose: widget.onClose,
        children: [
          SheetTitle.text('Delete ${editing.name}?'),
          const SheetNote('Only the search goes. Every note it found stays where it is.'),
          SheetGroup(
            children: [
              SheetRow(
                label: 'Delete smart notebook',
                danger: true,
                onPress: () {
                  widget.store.remove(editing.id);
                  widget.onClose();
                },
              ),
              SheetRow(label: 'Cancel', onPress: () => setState(() => _deleting = false)),
            ],
          ),
        ],
      );
    }
    final list = widget.store.value;
    final at = editing == null ? -1 : list.indexWhere((each) => each.id == editing.id);
    final changed = editing == null || _name.trim() != editing.name || _query.trim() != editing.query;
    return Sheet(
      label: editing?.name ?? 'Save this search',
      onClose: widget.onClose,
      children: [
        SheetTitle.text(editing?.name ?? 'Save this search'),
        SheetNote(editing == null
            ? 'A smart notebook keeps the search, not the notes: it shows whatever the search finds, here and on your other devices.'
            : 'It shows whatever its search finds. Change the search and the notes it shows change with it.'),
        SheetGroup(
          children: [
            SheetField(
              key: const ValueKey('smart-name'),
              label: 'Name',
              value: _name,
              onChange: (text) => setState(() => _name = text),
              autoFocus: editing == null,
              autoCapitalize: TextCapitalization.sentences,
              enterKeyHint: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            SheetField(
              key: const ValueKey('smart-query'),
              label: 'Search',
              value: _query,
              onChange: (text) => setState(() => _query = text),
              autoCapitalize: TextCapitalization.none,
              autoCorrect: false,
              enterKeyHint: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            SheetRow(label: editing == null ? 'Save' : 'Save changes', onPress: _submit, disabled: _name.trim().isEmpty || _query.trim().isEmpty || !changed),
          ],
        ),
        if (editing != null && list.length > 1)
          SheetGroup(
            children: [
              SheetRow(label: 'Move up', onPress: at > 0 ? () => widget.store.move(editing.id, at - 1) : null, disabled: at <= 0),
              SheetRow(label: 'Move down', onPress: at >= 0 && at < list.length - 1 ? () => widget.store.move(editing.id, at + 1) : null, disabled: at < 0 || at >= list.length - 1),
            ],
          ),
        if (editing != null)
          SheetGroup(
            children: [
              SheetRow(label: 'Delete smart notebook', hint: 'The notes it finds stay.', danger: true, onPress: () => setState(() => _deleting = true)),
            ],
          ),
      ],
    );
  }
}
