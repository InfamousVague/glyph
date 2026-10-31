// Starting a run on the note (lib/ai/start.dart). A port of src/app/ai/start.test.ts, case for case.
//
// The page mocked `startRun` to keep each request and answer a finished run; here `noteRunStarter` is the test's own
// for the same. The page's `EditorView` is a state and a dispatch (ai_changes_test.dart `TestView`).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_changes.dart';
import 'package:ghost_md/ai/available.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/land.dart';
import 'package:ghost_md/ai/log.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/ai/start.dart';
import 'package:ghost_md/ai/summary_ask.dart';
import 'package:ghost_md/ai/summary_keep.dart';
import 'package:ghost_md/ai/summary_text.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/state/state.dart';

import 'ai_changes_test.dart' show TestView;

/// Every run asked for; each answers `done` as a finished run, so what follows the end (the title) can be seen.
final List<RunRequest> requests = [];

RunState finished(RunRequest request, String id) => RunState(
      id: id,
      noteId: request.noteId,
      kind: request.kind,
      instruction: request.instruction,
      model: request.model,
      scope: request.scope,
      placement: request.placement,
      phase: RunPhase.done,
      lines: const [],
      partial: '',
      thought: '',
      text: null,
      promptTokens: 0,
      promptTokensDone: 0,
      outputTokens: 0,
      maxTokens: request.maxTokens,
      tokensPerSecond: 0,
      elapsedMs: 0,
      hardware: null,
      truncated: false,
      message: null,
      startedAt: 0,
      endedAt: 0,
      hash: request.hash,
      batch: request.batch,
    );

TestView open(String doc) => TestView(EditorState.create(doc: doc, extensions: aiChangesState()));

const ready = Available(model: 'qwen3.5-2b', chosen: 'qwen3.5-4b');

({int start, int cursor, int oldEnd})? landing(TestView v) {
  final at = v.state.field(landingField);
  return at == null ? null : (start: at.start, cursor: at.cursor, oldEnd: at.oldEnd);
}

