import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/item_links.dart';
import 'package:ghost_md/plugins/github/github.dart';
import 'package:ghost_md/plugins/types.dart';

/// An issue's address, GitHub's answer as an issue, and an issue as a linked item. A port of
/// `src/app/plugins/github/issues.test.ts`, case for case.
void main() {
  const Map<String, Object?> raw = {
    'number': 12,
    'title': 'Ship the pricing page',
    'html_url': 'https://github.com/glyph/app/issues/12',
    'state': 'open',
    'updated_at': '2026-09-15T10:00:00Z',
    'labels': [
      {'name': 'bug'},
      'chore',
    ],
    'assignees': [
      {'login': 'matt'},
    ],
    'milestone': {'title': '1.5'},
  };

  group('an issue’s address', () {
    test('finds the repo and number, and ignores anything else on github.com', () {
      expect(issueAt('https://github.com/glyph/app/issues/12'), (owner: 'glyph', repo: 'app', number: 12));
      expect(issueAt('https://github.com/glyph/app/issues/12#issuecomment-99'), (owner: 'glyph', repo: 'app', number: 12));
      expect(issueAt('https://github.com/glyph/app/pull/12'), isNull);
      expect(issueAt('https://github.com/glyph/app'), isNull);
      expect(issueAt('https://notgithub.com/glyph/app/issues/12'), isNull);
      expect(issueAt('not a url'), isNull);
      expect(isIssueUrl('https://github.com/glyph/app/issues/3'), isTrue);
    });

    test('keys an issue by its repo and number, so two repos never share one', () {
      expect(issueKey('https://github.com/glyph/app/issues/12'), 'glyph/app#12');
      expect(issueKey('https://github.com/other/app/issues/12'), 'other/app#12');
      expect(issueKey('https://github.com/glyph/app'), isNull);
    });
  });

  group('what GitHub answered', () {
    test('reads an issue’s words, who has it and what it is labelled', () {
      final issue = asIssue(raw, 'glyph', 'app');
      expect(issue.title, 'Ship the pricing page');
      expect(issue.state, 'open');
      expect(issue.labels, ['bug', 'chore']);
      expect(issue.assignees, ['matt']);
      expect(issueBrief(issue), ['@matt', 'bug']);
      expect([for (final field in issueFields(issue)) field.label], ['Repo', 'Number', 'State', 'Assignee', 'Labels', 'Milestone']);
    });

    test('says where a closed issue stands, and why where GitHub says', () {
      expect(issueState(asIssue({...raw, 'state': 'closed'}, 'glyph', 'app')), 'Closed');
      expect(issueState(asIssue({...raw, 'state': 'closed', 'state_reason': 'not_planned'}, 'glyph', 'app')), 'Closed as not planned');
    });

    test('stands an issue with nothing filled in on its own', () {
      final issue = asIssue(const {'number': 4}, 'glyph', 'app');
      expect(issue.title, 'Issue #4');
      expect(issue.url, 'https://github.com/glyph/app/issues/4');
      expect(issueBrief(issue), isEmpty);
    });
  });

  group('an issue as a linked item', () {
    test('is to do while open and done once closed, which is what ticks the box', () {
      expect(detailsFromRaw(raw, 'glyph', 'app').status, const MarkStatus('Open', Stage.todo));
      expect(detailsFromRaw({...raw, 'state': 'closed'}, 'glyph', 'app').status, const MarkStatus('Closed', Stage.done));
    });

    test('carries the issue’s own address and when it last changed', () {
      final details = detailsFromRaw(raw, 'glyph', 'app');
      expect(details.url, 'https://github.com/glyph/app/issues/12');
      expect(details.editedAt, DateTime.utc(2026, 9, 15, 10).millisecondsSinceEpoch);
      expect(details.title, 'Ship the pricing page');
    });
  });

  group('the GitHub plugin', () {
    test('is one plugin for repos and issues, standard, reaching only GitHub', () {
      expect(githubPlugin.manifest.id, 'github');
      expect(githubPlugin.manifest.standard, isTrue);
      expect(githubPlugin.manifest.hosts, ['api.github.com']);
      expect(githubPlugin.marks, isNotNull);
      expect(githubPlugin.formatContext, isNotNull);
      expect(githubPlugin.itemAction?.label, 'GitHub');
    });

    test('writes an item’s link the way the editor reads it back', () {
      final line = linkedLine('- [ ] Ship the pricing page', 'https://github.com/glyph/app/issues/12', 'github');
      expect(line, '- [ ] Ship the pricing page [github](https://github.com/glyph/app/issues/12)');
      // Sent once, it is not offered again.
      expect([for (final item in unsentItems('$line\n- [ ] Write the copy')) item.text], ['Write the copy']);
    });

    // Not a case of the page's: the manifest's words, held to the page's own (src/app/plugins/github/manifest.ts).
    test('says what the page’s manifest says, and keeps its token as a secret', () {
      final manifest = githubPlugin.manifest;
      expect(manifest.name, 'GitHub');
      expect(
        manifest.description,
        'Links a note to a repo: its list items become issues you can tick off from either side, and the repo is read on the phone into a short briefing so names and terms come out right when the note is formatted.',
      );
      expect([manifest.version, manifest.author], ['1.0.0', 'Ghost.md']);
      expect([for (final p in manifest.permissions) p.kind], [Permission.notes, Permission.network, Permission.ai]);
      expect([for (final p in manifest.permissions) p.why], [
        'Sends a note’s list items to the repo as issues, and writes each one’s link back into the note.',
        'Reads the repo’s README, docs and file list from GitHub, and makes and closes the issues you send. Nothing else of your notes goes there.',
        'The model on your phone writes the briefing from what it read.',
      ]);
      expect(manifest.storage, ['glyph-github-projects', 'glyph-project-links', 'glyph-github-token', 'glyph-github-issues']);
      expect(manifest.secrets, ['glyph-github-token']);
      expect(manifest.native, isNull);
      expect(githubPlugin.icon, 'git-branch');
      expect(githubPlugin.settings?.hue, 'indigo');
      expect([for (final found in githubPlugin.settings!.settings) found.name], ['Repos', 'Token']);
    });
  });
}
