import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/slack/slack.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import 'support.dart';

/// Settings › Meetings' Post to Slack and the Slack page's line on meetings (lib/plugins/slack/meetings_section.dart;
/// Matt, 2026-10-26): drawn only with a channel, the switch off until a channel is chosen, Simple's More, and a
/// meeting that did not post said with Slack's reason and Try now.
void main() {
  setUpAll(loadAppFonts);

  const hook = 'https://hooks.slack.com/services/T0/B0/abc';

  late FakeSlack slack;
  late Registry before;

  setUp(() {
    slack = FakeSlack();
    before = plugins;
    usePlugins(createRegistry([slackPlugin], store: MemorySwitches({'slack': true})));
  });

  tearDown(() {
    usePlugins(before);
    meetingSlackPoster = null;
  });

  Finder switchOf(String label) => find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == label);
  Finder pick(String label) => find.byWidgetPredicate((w) => w is Pick && w.label == label);

  Future<void> pumpSection(WidgetTester tester, {bool simple = false}) async {
    await pumpPane(tester, PaneBody(children: [MeetingsSlackSection(prefs: preferences)]));
    if (simple) {
      preferences.value = preferences.value.choosing('simple');
      await settle(tester);
    }
  }

  testWidgets('is not drawn with no channel, nor with the plugin off', (tester) async {
    await pumpSection(tester);
    expect(textOf(tester), isNot(contains('Post to Slack')));
    await addChannel('#launch', hook);
    await settle(tester);
    expect(textOf(tester), contains('Post meetings to Slack'));
    plugins.setEnabled('slack', false);
    await settle(tester);
    expect(find.byType(GlacierSwitch), findsNothing);
    await away(tester);
  });

  testWidgets('is off until a channel is chosen, then on, with the share link on and its warning', (tester) async {
    await addChannel('#launch', hook);
    await addChannel('#ops', '$hook-ops');
    await pumpSection(tester);
    expect(tester.widget<GlacierSwitch>(switchOf('Post meetings to Slack')).checked, isFalse);
    expect(tester.widget<GlacierSwitch>(switchOf('Post meetings to Slack')).disabled, isTrue);
    expect(textOf(tester), contains('Choose a channel below first.'));
    expect(tester.widget<GlacierSwitch>(switchOf('Include a share link')).checked, isTrue);
    expect(textOf(tester), contains(meetingShareWarning));
    expect(meetingShareWarning, contains('a team’s meeting too'));
    await press(tester, action('Choose'));
    await press(tester, pick('Post meetings to #ops'));
    expect(tester.widget<GlacierSwitch>(switchOf('Post meetings to Slack')).checked, isTrue);
    expect(textOf(tester), contains('go to #ops once, as soon as it is written up'));
    await tester.tap(switchOf('Include a share link'));
    await settle(tester);
    expect(meetingSlackSettings().share, isFalse);
    await away(tester);
  });

  testWidgets('keeps the channel and the share link behind More in Simple', (tester) async {
    await addChannel('#launch', hook);
    await pumpSection(tester, simple: true);
    expect(switchOf('Post meetings to Slack'), findsOneWidget);
    expect(switchOf('Include a share link'), findsNothing);
    // One channel: the switch chooses it.
    expect(tester.widget<GlacierSwitch>(switchOf('Post meetings to Slack')).disabled, isFalse);
    await press(tester, action('Show'));
    expect(switchOf('Include a share link'), findsOneWidget);
    await tester.tap(switchOf('Post meetings to Slack'));
    await settle(tester);
    expect(postsMeetings(), isTrue);
    await away(tester);
  });

  testWidgets('says a meeting that did not post, with Slack’s reason, and Try now posts it', (tester) async {
    await addChannel('#launch', hook);
    setMeetingPosts(true);
    var prefs = Preferences.defaults;
    final poster = meetingSlackPoster = MeetingSlackPoster(
      preferences: () => prefs,
      setPreferences: (change) => prefs = change(prefs),
      getNote: (id) async => Note(id: id, body: '# Standup\n\n## Summary\nA standup.\n\n- [ ] Ship it.', createdAt: 1, updatedAt: 1),
      kept: (_) => null,
    );
    slack.refuse = (404, 'no_service');
    await tester.runAsync(() => poster.meetingSummarized('n1', '# Standup'));
    await pumpSection(tester);
    expect(textOf(tester), contains('Not posted: “Standup”'));
    expect(textOf(tester), contains('Slack no longer knows this webhook'));
    expect(textOf(tester), contains('tried 1 of 5'));
    slack.refuse = null;
    await tester.runAsync(() async {
      await tester.tap(action('Try now'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    expect(textOf(tester), isNot(contains('Not posted')));
    expect(slack.posts.last.text, contains('• Ship it.'));
    await away(tester);
  });

  testWidgets('the Slack page says where meetings go, and that they are set in Settings › Meetings', (tester) async {
    await addChannel('#launch', hook);
    await pumpPane(tester, const SlackPane());
    expect(textOf(tester), contains('Meetings aren’t posted'));
    setMeetingPosts(true);
    await settle(tester);
    expect(textOf(tester), contains('Meetings post to #launch'));
    expect(textOf(tester), contains('Set in Settings › Meetings.'));
    await away(tester);
  });
}
