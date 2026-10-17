/// The app's own Claude, for the whole app (docs/CLAUDE_APP.md): the settings, the one run at a time, the
/// conversation an Ask Claude sheet continues, and the inbox.
///
/// One run at a time: an ask while one is working waits for it (the inbox's requests queue behind the person's).
/// The conversation is kept until the sheet's New chat or the app closes; it is never written anywhere.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'claude_run.dart';
import 'claude_settings.dart';
import 'claude_tools.dart';
import 'messages_api.dart';

/// The title of the note of standing instructions the connector keeps (mcp/server.ts `ensureRulesNote`), handed to
/// the app's Claude too.
const String claudeRulesTitle = 'Claude rules';

class ClaudeRunner extends ChangeNotifier {
  ClaudeRunner({required this.settings, required this.notes, required this.desk, ClaudeApi Function(String key)? api, DateTime Function()? now})
      : _api = api ?? ((key) => ClaudeApi(key: key)),
        _now = now ?? DateTime.now {
    settings.addListener(notifyListeners);
  }

  final ClaudeSettings settings;
  final ClaudeNotes notes;
  final ClaudeDesk desk;
  final ClaudeApi Function(String key) _api;
  final DateTime Function() _now;

  ClaudeRun? _run;

  /// The run working now, or the last one.
  ClaudeRun? get run => _run;

  bool get working => _run?.working ?? false;

  /// The ask the sheet shows, for a follow-up: the conversation's messages so far.
  List<Map<String, Object?>> _history = const [];

  /// The runs of this conversation, oldest first, for the sheet.
  final List<ClaudeRun> conversation = [];

  Future<void> _queue = Future<void>.value();

  /// Whether Claude can be asked: a key is kept.
  bool get ready => settings.hasKey;

  /// Asks Claude. In the sheet's conversation unless [alone] (the inbox's requests are each their own). Answers the
  /// run once it has started, which is after any run before it has ended.
  Future<ClaudeRun> ask(String prompt, {bool alone = false, String? extraSystem}) {
    final started = Completer<ClaudeRun>();
    _queue = _queue.then((_) => _start(prompt, started, alone: alone, extraSystem: extraSystem)).catchError((Object error) {
      // A failure here never stops the asks after it.
      if (!started.isCompleted) started.completeError(error);
    });
    return started.future;
  }

  Future<void> _start(String prompt, Completer<ClaudeRun> started, {required bool alone, String? extraSystem}) async {
    await settings.load();
    final key = settings.key;
    if (key == null) {
      started.completeError(const ClaudeError('Add your Anthropic API key in Settings › Ask Claude.'));
      return;
    }
    String? rules;
    try {
      rules = (await notes.read(title: claudeRulesTitle))?.body;
    } catch (_) {
      rules = null;
    }
    final system = [claudeSystem(now: _now(), rules: rules), ?extraSystem].join('\n\n');
    final made = ClaudeRun(api: _api(key), model: settings.model, effort: settings.effortChosen ? settings.effort : null, notes: notes, desk: desk, prompt: prompt, system: system, history: alone ? null : _history);
    _run?.removeListener(notifyListeners);
    _run = made..addListener(notifyListeners);
    if (!alone) conversation.add(made);
    notifyListeners();
    started.complete(made);
    await made.run();
    if (!alone) _history = made.messages;
    notifyListeners();
  }

  /// Stops the run working now.
  void stop() => _run?.stop();

  /// A fresh conversation in the sheet.
  void newChat() {
    if (working) return;
    _history = const [];
    conversation.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    settings.removeListener(notifyListeners);
    _run?.removeListener(notifyListeners);
    super.dispose();
  }
}
