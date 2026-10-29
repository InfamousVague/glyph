import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/slack/slack.dart';
import 'package:ghost_md/share/share.dart';

import '../../share/support.dart' show FakeService, Pictures, SignedAccount, apiOf, testAccount;
import 'support.dart';

/// A meeting's action items posted to Slack once it is written up (lib/plugins/slack/meetings.dart; Matt,
/// 2026-10-26): what a summary's action items are, the message they make, and the posting, once for the account,
/// tried again when it fails, and with the note's share link made by the app's own share.
void main() {
  const hook = 'https://hooks.slack.com/services/T0/B0/abc';

  /// The summary in the shape the app writes it (lib/format/prompt.dart's example), over a Ghost meeting's
  /// transcript.
  const summary = '## Summary\nA call that fixed the launch date and who does what next.\n\n'
      '- The launch is in the second week of March.\n- Pricing: still open.\n- Sam: the press list by Friday.\n\n'
      '- Decided: no paid ads until the beta closes.\n\n'
      '- [ ] First pass at the site copy by Friday.\n- [ ] Book the venue @dana 📅 2026-10-31\n- [x] Send the invite.';
  const transcript = '## Transcript\n\n**Sam Lee:** I can take the press list.\n\n**Dana:** And the venue.\n';
  const meeting = '# Launch sync\n\nGhost was in this meeting on 21 Oct, 14:00 to 14:45.\n\n$summary\n\n$transcript';

  group('a summary’s action items', () {
    test('are its to-dos, with their person and due day, and the points that give someone who spoke an action', () {
      final actions = meetingActions(summary, attendees: const ['Sam Lee', 'Dana']);
      expect(actions, const [
        MeetingAction(text: 'the press list by Friday.', assignee: 'Sam'),
        MeetingAction(text: 'First pass at the site copy by Friday.'),
        MeetingAction(text: 'Book the venue', assignee: '@dana', due: '2026-10-31'),
        MeetingAction(text: 'Send the invite.', done: true),
      ]);
    });

    test('leave out a point that names no one who spoke, and every decision', () {
      final actions = meetingActions(summary);
      expect([for (final a in actions) a.text], ['First pass at the site copy by Friday.', 'Book the venue', 'Send the invite.']);
      expect(actions.any((a) => a.text.contains('Pricing') || a.text.contains('paid ads')), isFalse);
    });

    test('are none for a summary of points alone', () {
      const points = '## Summary\nA quick check-in.\n\n- The build is green.\n- Nothing is blocked.';
      expect(meetingActions(points, attendees: const ['Sam']), isEmpty);
      expect(meetingDecisions(points), isEmpty);
      expect(meetingGist(points), 'A quick check-in.');
    });

    test('come with the decisions and the one sentence', () {
      expect(meetingDecisions(summary), ['no paid ads until the beta closes.']);
      expect(meetingGist(summary), 'A call that fixed the launch date and who does what next.');
    });
  });

  group('the message', () {
    MeetingPost post({List<MeetingAction> actions = const [], List<String> decisions = const [], String? share, String? team}) => MeetingPost(
          noteId: 'n-1',
          title: 'Launch <sync> & co',
          startedAt: DateTime.utc(2026, 10, 21, 14).millisecondsSinceEpoch,
          lengthMs: 45 * 60000,
          gist: 'A call about the **launch**.',
          actions: actions,
          decisions: decisions,
          team: team,
          shareLink: share,
          me: 'matt',
        );

    test('is the title, when and how long, then the items, a brief summary and the public link, in mrkdwn (Matt, 2026-10-28)', () {
      final text = meetingMessage(post(
        actions: const [MeetingAction(text: 'First pass at the copy'), MeetingAction(text: 'Book the venue', assignee: '@dana', due: '2026-10-31'), MeetingAction(text: 'the press list', assignee: 'Sam')],
        decisions: const ['No paid ads until the beta closes.'],
        share: 'https://ghostmarkdown.com/read.html#abc.def',
        team: 'HelloTrade',
      ));
      final lines = text.split('\n');
      expect(lines[0], '*Launch &lt;sync&gt; &amp; co*');
      expect(lines[1], matches(RegExp(r'^<!date\^1792591200\^\{date_short_pretty\} at \{time\}\|[^>]+> · 45 min · HelloTrade$')));
      expect(lines.sublist(2), [
        '',
        '*Action items*',
        '• *@matt*: First pass at the copy',
        '• *@dana*: Book the venue _(due ${lines[5].split('(due ').last.split(')').first})_',
        '• *Sam*: the press list',
        '',
        '*Summary*',
        'A call about the *launch*.',
        '• Decided: No paid ads until the beta closes.',
        '',
        '<https://ghostmarkdown.com/read.html#abc.def|Read the notes and transcript>',
      ]);
      // The due day in the phone's words: "Sat, 31 Oct" here, "Sat, Oct 31" in the US.
      expect(lines[5], matches(RegExp(r'^• \*@dana\*: Book the venue _\(due Sat, (?:31 Oct|Oct 31)\)_$')));
    });

    test('says there are no action items, and carries the app’s link alone without a share', () {
      final text = meetingMessage(post());
      expect(text, contains('\n\nNo action items.\n\n*Summary*\n'));
      expect(text, endsWith('<ghostmd://note/n-1|Open in Ghost.md>'));
      expect(text, isNot(contains('Decided')));
      expect(text, isNot(contains('read.html')));
    });

    test('lists the first 25 items, leaves out a long list of decisions, and stays under Slack’s length', () {
      final many = [for (var i = 0; i < 40; i++) MeetingAction(text: 'Item $i ${'x' * 2000}')];
      final text = meetingMessage(post(actions: many, decisions: [for (var i = 0; i < 6; i++) 'Decision $i']));
      expect(text.length, lessThanOrEqualTo(40000));
      expect(text, contains('_The rest is in Ghost.md: it is longer than one Slack message._'));
      final shorter = meetingMessage(post(actions: [for (var i = 0; i < 30; i++) MeetingAction(text: 'Item $i')], decisions: [for (var i = 0; i < 6; i++) 'Decision $i']));
      expect('• '.allMatches(shorter).length, 25);
      expect(shorter, contains('_and 5 more in Ghost.md_'));
      expect(shorter, isNot(contains('Decided:')));
    });

    test('is made from the note: its title, the meeting’s start, its length, and its summary', () {
      final note = Note(id: 'n1', body: meeting, createdAt: 1000, updatedAt: 1000, recordingMs: 80 * 60000);
      final made = meetingPostOf(note, startedAt: 5000, team: 'HelloTrade');
      expect(made.title, 'Launch sync');
      expect(made.startedAt, 5000);
      expect(meetingLength(made.lengthMs!), '1 hr 20 min');
      expect(made.actions.first, const MeetingAction(text: 'the press list by Friday.', assignee: 'Sam'));
      expect(made.decisions, hasLength(1));
      expect(meetingLength(45 * 60000), '45 min');
      expect(meetingLength(2 * 3600000), '2 hr');
    });
  });

  group('the posting', () {
    late FakeSlack slack;
    late Preferences prefs;
    late Map<String, Note> notes;
    late Registry before;
    late List<String> shared;

    MeetingSlackPoster poster({Future<String> Function(Note note)? share}) => MeetingSlackPoster(
          preferences: () => prefs,
          setPreferences: (change) => prefs = change(prefs),
          getNote: (id) async => notes[id],
          shareLink: share ??
              (note) async {
                shared.add(note.id);
                return 'https://ghostmarkdown.com/read.html#${note.id}.key';
              },
          kept: (_) => null,
          now: () => 1000,
        );

    setUp(() async {
      slack = FakeSlack();
      before = plugins;
      usePlugins(createRegistry([slackPlugin], store: MemorySwitches({'slack': true})));
      prefs = Preferences.defaults;
      notes = {'n1': Note(id: 'n1', body: meeting, createdAt: 1000, updatedAt: 1000, recordingMs: 45 * 60000)};
      shared = [];
    });

    tearDown(() => usePlugins(before));

    test('is offered only with the plugin on and a channel on the device', () async {
      expect(meetingSlackOffered(), isFalse);
      await addChannel('#launch', hook);
      expect(meetingSlackOffered(), isTrue);
      plugins.setEnabled('slack', false);
      expect(meetingSlackOffered(), isFalse);
    });

    test('is off until a channel is chosen, and on once one is', () async {
      final launch = await addChannel('#launch', hook);
      final ops = await addChannel('#ops', '$hook-ops');
      expect(meetingSlackSettings().on, isFalse);
      expect(meetingSlackSettings().share, isTrue);
      // With two to choose from, the switch waits for a choice.
      setMeetingPosts(true);
      expect(postsMeetings(), isFalse);
      chooseMeetingChannel(ops.id);
      expect(postsMeetings(), isTrue);
      expect(meetingChannel(), ops);
      setMeetingPosts(false);
      chooseMeetingChannel(launch.id);
      // A change of channel is not the switch.
      expect(postsMeetings(), isFalse);
      await forgetChannel(launch.id);
      await forgetChannel(ops.id);
      // With one channel, the switch chooses it.
      final only = await addChannel('#only', '$hook-only');
      setMeetingPosts(true);
      expect(meetingChannel(), only);
      expect(postsMeetings(), isTrue);
    });

    test('posts once a meeting is written up, with its share link, and marks it for the account', () async {
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      expect(await poster().meetingSummarized('n1', meeting), isTrue);
      expect(slack.posts, hasLength(1));
      final text = slack.posts.single.text! as String;
      expect(text, startsWith('*Launch sync*\n'));
      expect(text, contains('• *Sam*: the press list by Friday.'));
      expect(text, endsWith('<https://ghostmarkdown.com/read.html#n1.key|Read the notes and transcript>'));
      expect(text, isNot(contains('ghostmd://')), reason: 'the public link alone where there is one');
      expect(shared, ['n1']);
      expect(prefs.more[slackMeetingPostsKey], {'n1': {'at': 1000, 'posted': 1000}});
      expect(meetingPostTries(), isEmpty);
    });

    test('posts nothing for a summary made again, or on another device that writes it up', () async {
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      await poster().meetingSummarized('n1', meeting);
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      // Another device: its own channels and settings, the account's preferences as synced.
      final synced = prefs;
      final other = FakeSlack();
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      prefs = synced;
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      expect(other.posts, isEmpty);
      expect(slack.posts, hasLength(1));
    });

    test('posts nothing with the switch off, and marks nothing, so turning it on later still posts it', () async {
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      setMeetingPosts(false);
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      expect(slack.posts, isEmpty);
      expect(prefs.more[slackMeetingPostsKey], isNull);
      expect(shared, isEmpty);
    });

    test('posts nothing with no channel', () async {
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      expect(slack.ground.asked, isEmpty);
    });

    test('goes without a share link when it is turned off, or none can be made', () async {
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      setMeetingShareLink(false);
      await poster().meetingSummarized('n1', meeting);
      expect(shared, isEmpty);
      expect(slack.posts.single.text, isNot(contains('read.html')));

      setMeetingShareLink(true);
      notes['n2'] = Note(id: 'n2', body: meeting, createdAt: 1, updatedAt: 1);
      await poster(share: (_) async => throw const ShareError('Sign in under Settings > Account to share.')).meetingSummarized('n2', meeting);
      expect(slack.posts, hasLength(2));
      expect(slack.posts.last.text, endsWith('<ghostmd://note/n2|Open in Ghost.md>'));
    });

    test('is a job on the app\'s record of running work: "Posted to #launch" as it lands; quiet while tries are left, then red with Retry', () async {
      final record = Activity(store: () => MemoryStored());
      useActivity(record);
      addTearDown(() => useActivity(Activity()));
      final ended = <Job>[];
      final hearing = record.events.where((e) => e.kind == JobEventKind.ended).listen((e) => ended.add(e.job!));
      addTearDown(hearing.cancel);
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      slack.refuse = (404, 'no_service');
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      expect(record.value, isEmpty, reason: 'tried again as the app next runs: quietly');
      for (var run = 2; run <= meetingPostTriesMost; run++) {
        await poster().resume();
      }
      final failed = record['slack:n1']!;
      expect((failed.state, failed.kind, failed.title), (JobState.failed, JobKind.meetings, 'Posting Launch sync to Slack'));
      expect(failed.cause, contains('Slack no longer knows this webhook'));
      expect(failed.fix!.kind, JobFixKind.retry);
      slack.refuse = null;
      failed.fix!.onPress();
      await pumpEventQueue();
      expect(record['slack:n1'], isNull, reason: 'posted on Retry');
      expect(ended.last.result!.words, 'Posted to #launch');
      expect(record.log.today.words, '1 Slack post, 1 failed');
    });

    test('keeps a failure with Slack’s reason, tries again when the app runs, and stops after five tries', () async {
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      slack.refuse = (404, 'no_service');
      final first = poster();
      expect(await first.meetingSummarized('n1', meeting), isFalse);
      expect(failedMeetingPosts().single.said, contains('Slack no longer knows this webhook'));
      expect(failedMeetingPosts().single.tries, 1);
      expect(meetingPostMarked(prefs, 'n1'), isTrue);
      expect(meetingTryLine(failedMeetingPosts().single), endsWith('Ghost.md tries again when it next opens (tried 1 of 5).'));

      // Each run of the app is a try.
      for (var run = 2; run <= meetingPostTriesMost; run++) {
        expect(await poster().resume(), 0);
      }
      expect(failedMeetingPosts().single.spent, isTrue);
      expect((prefs.more[slackMeetingPostsKey] as Map)['n1'], containsPair('failed', 1000));
      final asked = slack.posts.length;
      expect(await poster().resume(), 0);
      expect(slack.posts.length, asked, reason: 'its tries are spent');

      // Slack is fixed: Try now posts it, and it is let go.
      slack.refuse = null;
      expect(await poster().tryNow('n1'), 1);
      expect(meetingPostTries(), isEmpty);
      expect((prefs.more[slackMeetingPostsKey] as Map)['n1'], containsPair('posted', 1000));
    });

    test('is posted on the next run after a failure, and not twice', () async {
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      slack.refuse = (500, 'oops');
      await poster().meetingSummarized('n1', meeting);
      slack.refuse = null;
      expect(await poster().resume(), 1);
      expect(await poster().resume(), 0);
      expect(slack.posts, hasLength(2));
      expect(meetingPostTries(), isEmpty);
    });

    test('lets go of a meeting deleted meanwhile, and of one let go from the page', () async {
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      slack.refuse = (500, 'oops');
      notes['n2'] = Note(id: 'n2', body: meeting, createdAt: 1, updatedAt: 1);
      await poster().meetingSummarized('n1', meeting);
      await poster().meetingSummarized('n2', meeting);
      forgetMeetingPost('n2');
      notes.remove('n1');
      slack.refuse = null;
      expect(await poster().resume(), 0);
      expect(meetingPostTries(), isEmpty);
    });

    test('makes the share link with the app’s own share, the link the note’s Share sheet copies', () async {
      final service = await FakeService.start(seed: testAccount);
      final store = PreferencesStore()..startWithoutStorage();
      final shares = Shares(account: SignedAccount()..signIn(service), api: apiOf(service), crypto: service.crypto, prefs: store, pictures: Pictures(), listNotes: () async => notes.values.toList());
      await addChannel('#launch', hook);
      setMeetingPosts(true);
      await poster(share: (note) async => shares.shareNote(note, await shares.listNotes())).meetingSummarized('n1', meeting);
      final link = shares.linkFor('n1');
      expect(link, isNotNull);
      expect(slack.posts.single.text, contains('<$link|Read the notes and transcript>'));
      // The share holds the note whole, transcript and all, as any share does.
      final read = await shares.readShared(link!);
      expect(read.pages.single.body, contains('**Sam Lee:** I can take the press list.'));
    });
  });
}
