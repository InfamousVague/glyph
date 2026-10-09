/// The GitHub plugin's page in Settings: the repos read on this phone, each with what wrote its briefing and a way
/// to forget it, and the token, which private repos need to be read and every repo needs before a note's list items
/// can go there as issues. Linking a repo to a note is on the note, from its cog. A port of
/// `src/app/plugins/github/GitHubPane.tsx` and `GitHubPane.module.css`.
///
/// What differs:
/// - The token is kept in the secure store (repos.dart), whose first read is not instant: the page draws again
///   when the plugin's storage or its secrets change, so a kept token shows as soon as it has been read.
/// - A repo's day is said in English, in the phone's own order once it has said which (core/locale_dates.dart:
///   "September 20", "20 September") and the month first until then, where the page asked the browser's language.
/// - The page is a [PaneBody], where React returned a fragment into the pane.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/locale_dates.dart';
import '../../settings/kit/settings_kit.dart';
import '../host.dart' show onPluginStorage;
import 'plain_field.dart';
import 'repos.dart';

const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// `toLocaleDateString(undefined, { month: 'long', day: 'numeric' })`, in English: "September 20", and "20
/// September" once a British phone has said it is one.
String packedDay(int ms) {
  final day = DateTime.fromMillisecondsSinceEpoch(ms);
  return toldDate(day, DateForm.MMMMd) ?? '${_months[day.month - 1]} ${day.day}';
}

/// The line under a repo's name: what wrote its briefing, and when.
String packedLine(Project p) => '${p.packModel != null ? 'Read by ${p.packModel}' : 'Kept from its README'}, ${packedDay(p.packedAt)}.';

class GitHubPane extends StatefulWidget {
  const GitHubPane({super.key});

  @override
  State<GitHubPane> createState() => _GitHubPaneState();
}

class _GitHubPaneState extends State<GitHubPane> {
  /// The token being typed, before it is kept.
  final TextEditingController _typed = TextEditingController();
  late final VoidCallback _stop;

  @override
  void initState() {
    super.initState();
    _typed.addListener(_redraw);
    _stop = onPluginStorage(_redraw);
  }

  @override
  void dispose() {
    _stop();
    _typed.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _keep() {
    unawaited(setGithubToken(_typed.text));
    _typed.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final known = projects();
    final hasToken = githubToken().isNotEmpty;
    return PaneBody(
      children: [
        PaneSection(
          title: 'Repos',
          description: const Text('Repos the model on your phone has read. A note linked to one is formatted knowing its names and terms, and its list items can go there as issues.'),
          children: [
            if (known.isEmpty)
              const SettingsEmpty(icon: AppIcon(Lucide.gitBranch, size: 22), title: 'No repos yet.', body: Text('Open a note, tap More, and choose GitHub repo to link one.'))
            else
              for (final p in known)
                SettingRow(
                  key: ValueKey(p.id),
                  icon: const AppIcon(Lucide.gitBranch, size: 16),
                  label: '${p.owner}/${p.repo}',
                  hint: Text(packedLine(p)),
                  control: RowAction(onPress: () => removeProject(p.id), child: const Text('Forget')),
                ),
          ],
        ),
        PaneSection(
          title: 'Token',
          description: const Text('A token lets Ghost.md read private repos and make and close issues from your notes. It stays on this phone.'),
          children: [
            if (hasToken)
              SettingRow(
                label: 'A token is kept',
                hint: const Text('Issues can be made and closed from a linked note.'),
                control: RowAction(
                  onPress: () {
                    unawaited(setGithubToken(''));
                    _typed.clear();
                  },
                  child: const Text('Forget'),
                ),
              )
            else
              SettingRow(
                label: 'No token',
                hint: const Text('Public repos are read without one, but sending list items as issues needs it.'),
                layout: SettingRowLayout.stacked,
                // `.token`: the box and its button, one under the other across the row, the button at its end.
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: t.space(2),
                  children: [
                    PlainField(label: 'GitHub token', controller: _typed, placeholder: 'github_pat_…', secret: true),
                    Align(alignment: AlignmentDirectional.centerEnd, child: RowAction(disabled: _typed.text.trim().isEmpty, onPress: _keep, child: const Text('Keep it'))),
                  ],
                ),
              ),
          ],
        ),
        const SettingsFootnote(child: Text('Only the repo goes to the model, and the model runs on your phone. Issues carry the words of the items you send, and nothing else.')),
      ],
    );
  }
}
