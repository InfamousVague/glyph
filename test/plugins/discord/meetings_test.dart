import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/discord/discord.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/slack/slack.dart' show slackMeetingPostsKey, withMeetingPostMark;
import 'package:ghost_md/share/share.dart' show ShareError;
import 'package:ghost_md/sync/prefs.dart' show syncedPrefs;

import 'support.dart';

/// A meeting's action items posted to Discord once it is written up (lib/plugins/discord/meetings.dart; Matt,
/// 2026-10-26): the message in Discord's Markdown with its timestamp and its links, held to one message; the posting
/// once for the account on its own mark, off with the switch, tried again when it fails, and never on an iPhone.
void main() {
  final hook = webhookOf('123456789012345678');

  /// The summary in the shape the app writes it, as Slack's tests have it.
  const summary = '## Summary\nA call that fixed the launch date and who does what next.\n\n'
      '- The launch is in the second week of March.\n- Pricing: still open.\n- Sam: the press list by Friday.\n\n'
      '- Decided: no paid ads until the beta closes.\n\n'
      '- [ ] First pass at the site copy by Friday.\n- [ ] Book the venue @dana 📅 2026-10-31\n- [x] Send the invite.';
  const transcript = '## Transcript\n\n**Sam Lee:** I can take the press list.\n\n**Dana:** And the venue.\n';
  const meeting = '# Launch sync\n\nGhost was in this meeting on 21 Oct, 14:00 to 14:45.\n\n$summary\n\n$transcript';

  group('the message', () {
    MeetingPost post({List<MeetingAction> actions = const [], List<String> decisions = const [], String? share, String? team, String title = 'Launch_sync *v2*'}) => MeetingPost(
          noteId: 'n-1',
          title: title,
          startedAt: DateTime.utc(2026, 10, 21, 14).millisecondsSinceEpoch,
          lengthMs: 45 * 60000,
          gist: 'A call about the **launch**.',
          actions: actions,
          decisions: decisions,
          team: team,
          shareLink: share,
          me: 'matt',
        );

    test('is the title, a Discord timestamp and how long, the items, the decisions and both links', () {
      final text = discordMeetingMessage(post(
        actions: const [
          MeetingAction(text: 'First pass at the __copy__'),
          MeetingAction(text: 'Book the venue', assignee: '@dana', due: '2026-10-31'),
          MeetingAction(text: 'the press list', assignee: 'Sam'),
          MeetingAction(text: 'Send the invite', done: true),
        ],
        decisions: const ['No paid ads until the beta closes.'],
        share: 'https://ghostmarkdown.com/read.html#abc.def',
        team: 'Hello_Trade',
      ));
      final lines = text.split('\n');
      expect(lines.take(3), [r'## Launch\_sync \*v2\*', r'<t:1792591200:f> · 45 min · Hello\_Trade', '*A call about the launch.*']);
      // The due day in the phone's words: "Sat, 31 Oct" here, "Sat, Oct 31" in the US.
      expect(lines[6], matches(RegExp(r'^- \*\*@dana\*\*: Book the venue \*\(due Sat, (?:31 Oct|Oct 31)\)\*$')));
      expect([...lines.sublist(3, 6), ...lines.sublist(7)], [
        '',
        '**Action items**',
        '- **@matt**: First pass at the **copy**',
        '- **Sam**: the press list',
        '- **@matt**: ~~Send the invite~~',
        '',
        '**Decisions**',
        '- No paid ads until the beta closes.',
        '',
        '[Read the notes and transcript](https://ghostmarkdown.com/read.html#abc.def)',
        '-# In Ghost.md: `ghostmd://note/n-1`',
      ]);
    });

    test('says there are no action items, and carries the app’s line alone without a share', () {
      final text = discordMeetingMessage(post());
      expect(text, contains('\n\nNo action items.\n\n'));
      expect(text, endsWith('\n\n-# In Ghost.md: `ghostmd://note/n-1`'));
      expect(text, isNot(contains('Decisions')));
      expect(text, isNot(contains('](')), reason: 'no link without a share: Discord links no ghostmd://');
    });

    test('stays one message: the decisions go first, then items from the end, and the links stay', () {
      final many = [for (var i = 0; i < 25; i++) MeetingAction(text: 'Item $i ${'x' * 90}')];
      final text = discordMeetingMessage(post(actions: many, decisions: const ['Ship it.'], share: 'https://ghostmarkdown.com/read.html#abc.def'));
      expect(text.length, lessThanOrEqualTo(2000));
      expect(text, isNot(contains('**Decisions**')));
      expect(text, matches(RegExp(r'\*and \d+ more in Ghost\.md\*')));
      expect(text, endsWith('[Read the notes and transcript](https://ghostmarkdown.com/read.html#abc.def)\n-# In Ghost.md: `ghostmd://note/n-1`'));
      // Short items: the first 25 listed, the rest counted, the decisions kept while they fit.
      final shorter = discordMeetingMessage(post(actions: [for (var i = 0; i < 30; i++) MeetingAction(text: 'Item $i')], decisions: const ['Ship it.']));
      expect(RegExp(r'^- \*\*@matt\*\*: Item', multiLine: true).allMatches(shorter).length, 25);
      expect(shorter, contains('*and 5 more in Ghost.md*'));
      expect(shorter, contains('**Decisions**\n- Ship it.'));
    });

    test('is made from the note, as Slack’s post is', () {
      final note = Note(id: 'n1', body: meeting, createdAt: 1000, updatedAt: 1000, recordingMs: 80 * 60000);
      final text = discordMeetingMessage(meetingPostOf(note, startedAt: 1792591200000));
      expect(text, startsWith('## Launch sync\n<t:1792591200:f> · 1 hr 20 min\n*A call that fixed the launch date and who does what next.*\n'));
      expect(text, contains('- **Sam**: the press list by Friday.'));
      expect(text, contains('- **@dana**: Book the venue'));
      expect(text, contains('**Decisions**\n- no paid ads until the beta closes.'));
    });
  });

  group('the posting', () {
    late FakeDiscord discord;
    late Preferences prefs;
    late Map<String, Note> notes;
    late Registry before;
    late List<String> shared;

    MeetingDiscordPoster poster({Future<String> Function(Note note)? share}) => MeetingDiscordPoster(
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

    setUp(() {
      discord = FakeDiscord();
      before = plugins;
      usePlugins(createRegistry([discordPlugin], store: MemorySwitches({'discord': true})));
      prefs = Preferences.defaults;
      notes = {'n1': Note(id: 'n1', body: meeting, createdAt: 1000, updatedAt: 1000, recordingMs: 45 * 60000)};
      shared = [];
    });

    tearDown(() {
      usePlugins(before);
      debugDefaultTargetPlatformOverride = null;
    });

    test('is offered only with the plugin on and a channel on the device, and never on an iPhone', () async {
      expect(meetingDiscordOffered(), isFalse);
      await addDiscordChannel('#launch', hook);
      expect(meetingDiscordOffered(), isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(meetingDiscordOffered(), isFalse);
      debugDefaultTargetPlatformOverride = null;
      plugins.setEnabled('discord', false);
      expect(meetingDiscordOffered(), isFalse);
    });

    test('is off until a channel is chosen, and on once one is', () async {
      final launch = await addDiscordChannel('#launch', hook);
      final ops = await addDiscordChannel('#ops', webhookOf('223456789012345678'));
      expect(discordMeetingSettings().on, isFalse);
      expect(discordMeetingSettings().share, isTrue);
      setDiscordMeetingPosts(true);
      expect(postsMeetingsToDiscord(), isFalse, reason: 'with two to choose from, the switch waits for a choice');
      chooseDiscordMeetingChannel(ops.id);
      expect(postsMeetingsToDiscord(), isTrue);
      expect(discordMeetingChannel(), ops);
      setDiscordMeetingPosts(false);
      chooseDiscordMeetingChannel(launch.id);
      expect(postsMeetingsToDiscord(), isFalse, reason: 'a change of channel is not the switch');
      await forgetDiscordChannel(launch.id);
      await forgetDiscordChannel(ops.id);
      final only = await addDiscordChannel('#only', webhookOf('323456789012345678'));
      setDiscordMeetingPosts(true);
      expect(discordMeetingChannel(), only);
      expect(postsMeetingsToDiscord(), isTrue);
    });

    test('posts once a meeting is written up, with its share link, and marks it for the account', () async {
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      expect(await poster().meetingSummarized('n1', meeting), isTrue);
      final text = discord.said.single;
      expect(text, startsWith('## Launch sync\n'));
      expect(text, contains('- **Sam**: the press list by Friday.'));
      expect(text, endsWith('[Read the notes and transcript](https://ghostmarkdown.com/read.html#n1.key)\n-# In Ghost.md: `ghostmd://note/n1`'));
      expect(discord.posts.single.body['allowed_mentions'], {'parse': <Object?>[]});
      expect(shared, ['n1']);
      expect(prefs.more[discordMeetingPostsKey], {'n1': {'at': 1000, 'posted': 1000}});
      expect(discordMeetingPostTries(), isEmpty);
    });

    test('posts nothing for a summary made again, or on another device that writes it up', () async {
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      await poster().meetingSummarized('n1', meeting);
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      // Another device: its own ground, the account's preferences as synced.
      final synced = prefs;
      final other = FakeDiscord();
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      prefs = synced;
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      expect(other.posts, isEmpty);
      expect(discord.posts, hasLength(1));
    });

    test('keeps its own mark: a meeting already posted to Slack still goes to Discord, once', () async {
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      prefs = withMeetingPostMark(prefs, 'n1', at: 900, posted: 900);
      expect(await poster().meetingSummarized('n1', meeting), isTrue);
      expect((prefs.more[slackMeetingPostsKey] as Map).keys, ['n1']);
      expect((prefs.more[discordMeetingPostsKey] as Map).keys, ['n1']);
      expect(syncedPrefs, containsAll([slackMeetingPostsKey, discordMeetingPostsKey]));
    });

    test('posts nothing with the switch off, and marks nothing, so turning it on later still posts it', () async {
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      setDiscordMeetingPosts(false);
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      expect(discord.posts, isEmpty);
      expect(prefs.more[discordMeetingPostsKey], isNull);
      expect(shared, isEmpty);
      setDiscordMeetingPosts(true);
      expect(await poster().meetingSummarized('n1', meeting), isTrue);
    });

    test('posts nothing with no channel, or with the plugin off', () async {
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      plugins.setEnabled('discord', false);
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      expect(discord.ground.asked, isEmpty);
    });

    test('goes without a share link when it is turned off, or none can be made', () async {
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      setDiscordMeetingShareLink(false);
      await poster().meetingSummarized('n1', meeting);
      expect(shared, isEmpty);
      expect(discord.said.single, isNot(contains('read.html')));

      setDiscordMeetingShareLink(true);
      notes['n2'] = Note(id: 'n2', body: meeting, createdAt: 1, updatedAt: 1);
      await poster(share: (_) async => throw const ShareError('Sign in under Settings > Account to share.')).meetingSummarized('n2', meeting);
      expect(discord.said.last, endsWith('\n\n-# In Ghost.md: `ghostmd://note/n2`'));
    });

    test('keeps a failure with Discord’s reason, tries again when the app runs, and stops after five tries', () async {
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      discord.refuse = (404, unknownWebhook);
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      expect(failedDiscordMeetingPosts().single.said, contains('Discord no longer knows this webhook'));
      expect(failedDiscordMeetingPosts().single.tries, 1);
      expect(discordMeetingPostMarked(prefs, 'n1'), isTrue);
      for (var run = 2; run <= meetingPostTriesMost; run++) {
        expect(await poster().resume(), 0);
      }
      expect(failedDiscordMeetingPosts().single.spent, isTrue);
      expect((prefs.more[discordMeetingPostsKey] as Map)['n1'], containsPair('failed', 1000));
      final asked = discord.posts.length;
      expect(await poster().resume(), 0);
      expect(discord.posts.length, asked, reason: 'its tries are spent');

      discord.refuse = null;
      expect(await poster().tryNow('n1'), 1);
      expect(discordMeetingPostTries(), isEmpty);
      expect((prefs.more[discordMeetingPostsKey] as Map)['n1'], containsPair('posted', 1000));
    });

    test('a long rate limit is a failed try, posted on the next run, and not twice', () async {
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      discord.answers.add((429, '{"message": "You are being rate limited.", "retry_after": 60, "global": false}', const {}));
      expect(await poster().meetingSummarized('n1', meeting), isFalse);
      expect(failedDiscordMeetingPosts().single.said, 'Discord asked for fewer posts. Try again in 60 seconds.');
      expect(discord.waited, isEmpty);
      expect(await poster().resume(), 1);
      expect(await poster().resume(), 0);
      expect(discord.posts, hasLength(2));
      expect(discordMeetingPostTries(), isEmpty);
    });

    test('lets go of a meeting deleted meanwhile, and of one let go from the page', () async {
      await addDiscordChannel('#launch', hook);
      setDiscordMeetingPosts(true);
      discord.refuse = (500, '{}');
      notes['n2'] = Note(id: 'n2', body: meeting, createdAt: 1, updatedAt: 1);
      await poster().meetingSummarized('n1', meeting);
      await poster().meetingSummarized('n2', meeting);
      forgetDiscordMeetingPost('n2');
      notes.remove('n1');
      discord.refuse = null;
      expect(await poster().resume(), 0);
      expect(discordMeetingPostTries(), isEmpty);
    });
  });
}
