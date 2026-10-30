/// Forms from a share link (docs/FORMS.md; Matt, 2026-10-30, the ninth of a list of plain-Markdown features: "add all
/// 12"): a note holding a ```form fence is a form. Shared by its link, the reader page draws it as a form anyone can
/// fill in (tauri/src/read/FormRead.tsx); what they send is sealed in their browser to this account's key, or to
/// every member's of the team whose notebook it files into, and each answer is filed here as a ticket
/// (lib/forms/form_inbox.dart).
///
/// The fence, the same grammar the reader's tauri/src/read/form.ts reads:
///
/// ```form
/// to: [[Bug reports]]          the notebook its tickets go into
/// ticket: Bug: {Summary}       a ticket's title, a field's answer in braces
/// template: Bug report         a ticket template to start each ticket from
/// thanks: Thanks, we'll look into it.
/// button: Send report
/// - Summary: short, required
/// - What happened: long, required
/// - How bad: choice (Annoying | Blocking | Lost work)
/// - Your email: email, optional
/// - Screenshot: file
/// ```
///
/// A field is `- Label: kind`, the kind `short` (one line), `long` (a paragraph), `choice` (one of the options in
/// brackets, split by `|` or `,`), `email` or `file`, then `required` or `optional` (optional unless it says). A field
/// with no kind is short. `to`, `ticket` and `template` are the owner's: the share carries the rest ([publicFormBody]),
/// so a visitor reads the form and not where it goes. What the note says outside the fence is the form's introduction.
///
/// Pure: nothing here draws or stores, and every rule is a test (test/forms/form_def_test.dart).
library;

import '../core/front_matter.dart' show frontMatterOffset;
import '../core/item_syntax.dart' show jsTrim;
import '../core/properties.dart' show withProperty;
import '../core/title_key.dart' show titleKey;

/// What a field takes.
enum FormFieldKind { short, long, choice, email, file }

/// One field of a form: its label (the key its answer is filed under), what it takes, and whether it must be filled.
class FormField {
  const FormField({required this.label, required this.kind, this.required = false, this.options = const []});
  final String label;
  final FormFieldKind kind;
  final bool required;
  final List<String> options;

  @override
  bool operator ==(Object other) => other is FormField && other.label == label && other.kind == kind && other.required == required && _same(other.options, options);

  @override
  int get hashCode => Object.hash(label, kind, required, Object.hashAll(options));

  @override
  String toString() => 'FormField($label, ${kind.name}${required ? ', required' : ''}${options.isEmpty ? '' : ', $options'})';
}

bool _same(List<String> a, List<String> b) => a.length == b.length && [for (var i = 0; i < a.length; i += 1) a[i] == b[i]].every((same) => same);

/// A form as its fence says it.
class FormDef {
  const FormDef({required this.fields, this.to, this.ticket, this.template, this.thanks, this.button});
  final List<FormField> fields;

  /// The notebook its tickets go into, by title; null for the one the form's note is a page of.
  final String? to;

  /// A ticket's title, `{Label}` standing for that field's answer; null for the first answer.
  final String? ticket;

  /// The ticket template each ticket starts from, by name; null for none.
  final String? template;
  final String? thanks;
  final String? button;

  /// Whether it takes a file, so the service takes the larger answer (server/src/forms.rs `FILE_LIMIT`).
  bool get takesFile => fields.any((field) => field.kind == FormFieldKind.file);
}

/// The most fields a form has, and how long a label or an option may be.
const int mostFields = 30;
const int _labelLimit = 80;

final RegExp _fence = RegExp(r'^(`{3,}|~{3,})\s*form\s*$', caseSensitive: false);
const Map<String, FormFieldKind> _kinds = {
  'short': FormFieldKind.short, 'text': FormFieldKind.short, 'line': FormFieldKind.short,
  'long': FormFieldKind.long, 'paragraph': FormFieldKind.long, 'textarea': FormFieldKind.long,
  'choice': FormFieldKind.choice, 'select': FormFieldKind.choice, 'choose': FormFieldKind.choice,
  'email': FormFieldKind.email,
  'file': FormFieldKind.file, 'attachment': FormFieldKind.file, 'upload': FormFieldKind.file,
};
final RegExp _item = RegExp(r'^\s*[-*+]\s+(.+?)\s*$');
final RegExp _spec = RegExp(r'^(?:([a-z]+)\b\s*(?:\(([^)]*)\))?)?\s*(.*)$', caseSensitive: false);
final RegExp _setting = RegExp(r'^\s*(to|notebook|ticket|title|template|thanks|button)\s*:\s*(.*?)\s*$', caseSensitive: false);
final RegExp _word = RegExp('^[a-z]+', caseSensitive: false);
final RegExp _linked = RegExp(r'^\[\[(.*)\]\]$');

