import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/orgs/types.dart';
import 'package:ghost_md/plugins/github/plain_field.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/slack/slack.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';

import 'support.dart';

/// The Slack plugin's page in Settings: a channel added by name and pasted webhook, which is never shown again; a
/// test message, a new name and forgetting; and where an organization's news goes, for the organizations the person
/// is in. A port of `src/app/plugins/slack/SlackPane.test.tsx`.
///
/// Not ported: "says Slack works in the app, in a browser". That was the page outside the app, which this never
/// is; its place is taken by the page on a build that cannot post.
void main() {
  setUpAll(loadAppFonts);

  const hook = 'https://hooks.slack.com/services/T0/B0/secretpart';

  late FakeSlack slack;

  setUp(() => slack = FakeSlack());

  Finder field(String label) => find.descendant(of: find.byWidgetPredicate((w) => w is PlainField && w.label == label), matching: find.byType(EditableText));
  Finder pick(String label) => find.byWidgetPredicate((w) => w is Pick && w.label == label);

  Future<void> type(WidgetTester tester, String label, String text) async {
    await tester.enterText(field(label), text);
    await tester.pump();
  }

  Future<void> addLaunch(WidgetTester tester) async {
    await type(tester, 'Channel name', '#launch');
    await type(tester, 'Webhook', hook);
    await press(tester, action('Add it'));
    expect(textOf(tester), contains('Added #launch.'));
  }

  OrgRow member(String id, String name, [String state = 'member']) => OrgRow(id: id, name: name, role: 'member', state: state, members: 3);

  group('Slack’s page', () {
    testWidgets('says Slack needs the newest Ghost.md, on a build that cannot post', (tester) async {
      usePluginGround(PluginGround(stored: MemoryStored.new, hasNativeGeneration: (wanted) async => false));
      await pumpPane(tester, const SlackPane());
      expect(textOf(tester), contains('Slack needs the newest Ghost.md.'));
      expect(find.byType(PlainField), findsNothing);
      await away(tester);
    });

    testWidgets('adds a channel, then lists it by its name alone, kept on this device', (tester) async {
      await pumpPane(tester, const SlackPane());
      expect(textOf(tester), contains('No channels yet'));
      expect(textOf(tester), contains('Kept on this device'));
      await type(tester, 'Channel name', '#launch');
      await type(tester, 'Webhook', 'https://example.com/hook');
      expect(textOf(tester), contains('isn’t a Slack webhook'));
      expect(actionEnabled(tester, 'Add it'), isFalse);
      await addLaunch(tester);
      expect([for (final c in channels()) c.name], ['#launch']);
      expect(textOf(tester), isNot(contains('secretpart')));
      expect(tester.widget<EditableText>(field('Webhook')).controller.text, '');
      // Typed as a secret, kept as one, and nothing was asked of Slack.
      expect(tester.widget<EditableText>(field('Webhook')).obscureText, isTrue);
      expect(slack.webhookOf(channels().single), hook);
      expect(slack.ground.kept.allKeys.any((key) => (slack.ground.kept.getItem(key) ?? '').contains('secretpart')), isFalse);
      expect(slack.ground.asked, isEmpty);
      await away(tester);
    });

    testWidgets('sends a test, renames and forgets a channel', (tester) async {
      await pumpPane(tester, const SlackPane());
      await addLaunch(tester);
      await press(tester, action('Test'));
      expect(textOf(tester), contains('Sent a test to #launch.'));
      expect(slack.posts, [(url: hook, text: 'A test from Ghost.md. What you post from this device will land here.')]);
      expect(isWebhookPost(slack.ground.asked.single, hook), isTrue);
      await press(tester, action('Rename'));
      // The row's own field, above the one a new channel is named in.
      await tester.enterText(field('Channel name').first, '#ship');
      await tester.pump();
      await press(tester, action('Keep it'));
      expect([for (final c in channels()) c.name], ['#ship']);
      await press(tester, action('Forget'));
      expect(textOf(tester), contains('Forgot #ship.'));
      expect(channels(), isEmpty);
      expect(slack.ground.secrets.held, isEmpty);
      await away(tester);
    });

    testWidgets('chooses a channel for the news of each organization the person is in, and nowhere again', (tester) async {
      slackOrgs = SlackOrgs(list: () => [member('acme', 'Acme'), member('globex', 'Globex', 'invited')]);
      await pumpPane(tester, const SlackPane());
      expect(textOf(tester), isNot(contains('ORGANIZATIONS’ NEWS')));
      await addLaunch(tester);
      expect(textOf(tester), contains('ORGANIZATIONS’ NEWS'));
      expect(textOf(tester), contains('each device with a channel set posts the news'));
      expect(textOf(tester), isNot(contains('Globex')));
      await press(tester, action('Change'));
      await press(tester, pick('Post Acme’s news to #launch'));
      expect(newsChannelFor('acme')?.name, '#launch');
      expect(textOf(tester), contains('Its news goes to #launch.'));
      await press(tester, action('Change'));
      await press(tester, pick('Don’t post Acme’s news'));
      expect(newsChannelFor('acme'), isNull);
      await away(tester);
    });

    // Not a case of the page's test, though the page does it: a channel whose webhook is gone says so.
    testWidgets('says a listed channel has lost its webhook, and will not test it', (tester) async {
      await addChannel('#launch', hook);
      slack.ground.secrets.held.clear();
      await pumpPane(tester, const SlackPane());
      expect(textOf(tester), contains('Its webhook isn’t on this device any more. Forget it and add it again.'));
      expect(actionEnabled(tester, 'Test'), isFalse);
      expect(actionEnabled(tester, 'Forget'), isTrue);
      await away(tester);
    });
  });
}
