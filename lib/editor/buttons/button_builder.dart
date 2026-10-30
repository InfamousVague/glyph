/// A button made in a small builder, from the + and the `/` palette's A button (Matt, 2026-10-30, of a list of
/// plain-Markdown features: "add all 12"): what it does, what it does it with, and its label, the button as it will
/// be drawn and the line it writes under them, and Add, which writes that line at the caret. Behind More in both
/// modes, with the rest of what a note is made of.
library;

import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../core/note_buttons.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import 'buttons.dart' show NoteButtonChip, buttonIcon;

/// The builder's kinds, in the order it offers them: a verb and, for a post, where to.
enum ButtonKind {
  set('Set a field', 'Move its status, assign it, or any field of this note.'),
  slack('Post to Slack', 'This note, or words of your own, to a channel. Asks first.'),
  discord('Post to Discord', 'This note, or words of your own, to a channel. Asks first.'),
  claude('Ask Claude', 'One of your Claude rules, or a prompt, on this note. Asks first.'),
  open('Open', 'A note by its title, or a link.'),
  make('New from template', 'A note from one of your templates, in a notebook or a folder.');

  const ButtonKind(this.words, this.hint);
  final String words;
  final String hint;
}

/// What the builder has been given so far.
class ButtonDraft {
  ButtonKind kind = ButtonKind.set;
  String label = '';
  String field = 'status';
  String value = 'Done';
  String channel = '';
  String text = '';
  String rule = '';
  String prompt = '';
  String target = '';
  String template = '';
  String place = '';
  String title = '';

  /// The label it will have: the one typed, or what it does.
  String get shownLabel => label.trim().isNotEmpty ? label.trim() : suggested;

  /// A label for what it does, where none is typed.
  String get suggested => switch (kind) {
        ButtonKind.set => field.trim().toLowerCase() == 'status' ? 'Move to ${value.trim().isEmpty ? '…' : value.trim()}' : 'Set ${field.trim().isEmpty ? 'a field' : field.trim()}',
        ButtonKind.slack => 'Post to Slack',
        ButtonKind.discord => 'Post to Discord',
        ButtonKind.claude => rule.trim().isNotEmpty ? rule.trim() : 'Ask Claude',
        ButtonKind.open => target.trim().isEmpty ? 'Open' : 'Open ${target.trim()}',
        ButtonKind.make => template.trim().isEmpty ? 'New note' : 'New ${template.trim()}',
      };

  /// The button the draft makes.
  NoteButton get button {
    String? some(String text) => text.trim().isEmpty ? null : text.trim();
    final link = target.trim().contains('://') || target.trim().startsWith('mailto:');
    final (verb, values) = switch (kind) {
      ButtonKind.set => (ButtonVerb.set, <String, String>{?some(field): value.trim()}),
      ButtonKind.slack || ButtonKind.discord => (ButtonVerb.post, <String, String>{'to': kind == ButtonKind.slack ? 'slack' : 'discord', 'channel': ?some(channel), 'text': ?some(text)}),
      ButtonKind.claude => (ButtonVerb.claude, some(rule) != null ? <String, String>{'rule': some(rule)!} : <String, String>{'prompt': ?some(prompt)}),
      ButtonKind.open => (ButtonVerb.open, <String, String>{(link ? 'url' : 'note'): ?some(target)}),
      ButtonKind.make => (ButtonVerb.make, <String, String>{'template': ?some(template), 'in': ?some(place), 'title': ?some(title)}),
    };
    return NoteButton(label: shownLabel, verb: verb, values: values);
  }

  /// Whether it does something yet: what each kind needs is given.
  bool get ready => switch (kind) {
        ButtonKind.set => field.trim().isNotEmpty,
        ButtonKind.slack || ButtonKind.discord => true,
        ButtonKind.claude => rule.trim().isNotEmpty || prompt.trim().isNotEmpty,
        ButtonKind.open => target.trim().isNotEmpty,
        ButtonKind.make => template.trim().isNotEmpty,
      };
}

/// A test's answer in place of the sheet's: the line it would write.
@visibleForTesting
Future<String?> Function()? debugBuildButton;

/// Opens the builder over the app; answers the line to write, or null for none.
Future<String?> buildButton(BuildContext context, {List<String> templates = const []}) {
  final answering = debugBuildButton;
  if (answering != null) return answering();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future.value(null);
  final answer = Completer<String?>();
  late final OverlayEntry entry;
  void done(String? line) {
    if (answer.isCompleted) return;
    entry.remove();
    answer.complete(line);
  }

  entry = OverlayEntry(builder: (_) => ButtonBuilderSheet(templates: templates, onDone: done));
  overlay.insert(entry);
  return answer.future;
}

