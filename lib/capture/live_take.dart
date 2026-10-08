/// A recording's notes as the live reader (`live_route.dart`) leaves them, over notes held in memory: the recorder's
/// bookkeeping without its screen, its microphone or its store. The voice suite (`voice_suite.dart`) plays each
/// script through it, and the live reader's tests read what a recording would write from it; the recorder applies
/// the same steps to its take and its writer, and writes the same bodies at Done, since both compose with
/// `placeTake`.
///
/// A port of `src/app/capture/liveTake.ts`.
///
/// What differs: the web's private `Written` is the public [Written] here, since [LiveTake.parts] and
/// [LiveTake.inserts] hold it and Dart cannot hand out a private type. An ask's `run` is the web's word for the kind
/// of run as a `String` (see `live_route.dart`). [LiveTake.result] answers a record where the web answers an object.
library;

import '../core/note_text.dart';
import 'append_body.dart';
import 'instruction_mutation.dart';
import 'live_route.dart';
import 'markdown.dart';
import 'place.dart' hide Placed;
import 'take_host.dart';
import 'take_types.dart';

/// A note held in memory: its id and its body.
class MemoryNote implements LiveNote {
  const MemoryNote({required this.id, required this.body});

  @override
  final String id;
  @override
  final String body;

  @override
  String toString() => '{id: $id, body: $body}';
}

/// The words for one note, as Done writes them.
class Written {
  Written({required this.note, required this.title, required this.placing, required this.segments});

  /// The note the words are for; null for a note of their own, made at Done.
  final MemoryNote? note;

  /// A note of their own by name ("New note “House chores”").
  final String? title;
  final Placing placing;
  List<Segment> segments;
}

class LiveTakeOptions {
  const LiveTakeOptions({this.own, this.locked, this.published});

  /// The note whose own Speak this is.
  final MemoryNote? own;
  final bool? locked;
  final bool Function(String id)? published;
}

class LiveTake {
  LiveTake(this._notes, [this._options = const LiveTakeOptions()]) : aim = _options.own, placing = _options.own != null ? placingFor(_options.own!.body, own: true) : end;

  final List<MemoryNote> _notes;
  final LiveTakeOptions _options;

  final LiveRoute<MemoryNote> live = LiveRoute<MemoryNote>();

  /// The take's words, for the note it is aimed at now.
  List<Segment> segments = [];
  MemoryNote? aim;

  /// A note of the take's own, to be made at Done with this title.
  String? pendingTitle;
  Placing placing;

  /// What was said before "New note", for the note it was said for.
  List<Written> parts = [];
  Map<int, Written> inserts = {};
  LiveCard<MemoryNote>? card;
  List<RouteView> chips = [];
  List<({String? run, String instruction})> asks = [];
  List<String> log = [];
  List<Span> commandSpans = [];
  List<Span> keywordSpans = [];

  /// The one-shots closed (`insert-end`), in order: the recorder shows each one's lines then.
  List<int> ended = [];
  bool routed = false;

  LiveContext<MemoryNote> _ctx() => LiveContext<MemoryNote>(
    notes: [
      for (final note in _notes)
        if (noteTitle(note.body).isNotEmpty) LiveCandidate(id: note.id, title: noteTitle(note.body), note: note),
    ],
    aim: aim,
    own: _options.own != null,
    locked: _options.locked ?? false,
    published: _options.published,
  );

  void phrase(Segment segment, int now) {
    apply(live.phrase(segment, _ctx(), now));
  }

  void tick(int now) {
    apply(live.tick(now, _ctx()));
  }

  void answer(CardChoice choice) {
    final card = this.card;
    if (card != null) apply(live.answer(card.id, choice, _ctx()));
  }

  void decline(int now) {
    apply(live.decline(_ctx(), now));
  }

  void close(int now) {
    apply(live.close(_ctx(), now));
  }

  /// A take-back's Undo, tapped.
  void undo(int id) {
    apply(live.undoTakeBack(id));
  }

  /// "New note", tapped: as the recorder's `startNewNote` does it, the reader told first.
  void forked() {
    apply(live.forked());
    apply(const [LiveStepNewNote()]);
  }