/// Where the first ```form fence of [body] is: its opening line and its closing one (the end, unclosed), or null.
({int open, int close, List<String> lines})? fenceIn(String body) {
  final lines = body.split('\n');
  for (var at = 0; at < lines.length; at += 1) {
    final opened = _fence.firstMatch(jsTrim(lines[at]));
    if (opened == null) continue;
    final mark = opened.group(1)!;
    for (var end = at + 1; end < lines.length; end += 1) {
      final line = jsTrim(lines[end]);
      if (line.startsWith(mark[0] * mark.length) && line.replaceAll(RegExp('[`~]'), '').isEmpty) return (open: at, close: end, lines: lines);
    }
    return (open: at, close: lines.length, lines: lines);
  }
  return null;
}

/// Whether [body] is a form: it holds a ```form fence.
bool isFormBody(String body) => body.contains('form') && fenceIn(body) != null;

String _unlinked(String text) => jsTrim(text.replaceFirstMapped(_linked, (m) => m.group(1)!));

/// One field out of what follows its `- `: split at the last colon whose spec reads as one.
FormField? _fieldOf(String text) {
  var label = text;
  var spec = '';
  for (var at = text.lastIndexOf(':'); at > 0; at = text.lastIndexOf(':', at - 1)) {
    final rest = jsTrim(text.substring(at + 1));
    final word = (_word.firstMatch(rest)?.group(0) ?? '').toLowerCase();
    if (rest.isEmpty || _kinds.containsKey(word) || word == 'required' || word == 'optional') {
      label = text.substring(0, at);
      spec = rest;
      break;
    }
  }
  label = jsTrim(label);
  var required = false;
  if (label.endsWith('*')) {
    required = true;
    label = jsTrim(label.substring(0, label.length - 1));
  }
  if (label.isEmpty) return null;
  final parts = _spec.firstMatch(spec)!;
  final kind = _kinds[(parts.group(1) ?? '').toLowerCase()];
  // A spec whose first word is no kind is all flags: `- Summary: required`.
  final flags = (kind != null ? parts.group(3) ?? '' : spec).toLowerCase().split(',').map(jsTrim).toList();
  if (flags.contains('required')) required = true;
  if (flags.contains('optional')) required = false;
  final options = <String>[];
  if (kind == FormFieldKind.choice && parts.group(2) != null) {
    for (final option in parts.group(2)!.split(RegExp('[|,]'))) {
      final clean = jsTrim(option);
      final cut = clean.length > _labelLimit ? clean.substring(0, _labelLimit) : clean;
      if (cut.isNotEmpty && !options.contains(cut) && options.length < mostFields) options.add(cut);
    }
  }
  final taken = kind == FormFieldKind.choice && options.isEmpty ? FormFieldKind.short : kind ?? FormFieldKind.short;
  return FormField(label: label.length > _labelLimit ? label.substring(0, _labelLimit) : label, kind: taken, required: required, options: List.unmodifiable(options));
}

/// The form [body] holds, or null for a note with no ```form fence. Two fields of one label are one, the first.
FormDef? formOf(String body) {
  final fence = fenceIn(body);
  if (fence == null) return null;
  final fields = <FormField>[];
  String? to, ticket, template, thanks, button;
  for (final line in fence.lines.sublist(fence.open + 1, fence.close)) {
    final setting = _setting.firstMatch(line);
    if (setting != null && !RegExp(r'^\s*[-*+]\s').hasMatch(line)) {
      final value = jsTrim(setting.group(2)!);
      if (value.isEmpty) continue;
      switch (setting.group(1)!.toLowerCase()) {
        case 'to' || 'notebook':
          to = _unlinked(value);
        case 'ticket' || 'title':
          ticket = value;
        case 'template':
          template = _unlinked(value);
        case 'thanks':
          thanks = value;
        case 'button':
          button = value.length > _labelLimit ? value.substring(0, _labelLimit) : value;
      }
      continue;
    }
    final item = _item.firstMatch(line);
    if (item == null || fields.length >= mostFields) continue;
    final field = _fieldOf(item.group(1)!);
    if (field != null && !fields.any((f) => f.label.toLowerCase() == field.label.toLowerCase())) fields.add(field);
  }
  return FormDef(fields: List.unmodifiable(fields), to: to, ticket: ticket, template: template, thanks: thanks, button: button);
}

final RegExp _ownersLine = RegExp(r'^\s*(to|notebook|ticket|title|template)\s*:', caseSensitive: false);

/// What a form's share carries: the note without its front matter, and its fence without the owner's own lines
/// (`to`, `ticket`, `template`), so a visitor reads its fields and its introduction, and nothing of where it goes.
String publicFormBody(String body) {
  final words = body.substring(frontMatterOffset(body));
  final fence = fenceIn(words);
  if (fence == null) return words;
  final lines = fence.lines;
  return [
    ...lines.sublist(0, fence.open + 1),
    for (final line in lines.sublist(fence.open + 1, fence.close))
      if (!_ownersLine.hasMatch(line) || RegExp(r'^\s*[-*+]\s').hasMatch(line)) line,
    ...lines.sublist(fence.close),
  ].join('\n');
}

