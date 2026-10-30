/// Reading a finished recording with the on-device model, in two small steps (the core's `ai_voice_step`, prompts and
/// grammars in native/src/voice.rs). A port of `src/app/capture/voicePlan.ts` (the Tauri app's voice work that
/// followed 1.6).
///
/// 1. sort: is this a note, an addition, a new list, or both talk and a request?
/// 2. plan: the actions, each with its items as a real list, plus whatever else was said worth keeping as a note.
/// 3. polish (voice_polish.dart): for what the rules read, the same JSON again, with items split or joined and
///    Whisper's punctuation and titles tidied.
///
/// The model proposes; this file checks. Every field is validated by shape, a note to add to must be one of the
/// person's notes (and not a book, docs/BOOKS.md), and every item, title and note must be made of words they
/// actually said ([grounded]), so a small model that invents "Superman III" loses that item rather than writing it.
/// Text is escaped so it cannot become Markdown structure.
///
/// What differs:
/// - The stage and the kind are the words the core is sent (`'sort'`, `'plan'`, `'polish'`; `'note'`, `'add'`,
///   `'new'`, `'mixed'`), as `String`s. A [StepResult] is a sealed class ([StepAnswer], [StepRefused],
///   [StepUnavailable]).
/// - The native call is the host's: [voiceStepOver] and [diagnosticsOver] are made over the same `invoke` that
///   instruction_intent.dart's `inferInstruction` takes, and [runVoiceStep] is the step with no native side, which
///   answers that it is unavailable.
/// - A note is found as the rules find one (note_find.dart `findNote`), so "house chores" is House TODOs for the
///   model's title as for the rules'.
/// - Accents come off through ai/support/unaccent.dart, where the page used `normalize('NFKD')`.
library;

import 'dart:async';

import '../ai/support/unaccent.dart' show unaccented;
import '../core/book.dart' show isBookBody;
import 'command.dart' show Placement, PlacementHow;
import 'instruction_intent.dart' show InstructionInvoke;
import 'instruction_mutation.dart' show listTitle;
import 'note_find.dart' show FoundResolved, FoundUnsure, findNote;
import 'route.dart' show Candidate;

/// What kind of thing a recording is (`SortKind`): the words the sort step answers with.
const List<String> sortKinds = ['note', 'add', 'new', 'mixed'];

/// What one model step came to (`StepResult`).
sealed class StepResult {
  const StepResult();

  /// The web's `status`: `answer`, `refused` or `unavailable`.
  String get status;
}

/// The model's JSON, checked to be one whole object by the core, with its raw text for the voice log.
final class StepAnswer extends StepResult {
  const StepAnswer({required this.answer, required this.raw, required this.model});

  final Object? answer;
  final String raw;
  final String model;

  @override
  String get status => 'answer';
}

/// Not given to the model at all: a destructive request.
final class StepRefused extends StepResult {
  const StepRefused({required this.reason});

  final String reason;

  @override
  String get status => 'refused';
}

/// No model, no answer in time, or an answer that was not usable.
final class StepUnavailable extends StepResult {
  const StepUnavailable({required this.reason});

  final String reason;

  @override
  String get status => 'unavailable';
}

/// One call of the model: [stage] is `sort`, `plan` (with the [kind] sorting found) or `polish` (with the app's
/// [draft], as the plan's JSON) (`VoiceStep`).
typedef VoiceStep = Future<StepResult> Function(String stage, String? kind, String transcript, List<String> titles, [String? draft]);

/// One change a recording asks for, checked and ready to show on the card (`VoiceAction`).
sealed class VoiceAction<N extends Candidate> {
  const VoiceAction();

  /// The web's `do`: `append` or `create`.
  String get kind;
}

/// Words or items into an existing note.
final class VoiceAppend<N extends Candidate> extends VoiceAction<N> {
  const VoiceAppend({required this.note, required this.text, required this.placement});

  final N note;
  final String text;
  final Placement placement;

  @override
  String get kind => 'append';

  VoiceAppend<N> copyWith({String? text, Placement? placement}) => VoiceAppend<N>(note: note, text: text ?? this.text, placement: placement ?? this.placement);

