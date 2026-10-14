/// The last editor. A port of `src/app/capture/voicePolish.ts` (the Tauri app's voice work that followed 1.6).
///
/// The rules read a recording instantly but not always well: five things said slowly can land as one item, a title
/// keeps the "?" Whisper put on it, text keeps every pause as a full stop. The on-device model gets the draft and what
/// was said and returns the same plan, tidied.
///
/// It only ever improves a draft that already works, so anything doubtful keeps the draft: no model, a late answer, an
/// answer that fails the same checks the plan step's answers do (`readPlan`: made of words they said), a different
/// number of actions, or one that lost words they said.
///
/// What differs: nothing but the shapes.
library;

import 'dart:convert';

import '../ai/support/unaccent.dart' show unaccented;
import 'command.dart' show PlacementHow;
import 'route.dart' show Candidate;
import 'voice_log.dart' show VoiceTrace;
import 'voice_plan.dart';

/// Words that may go: small joiners, filler, and the word said to stop the recording.
const Set<String> _mayGo = {'and', 'also', 'then', 'the', 'for', 'with', 'um', 'uh', 'anyway', 'okay', 'end', 'go', 'you', 'can', 'please'};

/// Of the words in the draft, the share the polished version must still have.
const double _keepShare = 0.9;

final RegExp _token = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final RegExp _plural = RegExp(r's$');

List<String> _tokens(String text) => [for (final match in _token.allMatches(unaccented(text.toLowerCase()))) match.group(0)!.replaceFirst(_plural, '')];

String _textOf(VoiceAction<Candidate> action) => switch (action) {
      VoiceCreate() => [action.title, ...action.items, action.body ?? ''].join(' '),
      VoiceAppend() => (action.placement.items?.isNotEmpty ?? false) ? action.placement.items!.join(' ') : action.text,
    };

/// The plan's JSON for the actions as the rules made them: what the model is asked to tidy (`draftOf`).
String draftOf(List<VoiceAction<Candidate>> actions) {
  return jsonEncode({
    'actions': [
      for (final action in actions)
        switch (action) {
          VoiceCreate() => {
              'do': 'create',
              'title': action.title,
              'items': action.items,
              'text': action.body,
              'as': (action.body?.isNotEmpty ?? false) ? 'text' : (action.tasks ? 'tasks' : 'list'),
            },
          VoiceAppend() when action.placement.how == PlacementHow.item && (action.placement.items?.isNotEmpty ?? false) => {
              'do': 'append',
              'note': action.note.title,
              'items': action.placement.items,
              'text': null,
              'as': action.placement.task ? 'tasks' : 'list',
            },
          VoiceAppend() => {'do': 'append', 'note': action.note.title, 'items': const <String>[], 'text': action.text, 'as': 'text'},
        },
    ],
    'note': null,
  });
}

/// Whether [after] still has what [before] said, apart from the words that may go (`keepsWords`).
bool keepsWords(String before, String after) {
  final had = _tokens(before).where((word) => word.length >= 2 && !_mayGo.contains(word)).toList();
  if (had.isEmpty) return true;
  final kept = _tokens(after).toSet();
  return had.where(kept.contains).length / had.length >= _keepShare;
}

/// The polished plan laid over the draft, action by action: only the words change (a title, items, text); which note,
/// where and how it lands stay as the rules had them. Null when the answer cannot be trusted as a whole
/// (`mergePolished`).
List<VoiceAction<N>>? mergePolished<N extends Candidate>(
  List<VoiceAction<N>> actions,
  Object? answer,
  String transcript,
  List<N> notes, [
  List<String>? why,
]) {
  final read = readPlan<N>(answer, transcript, notes);
  if (read == null) {
    why?.add('the answer could not be read');
    return null;
  }
  why?.addAll(read.problems);
  if (read.actions.length != actions.length) {
    why?.add('it returned ${read.actions.length} actions for ${actions.length}');
    return null;
  }
  final merged = <VoiceAction<N>>[];
  for (var at = 0; at < actions.length; at += 1) {
    final draft = actions[at];
    final polished = read.actions[at];
    merged.add(switch ((draft, polished)) {
      (final VoiceCreate<N> draft, final VoiceCreate<N> polished) => polished.body != null || polished.title.isEmpty
          ? draft
          : draft.copyWith(title: polished.title, items: polished.items.isNotEmpty || draft.items.isEmpty ? polished.items : draft.items),
      (final VoiceAppend<N> draft, final VoiceAppend<N> polished) => _mergeAppend(draft, polished),
      _ => draft,
    });
  }
  return keepsWords(actions.map(_textOf).join(' '), merged.map(_textOf).join(' ')) ? merged : null;
}

VoiceAction<N> _mergeAppend<N extends Candidate>(VoiceAppend<N> draft, VoiceAppend<N> polished) {
  if (polished.note.id != draft.note.id) return draft;
  final items = polished.placement.items;
  if (draft.placement.how == PlacementHow.item && (draft.placement.items?.isNotEmpty ?? false)) {
    if (items == null || items.isEmpty) return draft;
    return draft.copyWith(
      text: items.join(', '),
      placement: draft.placement.copyWith(many: items.length > 1, items: items),
    );
  }
  if ((items?.isNotEmpty ?? false) || polished.text.trim().isEmpty) return draft;
  return draft.copyWith(text: polished.text);
}

String _cut(String text, int max) => text.length > max ? text.substring(0, max) : text;

/// The actions the rules made, polished by the model; the same actions when it cannot help. Never throws and never
/// blocks the card for longer than the model's own wait (native, a minute) (`polishActions`).
Future<List<VoiceAction<N>>> polishActions<N extends Candidate>(
  List<VoiceAction<N>> actions,
  String transcript,
  List<N> notes,
  VoiceStep step,
  VoiceTrace trace,
) async {
  if (actions.isEmpty) return actions;
  final draft = draftOf(actions);
  final StepResult polished;
  try {
    polished = await step('polish', null, transcript, const [], draft);
  } catch (failure) {
    trace.step('polish failed: ${failure is Exception ? '$failure'.replaceFirst('Exception: ', '') : failure}; kept the draft');
    return actions;
  }
  if (polished is! StepAnswer) {
    trace.step('polish ${polished.status}: ${polished is StepRefused ? polished.reason : (polished as StepUnavailable).reason}; kept the draft');
    return actions;
  }
  trace.step('polish (${polished.model}): ${polished.raw}');
  final why = <String>[];
  final merged = mergePolished<N>(actions, polished.answer, transcript, notes, why);
  for (final line in why) {
    trace.step('polish check: $line');
  }
  if (merged == null) {
    trace.step('polish: kept the draft');
    return actions;
  }
  final before = actions.map(_textOf).toList();
  final after = merged.map(_textOf).toList();
  trace.step(
    jsonEncode(after) == jsonEncode(before)
        ? 'polish: the draft was already right'
        : 'polish: tidied ${_cut(before.join(' | '), 200)} → ${_cut(after.join(' | '), 200)}',
  );
  return merged;
}
