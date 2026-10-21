/// A request from the watch asked of the app's own Claude (lib/watch/watch_notes.dart, "To Claude"): the run asked,
/// followed to its end, and what came of it. The root's own (lib/root/root_claude.dart) puts up the talk's sheet with
/// the app in front, and asks out of sight through [RunnerWatchClaude] otherwise.
library;

import '../claude/claude_run.dart';
import '../claude/claude_runner.dart';
import 'watch_link.dart';
import 'watch_notes.dart';

/// What came of [run], once it is over: a failure ([ClaudeState.failed]) is why; done or stopped by the person is done.
Future<WatchAsked> watchRunOutcome(ClaudeRun run) async {
  final over = await ClaudeRunner.over(run);
  if (over.state == ClaudeState.failed) return WatchAskFailed(over.problem ?? 'Something went wrong');
  return WatchAskedDone(over.answer);
}

/// [WatchClaude] over [runner], in the chat's conversation as Talk to Claude asks, writing through [desk] (the
/// runner's own where null). A refusal before anything is sent (Claude off, no key, the month's spending limit) is a
/// failure, and the take a voice note saying so.
class RunnerWatchClaude implements WatchClaude {
  RunnerWatchClaude({required this.runner, required this.shown, this.desk});

  final ClaudeRunner runner;

  /// Whether Claude is shown here: its plugin on and a key on this device.
  final bool Function() shown;
  final ClaudeDesk? Function()? desk;

  @override
  Future<bool> ready() async {
    await runner.settings.load();
    return shown() && runner.settings.watch;
  }

  @override
  Future<WatchAsked> ask({required String words, required String prompt, required WatchTake take}) async {
    final ClaudeRun run;
    try {
      run = await runner.ask(prompt, desk: desk?.call());
    } catch (error) {
      return WatchAskFailed('$error');
    }
    return watchRunOutcome(run);
  }
}
