import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart';
import '../../core/snippets.dart';
import '../../core/snippets_note.dart' show SnippetsSource, snippetsSource;
import '../account_forms.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../settings_search.dart';

/// What Settings' search finds on Snippets, by the names the page draws.
const List<SettingsFindable> snippetsFindable = [
  SettingsFindable('Your snippets', 'snippet snippets text expansion expand shortcut abbreviation trigger semicolon sig address date time reorder delete'),
  SettingsFindable('New snippet', 'add make create snippet text expansion trigger'),
];

/// The row's reading: the triggers, the first three of them.
String snippetsSummary(Preferences prefs) {
  final list = prefs.snippets;
  if (list.isEmpty) return 'None yet';
  final shown = [for (final each in list.take(3)) each.trigger].join(', ');
  return list.length > 3 ? '$shown and ${list.length - 3} more' : shown;
}

/// Settings › Snippets (Matt, 2026-10-27: "build ... snippets"; lib/core/snippets.dart): the person's own text
/// expansions, each a trigger (`;sig`) and the words it becomes. Every one listed by its trigger with what it writes
/// now, to move up or down (the order the +'s More lists them in), and to edit or delete; then New snippet. Editing
/// one opens a form under the list: the trigger, the words on as many lines as they need, the placeholders, and a
/// preview of what typing the trigger would write this minute, with a bar where the caret lands. What is wrong is said
/// as it is typed (no trigger, one that breaks the rule or is taken, no words), and Save waits for it.
///
/// Kept in the Snippets note (lib/core/snippets_note.dart; docs/MARKDOWN_FIRST.md decision 19), which syncs as any
/// note does and is in the Library folder, and in the preferences ([Preferences.snippets]) for the builds before it,
/// so a snippet made on the phone is on the Mac.
class SnippetsPane extends StatefulWidget {
  const SnippetsPane({super.key, this.prefs, this.clock, this.snippets});

  /// The preferences it reads and writes; the app's own when left out.
  final PreferencesStore? prefs;

  /// The snippets as the Snippets note holds them (lib/core/snippets_note.dart), read and written through it; the
  /// app's own when left out, and the preferences alone where the app has none yet (a test).
  final SnippetsSource? snippets;

  /// The moment the previews are written at; the device's own when left out.
  final DateTime Function()? clock;

  static Widget hosted(BuildContext context) => const SnippetsPane();

  @override
  State<SnippetsPane> createState() => _SnippetsPaneState();
}

/// The form: a snippet being edited, by id, or a new one (null).
class _Editing {
  const _Editing(this.id);
  final String? id;
}

class _SnippetsPaneState extends State<SnippetsPane> {
  PreferencesStore get _store => widget.prefs ?? preferences;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  _Editing? _editing;
  String _trigger = '';
  final TextEditingController _words = TextEditingController();

  @override
  void initState() {
    super.initState();
    _words.addListener(_typed);
  }

  @override
  void dispose() {
    _words
      ..removeListener(_typed)
      ..dispose();
    super.dispose();
  }

  void _typed() => setState(() {});

  SnippetsSource? get _source => widget.snippets ?? snippetsSource;

  /// The list as it is now: the Snippets note's where there is one, else the preferences'.
  List<Snippet> _list() => _source?.value ?? _store.value.snippets;

  /// Kept in the Snippets note (and the preferences, for the builds before it), or in the preferences alone where
  /// the app has no note to write.
  void _set(List<Snippet> next) {
    final source = _source;
    if (source != null) {
      unawaited(source.set(next));
      return;
    }
    _store.update((now) => now.copyWith(snippets: List.unmodifiable(next)));
  }

  void _open(Snippet? snippet) => setState(() {
        _editing = _Editing(snippet?.id);
        _trigger = snippet?.trigger ?? ';';
        _words.text = snippet?.text ?? '';
      });

  void _close() => setState(() {
        _editing = null;
        _trigger = '';
        _words.text = '';
      });

  /// The rest of the list, for a trigger that is taken: all of it for a new snippet.
  List<Snippet> _others(List<Snippet> list) => [for (final each in list) if (each.id != _editing?.id) each];

  void _save(List<Snippet> list) {
    final editing = _editing;
    if (editing == null || snippetProblem(_trigger, _words.text, _others(list)) != null) return;
    final trigger = keptTrigger(_trigger);
    final id = editing.id;
    _set(id == null
        ? [...list, Snippet(id: newSnippetId(list, _now()), trigger: trigger, text: _words.text)]
        : [for (final each in list) each.id == id ? each.copyWith(trigger: trigger, text: _words.text) : each]);
    _close();
  }

  void _delete(List<Snippet> list, String id) {
    _set([for (final each in list) if (each.id != id) each]);
    if (_editing?.id == id) _close();
  }

