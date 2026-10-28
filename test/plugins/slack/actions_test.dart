import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/slack/slack.dart';
import 'package:glacier/glacier.dart' show HapticKind;

import 'support.dart';

/// Slack's two rows on a note's More sheet: shown only once a channel is added on a build that can post, the
/// summary's only on a note with a meeting's summary, and each saying on the note where it went or why it didn't.
/// A port of `src/app/plugins/slack/actions.test.ts`, case for case.
void main() {
  const hook = 'https://hooks.slack.com/services/T0/B0/abc';
  const meeting = '# Standup\n\n## Summary\nWe agreed to ship on Friday.\n\n- [ ] Sam: write the post\n\n## Transcript\nSam: so…';

  late FakeSlack slack;

  setUp(() {
    slack = FakeSlack();
    slackKeptText = (noteId) => null;
  });

  TestNote noteOf(String body) => TestNote(body, noteId: 'n1');

  group('Post to Slack', () {
    test('shows only once a channel is added, on a binary that can post', () async {
      expect(postNote.visible('n1', 'Hello'), isFalse);
      await addChannel('#launch', hook);
      expect(postNote.visible('n1', 'Hello'), isTrue);
      setSlackReady(false);
      expect(postNote.visible('n1', 'Hello'), isFalse);
    });

    test('is greyed on a note with nothing in it, and names the one channel', () async {
      await addChannel('#launch', hook);
      expect(postNote.enabled('n1', '---\nlocation: 1, 2\n---\n'), isFalse);
      expect(postNote.hint('n1', ''), 'Nothing to post yet.');
      expect(postNote.enabled('n1', 'Hello'), isTrue);
      expect(postNote.hint('n1', 'Hello'), 'The whole note goes to #launch, as it reads now.');
    });

    test('offers every channel to choose from, and posts to the one chosen', () async {
      await addChannel('#launch', hook);
      final ops = await addChannel('#ops', '$hook-ops');
      expect([for (final c in postNote.choices!('n1')) c.label], ['#launch', '#ops']);
      expect([for (final c in postNote.choices!('n1')) c.id].last, ops.id);
      expect(postNote.hint('n1', 'Hello'), 'The whole note goes to one of 2 channels, as it reads now.');
      final note = noteOf('# Launch\n\nShip **Friday**.');
      await postNote.run(note, ops.id);
      expect(slack.posts, [(url: '$hook-ops', text: '*Launch*\nShip *Friday*.')]);
      expect(isWebhookPost(slack.ground.asked.single, '$hook-ops'), isTrue);
      expect(note.said, ['Posted to #ops.']);
      expect(slack.felt, [HapticKind.success]);
    });

    test('says why when Slack refuses, in its words', () async {
      final launch = await addChannel('#launch', hook);
      slack.refuse = (404, 'no_service');
      final note = noteOf('Hello');
      await postNote.run(note, launch.id);
      expect(note.said, ['Not posted to #launch. Slack no longer knows this webhook. Make a new one in Slack and add the channel again.']);
      expect(slack.felt, isEmpty);
    });

    test('says so when the channel chosen has gone meanwhile', () async {
      await addChannel('#launch', hook);
      await addChannel('#ops', hook);
      final note = noteOf('Hello');
      await postNote.run(note, 'gone');
      expect(slack.posts, isEmpty);
      expect(note.said, ['That Slack channel isn’t on this device any more.']);
    });

    // Not a case of the page's: the one channel, with no choice handed over.
    test('posts to the one channel when there is no other to choose', () async {
      await addChannel('#launch', hook);
      final note = noteOf('Hello');
      await postNote.run(note);
      expect(slack.posts, [(url: hook, text: '*Hello*')]);
      expect(note.said, ['Posted to #launch.']);
    });
  });

  group('Post the summary to Slack', () {
    test('shows only on a note with a meeting’s summary', () async {
      await addChannel('#launch', hook);
      expect(postSummary.visible('n1', '# Standup\n\nWe met.'), isFalse);
      expect(postSummary.visible('n1', meeting), isTrue);
      expect(postSummary.enabled('n1', meeting), isTrue);
      expect(postSummary.hint('n1', meeting), 'The meeting’s action items, a brief summary and the link to its notes go to #launch.');
    });

    test('posts the summary alone, under the note’s title', () async {
      final launch = await addChannel('#launch', hook);
      final note = noteOf(meeting);
      await postSummary.run(note, launch.id);
      expect(slack.posts, [(url: hook, text: '*Standup*\n*Summary*\nWe agreed to ship on Friday.\n\n☐ Sam: write the post')]);
      expect(note.said, ['Posted to #launch.']);
    });

    // Matt, 2026-10-28: a meeting's summary posted by hand goes as the meeting's own post, action items, a brief
    // summary, then the public link, and counts as its one post so it does not go again by itself.
    test('with the meetings poster, posts the action items, a brief summary and the public link, and marks it posted', () async {
      final launch = await addChannel('#launch', hook);
      var prefs = const Preferences();
      final saved = Note(id: 'n1', body: meeting, createdAt: 1000, updatedAt: 1000);
      meetingSlackPoster = MeetingSlackPoster(
        preferences: () => prefs,
        setPreferences: (change) => prefs = change(prefs),
        getNote: (id) async => id == 'n1' ? saved : null,
        shareLink: (note) async => 'https://ghostmarkdown.com/read.html#n1.key',
        kept: (_) => null,
        now: () => 1000,
      );
      addTearDown(() => meetingSlackPoster = null);
      final note = noteOf(meeting);
      await postSummary.run(note, launch.id);
      final text = slack.posts.single.text as String;
      expect(text.indexOf('*Action items*'), lessThan(text.indexOf('*Summary*')));
      expect(text, contains('• Sam: write the post'));
      expect(text, contains('We agreed to ship on Friday.'));
      expect(text, endsWith('<https://ghostmarkdown.com/read.html#n1.key|Read the notes and transcript>'));
      expect(note.said, ['Posted to #launch.']);
      expect(meetingPostMarked(prefs, 'n1'), isTrue, reason: 'not posted again once written up');
    });

    test('says so when the summary was taken out before it went', () async {
      final launch = await addChannel('#launch', hook);
      final note = noteOf('# Standup\n\nWe met.');
      await postSummary.run(note, launch.id);
      expect(slack.posts, isEmpty);
      expect(note.said, ['There is no summary in this note to post.']);
    });
  });

  // Not a case of the page's: the manifest's words, held to the page's own (src/app/plugins/slack/manifest.ts).
  group('the Slack plugin', () {
    test('says what the page’s manifest says, off until switched on, and keeps its webhooks as secrets', () {
      final manifest = slackPlugin.manifest;
      expect([manifest.id, manifest.name, manifest.version, manifest.author, manifest.standard], ['slack', 'Slack', '1.0.0', 'Ghost.md', false]);
      expect(manifest.description, 'Posts a note, or a meeting’s summary, to a Slack channel when you say so, and an organization’s news to its channel.');
      expect([for (final p in manifest.permissions) p.kind.name], ['notes', 'network', 'native']);
      expect([for (final p in manifest.permissions) p.why], [
        'Reads the note you post, or its summary, to make the message. Nothing in the note changes.',
        // The port's own words: meetings post by themselves where a channel is chosen for them (meetings.dart).
        'Posts to the channels you add, straight from this device. Only what you choose to post goes: a note you post, each meeting’s action items where you chose a channel for meetings, and an organization’s news where you set a channel for it.',
        'Keeps each channel’s webhook inside the app, where no page can read it back, and posts with it.',
      ]);
      expect(manifest.hosts, ['hooks.slack.com']);
      expect([manifest.native!.generation, ...manifest.native!.commands], [25, 'slack_channels', 'slack_save_channel', 'slack_forget_channel', 'slack_post']);
      expect(manifest.storage, ['glyph-slack-channels', 'glyph-slack-news', 'glyph-slack-posted', 'glyph-slack-meetings', 'glyph-slack-meeting-queue']);
      expect(manifest.secrets, ['glyph-slack-webhook:']);
      expect([slackPlugin.icon, slackPlugin.settings?.hue], ['hash', 'magenta']);
      expect([for (final found in slackPlugin.settings!.settings) found.name], ['Channels', 'Add a channel']);
      expect([for (final action in slackPlugin.noteActions) action.id], ['slack-post-note', 'slack-post-summary']);
    });

    test('reads its row in Settings by how many channels there are', () async {
      expect(slackPlugin.settings!.summary(), 'Channels to post to');
      await addChannel('#launch', hook);
      expect(slackPlugin.settings!.summary(), '1 channel');
      await addChannel('#ops', hook);
      expect(slackPlugin.settings!.summary(), '2 channels');
    });
  });
}
