/// The GitHub plugin, standard in Ghost.md: a note linked to a repo works with that repo both ways. A port of
/// `src/app/plugins/github/index.tsx`.
///
/// Matt: "a GitHub issues plugin that allows us to sync list items with GitHub project issues, or make it part of
/// an overall GitHub plugin that's provided by default like Notion". One plugin, one link on a note, two things
/// done with it:
///
/// - **Issues.** A list item sent becomes an issue on the repo, and its words become a link to it. From then on the
///   item and the issue are the same thing: the pill on the item says whether it is open, ticking the box closes
///   the issue, and an issue closed on GitHub ticks the box (details.dart). Sending needs a token; reading doesn't.
/// - **Context.** The repo is read on the phone into a short briefing that goes with the note whenever the model
///   formats it (repos.dart).
///
/// Where it shows: "GitHub repo" under Linked to on a note's cog, "Send list to GitHub" beside it, a swipe on a
/// list item, a quiet "GitHub" after an item not sent yet, and in Settings the repos and the token.
///
/// What differs: the plugin's icon is the kit's by name (`git-branch`); the buzz after a send is [githubFelt],
/// which a test stills; the token and the model are repos.dart's seams ([warmGithub], [githubDistiller]).
library;

import 'package:glacier/glacier.dart' show HapticFn, HapticKind, fireMotor;

import '../../core/item_links.dart' show unsentItems;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../send_items.dart';
import '../types.dart';
import 'details.dart';
import 'github_pane.dart';
import 'issues.dart';
import 'manifest.dart';
import 'marks.dart';
import 'project_picker.dart';
import 'repos.dart';

export 'details.dart';
export 'github_pane.dart';
export 'issues.dart';
export 'manifest.dart' show GithubFailure, tokenSecret;
export 'marks.dart';
export 'project_picker.dart';
export 'repos.dart';

/// The buzz when issues are made (`fireNativeHaptic('success')`).
HapticFn githubFelt = fireMotor;

/// What has just been sent from a note, so the same words are never made into two issues
/// (lib/plugins/send_items.dart).
final ItemSender _sender = ItemSender('github', now: () => githubNow());

/// For the tests: what was sent is otherwise kept in memory for the app's life, five minutes a send (`forgetSent`).
void forgetSent() => _sender.forget();

/// Sends list items to the linked repo: each becomes an issue, kept for its pill at once, and its words a link to
/// it (lib/plugins/send_items.dart has the rules), then says how many lines now link to one.
Future<void> _sendItems(Project project, List<SendItem> items, NoteEditing editing) async {
  final done = await _sender.send(items, project.id, editing, (text) async {
    final issue = await createIssue(owner: project.owner, repo: project.repo, title: text);
    rememberIssue(issue);
    return issue.url;
  });
  if (done == null || done.marked == 0) return;
  githubFelt(HapticKind.success);
  editing.say('${done.marked == 1 ? 'Made 1 issue' : 'Made ${done.marked} issues'} in ${project.owner}/${project.repo}.');
}

String _summary() {
  final count = projects().length;
  return count > 0 ? '$count ${count == 1 ? 'repo' : 'repos'}${canWriteIssues() ? ', issues on' : ''}' : 'Repos, issues and context';
}

final GlyphPlugin githubPlugin = GlyphPlugin(
  manifest: manifest,
  icon: 'git-branch',
  settings: PluginSettings(
    pane: (context) => const GitHubPane(),
    hue: 'graphite',
    // What Settings' search finds on the page: its cards, by their titles.
    settings: const [SettingsFindable('Repos', 'repositories briefing context'), SettingsFindable('Token', 'private issues')],
    summary: _summary,
  ),
  noteLinks: [
    NoteLink(
      id: 'github-repo',
      label: 'GitHub repo',
      icon: (context, size) => RepoMark(size: size),
      hint: (noteId) {
        final project = projectFor(noteId);
        if (project == null) return 'A repo for this note: its list items can go there as issues, and the AI reads it for context.';
        return canWriteIssues() ? '${project.owner}/${project.repo}. List items can go there as issues.' : '${project.owner}/${project.repo}. Add a token in Settings to send items as issues.';
      },
      picker: (context, noteId, onDone) => ProjectPicker(noteId: noteId, onDone: onDone),
      linked: (noteId) {
        final project = projectFor(noteId);
        return project == null ? null : '${project.owner}/${project.repo}';
      },
    ),
  ],
  noteActions: [
    NoteAction(
      id: 'github-send-list',
      label: 'Send list to GitHub',
      icon: (context, size) => RepoMark(size: size),
      visible: (noteId, body) => projectFor(noteId) != null,
      hint: (noteId, body) {
        if (!canWriteIssues()) return needsToken;
        final project = projectFor(noteId);
        final unsent = unsentItems(body).length;
        if (unsent == 0) return 'Every item is already an issue.';
        return '$unsent ${unsent == 1 ? 'item isn’t' : 'items aren’t'} there yet. Each becomes an issue in ${project?.owner}/${project?.repo} and a link.';
      },
      enabled: (noteId, body) => canWriteIssues() && unsentItems(body).isNotEmpty,
      run: (editing, [choice]) async {
        final project = projectFor(editing.noteId);
        if (project != null) await _sendItems(project, [for (final item in unsentItems(editing.body())) (text: item.text, line: item.line)], editing);
      },
    ),
  ],
  itemAction: ItemAction(
    id: 'github-send-item',
    label: 'GitHub',
    busyLabel: 'Sending…',
    available: (noteId) => canWriteIssues() && projectFor(noteId) != null,
    run: (text, editing) async {
      final project = projectFor(editing.noteId);
      if (project != null) await _sendItems(project, [(text: text, line: null)], editing);
    },
  ),
  // The quiet "GitHub" after each item not sent yet, once a repo is linked and a token is in.
  suggest: (noteId, body) {
    final project = projectFor(noteId);
    if (project == null || !canWriteIssues()) return const [];
    return [
      for (final item in unsentItems(body))
        Suggestion(line: item.line, label: 'GitHub', busyLabel: 'Sending', run: (editing) => _sendItems(project, [(text: item.text, line: item.line)], editing)),
    ];
  },
  marks: githubDetails,
  formatContext: const FormatContext(forNote: projectContextFor, version: projectContextVersion),
);