void main() {
  setUp(() {
    useStored(MemoryStored());
    requests.clear();
    noteRunStarter = (request) {
      requests.add(request);
      final id = 'r${requests.length}';
      return RunHandle(id: id, done: Future.value(finished(request, id)), cancel: () {});
    };
  });
  tearDown(() => noteRunStarter = startRun);

  group('starting a run on the note', () {
    test('places each kind: a rewrite over the words, a summary above, a continuation under', () {
      expect(placementOf(RunKind.format), Placement.replace);
      expect(placementOf(RunKind.ask), Placement.replace);
      expect(placementOf(RunKind.summarize), Placement.prepend);
      expect(placementOf(RunKind.continueWriting), Placement.append);
    });

    test('gives the model the note after its front matter, and lands the rewrite there', () {
      final v = open('---\ntitle: "A"\n---\n# A\nwords\n');
      final started = startNoteRun(v, 'n', RunKind.format, ready);
      expect(started.ok, isTrue);
      final asked = requests[0];
      expect((asked.noteId, asked.kind, asked.model, asked.prompt, asked.scope), ('n', RunKind.format, 'qwen3.5-2b', '# A\nwords\n', const RunScope(from: 19, to: 29)));
      expect(landing(v), (start: 19, cursor: 19, oldEnd: 29));
    });

    test('gives the model the words after where the note was written, and lands the rewrite after it', () {
      final v = open('---\nlocation: 51.5074,-0.1278\nplace: "London"\n---\n# A\nwords\n');
      startNoteRun(v, 'n', RunKind.format, ready);
      expect((requests[0].prompt, requests[0].scope), ('# A\nwords\n', const RunScope(from: 50, to: 60)));
      expect(landing(v), (start: 50, cursor: 50, oldEnd: 60));
    });

    test('gives the model a rule with words under it, which the editor shows as words (core/front_matter.dart)', () {
      final v = open('---\nSome words here\n---\n# A\n');
      startNoteRun(v, 'n', RunKind.format, ready);
      expect((requests[0].prompt, requests[0].scope), ('---\nSome words here\n---\n# A\n', const RunScope(from: 0, to: 28)));
      expect(landing(v), (start: 0, cursor: 0, oldEnd: 28));
    });

    test('lands a summary above the note and a continuation under it', () {
      final v = open('# A\nwords\n');
      startNoteRun(v, 'n', RunKind.summarize, ready);
      expect(landing(v), (start: 0, cursor: 0, oldEnd: 0));
      startNoteRun(v, 'n', RunKind.continueWriting, ready);
      expect(landing(v), (start: 10, cursor: 10, oldEnd: 10));
      expect(requests[1].maxTokens, lessThanOrEqualTo(512));
    });

    test('puts an ask’s instruction in with the note, and refuses an ask with none', () {
      final v = open('# A\nwords\n');
      expect(startNoteRun(v, 'n', RunKind.ask, ready), const NotStarted('Say what to do with the note.'));
      startNoteRun(v, 'n', RunKind.ask, ready, instruction: ' add a title ');
      expect((requests[0].kind, requests[0].instruction, requests[0].prompt), (RunKind.ask, 'add a title', 'Instruction: add a title\n\nThe note:\n# A\nwords\n'));
    });

    test('lands a run placed on its own over its scope, whatever its kind would do', () {
      expect(landingAt(RunKind.summarize, const RunScope(from: 8, to: 20), 40, Placement.replace), (start: 8, cursor: 8, oldEnd: 20));
      expect(landingAt(RunKind.summarize, const RunScope(from: 8, to: 8), 40, Placement.replace), (start: 8, cursor: 8, oldEnd: 8));
    });

    test('says why it cannot start', () {
      final v = open('');
      expect(startNoteRun(v, 'n', RunKind.format, ready), const NotStarted('Nothing in the note yet.'));
      expect(startNoteRun(v, 'n', RunKind.format, const Unavailable(reason: 'Not here.', get: null, waiting: false)), const NotStarted('Not here.'));
      expect(requests, isEmpty);
    });
  });

  group('the recording’s summary as a run', () {
    const recording = SummaryAsk(words: 'That is the March launch settled. Sam owns the press list.', model: 'qwen3.5-4b', maxTokens: 300, replace: false);
    const answer = '# March launch\nWhat the call settled.\n\n- Launch in March.\n\n- [ ] Book the venue.';
    const section = '## Summary\nWhat the call settled.\n\n- Launch in March.\n\n- [ ] Book the venue.';

    /// The last run's answer streamed through its restore into a lander a character at a time, then finished: the
    /// note as it reads after.
    String stream(TestView v, String answer) {
      final restore = requests.last.restore!;
      final lander = Lander(v, 'r${requests.length}', const LanderOptions(wisp: false, haptic: false), v.state.doc.toString());
      for (var n = 1; n <= answer.length; n += 1) {
        final lines = restore(answer.substring(0, n), false).split('\n');
        lander.land(lines.sublist(0, lines.length - 1));
      }
      lander.finish(allLines(restore(answer, true)));
      return v.state.doc.toString();
    }

    test('is given the tape’s words and the recording prompt, and lands under the title with a blank line first', () {
      final v = open('# Planning call\n\nWe started with the launch.');
      final started = startRecordingRun(v, 'n', ready, recording);
      expect(started.ok, isTrue);
      final asked = requests[0];
      expect((asked.kind, asked.model, asked.prompt, asked.maxTokens, asked.scope, asked.placement), (RunKind.summarize, 'qwen3.5-4b', recording.words, 300, const RunScope(from: 16, to: 16), Placement.replace));
      expect(asked.system, contains('one recording'));
      expect(landing(v), (start: 16, cursor: 16, oldEnd: 16));
      // The answer shaped as it streams: the model's heading never lands, and a blank line comes first.
      expect(asked.restore!('# March launch\nWhat the call set', false), '\n## Summary\nWhat the call set');
      expect(asked.restore!(answer, true), '\n$section');
    });

    test('puts a blank line under a title that runs straight into its paragraph, so the section stands on its own', () {
      final v = open('# Planning call\nWe started with the launch.');
      startRecordingRun(v, 'n', ready, recording);
      expect(v.state.doc.toString(), '# Planning call\n\nWe started with the launch.');
      expect(requests[0].scope, const RunScope(from: 16, to: 16));
    });

    test('lands over the section the note has when it is still the app’s, carrying its ticked to-dos, and refuses one the person edited', () {
      const old = '## Summary\nThe old line.\n\n- [x] Send Sam the list.\n- [ ] Book the venue.';
      final v = open('# Planning call\n\n$old\n\nWe started with the launch.');
      keepSummary('n', const KeptSummary(text: old, model: 'm', at: 1, forMs: 1000));
      startRecordingRun(v, 'n', ready, recording);
      // The scope takes the section's newline with it, so the lander does not put another after its last line.
      expect((requests[0].scope, requests[0].placement), (const RunScope(from: 17, to: 17 + old.length + 1), Placement.replace));
      expect(landing(v), (start: 17, cursor: 17, oldEnd: 17 + old.length + 1));
      // No blank first over an old section, and the ticked to-do carried as it finishes.
      expect(requests[0].restore!(answer, false), section);
      expect(requests[0].restore!(answer, true), '$section\n- [x] Send Sam the list.');

      keepSummary('n', const KeptSummary(text: '## Summary\nSomething else.', model: 'm', at: 1, forMs: 1000));
      expect(startRecordingRun(v, 'n', ready, recording), const SummaryRefused('edited'));
      expect(startRecordingRun(v, 'n', ready, recording.replacing(true)).ok, isTrue);
      expect(startRecordingRun(v, 'n', ready, recording.ofWords(' ')), const SummaryRefused('nothing'));
    });

    test('remakes the section in place: the same answer leaves the note as it was, a shorter one leaves one blank line under it', () {
      const old = '## Summary\nThe old line.\n\n- Launch moves.\n\n- [ ] Book the venue.';
      const body = '# Planning call\n\n$old\n\nWe started with the launch.';
      final v = open(body);
      keepSummary('n', const KeptSummary(text: old, model: 'm', at: 1, forMs: 1000));
      startRecordingRun(v, 'n', ready, recording.replacing(true));
      expect(stream(v, '# T\nThe old line.\n\n- Launch moves.\n\n- [ ] Book the venue.'), body);
      startRecordingRun(v, 'n', ready, recording.replacing(true));
      expect(stream(v, '# T\nA newer line.\n\n- [ ] One thing.'), '# Planning call\n\n## Summary\nA newer line.\n\n- [ ] One thing.\n\nWe started with the launch.');
    });

    test('is closed by the kept text, so a list of the person’s under it is neither the section nor edited', () {
      const written = '## Summary\nWhat the call settled.\n\n- [ ] Book the venue.';
      const list = '- [ ] Call Sam\n- [ ] Book the room';
      final v = open('# Planning call\n\n$written\n\n$list');
      keepSummary('n', const KeptSummary(text: written, model: 'm', at: 1, forMs: 1000));
      final started = startRecordingRun(v, 'n', ready, recording);
      expect(started.ok, isTrue);
      expect(requests[0].scope, const RunScope(from: 17, to: 17 + written.length + 1));
      expect(stream(v, '# T\nA newer line.\n\n- [ ] Book the venue before the 10th.'), '# Planning call\n\n## Summary\nA newer line.\n\n- [ ] Book the venue before the 10th.\n\n$list');
    });

    test('lands the model’s heading as the title of a note with no words, which the section would otherwise title', () {
      var v = open('');
      expect(startRecordingRun(v, 'n', ready, recording).ok, isTrue);
      expect(stream(v, answer), '# March launch\n\n$section\n');
      v = open('![](image/a.jpg)');
      expect(startRecordingRun(v, 'n', ready, recording).ok, isTrue);
      expect(stream(v, answer), '![](image/a.jpg)\n\n# March launch\n\n$section\n');
    });

    test('takes the model’s heading as the title once the run is done, only while the note wears a meeting’s date title', () async {
      final v = open('# Meeting, 26 Sep 14:05\n\nWords.');
      startRecordingRun(v, 'n', ready, recording);
      requests[0].restore!(answer, true);
      await Future<void>.value();
      expect(v.state.doc.toString(), '# March launch\n\nWords.');
      final kept = open('# Sam’s call\n\nWords.');
      startRecordingRun(kept, 'n', ready, recording);
      requests[1].restore!(answer, true);
      await Future<void>.value();
      expect(kept.state.doc.toString(), '# Sam’s call\n\nWords.');
    });

    test('lands an answer the queue already has at once, as tracked changes with no run, and answers the section as landed', () {
      final v = open('# Planning call\n\nWe started with the launch.');
      final started = startRecordingRun(v, 'n', ready, recording.withText(answer));
      expect(started, const SummaryLanded(section));
      expect(requests, isEmpty);
      // Signed by the AI as a run's landing is (ai/note_landing.dart).
      expect(withoutSummaryFacts(v.state.doc.toString()), '---\nauthors: Ghost\n---\n# Planning call\n\n$section\n\nWe started with the launch.');
      expect(summarySection(v.state.doc.toString())?.text, section);
      // And the summary's facts, so the note itself says what the app wrote (summary_keep.dart `withSummaryFacts`).
      expect(summaryFactsOf(v.state.doc.toString())?.text, section);
      expect(summaryFactsOf(v.state.doc.toString())?.model, 'qwen3.5-4b');
      // Marked as the AI's lines, with the bookmark put away, and the before and after in the log for Undo.
      expect(v.state.field(aiChangesField), isNotEmpty);
      expect(v.state.field(landingField), isNull);
      expect(runsOf('n').any((r) => r.before == '# Planning call\n\nWe started with the launch.'), isTrue);
      // Over an old section the same way, and refused for one the person edited.
      keepSummary('n', const KeptSummary(text: section, model: 'm', at: 1, forMs: 1000));
      final again = startRecordingRun(v, 'n', ready, recording.withText('# T\nA newer line.\n\n- [ ] One thing.'));
      expect(again, const SummaryLanded('## Summary\nA newer line.\n\n- [ ] One thing.'));
      expect(withoutSummaryFacts(v.state.doc.toString()), '---\nauthors: Ghost\n---\n# Planning call\n\n## Summary\nA newer line.\n\n- [ ] One thing.\n\nWe started with the launch.');
      expect(startRecordingRun(v, 'n', ready, recording.withText(answer)), const SummaryRefused('edited'));
      expect(readSummary('n')?.text, section);
    });
  });

  group('where a run’s lines land', () {
    test('is over the part for a rewrite, at the part’s start for a summary, and at the very end for a continuation', () {
      const scope = RunScope(from: 12, to: 40);
      expect(landingAt(RunKind.format, scope, 60), (start: 12, cursor: 12, oldEnd: 40));
      expect(landingAt(RunKind.ask, scope, 60), (start: 12, cursor: 12, oldEnd: 40));
      expect(landingAt(RunKind.summarize, scope, 60), (start: 12, cursor: 12, oldEnd: 12));
      expect(landingAt(RunKind.continueWriting, scope, 60), (start: 60, cursor: 60, oldEnd: 60));
    });

    test('stays inside a note that has grown shorter since the run was asked for', () {
      expect(landingAt(RunKind.format, const RunScope(from: 12, to: 40), 20), (start: 12, cursor: 12, oldEnd: 20));
      expect(landingAt(RunKind.summarize, const RunScope(from: 30, to: 40), 20), (start: 20, cursor: 20, oldEnd: 20));
    });
  });
}
