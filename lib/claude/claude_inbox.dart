/// The "Ask Claude" inbox, worked through by the app itself (docs/CLAUDE_APP.md, "The inbox"; docs/CLAUDE_LIVE.md,
/// "The Ask Claude inbox"). The note is the connector's: a personal note titled "Ask Claude" whose open `- [ ]`
/// items are requests. The connector's prompt and the Mac's scheduled routine work through it now and then; with a
/// key kept on this device and the inbox switch on (Settings › Claude), the app does each request a few
/// seconds after it is written, live, and answers it in the connector's own way: a line under it, indented two
/// spaces, `  - ` and one sentence of what was done, and the request ticked unless it could not be done.
///
/// A request is written in the inbox, so it is the person's typing that adds one: a line is taken as a request only
/// once it has stood unchanged for [inboxSettle], and never while the caret is on it. An item that has an answer
/// under it is done, ticked or not. Each request is asked once a launch, so one that fails is not asked again until
/// it is changed.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'claude_run.dart';
import 'claude_runner.dart';

/// The inbox's title (mcp/prompts.ts `INBOX_TITLE`).
const String inboxTitle = 'Ask Claude';

/// How long a request stands unchanged before it is asked.
const Duration inboxSettle = Duration(seconds: 4);

/// One open request in the inbox's words.
@immutable
class InboxRequest {
  const InboxRequest({required this.line, required this.indent, required this.text});

  /// Its line's number, from 0.
  final int line;
  final String indent;
  final String text;

  @override
  bool operator ==(Object other) => other is InboxRequest && other.line == line && other.indent == indent && other.text == text;

  @override
  int get hashCode => Object.hash(line, indent, text);
}

final RegExp _open = RegExp(r'^(\s*)[-*+] \[ \] (.*\S.*)$');
final RegExp _item = RegExp(r'^(\s*)[-*+] ');

/// The open requests with no answer under them, in order.
List<InboxRequest> openRequests(String body) {
  final lines = body.split('\n');
  final found = <InboxRequest>[];
  var fence = false;
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```')) fence = !fence;
    if (fence) continue;
    final match = _open.firstMatch(line);
    if (match == null) continue;
    final indent = match.group(1)!;
    // An answer is the next line, an item indented deeper than the request.
    if (i + 1 < lines.length) {
      final next = _item.firstMatch(lines[i + 1]);
      if (next != null && next.group(1)!.length > indent.length) continue;
    }
    found.add(InboxRequest(line: i, indent: indent, text: match.group(2)!.trim()));
  }
  return found;
}

/// [body] with [request] answered: [answer] on a line under it, and its box ticked where [done]. Null when the
/// request is no longer where it was, as it was (the person changed it meanwhile).
String? answerRequest(String body, InboxRequest request, String answer, {required bool done}) {
  final lines = body.split('\n');
  // The request found by its words: lines above it may have come or gone while Claude worked.
  var at = -1;
  for (var i = 0; i < lines.length; i += 1) {
    final match = _open.firstMatch(lines[i]);
    if (match != null && match.group(2)!.trim() == request.text && match.group(1) == request.indent) {
      if (i + 1 < lines.length) {
        final next = _item.firstMatch(lines[i + 1]);
        if (next != null && next.group(1)!.length > request.indent.length) continue;
      }
      at = i;
      break;
    }
  }
  if (at < 0) return null;
  if (done) lines[at] = lines[at].replaceFirst('[ ]', '[x]');
  final said = answer.replaceAll('\n', ' ').trim();
  lines.insert(at + 1, '${request.indent}  - ${said.isEmpty ? 'Done.' : said}');
  return lines.join('\n');
}

/// The inbox as the connector makes it the first time (mcp/prompts.ts `INBOX_BODY`), with [line] as its first
/// request in place of the empty to-do.
String newInboxBody(String line) => '# $inboxTitle\n\nWrite a request for Claude as a to-do below, one per line. Claude works through the open ones: it does each, writes what it did on a line under it, and ticks it.\n\n$line\n';

/// [body] with [line] added as its newest request: after the last to-do of the list, in an empty to-do's place
/// where the list ends with one, else at the end.
String addInboxRequest(String body, String line) {
  final lines = body.split('\n');
  // An empty `- [ ]` at the end of the list is the place for it, as the connector leaves one.
  for (var i = lines.length - 1; i >= 0; i -= 1) {
    if (lines[i].trim().isEmpty) continue;
    if (RegExp(r'^\s*[-*+] \[ \]\s*$').hasMatch(lines[i])) {
      lines[i] = line;
      return lines.join('\n');
    }
    break;
  }
  final trimmed = body.trimRight();
  return '${trimmed.isEmpty ? '' : '$trimmed\n'}$line\n';
}

/// What Claude is told with each request.
String inboxPrompt(String request) => [
      'A request from my “$inboxTitle” inbox in Ghost.md:',
      '',
      request,
      '',
      'Do it with your tools. Do not change the “$inboxTitle” note itself: the app writes your answer under the request.',
      'End your reply with one last line on its own: `DONE: ` or `COULD NOT: ` and then one sentence saying what you did (or why it could not be done), naming any note you made or changed as [[its title]].',
    ].join('\n');

/// The last line's verdict and sentence.
({bool done, String sentence}) inboxVerdict(String answer) {
  final lines = answer.trim().split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
  if (lines.isEmpty) return (done: true, sentence: 'Done.');
  final last = lines.last.replaceAll('`', '');
  if (last.toUpperCase().startsWith('DONE:')) return (done: true, sentence: last.substring(5).trim());
  if (last.toUpperCase().startsWith('COULD NOT:')) return (done: false, sentence: last.substring(10).trim());
  final sentence = last.length > 240 ? '${last.substring(0, 237)}…' : last;
  return (done: true, sentence: sentence);
}

