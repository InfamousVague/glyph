// A notebook's rules and GitHub sheet (lib/book/rules_sheet.dart; Matt, 2026-10-31): the rules as sentences, the
// sentence builder writing a rule into the notebook's rules fence, the text, and the repos and what a merge does. On a
// phone and a desktop, light and dark, with pictures into build/feature-shots/tickets-automation/ under
// --update-goldens.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/book/rules.dart';
import 'package:ghost_md/book/rules_sheet.dart';
import 'package:ghost_md/core/front_matter.dart' show frontMatterValue;

import '../support/feature_shot.dart';
import '../support/render.dart';

const String notebook = '''---
title: Help desk
book: true
key: HT
---
# Help desk

- [[HT-12 Fix the login]]

```rules
When status becomes Done, post to Slack #eng "{id} {title} shipped"
When a ticket is created, set assignee to Sam
When the moon is full, howl
```
''';

void main() {
  setUpAll(loadAppFonts);

  late String body;
  late List<String> closed;

  Future<void> show(WidgetTester tester, {Size size = const Size(390, 844), String theme = 'light'}) async {
    await pumpApp(
      tester,
      size: size,
      prefs: AppPreferences(theme: theme),
      home: RulesSheet(body: () => body, write: (change) => body = change(body), people: const ['Sam', 'Priya'], hasToken: true, onClose: () => closed.add('closed')),
    );
    await settle(tester);
  }

  setUp(() {
    body = notebook;
    closed = [];
  });

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)), text);
    await tester.pump();
  }

  testWidgets('the rules read as sentences, and a line it cannot read says why', (tester) async {
    await show(tester);
    expect(find.text('When status becomes Done, post to Slack #eng "{id} {title} shipped"'), findsOneWidget);
    expect(find.text('When a ticket is created, set assignee to Sam'), findsOneWidget);
    expect(find.text('When the moon is full, howl'), findsOneWidget);
    expect(find.textContaining('Not a “when” this app knows'), findsOneWidget);
    await away(tester);
  });

  testWidgets('the builder: a rule made as a sentence, slot by slot, and written into the fence', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('rule-add')));
    await settle(tester);
    expect(find.byKey(const ValueKey('rule-sentence')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slot-trigger')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('trigger-blocked')));
    await settle(tester);
    await type(tester, 'value-days', '2');
    await tester.tap(find.byKey(const ValueKey('slot-verb-0')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('verb-postdiscord')));
    await settle(tester);
    await type(tester, 'value-channel', '#triage');
    await type(tester, 'value-text', '{id} is stuck');
    await tester.tap(find.byKey(const ValueKey('slot-condition')));
    await settle(tester);
    await type(tester, 'value-condition', 'priority is High');
    expect(find.text('blocked for'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('post to Discord'), findsOneWidget);
    expect(find.text('#triage “{id} is stuck”'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('rule-save')));
    await tester.tap(find.byKey(const ValueKey('rule-save')));
    await settle(tester);
    final rules = rulesIn(body);
    expect(rules.rules.last.text, 'When blocked for 2 days and priority is High, post to Discord #triage "{id} is stuck"');
    expect(rules.problems.single.text, 'When the moon is full, howl', reason: 'kept where it was');
    await away(tester);
  });

  testWidgets('a rule opened, changed and saved over its own line; another deleted', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('rule-0')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('slot-value')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('status-In review')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('rule-save')));
    await tester.tap(find.byKey(const ValueKey('rule-save')));
    await settle(tester);
    expect(rulesFenceOf(body)!.text.split('\n').first, 'When status becomes In review, post to Slack #eng "{id} {title} shipped"');
    await tester.tap(find.byKey(const ValueKey('rule-1')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('rule-delete')));
    await tester.tap(find.byKey(const ValueKey('rule-delete')));
    await settle(tester);
    expect(rulesIn(body).rules, hasLength(1));
    await away(tester);
  });

  testWidgets('the text: the fence’s own lines, saved as typed', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('rule-text')));
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('rules-text')), matching: find.byType(EditableText)), 'When due passes, notify me\nWhen it rains, sing');
    await tester.pump();
    expect(find.textContaining('Line 2:'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rules-text-save')));
    await settle(tester);
    expect(rulesFenceOf(body)!.text, 'When due passes, notify me\nWhen it rains, sing');
    await away(tester);
  });

  testWidgets('GitHub: the repos written as typed, and what a merge does', (tester) async {
    await show(tester);
    await type(tester, 'rules-github', 'ghost/app, ghost/site');
    expect(githubReposOf(body), ['ghost/app', 'ghost/site']);
    await tester.ensureVisible(find.byKey(const ValueKey('merge-In review')));
    await tester.tap(find.byKey(const ValueKey('merge-In review')));
    await settle(tester);
    expect(frontMatterValue(body, 'on-merge'), 'In review');
    await tester.ensureVisible(find.byKey(const ValueKey('merge-off')));
    await tester.tap(find.byKey(const ValueKey('merge-off')));
    await settle(tester);
    expect(onMergeOf(body), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('merge-done')));
    await tester.tap(find.byKey(const ValueKey('merge-done')));
    await settle(tester);
    expect(frontMatterValue(body, 'on-merge'), isNull);
    expect(onMergeOf(body), 'done');
    await away(tester);
  });

  test('the More sheet’s line', () {
    expect(rulesSummary('---\ngithub: ghost/app\n---\n'), 'ghost/app');
    expect(rulesSummary(notebook), '2 rules');
    expect(rulesSummary('# Empty\n'), startsWith('When a ticket changes'));
  });

  for (final theme in ['light', 'dark']) {
    for (final (size, where) in [(const Size(390, 844), 'phone'), (const Size(1280, 800), 'desktop')]) {
      testWidgets('the rules and the builder, $where, $theme', (tester) async {
        body = notebook.replaceFirst('key: HT', 'key: HT\ngithub: ghost/app');
        await show(tester, size: size, theme: theme);
        await featureShot(tester, 'tickets-automation', 'rules-$where-$theme');
        await tester.tap(find.byKey(const ValueKey('rule-0')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('slot-value')));
        await settle(tester);
        await featureShot(tester, 'tickets-automation', 'rule-builder-$where-$theme');
        await away(tester);
      });
    }
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