  @override
  bool operator ==(Object other) => other is VoiceAppend && other.note == note && other.text == text && other.placement == placement;

  @override
  int get hashCode => Object.hash(kind, note, text, placement);

  @override
  String toString() => '{do: append, note: $note, text: $text, placement: $placement}';
}

/// A new list with [items], or a new note with [body] (the words, as sentences).
final class VoiceCreate<N extends Candidate> extends VoiceAction<N> {
  const VoiceCreate({required this.title, required this.items, required this.tasks, this.body, this.template, this.place});

  final String title;
  final List<String> items;
  final bool tasks;
  final String? body;

  /// A template said for it and the place it goes in ("new bug in Kiln"; template_ask.dart).
  final String? template;
  final String? place;

  @override
  String get kind => 'create';

  VoiceCreate<N> copyWith({String? title, List<String>? items}) => VoiceCreate<N>(title: title ?? this.title, items: items ?? this.items, tasks: tasks, body: body, template: template, place: place);

  @override
  bool operator ==(Object other) => other is VoiceCreate && other.title == title && _same(other.items, items) && other.tasks == tasks && other.body == body && other.template == template && other.place == place;

  @override
  int get hashCode => Object.hash(kind, title, Object.hashAll(items), tasks, body, template, place);

  @override
  String toString() => '{do: create, title: $title, items: $items, tasks: $tasks${body == null ? '' : ', body: $body'}${template == null ? '' : ', template: $template, in: $place'}}';
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The step with no native side: there is no model to ask.
Future<StepResult> runVoiceStep(String stage, String? kind, String transcript, List<String> titles, [String? draft]) async =>
    const StepUnavailable(reason: 'The on-device model runs in the installed app.');

int _sequence = 0;

String _failureText(Object failure) {
  final text = '$failure';
  for (final lead in const ['Exception: ', 'Error: ']) {
    if (text.startsWith(lead)) return text.substring(lead.length);
  }
  return text;
}

/// The native step, over the host's [invoke] (`runVoiceStep`). [preferredModel] is the preferences' `formatModel`.
VoiceStep voiceStepOver(InstructionInvoke invoke, {String? preferredModel, int Function()? now}) {
  return (stage, kind, transcript, titles, [draft]) async {
    final at = now != null ? now() : DateTime.now().millisecondsSinceEpoch;
    final id = 'voice-${at.toRadixString(36)}-${_sequence += 1}';
    try {
      final value = await invoke('ai_voice_step', {
        'request': {
          'id': id,
          'transcript': transcript,
          'titles': titles.take(60).toList(),
          'stage': stage,
          'kind': kind,
          'draft': ?draft,
          'preferredModel': preferredModel ?? '',
        },
      });
      if (value is Map) {
        final status = value['status'];
        if (status == 'answer' && value['raw'] is String && value['model'] is String) {
          return StepAnswer(answer: value['answer'], raw: value['raw'] as String, model: value['model'] as String);
        }
        if (status == 'refused' && value['reason'] is String) return StepRefused(reason: value['reason'] as String);
        if (status == 'unavailable' && value['reason'] is String) return StepUnavailable(reason: value['reason'] as String);
      }
      return const StepUnavailable(reason: 'The on-device model returned something unexpected.');
    } catch (failure) {
      return StepUnavailable(reason: _failureText(failure));
    }
  };
}

String _two(int n) => n.toString().padLeft(2, '0');

/// The native engine as the voice log should read it: whether a model is in memory, what is running or waiting (a run
/// that never ends shows here with its age), and the last things it did (`engineDiagnostics`). Never throws; with no
/// native side there is nothing to read.
Future<List<String>> Function([int events]) diagnosticsOver(InstructionInvoke? invoke) {
  return ([events = 6]) async {
    if (invoke == null) return const [];
    try {
      final read = await invoke('ai_diagnostics', const {}).timeout(const Duration(seconds: 2), onTimeout: () => throw TimeoutException('no answer in 2 s'));
      final d = read as Map;
      final runs = (d['runs'] as List).cast<Map>();
      final line = runs.isEmpty ? 'none' : runs.map((run) => '${run['what']} ${run['id']} for ${((run['ageMs'] as num) / 1000).toStringAsFixed(1)}s').join(', ');
      final started = d['engineStarted'] == true;
      final loaded = d['modelLoaded'] == true;
      final seen = (d['events'] as List).cast<Map>();
      return [
        'engine: ${started ? (loaded ? 'model in memory' : 'started, model not in memory') : 'not started yet'}; running: $line',
        for (final event in seen.skip(seen.length > events ? seen.length - events : 0))
          () {
            final time = DateTime.fromMillisecondsSinceEpoch((event['at'] as num).toInt());
            return 'engine ${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}: ${event['line']}';
          }(),
      ];
    } catch (failure) {
      return ['engine: could not be read (${failure is TimeoutException ? failure.message : _failureText(failure)})'];
    }
  };
}

/// The sort's kind, or null for an answer that is not one of the four (`readSort`).
String? readSort(Object? answer) {
  final kind = answer is Map ? answer['kind'] : null;
  return kind is String && sortKinds.contains(kind) ? kind : null;
}

/// [value] as text for a note: a string of at most [max] characters with no control characters, its runs of spaces
/// as one; otherwise null.
String? _text(Object? value, int max) {
  if (value is! String || value.trim().isEmpty) return null;
  final runes = value.runes;
  if (runes.length > max || runes.any((c) => c < 32)) return null;
  return value.replaceAll(_spaces, ' ').trim();
}

final RegExp _spaces = RegExp(r'\s+');
final RegExp _token = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final RegExp _digits = RegExp(r'^\d+$');
final RegExp _joiner = RegExp(r'^(?:the|and|for|with)$');
final RegExp _hasDigit = RegExp(r'\d');
final RegExp _plural = RegExp(r's$');

const List<String> _numbers = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty'];

List<String> _tokens(String text) => [for (final match in _token.allMatches(unaccented(text.toLowerCase()))) match.group(0)!];

/// The words of [said], lower-cased, for checking that something was said (`wordsOf`).
Set<String> wordsOf(String said) {
  final words = _tokens(said);
  final all = <String>{};
  for (final word in words) {
    all.add(word);
    // "part two" said, "Part 2" written, and the other way round.
    final spelled = _numbers.indexOf(word);
    if (spelled >= 0) all.add('$spelled');
    if (_digits.hasMatch(word)) {
      final number = int.tryParse(word);
      if (number != null && number < _numbers.length) all.add(_numbers[number]);
    }
    // "spiderman" said, "Spider-Man" written: the joined and the split forms both count.
    all.add(word.replaceFirst(_plural, ''));
  }
  // Two words said together also count as their joined form: "spider man" is "spiderman".
  for (var i = 0; i + 1 < words.length; i += 1) {
    all.add('${words[i]}${words[i + 1]}');
  }
  return all;
}

/// Whether every word of [written] (three letters or more, and every number) was said. Small joining words may be
/// added.
bool grounded(String written, Set<String> said) {
  final words = _tokens(written);
  final joined = words.join();
  if (joined.isNotEmpty && said.contains(joined)) return true;
  return words.every((word) => (word.length < 3 && !_hasDigit.hasMatch(word)) || said.contains(word) || said.contains(word.replaceFirst(_plural, '')) || _joiner.hasMatch(word));
}

final RegExp _marks = RegExp(r'[\\`*_\[\]<>|]');
final RegExp _blockLead = RegExp(r'^(\s*)([#>+-]|\d+[.)])(?=\s|$)');

/// Model text as literal note text: what it says stays, but it cannot open a heading, quote, list, link, code or
/// HTML. Lighter than escaping every mark, so "St. Louis" and "Spider-Man" read as they are in the editor.
String plainText(String said) => said.replaceAllMapped(_marks, (m) => '\\${m[0]}').replaceFirstMapped(_blockLead, (m) => '${m[1]}\\${m[2]}');

/// The model's plan, checked (`ReadPlan`).
class ReadPlan<N extends Candidate> {
  const ReadPlan({required this.actions, required this.note, required this.problems});