/// What a new form starts with, under its title: a line for the visitor, and a fence a bug report or a request fits,
/// filing into [notebook] (`{{journal}}` where the page's template filling names it, lib/book/entry_starts.dart).
String newFormWords({String notebook = '{{journal}}'}) => [
      'Tell people what this form is for. What you write here is shown above the form; the fence below is the form.',
      '',
      '```form',
      'to: [[$notebook]]',
      'ticket: {Summary}',
      "thanks: Thanks, we'll take a look.",
      '- Summary: short, required',
      '- Details: long, required',
      '- Your email: email, optional',
      '```',
      '',
    ].join('\n');

// ---- an answer ------------------------------------------------------------------------------------------------------

/// A file sent with an answer.
class FormFile {
  const FormFile({required this.field, required this.name, required this.type, required this.bytes});
  final String field;
  final String name;
  final String type;
  final List<int> bytes;
}

/// An answer, opened: each field's words in the form's order, the file if one came, and when it was sent (ms).
class FormAnswer {
  const FormAnswer({required this.answers, this.file, this.at});
  final List<(String, String)> answers;
  final FormFile? file;
  final int? at;

  /// The answer to [label], matched as a person would say it; null for none.
  String? of(String label) {
    final key = titleKey(label);
    for (final (field, value) in answers) {
      if (titleKey(field) == key) return value;
    }
    return null;
  }
}

/// A ticket's title from [def]'s pattern, each `{Label}` the answer to that field (blank where there is none), or the
/// first answer's first line where there is no pattern, or a pattern none of whose fields were answered; "Form
/// answer" when that leaves nothing. At most 120 characters, on one line.
String ticketTitleOf(FormDef? def, FormAnswer answer) {
  final pattern = def?.ticket;
  var placed = 0, filled = 0;
  var title = pattern == null
      ? ''
      : pattern.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) {
          placed += 1;
          final value = answer.of(m.group(1)!);
          if (value != null) filled += 1;
          return value ?? '';
        });
  if ((placed > 0 && filled == 0) || jsTrim(title).replaceAll(RegExp(r'[\s:–—-]+'), '').isEmpty) title = answer.answers.isEmpty ? '' : answer.answers.first.$2;
  // A title is one line, with nothing a page's title may not hold, and of a length a list can show.
  title = jsTrim(title.split('\n').first.replaceAll(RegExp(r'[\[\]#|]'), ' ').replaceAll(RegExp(r'\s+'), ' '));
  if (title.length > 120) title = '${jsTrim(title.substring(0, 119))}…';
  return title.isEmpty ? 'Form answer' : title;
}

/// A front-matter key for a field: its label in lower case, words joined by dashes (`How bad` is `how-bad`).
String fieldKey(String label) => label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

/// Keys a ticket's front matter already means something by, which a field of the same name does not take over.
const Set<String> _ownKeys = {'type', 'id', 'status', 'title', 'assignee', 'labels', 'priority', 'due', 'blocked-by', 'parent', 'via', 'form', 'answered', 'email', 'book', 'key'};

/// [body], a ticket made for [answer], with the answer in it: in the front matter `via: form`, `form: [[the form]]`,
/// `answered:` (when, ISO 8601), `email:` for an email field's answer, and each short or choice answer under its
/// field's key; in the body, each field's words under a heading of its label, a picture or a file sent as its link
/// ([fileLink]), and the line saying it came by the form and when.
String withAnswer(String body, FormDef? def, FormAnswer answer, {required String formTitle, required DateTime at, String? fileLink}) {
  var out = withProperty(body, 'via', 'form');
  if (formTitle.isNotEmpty) out = withProperty(out, 'form', '[[$formTitle]]');
  out = withProperty(out, 'answered', at.toUtc().toIso8601String());
  final kinds = {for (final field in def?.fields ?? const <FormField>[]) field.label.toLowerCase(): field.kind};
  for (final (label, value) in answer.answers) {
    final kind = kinds[label.toLowerCase()] ?? FormFieldKind.short;
    if (kind == FormFieldKind.email) {
      out = withProperty(out, 'email', value);
    } else if ((kind == FormFieldKind.short || kind == FormFieldKind.choice) && !value.contains('\n') && value.length <= 200) {
      final key = fieldKey(label);
      if (key.isNotEmpty && !_ownKeys.contains(key)) out = withProperty(out, key, value);
    }
  }
  final words = StringBuffer(out.replaceFirst(RegExp(r'\s*$'), ''))..write('\n');
  for (final (label, value) in answer.answers) {
    words
      ..write('\n## $label\n\n')
      ..write(value.replaceAll('\r\n', '\n').trim())
      ..write('\n');
  }
  if (answer.file != null && fileLink != null) {
    words
      ..write('\n## ${answer.file!.field}\n\n')
      ..write(fileLink)
      ..write('\n');
  }
  final when = at.toUtc().toIso8601String().substring(0, 16).replaceFirst('T', ' ');
  words.write('\n_Via ${formTitle.isEmpty ? 'a form' : 'the form [[$formTitle]]'}, $when UTC._\n');
  return words.toString();
}
