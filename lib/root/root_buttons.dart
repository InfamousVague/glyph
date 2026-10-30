part of 'ghost_root.dart';

/// What a button in a note reaches past its note with (Matt, 2026-10-30, of a list of plain-Markdown features: "add all
/// 12"; lib/editor/buttons): Slack's and Discord's channels, the app's Claude, a note or a link opened, and a note made
/// from one of your templates. The press, its question and its job on the activity record are the editor's
/// (button_run.dart); these are only the doing.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which).
extension _RootButtons on _GhostRootState {
  ButtonWorld get _buttonWorld => ButtonWorld(
    post: _buttonPost,
    claude: _buttonClaude,
    openNote: _openTitle,
    openLink: widget.openLink,
    make: _buttonMake,
  );

  /// A channel by the name a button gives it, `#launch` or `launch`, in any case; the only one there is where it gives
  /// none.
  static T? _channelNamed<T>(List<T> list, String Function(T channel) name, String? said) {
    final want = (said ?? '').trim().replaceFirst(RegExp('^#'), '').toLowerCase();
    if (want.isEmpty) return list.length == 1 ? list.single : null;
    return list.where((channel) => name(channel).trim().replaceFirst(RegExp('^#'), '').toLowerCase() == want).firstOrNull;
  }

  Future<String> _buttonPost(String service, String? channel, String? text, String body) async {
    if (service == 'discord') {
      if (!plugins.isEnabled('discord')) throw 'Discord is switched off. Add it in the Market.';
      final list = discordChannels();
      final to = _channelNamed(list, (each) => each.name, channel);
      if (to == null) throw list.isEmpty ? 'Discord has no channels on this device yet.' : 'Discord has no channel called ${channel ?? 'that'} on this device.';
      await postToDiscord(to, discordFitted(text ?? discordNoteText(body)));
      return to.name;
    }
    if (!plugins.isEnabled('slack')) throw 'Slack is switched off. Add it in the Market.';
    final list = channels();
    final to = _channelNamed(list, (each) => each.name, channel);
    if (to == null) throw list.isEmpty ? 'Slack has no channels on this device yet.' : 'Slack has no channel called ${channel ?? 'that'} on this device.';
    await postToChannel(to, text ?? noteMessage(body));
    return to.name;
  }

  /// The app's Claude asked, on its own and not in the chat: the rule named, from the Claude rules it is given, or the
  /// prompt, on the note by its title. Finished when the run is.
  Future<void> _buttonClaude(String noteId, String title, {String? rule, String? prompt}) async {
    final named = title.trim().isEmpty ? 'the note open now' : 'the note “${title.trim()}”';
    final ask = rule != null && rule.trim().isNotEmpty
        ? 'Follow the rule “${rule.trim()}” from your Claude rules on $named, and change it as the rule says. Change nothing else.'
        : '${prompt!.trim()}\n\n(This is about $named.)';
    final run = await _claude.ask(ask, alone: true);
    await _claudeEnded(run);
    if (run.state == ClaudeState.failed) throw run.problem ?? 'Claude could not finish.';
  }

  /// A make: the template the button names, in the notebook or folder it names, or where a new note goes.
  bool _buttonMake(String template, String? place, String? title) {
    if (place != null && place.trim().isNotEmpty) {
      final made = _voiceFromTemplate(template, place, title ?? '');
      if (made == null) return false;
      final note = _showMade(made.body);
      made.file(note.id);
      return true;
    }
    final found = templateSaid(_allTemplates, template);
    if (found == null) return false;
    _new(null, found);
    return true;
  }
}

/// When [run] has ended, done, stopped or failed.
Future<void> _claudeEnded(ClaudeRun run) {
  bool ended() => run.state == ClaudeState.done || run.state == ClaudeState.stopped || run.state == ClaudeState.failed;
  if (ended()) return Future<void>.value();
  final finished = Completer<void>();
  void heard() {
    if (!ended() || finished.isCompleted) return;
    run.removeListener(heard);
    finished.complete();
  }

  run.addListener(heard);
  return finished.future;
}
