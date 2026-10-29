// Slack's setup (lib/plugins/slack/slack_setup.dart; Matt, 2026-10-29: "add the voiceover onboarding for the rest of the
// plugins"): its steps and their addresses (unverified), the channel added through the plugin's own addChannel, the
// check as the page's Test (one post), a webhook Slack refuses let go of and pasted again, and Set up at the head of the
// plugin's page. Slack is FakeSlack (support.dart): nothing is asked of the network.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/slack/slack.dart';

import 'support.dart';

const String hook = 'https://hooks.slack.com/services/T0001/B0001/abcDEF123';

void main() {
  late FakeSlack slack;

  setUp(() {
    useStored(MemoryStored());
    slack = FakeSlack();
  });
  tearDown(() => usePluginGround(PluginGround()));

  test('an intro, the webhook made, the channel added, a test sent, and a first thing to try', () {
    final setup = slackSetup();
    expect([for (final step in setup.steps) step.id], ['intro', 'webhook', 'paste', 'check', 'done']);
    final links = [for (final step in setup.steps.whereType<SetupOpen>()) for (final link in step.links) (link.url, link.verified)];
    expect(links, [(slackAppsUrl, false), (slackWebhooksGuideUrl, false)]);
    final paste = setup.steps.whereType<SetupPaste>().single;
    expect([for (final field in paste.fields) (field.id, field.secret)], [('name', false), ('webhook', true)]);
    expect(paste.fields.last.shape!('http://hooks.slack.com/services/x'), 'A Slack webhook starts with https://, never http://.');
    expect(slackPlugin.setup, isNotNull);
  });

  test('adds the channel as the page does, refusing a name taken; then needed no more', () async {
    final setup = slackSetup();
    expect(setup.ready(), isFalse);
    final paste = setup.steps.whereType<SetupPaste>().single;
    expect(await paste.save({'name': '#launch', 'webhook': hook}), isNull);
    expect([for (final channel in channels()) channel.name], ['#launch']);
    expect(slack.webhookOf(channels().single), hook);
    expect(setup.ready(), isTrue);
    expect(await slackSetup().steps.whereType<SetupPaste>().single.save({'name': '#Launch', 'webhook': hook}), 'There is a channel called #Launch already.');
  });

  test('the check is the page’s Test: one post to the channel just added', () async {
    final setup = slackSetup();
    await setup.steps.whereType<SetupPaste>().single.save({'name': '#launch', 'webhook': hook});
    final result = await setup.steps.whereType<SetupCheck>().single.run();
    expect((result.kind, result.words), (SetupCheckKind.ok, 'Sent a test to #launch. It’s there in Slack now.'));
    expect(slack.posts, [(url: hook, text: slackTestText)]);
  });

  test('a webhook Slack no longer knows is let go of, if the setup added it, and pasted again', () async {
    final setup = slackSetup();
    await setup.steps.whereType<SetupPaste>().single.save({'name': '#launch', 'webhook': hook});
    slack.refuse = (404, 'no_service');
    final check = setup.steps.whereType<SetupCheck>().single;
    final result = await check.run();
    expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
    expect(result.words, 'Slack no longer knows this webhook. Make a new one in Slack and add the channel again. It was taken out again.');
    expect(channels(), isEmpty);
    // Checked again with nothing pasted: nothing to post to.
    expect((await check.run()).words, 'No channel is added yet. Paste its webhook first.');
  });

  test('a channel from before is tested, and kept whatever Slack says', () async {
    await addChannel('#ops', hook);
    slack.refuse = (500, 'oops');
    final result = await slackSetupResult();
    expect((result.kind, result.words, result.pasteAgain), (SetupCheckKind.failed, 'Slack had a problem. Try again in a moment.', false));
    slack.refuse = (404, 'no_service');
    expect((await slackSetupResult()).pasteAgain, isTrue);
    expect([for (final channel in channels()) channel.name], ['#ops']);
  });

  testWidgets('the plugin’s page has Set up while there is no channel', (tester) async {
    await pumpPane(tester, const SlackPane());
    expect(find.text('Set up Slack'), findsOneWidget);
    expect(find.text('A few short steps: a webhook from Slack for a channel, and a test message to be sure it posts.'), findsOneWidget);
    await away(tester);
  });
}
