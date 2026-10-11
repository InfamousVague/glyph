// A run landing in the note on screen (lib/ai/note_landing.dart). A port of `src/app/ai/useLanding.test.tsx`, case
// for case. The model answers when the test says so (ai/runs.dart `simulateRuns`, as in runs_test.dart); the page's
// `EditorView` is a state and a dispatch.

import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:ghost_md/ai/ai_changes.dart';
import 'package:ghost_md/ai/available.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/log.dart';
import 'package:ghost_md/ai/note_landing.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/ai/start.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/note/byline.dart' show authorsOf;

import 'ai_changes_test.dart' show TestView;
import 'runs_test.dart' show Fake;

const ready = Available(model: 'qwen3.5-4b', chosen: 'qwen3.5-4b');
final List<Fake> fakes = [];

/// Lets a run's futures settle.
Future<void> settle() => Future<void>.delayed(Duration.zero);

TestView open(String doc) => TestView(EditorState.create(doc: doc, extensions: aiChangesState()));

void main() {
  final shown = <NoteLanding>[];

  /// The note, drawn: the page's `<Note noteId editor onDropped />`.
  void show(String noteId, TestView editor, {void Function(int count)? onDropped}) =>
      shown.add(NoteLanding(noteId, editor, LandingOptions(wisp: () => false, haptic: () => false, owner: () => 'matt', onDropped: onDropped)));

  setUp(() {
    useStored(MemoryStored());
    fakes.clear();
    simulateRuns((options) {
      final fake = Fake(options);
      fakes.add(fake);
      return fake.run;
    });
  });

  tearDown(() {
    for (final landing in shown) {
      landing.dispose();
    }
    shown.clear();
    forgetAllRuns();
    simulateRuns(null);
  });

  group('a run landing in the note on screen', () {
    test('puts each line in as the model finishes it, then the tidied answer, signed by the AI and kept for Undo', () async {
      const before = 'call sam\nbuy eggs\n';
      final v = open(before);
      show('n1', v);
      final started = startNoteRun(v, 'n1', RunKind.format, ready) as StartedRun;
      await settle();
      // A line lands only once its newline has come; the one under the pen waits.
      fakes[0].report(partial: '# Call Sam\n- Buy');
      expect(v.state.doc.toString(), '# Call Sam\nbuy eggs\n');
      expect(v.state.field(aiChangesField), isNotEmpty);
      fakes[0].finish('# Call Sam\n- Buy eggs\n');
      await settle();
      final after = v.state.doc.toString();
      expect(after.endsWith('# Call Sam\n- Buy eggs\n'), isTrue);
      // The person owns the note and the app's model co-wrote it.
      expect(authorsOf(after), ['matt', 'Ghost']);
      // The bookmark is put away, and the log has the words before and after.
      expect(v.state.field(landingField), isNull);
      final logged = runsOf('n1')[0];
      expect((logged.id, logged.outcome, logged.before, logged.after), (started.handle.id, RunOutcome.done, before, after));
    });

    test('keeps what landed when the run is stopped, and signs nothing', () async {
      final v = open('call sam\nbuy eggs\n');
      show('n2', v);
      final started = startNoteRun(v, 'n2', RunKind.format, ready) as StartedRun;
      await settle();
      fakes[0].report(partial: '# Call Sam\n');
      started.handle.cancel();
      await settle();
      expect(v.state.doc.toString(), '# Call Sam\nbuy eggs\n');
      expect(authorsOf(v.state.doc.toString()), isEmpty);
      expect(v.state.field(landingField), isNull);
      final logged = runsOf('n2')[0];
      expect((logged.outcome, logged.before, logged.after), (RunOutcome.stopped, 'call sam\nbuy eggs\n', '# Call Sam\nbuy eggs\n'));
    });

    test('leaves the review’s run alone: its findings land by their own road', () async {
      final v = open('fix the seat bar\n');
      show('n3', v);
      final handle = startRun(const RunRequest(noteId: 'n3', kind: RunKind.review, model: 'qwen3.5-4b', system: '', prompt: 'x', maxTokens: 100));
      await settle();
      fakes[0].report(partial: '[{"check":"words"}]\n');
      fakes[0].finish('[]\n');
      await handle.done;
      await settle();
      expect(v.state.doc.toString(), 'fix the seat bar\n');
    });

    test('keeps a line the person rewrote while the model was on it, and says the model’s was dropped', () async {
      final dropped = <int>[];
      final v = open('call sam\nbuy eggs\n');
      show('n4', v, onDropped: dropped.add);
      startNoteRun(v, 'n4', RunKind.format, ready);
      await settle();
      fakes[0].report(partial: '# Call Sam\n');
      // The person rewrites the next line while the model is still on it.
      final second = v.state.doc.line(2);
      v.dispatch(TransactionSpec(changes: ChangeSpec(from: second.from, to: second.to, insert: 'buy eggs and milk'), userEvent: 'input.type'));
      fakes[0].report(partial: '# Call Sam\n- Buy eggs\n');
      expect(v.state.doc.toString(), '# Call Sam\nbuy eggs and milk\n');
      fakes[0].finish('# Call Sam\n- Buy eggs\n');
      await settle();
      expect(v.state.doc.toString(), contains('# Call Sam\nbuy eggs and milk\n'));
      expect(v.state.doc.toString(), isNot(contains('- Buy eggs')));
      // How many is told once, when the run is done, and the note's toast says it. One line was dropped, but it says
      // 2: a known fault in ai/land.dart Lander.finish, carried over from the page, which counts the line as it
      // lands and again as it reads the finished answer over what landed. Pinned so a change to the count shows
      // here; once finish() is fixed on the page and here this reads [1].
      expect(dropped, [2]);
    });

    test('puts the model’s version above a rewritten line when it comes only with the finished answer (a known fault)', () async {
      final dropped = <int>[];
      final v = open('call sam\nbuy eggs\n');
      show('n5', v, onDropped: dropped.add);
      startNoteRun(v, 'n5', RunKind.format, ready);
      await settle();
      fakes[0].report(partial: '# Call Sam\n');
      final second = v.state.doc.line(2);
      v.dispatch(TransactionSpec(changes: ChangeSpec(from: second.from, to: second.to, insert: 'buy eggs and milk'), userEvent: 'input.type'));
      // The last line has no newline, so the model's version of it arrives only with the finished answer.
      fakes[0].finish('# Call Sam\n- Buy eggs');
      await settle();
      // The person's line stays, but the model's is put in above it rather than dropped, and nothing says so:
      // finish() strikes up to the cursor without moving past the line the person touched, so it finds nothing ahead
      // to match. The page's fault, pinned here as it is there so a fix shows; fixed, the note under its signature
      // reads '# Call Sam\nbuy eggs and milk\n' and onDropped says 1.
      expect(v.state.doc.toString(), '---\nauthors: matt, Ghost\n---\n# Call Sam\n- Buy eggs\nbuy eggs and milk\n');
      expect(dropped, isEmpty);
    });
  });
}