  void _move(List<Snippet> list, int from, int by) {
    final to = from + by;
    if (to < 0 || to >= list.length) return;
    final next = [...list];
    final moving = next.removeAt(from);
    next.insert(to, moving);
    _set(next);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _source == null ? _store : Listenable.merge([_store, _source]),
        builder: (context, _) {
          final list = _list();
          final now = _now();
          final editing = _editing;
          return PaneBody(
            children: [
              PaneSection(
                title: 'Your snippets',
                description: const Text('Type a trigger, then a space, Enter or Tab, and it becomes its words. Undo brings the trigger back. They are at the end of the +’s More too.'),
                children: [
                  if (list.isEmpty) const SettingRow(icon: AppIcon(Lucide.textCursorInput, size: 20), label: 'None yet', hint: Text('Make one below.')),
                  for (var i = 0; i < list.length; i++)
                    SettingRow(
                      key: ValueKey('snippet-${list[i].id}'),
                      icon: const AppIcon(Lucide.textCursorInput, size: 20),
                      label: list[i].trigger,
                      hint: Text(snippetPreviewLine(list[i], now)),
                      control: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (list.length > 1) ...[
                            _Move(label: 'Move ${list[i].trigger} up', icon: Lucide.chevronUp, onPress: i == 0 ? null : () => _move(list, i, -1)),
                            _Move(label: 'Move ${list[i].trigger} down', icon: Lucide.chevronDown, onPress: i == list.length - 1 ? null : () => _move(list, i, 1)),
                          ],
                          RowAction(key: ValueKey('snippet-edit-${list[i].id}'), onPress: () => _open(list[i]), child: const Text('Edit')),
                        ],
                      ),
                    ),
                  if (editing == null) SettingRow(key: const ValueKey('snippet-new'), icon: const AppIcon(Lucide.plus, size: 20), label: 'New snippet', onPress: () => _open(null)),
                ],
              ),
              if (editing != null) _form(list, editing, now),
              const SettingsFootnote(
                child: Text('A trigger is a semicolon and letters or digits, like ;sig or ;addr2. It is not expanded in code, nor in a note’s front matter.'),
              ),
            ],
          );
        },
      );

  Widget _form(List<Snippet> list, _Editing editing, DateTime now) {
    final t = context.tokens;
    final problem = snippetProblem(_trigger, _words.text, _others(list));
    // Said once there is something to say it of: a fresh form is not yet wrong.
    final typed = keptTrigger(_trigger) != ';' && keptTrigger(_trigger).isNotEmpty || _words.text.isNotEmpty;
    final made = expandSnippet(_words.text, now);
    final shown = placesCaret(Snippet(id: '', trigger: '', text: _words.text)) ? '${made.text.substring(0, made.caret)}▏${made.text.substring(made.caret)}' : made.text;
    final small = pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'));
    final editingOne = editing.id == null ? null : list.where((each) => each.id == editing.id).firstOrNull;
    return PaneSection(
      title: editingOne == null ? 'New snippet' : 'Edit ${editingOne.trigger}',
      children: [
        SettingsForm(
          children: [
            GlacierInput(
              key: const ValueKey('snippet-trigger'),
              ariaLabel: 'Trigger',
              placeholder: ';sig',
              autoCorrect: false,
              spellCheck: false,
              autoCapitalize: TextCapitalization.none,
              value: _trigger,
              onChange: (text) => setState(() => _trigger = text),
            ),
            _WordsField(key: const ValueKey('snippet-words'), controller: _words, placeholder: 'What it becomes. Markdown, as many lines as you like.'),
            Text('{date}, {time}, {datetime} are filled as it is written; {cursor} is where the caret lands.', style: small),
            if (_words.text.trim().isNotEmpty)
              Semantics(
                label: 'Preview',
                child: DecoratedBox(
                  key: const ValueKey('snippet-preview'),
                  decoration: BoxDecoration(color: t.color('app-ink').withValues(alpha: 0.05), borderRadius: BorderRadius.circular(t.radius('md'))),
                  child: Padding(padding: EdgeInsets.all(t.space(3)), child: Text(shown, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink')))),
                ),
              ),
            if (typed && problem != null) FormProblem(problem),
            Row(
              children: [
                FormSubmit(editingOne == null ? 'Add' : 'Save', wordKey: const ValueKey('snippet-save'), onPressed: problem == null ? () => _save(list) : null),
                const Spacer(),
                if (editingOne != null) RowAction(key: const ValueKey('snippet-delete'), onPress: () => _delete(list, editingOne.id), child: const Text('Delete')),
                RowAction(key: const ValueKey('snippet-cancel'), onPress: _close, child: const Text('Cancel')),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Up or down in the list, as an arrow; a step that cannot be taken is drawn faint and does nothing.
class _Move extends StatelessWidget {
  const _Move({required this.label, required this.icon, required this.onPress});

  final String label;
  final LucideIcon icon;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: RowAction(
        onPress: onPress ?? () {},
        disabled: onPress == null,
        child: AppIcon(icon, size: 16, color: onPress == null ? t.color('app-ink-3') : null),
      ),
    );
  }
}

/// The snippet's words: a field of several lines that grows with them, Enter a new line, nothing corrected, since
/// what is typed here is written into notes as it is.
class _WordsField extends StatefulWidget {
  const _WordsField({super.key, required this.controller, required this.placeholder});

  final TextEditingController controller;
  final String placeholder;

  @override
  State<_WordsField> createState() => _WordsFieldState();
}

class _WordsFieldState extends State<_WordsField> {
  final FocusNode _focus = FocusNode(debugLabel: 'snippet words');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink');
    final quiet = t.color('app-ink-3');
    final style = pageText(t, t.fontSize('sm'), color: ink, mono: true);
    return GlacierFocusRing(
      visible: _focus.hasFocus,
      offset: 1,
      radius: t.radius('md'),
      color: t.color('glacier-accent-solid'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focus.requestFocus,
        child: DecoratedBox(
          decoration: BoxDecoration(color: ink.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(t.radius('md'))),
          child: Padding(
            padding: EdgeInsets.all(t.space(3)),
            child: Stack(
              children: [
                if (widget.controller.text.isEmpty) ExcludeSemantics(child: Text(widget.placeholder, style: style.copyWith(color: quiet))),
                Semantics(
                  label: 'What it becomes',
                  textField: true,
                  child: EditableText(
                    controller: widget.controller,
                    focusNode: _focus,
                    style: style,
                    cursorColor: ink,
                    cursorWidth: 1,
                    backgroundCursorColor: quiet,
                    selectionColor: t.color('glacier-selection'),
                    minLines: 3,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
