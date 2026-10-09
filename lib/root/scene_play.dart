/// The scene after Done, played in Developer's bench from a script: what `src/app/diag/SceneBench.tsx` does inside
/// its card, given to lib/diag/scene_bench.dart as its `scene:` (the bench is a stage 9 piece and names nothing of
/// lib/scene itself).
///
/// The stages first; when they clear, the run, with the pretend model installed only round its start and taken out
/// the moment it returns, as the browser's own `?review` does, and again as the play goes, so no later real run is
/// ever played by the script. The run's note is the bench's own id, which no note has.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ai/kinds.dart' show RunKind;
import '../ai/review_stage.dart';
import '../ai/runs.dart';
import '../diag/scene_bench.dart';
import '../scene/at_work.dart';
import '../scene/scripted.dart';

/// [showSceneBench]'s `scene:`.
Widget scenePlay(BuildContext context, SceneBenchPlay play) => _ScenePlay(key: ValueKey<int>(play.opening), play: play);

class _ScenePlay extends StatefulWidget {
  const _ScenePlay({super.key, required this.play});
  final SceneBenchPlay play;

  @override
  State<_ScenePlay> createState() => _ScenePlayState();
}

class _ScenePlayState extends State<_ScenePlay> {
  ReviewStage? _stage;
  VoidCallback? _stop;

  @override
  void initState() {
    super.initState();
    final script = SceneScript.values.firstWhere((each) => each.name == widget.play.script, orElse: () => SceneScript.heat);
    _stop = scriptedStages((next) {
      if (!mounted) return;
      setState(() => _stage = next);
      if (next != null) return;
      simulateRuns(scriptedReview(script));
      startRun(RunRequest(noteId: widget.play.noteId, kind: RunKind.review, model: 'qwen3.5-4b', system: '', prompt: scriptPrompt, maxTokens: 1900, think: true, thinkBudget: 700));
      simulateRuns(null);
    });
  }

  @override
  void dispose() {
    _stop?.call();
    simulateRuns(null);
    final id = widget.play.noteId;
    unawaited(cancelRun(id).then<void>((_) => dismissRun(id), onError: (Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AtWork(inline: true, noteId: widget.play.noteId, opening: widget.play.opening, heard: scriptHeard, body: scriptBody, hasJob: true, stage: _stage);
}
