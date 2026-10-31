/// What a button in a note does when it is pressed (Matt, 2026-10-30, of a list of plain-Markdown features: "add all
/// 12"; the syntax is lib/core/note_buttons.dart). The editor's half is buttons.dart; this is the run.
///
/// - **`set`** writes its fields into the note's own front matter, through the editor, so one Undo takes it back.
/// - **`post`** and **`claude`** reach past the note, so each asks first (lib/sheet/ask_first.dart), and runs as a job
///   on the app's record of running work (docs/ACTIVITY.md), its plugin's mark on it: Slack's or Discord's for a post,
///   Claude's for Claude. The job says how it went; a failure is its red row with the cause.
/// - **`open`** opens a note by title, or a link.
/// - **`new`** makes a note from one of your templates (lib/notes/place_templates.dart), in a notebook or a folder.
///
/// What reaches past the note is the screen's ([ButtonWorld]), so a test hands in fakes. A view that cannot be edited
/// runs only an open: nothing else is done from a page someone reads.
library;

import 'package:flutter/widgets.dart';

import '../../core/background_jobs.dart';
import '../../core/note_buttons.dart';
import '../../core/properties.dart' show withTicketProperty;
import '../../sheet/ask_first.dart';
import '../editor.dart';

/// What a button reaches past its note with, from the screen: each one absent where the app cannot do it, and the
/// button then says so rather than doing nothing.
class ButtonWorld {
  const ButtonWorld({this.post, this.claude, this.openNote, this.openLink, this.make});

  /// Posts [text] (or, null, the note's words as its plugin posts a note) to a channel of [service] (`slack` or
  /// `discord`) by its name, the only one there is where [channel] is null. Answers the channel's name; throws what
  /// went wrong, in words.
  final Future<String> Function(String service, String? channel, String? text, String body)? post;

  /// Asks the app's Claude to follow [rule] from the Claude rules, or [prompt], on the note [noteId] called [title].
  /// Completes when Claude has finished; throws what went wrong.
  final Future<void> Function(String noteId, String title, {String? rule, String? prompt})? claude;

  /// Opens the note called [title], made if there is none, as a `[[link]]` does.
  final void Function(String title)? openNote;

  /// Opens a link, as a tapped link in a note does.
  final void Function(String url)? openLink;

  /// Makes a note from the template called [template], in the notebook or folder [place] where one is named, named
  /// [title] where one is given. Answers false where there is no such template or place.
  final bool Function(String template, String? place, String? title)? make;
}

/// The job id a button's run is kept under: its note and where it is, so a second press of the same button is the
/// same job (`begin` on a live id is the same job).
String buttonJobId(String noteId, NoteButton button) => 'button:$noteId:${button.from}';

/// What a button's press did, in a sentence, for the note to say; null for nothing to say.
typedef ButtonSaid = String?;

/// Runs [button] in the note on [view]: its fields written, or what it reaches past the note asked first and run as a
/// job. [editable] false runs an open alone. Answers what to say on the note, or null.
Future<ButtonSaid> runButton(BuildContext context, NoteButton button, {required EditorViewLike view, required bool editable, required String noteId, required String title, ButtonWorld? world}) async {
  if (!editable && !button.runsReadOnly) return null;
  switch (button.verb) {
    case ButtonVerb.set:
      return _set(view, button) ? null : 'Nothing to change.';
    case ButtonVerb.open:
      final url = button['url'];
      final note = button['note'];
      if (url != null && url.isNotEmpty) {
        final open = world?.openLink;
        if (open == null) return 'Links cannot be opened here.';
        open(url);
        return null;
      }
      if (note != null && note.isNotEmpty) {
        final open = world?.openNote;
        if (open == null) return 'Notes cannot be opened from here.';
        open(note);
        return null;
      }
      return 'This button opens nothing yet.';
    case ButtonVerb.make:
      final make = world?.make;
      final template = button['template'];
      if (make == null) return 'Notes cannot be made from here.';
      if (template == null || template.isEmpty) return 'This button names no template.';
      return make(template, button['in'], button['title']) ? null : 'There is no template called “$template”${button['in'] != null && button['in']!.isNotEmpty ? ', or no ${button['in']} to put it in' : ''}.';
    case ButtonVerb.post:
      return _post(context, button, view: view, noteId: noteId, title: title, world: world);
    case ButtonVerb.claude:
      return _claude(context, button, noteId: noteId, title: title, world: world);
  }
}