/// Hears the library for the inbox and asks its requests.
class ClaudeInbox {
  /// [body] reads the inbox's words now (from its editor where it is open), or null for no inbox; [changes] says
  /// when they may have changed; [caretLine] is the line the person's caret is on in it, or null where it is not
  /// open; [write] changes its words (through its editor where it is open). [on] is whether the app's Claude is on
  /// (the Claude plugin's switch, lib/plugins/claude): off, nothing is asked, and [changes] says when it moves.
  ClaudeInbox({required this.runner, required this.body, required this.changes, required this.write, this.caretLine, this.on});

  final ClaudeRunner runner;
  final bool Function()? on;
  final ({String id, String body})? Function() body;
  final Listenable changes;
  final int? Function(String id)? caretLine;
  final Future<void> Function(String id, String Function(String body) change) write;

  final Set<String> _asked = {};
  Timer? _settle;
  bool _started = false;
  bool _working = false;

  void start() {
    if (_started) return;
    _started = true;
    changes.addListener(_heard);
    runner.settings.addListener(_heard);
    _heard();
  }

  void _heard() {
    _settle?.cancel();
    _settle = Timer(inboxSettle, _look);
  }

  Future<void> _look() async {
    if (_working || !(on?.call() ?? true) || !runner.ready || !runner.settings.inbox) return;
    final inbox = body();
    if (inbox == null) return;
    final caret = caretLine?.call(inbox.id);
    InboxRequest? next;
    var waiting = false;
    for (final request in openRequests(inbox.body)) {
      if (_asked.contains(request.text)) continue;
      if (caret == request.line) {
        waiting = true;
        continue;
      }
      next = request;
      break;
    }
    if (next == null) {
      // A request under the person's caret is looked at again a little later: moving the caret changes no note.
      if (waiting) _heard();
      return;
    }
    _working = true;
    _asked.add(next.text);
    try {
      final run = await runner.ask(inboxPrompt(next.text), alone: true);
      await _ended(run);
      final verdict = run.state == ClaudeState.done
          ? inboxVerdict(run.answer)
          : (done: false, sentence: run.state == ClaudeState.stopped ? 'Stopped before it was done.' : 'Could not be done: ${run.problem ?? 'it stopped'}.');
      final request = next;
      await write(inbox.id, (words) => answerRequest(words, request, verdict.sentence, done: verdict.done) ?? words);
    } catch (_) {
      // No key, or the inbox went: the request stays open, asked again next launch.
    } finally {
      _working = false;
    }
    // The next, if any.
    _heard();
  }

  Future<void> _ended(ClaudeRun run) async {
    if (!run.working && run.state != ClaudeState.idle) return;
    final done = Completer<void>();
    void heard() {
      if (!run.working && run.state != ClaudeState.idle && !done.isCompleted) done.complete();
    }

    run.addListener(heard);
    heard();
    await done.future;
    run.removeListener(heard);
  }

  void dispose() {
    _settle?.cancel();
    if (_started) {
      changes.removeListener(_heard);
      runner.settings.removeListener(_heard);
    }
  }
}
