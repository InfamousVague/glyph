import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/plugins/github/github.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:glacier/glacier.dart' show HapticKind;

import 'support.dart';

/// Sending a list item to GitHub as an issue: the rules Notion's sending learned first, which GitHub's own copy
/// never had. A second press on the same words made a second issue, and an issue whose line had changed while
/// GitHub answered was made and left unmarked, which is what makes a person press again. A port of
/// `src/app/plugins/github/send.test.ts`, case for case.
///
/// What differs: the page stubbed its issues module and `projectFor`; here the note is really linked to a kept
/// repo, a token is really kept, and GitHub is the recorded `Fetcher`, so the requests are the plugin's own.
void main() {
  late TestGround ground;
  final made = <String>[];
  final felt = <HapticKind>[];
  FetchResponse? refusal;

  Map<String, Object?> repo(String owner, String name) => {'id': '$owner/$name', 'owner': owner, 'repo': name, 'url': '', 'branch': 'main', 'description': '', 'files': <String>[], 'pack': '', 'packModel': null, 'packedAt': 0};

  /// The repo the note is linked to.
  void link(String owner, String name) {
    ground.kept.setItem('glyph-github-projects', jsonEncode([repo(owner, name)]));
    linkProject('note-1', '$owner/$name');
  }

  setUp(() async {
    made.clear();
    felt.clear();
    refusal = null;
    ground = useGround((request) async {
      if (refusal case final refused?) {
        refusal = null;
        return refused;
      }
      final at = RegExp(r'^/repos/([^/]+)/([^/]+)/issues$').firstMatch(request.url.path)!;
      final title = (sentJson(request) as Map)['title'] as String;
      made.add(title);
      return FetchResponse.json(201, {'number': made.length, 'title': title, 'html_url': 'https://github.com/${at[1]}/${at[2]}/issues/${made.length}', 'state': 'open', 'labels': <Object?>[], 'assignees': <Object?>[]});
    });
    githubFelt = ([kind = HapticKind.light]) => felt.add(kind);
    forgetSent();
    forgetIssues();
    await setGithubToken('ghp_secret');
    link('o', 'r');
  });

  /// Sends [text] the way the quiet "GitHub" after the item does, through the plugin's own suggestion for that line.
  Future<void> send(TestNote note, String text) {
    final lines = note.body().split('\n');
    final suggestion = githubPlugin.suggest!('note-1', note.body()).where((s) => lines[s.line - 1].contains(text)).firstOrNull;
    if (suggestion == null) fail('nothing offered for $text');
    return suggestion.run(note);
  }

  Future<void> sendList(NoteEditing editing) => githubPlugin.noteActions.firstWhere((a) => a.id == 'github-send-list').run(editing);

  group('sending an item to GitHub', () {
    test('makes the issue and marks the line with it', () async {
      final note = TestNote('# Jobs\n\n- [ ] Fix the tab row\n- [ ] Ship it');
      await send(note, 'Fix the tab row');
      expect(made, ['Fix the tab row']);
      expect(note.lines[2], '- [ ] Fix the tab row [github](https://github.com/o/r/issues/1)');
      expect(note.said, ['Made 1 issue in o/r.']);
      expect(felt, [HapticKind.success]);
      final request = ground.asked.single;
      expect([request.method, request.url.toString(), header(request, 'Authorization')], ['POST', 'https://api.github.com/repos/o/r/issues', 'Bearer ghp_secret']);
      // Its pill knows the issue at once, before anything is read back from GitHub.
      final known = githubPlugin.marks!.peek('https://github.com/o/r/issues/1');
      expect(known, isA<MarkReady>());
      final details = (known! as MarkReady).details;
      expect([details.title, details.status?.stage], ['Fix the tab row', Stage.todo]);
    });

    test('makes one issue however often the same words are sent', () async {
      final note = TestNote('- [ ] Fix the tab row');
      await send(note, 'Fix the tab row');
      // The line is marked, so a second press would not normally be possible; the words are sent again all the same.
      note.lines[0] = '- [ ] Fix the tab row';
      await send(note, 'Fix the tab row');
      expect(made, ['Fix the tab row'], reason: 'the same words must not become two issues');
      expect(note.lines[0], '- [ ] Fix the tab row [github](https://github.com/o/r/issues/1)');
    });

    test('makes a new issue when the same words go to another repo', () async {
      final note = TestNote('- [ ] Fix the tab row');
      link('a', 'one');
      await send(note, 'Fix the tab row');
      // Undone, and the note linked to another repo: the words are that repo's to have, not a link to the first one's.
      note.lines[0] = '- [ ] Fix the tab row';
      link('b', 'two');
      await send(note, 'Fix the tab row');
      expect(made, ['Fix the tab row', 'Fix the tab row']);
      expect(note.lines[0], '- [ ] Fix the tab row [github](https://github.com/b/two/issues/2)');
      expect(note.said.last, 'Made 1 issue in b/two.');
    });

    test('marks the line it was on when the words have changed since', () async {
      final note = TestNote('- [ ] Fix the tab row');
      final run = send(note, 'Fix the tab row');
      // The person keeps typing while GitHub answers.
      note.lines[0] = '- [ ] Fix the tab row on the Fold';
      await run;
      expect(made, ['Fix the tab row']);
      expect(note.lines[0], '- [ ] Fix the tab row on the Fold [github](https://github.com/o/r/issues/1)');
    });

    test('sends a whole list from the cog, each item once, and says how many', () async {
      final note = TestNote('- [ ] One\n- [ ] Two\n- [x] Done already');
      await sendList(note);
      expect(made, ['One', 'Two']);
      expect(note.said, ['Made 2 issues in o/r.']);
      await sendList(note);
      expect(made, ['One', 'Two']);
    });

    test('gives each issue its own item when a line above them goes while GitHub answers', () async {
      final note = TestNote('- [ ] One\n- [ ] Two\n- [ ] Three');
      final run = sendList(note);
      // The first item is deleted while its issue is made: the others move up a line each.
      note.lines.removeAt(0);
      await run;
      expect(made, ['One', 'Two', 'Three']);
      expect(note.lines, ['- [ ] Two [github](https://github.com/o/r/issues/2)', '- [ ] Three [github](https://github.com/o/r/issues/3)'], reason: 'no item may take the link of the one before it');
      expect(note.said, ['Made 2 issues in o/r.']);
    });

    test('says GitHub’s refusal and stops there', () async {
      refusal = FetchResponse.json(401, {'message': 'Bad credentials'});
      final note = TestNote('- [ ] One\n- [ ] Two');
      await sendList(note);
      expect(note.said, ['GitHub didn’t accept that token. Check it in Settings > GitHub.']);
      expect(note.lines, ['- [ ] One', '- [ ] Two']);
      expect(ground.asked, hasLength(1));
      expect(felt, isEmpty);
    });
  });

  // Not cases of the page's send.test.ts, which stubbed these away: the rows as index.tsx words them.
  group('the plugin’s rows on a note', () {
    test('say what the link does, what it is, and that sending wants a token', () async {
      final repoLink = githubPlugin.noteLinks.single;
      expect([repoLink.id, repoLink.label], ['github-repo', 'GitHub repo']);
      expect(repoLink.hint('other'), 'A repo for this note: its list items can go there as issues, and the AI reads it for context.');
      expect(repoLink.linked!('other'), isNull);
      expect(repoLink.hint('note-1'), 'o/r. List items can go there as issues.');
      expect(repoLink.linked!('note-1'), 'o/r');
      await setGithubToken('');
      expect(repoLink.hint('note-1'), 'o/r. Add a token in Settings to send items as issues.');
    });

    test('offer the list only on a linked note, greyed without a token or with nothing left to send', () async {
      final action = githubPlugin.noteActions.single;
      expect([action.id, action.label], ['github-send-list', 'Send list to GitHub']);
      expect(action.visible('other', ''), isFalse);
      expect(action.visible('note-1', ''), isTrue);
      expect(action.hint('note-1', '- [ ] One\n- [ ] Two'), '2 items aren’t there yet. Each becomes an issue in o/r and a link.');
      expect(action.hint('note-1', '- [ ] One'), '1 item isn’t there yet. Each becomes an issue in o/r and a link.');
      expect(action.enabled('note-1', '- [ ] One'), isTrue);
      expect(action.hint('note-1', 'No list here.'), 'Every item is already an issue.');
      expect(action.enabled('note-1', 'No list here.'), isFalse);
      expect(githubPlugin.itemAction!.available('note-1'), isTrue);
      expect(githubPlugin.itemAction!.available('other'), isFalse);
      expect(githubPlugin.settings!.summary(), '1 repo, issues on');
      await setGithubToken('');
      expect(action.hint('note-1', '- [ ] One'), needsToken);
      expect(action.enabled('note-1', '- [ ] One'), isFalse);
      expect(githubPlugin.itemAction!.available('note-1'), isFalse);
      expect(githubPlugin.suggest!('note-1', '- [ ] One'), isEmpty);
      expect(githubPlugin.settings!.summary(), '1 repo');
    });

    test('send a swiped item, and close and reopen its issue from the pill’s menu', () async {
      final note = TestNote('- [ ] Fix the tab row');
      await githubPlugin.itemAction!.run('Fix the tab row', note);
      expect(note.lines.single, '- [ ] Fix the tab row [github](https://github.com/o/r/issues/1)');
      const url = 'https://github.com/o/r/issues/1';
      final close = githubPlugin.marks!.actions(url, 'Fix the tab row').single;
      expect([close.id, close.label, close.busyLabel, close.icon], ['done', 'Close issue', 'Closing…', MarkActionIcon.done]);
      ground.asked.clear();
      refusal = FetchResponse.json(200, {'number': 1, 'title': 'Fix the tab row', 'html_url': url, 'state': 'closed', 'state_reason': 'completed'});
      expect(await close.run(), '#1 is closed.');
      expect([ground.asked.single.method, ground.asked.single.url.toString()], ['PATCH', 'https://api.github.com/repos/o/r/issues/1']);
      expect(sentJson(ground.asked.single), {'state': 'closed', 'state_reason': 'completed'});
      final reopen = githubPlugin.marks!.actions(url, 'Fix the tab row').single;
      expect([reopen.id, reopen.label, reopen.busyLabel, reopen.icon], ['reopen', 'Open again', 'Opening…', MarkActionIcon.reopen]);
      expect(githubPlugin.marks!.reads('https://github.com/o/r/issues/9'), isTrue);
      expect(githubPlugin.marks!.reads('https://github.com/o/r/pull/9'), isFalse);
      await githubPlugin.marks!.open(url);
      expect(ground.opened, [url]);
    });

    test('hand the formatter the linked repo’s briefing', () {
      ground.kept.setItem('glyph-github-projects', jsonEncode([{...repo('o', 'r'), 'pack': 'A radio.', 'packedAt': 7}]));
      expect(githubPlugin.formatContext!.forNote('note-1'), startsWith('This note is about the project o/r.'));
      expect(githubPlugin.formatContext!.version('note-1'), 7);
      expect(githubPlugin.formatContext!.forNote('other'), isNull);
    });
  });
}