/// A `set`'s fields written into the front matter as one change: one Undo takes all of them back. A field's key keeps
/// the case the note wrote it in; an empty value takes it off.
bool _set(EditorViewLike view, NoteButton button) {
  final doc = view.state.doc.toString();
  var next = doc;
  for (final MapEntry(:key, :value) in button.values.entries) {
    next = withTicketProperty(next, _keyAsWritten(next, key), value.trim().isEmpty ? null : value.trim());
  }
  if (next == doc) return false;
  var start = 0;
  while (start < doc.length && start < next.length && doc.codeUnitAt(start) == next.codeUnitAt(start)) {
    start += 1;
  }
  var end = 0;
  while (end < doc.length - start && end < next.length - start && doc.codeUnitAt(doc.length - 1 - end) == next.codeUnitAt(next.length - 1 - end)) {
    end += 1;
  }
  view.dispatch(TransactionSpec(changes: ChangeSpec(from: start, to: doc.length - end, insert: next.substring(start, next.length - end)), userEvent: 'input.button'));
  return true;
}

final RegExp _frontKey = RegExp(r'^([\w.-]+)[ \t]*:', multiLine: true);

String _keyAsWritten(String body, String key) {
  if (!body.startsWith('---')) return key;
  final end = body.indexOf('\n---', 3);
  final front = end < 0 ? '' : body.substring(0, end);
  for (final found in _frontKey.allMatches(front)) {
    if (found.group(1)!.toLowerCase() == key.toLowerCase()) return found.group(1)!;
  }
  return key;
}

String _serviceName(String service) => service == 'discord' ? 'Discord' : 'Slack';

Future<ButtonSaid> _post(BuildContext context, NoteButton button, {required EditorViewLike view, required String noteId, required String title, ButtonWorld? world}) async {
  final post = world?.post;
  final service = (button['to'] ?? 'slack').toLowerCase() == 'discord' ? 'discord' : 'slack';
  final name = _serviceName(service);
  if (post == null) return '$name is not set up on this device.';
  final channel = button['channel'];
  final text = button['text'];
  final yes = await askFirst(
    context,
    FirstAsk(title: 'Post to $name?', note: '${text != null && text.isNotEmpty ? '“$text”' : 'This note, as it reads now,'} goes to ${channel != null && channel.isNotEmpty ? channel : 'its channel'}.', yes: 'Post'),
  );
  if (!yes) return null;
  final job = activity.begin(buttonJobId(noteId, button), kind: JobKind.meetings, title: button.label, line: 'Posting to $name', personStarted: true, plugin: service);
  try {
    final where = await post(service, channel, text, view.state.doc.toString());
    job.done(result: JobResult('Posted to $where'), tally: JobTally('$name post', '$name posts'));
    return 'Posted to $where.';
  } catch (failure) {
    final words = failure is String ? failure : _words(failure);
    job.failed('Not posted. $words');
    return 'Not posted. $words';
  }
}

Future<ButtonSaid> _claude(BuildContext context, NoteButton button, {required String noteId, required String title, ButtonWorld? world}) async {
  final claude = world?.claude;
  if (claude == null) return 'Claude is not set up on this device.';
  final rule = button['rule'];
  final prompt = button['prompt'];
  if ((rule == null || rule.isEmpty) && (prompt == null || prompt.isEmpty)) return 'This button asks Claude nothing yet.';
  final yes = await askFirst(
    context,
    FirstAsk(title: 'Ask Claude?', note: '${rule != null && rule.isNotEmpty ? 'Claude follows the rule “$rule” on this note' : 'Claude is asked “$prompt” about this note'}. It uses your Claude credits.', yes: 'Ask Claude'),
  );
  if (!yes) return null;
  final job = activity.begin(buttonJobId(noteId, button), kind: JobKind.ai, title: button.label, line: 'Claude is on “${title.isEmpty ? 'this note' : title}”', personStarted: true, plugin: 'claude');
  try {
    await claude(noteId, title, rule: rule, prompt: prompt);
    job.done(result: JobResult('Claude finished “${button.label}”'), tally: const JobTally('Claude button', 'Claude buttons'));
    return null;
  } catch (failure) {
    final words = failure is String ? failure : _words(failure);
    job.failed(words);
    return words;
  }
}

String _words(Object failure) {
  final said = failure.toString();
  return said.startsWith('Exception: ') ? said.substring(11) : said;
}
