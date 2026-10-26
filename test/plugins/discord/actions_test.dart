import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/discord/discord.dart';
import 'package:glacier/glacier.dart' show HapticKind;

import 'support.dart';

/// Discord's two rows on a note's More sheet (lib/plugins/discord/discord.dart; Matt, 2026-10-26): shown only once a
/// channel is added and not on an iPhone, the summary's only on a note with a meeting's summary, a long note cut
/// with its share link, and each saying on the note where it went or why it didn't.
void main() {
  final hook = webhookOf('123456789012345678');
  const meeting = '# Standup\n\n## Summary\nWe agreed to ship on Friday.\n\n- [ ] Sam: write the post\n\n## Transcript\nSam: so…';

  late FakeDiscord discord;

  setUp(() => discord = FakeDiscord());
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    discordShareLink = null;
  });

  TestNote noteOf(String body) => TestNote(body, noteId: 'n1');

  group('Post to Discord', () {
    test('shows only once a channel is added, and not on an iPhone', () async {
      expect(postNoteToDiscord.visible('n1', 'Hello'), isFalse);
      await addDiscordChannel('#launch', hook);
      expect(postNoteToDiscord.visible('n1', 'Hello'), isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(postNoteToDiscord.visible('n1', 'Hello'), isFalse);
    });

    test('is greyed on a note with nothing in it, and names the one channel', () async {
      await addDiscordChannel('#launch', hook);
      expect(postNoteToDiscord.enabled('n1', '---\nlocation: 1, 2\n---\n'), isFalse);
      expect(postNoteToDiscord.hint('n1', ''), 'Nothing to post yet.');
      expect(postNoteToDiscord.hint('n1', 'Hello'), 'The whole note goes to #launch, as it reads now.');
    });

    test('offers every channel to choose from, and posts to the one chosen, in Discord’s Markdown', () async {
      await addDiscordChannel('#launch', hook);
      final ops = await addDiscordChannel('#ops', webhookOf('223456789012345678'));
      expect([for (final c in postNoteToDiscord.choices!('n1')) c.label], ['#launch', '#ops']);
      expect(postNoteToDiscord.hint('n1', 'Hello'), 'The whole note goes to one of 2 channels, as it reads now.');
      final note = noteOf('# Launch\n\nShip __Friday__. @everyone');
      await postNoteToDiscord.run(note, ops.id);
      expect(discord.posts.single.url, webhookOf('223456789012345678'));
      expect(discord.said, ['## Launch\nShip **Friday**. @everyone']);
      expect(discord.posts.single.body['allowed_mentions'], {'parse': <Object?>[]});
      expect(note.said, ['Posted to #ops.']);
      expect(discord.felt, [HapticKind.success]);
    });

    test('says why when Discord refuses, in its words', () async {
      final launch = await addDiscordChannel('#launch', hook);
      discord.refuse = (404, unknownWebhook);
      final note = noteOf('Hello');
      await postNoteToDiscord.run(note, launch.id);
      expect(note.said, ['Not posted to #launch. Discord no longer knows this webhook. Make a new one in Discord and add the channel again.']);
      expect(discord.felt, isEmpty);
    });

    test('cuts a long note with its share link, and says so before it is pressed', () async {
      final launch = await addDiscordChannel('#launch', hook);
      final long = 'Long\n${[for (var i = 0; i < 300; i++) 'Line $i of the note.'].join('\n')}';
      // Signed out: no share to make, so the cut says the rest is in Ghost.md.
      expect(postNoteToDiscord.hint('n1', long), 'It is longer than one Discord message: the first part goes to #launch, saying the rest is in Ghost.md.');
      final shared = <String>[];
      discordShareLink = (id) async {
        shared.add(id);
        return 'https://ghostmarkdown.com/read.html#$id.key';
      };
      expect(postNoteToDiscord.hint('n1', long), contains('with a share link to the rest of the note, which anyone with the link can read'));
      final note = noteOf(long);
      await postNoteToDiscord.run(note, launch.id);
      expect(shared, ['n1']);
      expect(discord.said.single.length, lessThanOrEqualTo(2000));
      expect(discord.said.single, endsWith('**[Read the rest in Ghost.md](https://ghostmarkdown.com/read.html#n1.key)**'));
      expect(note.said, ['Posted to #launch.']);

      // A short note makes no share.
      await postNoteToDiscord.run(noteOf('Short'), launch.id);
      expect(shared, ['n1']);
    });

    test('cuts without a link when the share cannot be made', () async {
      final launch = await addDiscordChannel('#launch', hook);
      discordShareLink = (id) async => throw StateError('signed out');
      await postNoteToDiscord.run(noteOf('Long\n${'word ' * 1000}'), launch.id);
      expect(discord.said.single, endsWith('*The rest is in Ghost.md: it is longer than one Discord message.*'));
    });
  });

  group('Post the summary to Discord', () {
    test('shows only on a note with a meeting’s summary, and posts that section alone', () async {
      final launch = await addDiscordChannel('#launch', hook);
      expect(postSummaryToDiscord.visible('n1', 'No summary here'), isFalse);
      expect(postSummaryToDiscord.visible('n1', meeting), isTrue);
      expect(postSummaryToDiscord.hint('n1', meeting), 'The meeting’s summary goes to #launch, and nothing else of the note.');
      final note = noteOf(meeting);
      await postSummaryToDiscord.run(note, launch.id);
      expect(discord.said, ['## Standup\n### Summary\nWe agreed to ship on Friday.\n\n- ☐ Sam: write the post']);
      expect(note.said, ['Posted to #launch.']);
    });

    test('says there is no summary when it went meanwhile', () async {
      final launch = await addDiscordChannel('#launch', hook);
      final note = noteOf('Just words now');
      await postSummaryToDiscord.run(note, launch.id);
      expect(note.said, ['There is no summary in this note to post.']);
      expect(discord.posts, isEmpty);
    });

    test('says a channel forgotten meanwhile', () async {
      final launch = await addDiscordChannel('#launch', hook);
      await forgetDiscordChannel(launch.id);
      final note = noteOf(meeting);
      await postSummaryToDiscord.run(note, launch.id);
      expect(note.said, ['That Discord channel isn’t on this device any more.']);
    });
  });
}