  void apply(List<LiveStep<MemoryNote>> steps) {
    for (final step in steps) {
      switch (step) {
        case LiveStepWords<MemoryNote>():
          segments = inOrder([...segments, step.segment]);
        case LiveStepUnword<MemoryNote>():
          segments = withoutWords(segments, step.segments);
        case LiveStepCommand<MemoryNote>():
          commandSpans.add(step.span);
        case LiveStepKeyword<MemoryNote>():
          keywordSpans.add(step.span);
        case LiveStepRoute<MemoryNote>():
          aim = step.note;
          pendingTitle = null;
          placing = step.placing;
          routed = true;
        case LiveStepRouteNew<MemoryNote>():
          aim = null;
          pendingTitle = step.title;
          placing = placingFor(listTitle(step.title), said: Said(task: step.task));
          routed = true;
        case LiveStepHome<MemoryNote>():
          final own = _options.own;
          aim = own;
          pendingTitle = null;
          placing = own != null ? placingFor(own.body, own: true) : end;
          routed = false;
        case LiveStepPlacing<MemoryNote>():
          placing = step.placing;
        case LiveStepInsert<MemoryNote>():
          inserts[step.id] = Written(note: step.note, title: null, placing: step.placing, segments: [...step.segments]);
        case LiveStepInsertWords<MemoryNote>():
          inserts[step.id]?.segments.addAll(step.segments);
        case LiveStepInsertUnword<MemoryNote>():
          final insert = inserts[step.id];
          if (insert != null) insert.segments = withoutWords(insert.segments, step.segments);
        case LiveStepInsertEnd<MemoryNote>():
          ended.add(step.id);
        case LiveStepInsertDrop<MemoryNote>():
          final insert = inserts.remove(step.id);
          if (insert != null) segments = inOrder([...segments, ...insert.segments]);
        case LiveStepNewNote<MemoryNote>():
          parts.add(Written(note: aim, title: pendingTitle, placing: placing, segments: segments));
          segments = [];
          aim = null;
          pendingTitle = null;
          placing = end;
          routed = false;
        case LiveStepCard<MemoryNote>():
          card = step.card;
        case LiveStepAsk<MemoryNote>():
          asks.add((run: step.run, instruction: step.instruction));
        case LiveStepChip<MemoryNote>():
          final view = step.view;
          if (view != null) chips.add(view);
        case LiveStepLog<MemoryNote>():
          log.add(step.line);
        case LiveStepHaptic<MemoryNote>():
          break;
      }
    }
  }

  /// The words for one note, as Done writes them.
  ({String? id, String body}) _written(Written into, Map<String, String> bodies) {
    final note = into.note;
    final title = into.title;
    final titled = note == null && title == null;
    final markdown = renderNote(into.segments, '', RenderOptions(titled: titled)).markdown;
    if (note != null) {
      final base = bodies[note.id] ?? note.body;
      return (id: note.id, body: placeTake(base, markdown, into.placing).body);
    }
    if (title != null && title.isNotEmpty) return (id: null, body: placeTake(listTitle(title), markdown, into.placing).body);
    return (id: null, body: markdown);
  }

  /// What the recording leaves: every existing note's body by id, and the notes it made, in order (the take's own
  /// first when it has words). Written as Done writes: the parts, then the one-shots, then the take's own aim.
  ({Map<String, String> bodies, List<String> made}) result() {
    final bodies = <String, String>{for (final note in _notes) note.id: note.body};
    final made = <String>[];
    void write(Written into) {
      if (renderNote(into.segments).markdown.trim().isEmpty && into.note != null) return;
      final written = _written(into, bodies);
      final id = written.id;
      if (id != null && id.isNotEmpty) {
        bodies[id] = written.body;
      } else if (written.body.trim().isNotEmpty) {
        made.add(written.body);
      }
    }

    parts.forEach(write);
    inserts.values.forEach(write);
    write(Written(note: aim, title: pendingTitle, placing: placing, segments: segments));
    return (bodies: bodies, made: made);
  }

  /// The body of note [id] after the recording.
  String? body(String id) => result().bodies[id];

  /// The page as it reads now: the note aimed at with the words where they go.
  String page() {
    final aim = this.aim;
    final pendingTitle = this.pendingTitle;
    final markdown = renderNote(segments, '', RenderOptions(titled: aim == null && pendingTitle == null)).markdown;
    if (aim != null) return placeTake(aim.body, markdown, placing).body;
    if (pendingTitle != null && pendingTitle.isNotEmpty) return placeTake(listTitle(pendingTitle), markdown, placing).body;
    return appendBody('', markdown);
  }
}