class ButtonBuilderSheet extends StatefulWidget {
  const ButtonBuilderSheet({super.key, required this.onDone, this.templates = const []});

  /// The line to write, or null for Cancel.
  final ValueChanged<String?> onDone;

  /// Your templates' names, offered for New from template.
  final List<String> templates;

  @override
  State<ButtonBuilderSheet> createState() => ButtonBuilderSheetState();
}

class ButtonBuilderSheetState extends State<ButtonBuilderSheet> {
  final ButtonDraft draft = ButtonDraft();

  /// The kind's rows are open: the choice of what it does is made.
  bool _chosen = false;

  void _set(void Function() change) => setState(change);

  SheetField _field(String label, String value, ValueChanged<String> onChange, {String? placeholder}) =>
      SheetField(key: ValueKey<String>('button-field:$label'), label: label, value: value, placeholder: placeholder, autoCorrect: false, autoCapitalize: TextCapitalization.none, onChange: (text) => _set(() => onChange(text)));

  List<Widget> _fields() => switch (draft.kind) {
        ButtonKind.set => [_field('Field', draft.field, (t) => draft.field = t, placeholder: 'status'), _field('Value', draft.value, (t) => draft.value = t, placeholder: 'Done, or nothing to take it off')],
        ButtonKind.slack || ButtonKind.discord => [_field('Channel', draft.channel, (t) => draft.channel = t, placeholder: 'Its name, or the one there is'), _field('Words', draft.text, (t) => draft.text = t, placeholder: 'Left empty, the whole note')],
        ButtonKind.claude => [_field('Rule', draft.rule, (t) => draft.rule = t, placeholder: 'One of your Claude rules, by name'), _field('Or a prompt', draft.prompt, (t) => draft.prompt = t, placeholder: 'What to ask about this note')],
        ButtonKind.open => [_field('Note or link', draft.target, (t) => draft.target = t, placeholder: 'A title, or https://…')],
        ButtonKind.make => [
            _field('Template', draft.template, (t) => draft.template = t, placeholder: widget.templates.isEmpty ? 'Bug report' : widget.templates.take(3).join(', ')),
            _field('In', draft.place, (t) => draft.place = t, placeholder: 'A notebook or a folder, or nowhere'),
            _field('Title', draft.title, (t) => draft.title = t, placeholder: 'Left empty, the template’s'),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final button = draft.button;
    if (!_chosen) {
      return Sheet(
        key: const ValueKey('button-builder'),
        label: 'A button',
        onClose: () => widget.onDone(null),
        children: [
          SheetTitle.text('A button'),
          const SheetNote('A link that does something when it is pressed. Other apps show it as a link.'),
          SheetGroup(
            children: [
              for (final kind in ButtonKind.values)
                SheetRow(
                  key: ValueKey<String>('button-kind:${kind.name}'),
                  icon: SheetIcon(icon: AppIcon(buttonIcon(switch (kind) { ButtonKind.set => ButtonVerb.set, ButtonKind.slack || ButtonKind.discord => ButtonVerb.post, ButtonKind.claude => ButtonVerb.claude, ButtonKind.open => ButtonVerb.open, ButtonKind.make => ButtonVerb.make }), size: 18)),
                  label: kind.words,
                  hint: kind.hint,
                  onPress: () => _set(() {
                    draft.kind = kind;
                    _chosen = true;
                  }),
                ),
            ],
          ),
        ],
      );
    }
    return Sheet(
      key: const ValueKey('button-builder'),
      label: draft.kind.words,
      onClose: () => widget.onDone(null),
      onBack: () => _set(() => _chosen = false),
      children: [
        SheetTitle.text(draft.kind.words),
        SheetGroup(children: [..._fields(), _field('Label', draft.label, (t) => draft.label = t, placeholder: draft.suggested)]),
        // The button as it will be drawn, what it does, and the line it writes.
        Padding(
          key: const ValueKey('button-preview'),
          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NoteButtonChip(label: button.label, verb: button.verb, runs: true, onPress: null),
              SizedBox(height: t.space(2)),
              Text(button.does, style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-2'))),
              SizedBox(height: t.space(1)),
              Text(button.markdown, style: t.textAt(t.fontSize('xs'), mono: true, color: t.color('app-ink-3'))),
            ],
          ),
        ),
        SheetGroup(
          children: [
            SheetRow(key: const ValueKey('button-add'), label: 'Add', hint: draft.ready ? 'Written at the caret.' : 'Say what it does first.', disabled: !draft.ready, onPress: () => widget.onDone(button.markdown)),
          ],
        ),
      ],
    );
  }
}