  final List<VoiceAction<N>> actions;

  /// The rest of what was said, worth its own note; null for none.
  final String? note;

  /// What the checks set aside, for the voice log and the notice.
  final List<String> problems;
}

/// The model's plan, checked against the recording and the person's notes; null for a plan of the wrong shape
/// (`readPlan`).
ReadPlan<N>? readPlan<N extends Candidate>(Object? answer, String transcript, List<N> notes) {
  if (answer is! Map) return null;
  final actions = answer['actions'];
  if (actions is! List || actions.length > 3) return null;
  final said = wordsOf(transcript);
  final problems = <String>[];
  final out = <VoiceAction<N>>[];

  List<String> itemsOf(Object? value) {
    if (value is! List) return const [];
    final items = <String>[];
    for (final raw in value.take(50)) {
      final item = _text(raw, 200);
      if (item == null) continue;
      if (!grounded(item, said)) {
        problems.add('dropped “$item”: not something you said');
        continue;
      }
      items.add(plainText(item));
    }
    return items;
  }

  for (final raw in actions) {
    if (raw is! Map) continue;
    final as = raw['as'] == 'tasks'
        ? 'tasks'
        : raw['as'] == 'text'
            ? 'text'
            : 'list';
    if (raw['do'] == 'append') {
      final title = _text(raw['note'], 120);
      if (title == null) continue;
      final target = findNote<N>(title, notes);
      if (target is! FoundResolved<N>) {
        problems.add(target is FoundUnsure<N> ? '“$title” matches more than one note' : 'no note called “$title”');
        continue;
      }
      // A book is never written into by voice (docs/BOOKS.md), whoever read the command.
      final body = target.note.noteBody;
      if (body != null && isBookBody(body)) {
        problems.add('“$title” is a book, which a recording does not write into');
        continue;
      }
      final items = itemsOf(raw['items']);
      final words = _text(raw['text'], 4000);
      if (as == 'text' || (items.isEmpty && words != null)) {
        if (words == null || !grounded(words, said)) {
          problems.add(words != null ? 'dropped text for $title: not what you said' : 'nothing to add to $title');
          continue;
        }
        out.add(VoiceAppend<N>(note: target.note, text: plainText(words), placement: const Placement(how: PlacementHow.leave, task: false, many: false)));
        continue;
      }
      if (items.isEmpty) {
        problems.add('nothing to add to $title');
        continue;
      }
      out.add(VoiceAppend<N>(
        note: target.note,
        text: items.join(', '),
        placement: Placement(how: PlacementHow.item, task: as == 'tasks', many: items.length > 1, items: items),
      ));
    } else if (raw['do'] == 'create') {
      final title = _text(raw['title'], 120);
      if (title == null || !grounded(title, said)) {
        problems.add(title != null ? 'dropped the new list “$title”: not a name you said' : 'a new list with no name');
        continue;
      }
      final words = as == 'text' ? _text(raw['text'], 4000) : null;
      if (as == 'text' && (words == null || !grounded(words, said))) {
        problems.add(words != null ? 'dropped the note text for $title: not what you said' : 'a new note $title with nothing in it');
        continue;
      }
      out.add(VoiceCreate<N>(
        title: plainText(listTitle(title)),
        items: as == 'text' ? const [] : itemsOf(raw['items']),
        tasks: as == 'tasks',
        body: words != null ? plainText(words) : null,
      ));
    }
  }

  var rest = answer['note'] == null ? null : _text(answer['note'], 4000);
  if (rest != null && !grounded(rest, said)) {
    problems.add('dropped the note text: not what you said');
    rest = null;
  }
  // A small model often hands back the whole recording as "the rest". If it holds everything the actions already
  // took, it is the transcript again, not something left over.
  if (rest != null && out.isNotEmpty) {
    final inRest = wordsOf(rest);
    final taken = [
      for (final action in out)
        switch (action) {
          VoiceCreate<N>() => [action.title, ...action.items, action.body ?? ''].join(' '),
          VoiceAppend<N>() => (action.placement.items?.isNotEmpty ?? false) ? action.placement.items!.join(' ') : action.text,
        },
    ];
    if (taken.every((words) => grounded(words, inRest))) {
      problems.add('dropped the rest of the note: it repeats what was already taken');
      rest = null;
    }
  }
  return ReadPlan<N>(actions: out, note: rest != null ? plainText(rest) : null, problems: problems);
}
