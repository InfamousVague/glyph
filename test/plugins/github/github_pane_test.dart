import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/plugins/github/github.dart';
import 'package:ghost_md/plugins/github/plain_field.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';

import 'support.dart';

/// The GitHub plugin's page in Settings: the repos read on this phone and a way to forget each, and the token,
/// typed once and then only said to be kept. A port of `src/app/plugins/github/GitHubPane.test.tsx`, case for case.
void main() {
  setUpAll(loadAppFonts);

  late TestGround ground;

  Map<String, Object?> kept([Map<String, Object?> over = const {}]) => {
        'id': 'infamousvague/attackfm',
        'owner': 'InfamousVague',
        'repo': 'AttackFM',
        'url': 'https://github.com/InfamousVague/AttackFM',
        'branch': 'main',
        'description': '',
        'files': ['README.md'],
        'pack': 'A radio.',
        'packModel': null,
        'packedAt': DateTime(2026, 9, 20, 12).millisecondsSinceEpoch,
        ...over,
      };

  setUp(() => ground = useGround());

  Finder tokenField() => find.byWidgetPredicate((w) => w is PlainField && w.label == 'GitHub token');

  group('the day a repo was read, in the phone’s own words (core/locale_dates.dart)', () {
    tearDown(() => toldLocale = null);
    final read = DateTime(2026, 9, 20, 12).millisecondsSinceEpoch;

    test('an American phone has the month first', () {
      toldLocale = DateLocale.enUS;
      expect(packedDay(read), 'September 20');
    });

    test('a British phone has the day first', () {
      toldLocale = DateLocale.enGB;
      expect(packedDay(read), '20 September');
    });
  });

  group('the GitHub page', () {
    testWidgets('says there are no repos yet, and where one is linked from', (tester) async {
      await pumpPane(tester, const GitHubPane());
      expect(textOf(tester), contains('No repos yet.'));
      expect(textOf(tester), contains('choose GitHub repo to link one'));
      await away(tester);
    });

    testWidgets('lists each repo with what wrote its briefing, and forgets one along with its links', (tester) async {
      ground.kept.setItem('glyph-github-projects', jsonEncode([kept(), kept({'id': 'o/r', 'owner': 'o', 'repo': 'r', 'packModel': 'qwen3.5-4b'})]));
      linkProject('n1', 'infamousvague/attackfm');
      await pumpPane(tester, const GitHubPane());
      final rows = [for (final row in tester.widgetList<SettingRow>(find.byType(SettingRow))) if (row.label.contains('/')) row];
      expect([for (final row in rows) row.label], ['InfamousVague/AttackFM', 'o/r']);
      expect((rows[0].hint! as Text).data, 'Kept from its README, September 20.');
      expect((rows[1].hint! as Text).data, 'Read by qwen3.5-4b, September 20.');
      await press(tester, action('Forget', find.widgetWithText(SettingRow, 'InfamousVague/AttackFM')));
      expect([for (final p in projects()) p.id], ['o/r']);
      expect(projectFor('n1'), isNull);
      expect(textOf(tester), isNot(contains('InfamousVague/AttackFM')));
      await away(tester);
    });

    testWidgets('keeps a token typed in, trimmed, and then only says one is kept until it is forgotten', (tester) async {
      await pumpPane(tester, const GitHubPane());
      expect(actionEnabled(tester, 'Keep it'), isFalse);
      await tester.enterText(find.descendant(of: tokenField(), matching: find.byType(EditableText)), '  github_pat_abc  ');
      await tester.pump();
      expect(actionEnabled(tester, 'Keep it'), isTrue);
      // Typed as a secret: dots on the screen, and nothing of it said.
      expect(tester.widget<EditableText>(find.descendant(of: tokenField(), matching: find.byType(EditableText))).obscureText, isTrue);
      await press(tester, action('Keep it'));
      expect(githubToken(), 'github_pat_abc');
      expect(ground.secrets.held, {'glyph-github-token': 'github_pat_abc'});
      expect(ground.kept.getItem('glyph-github-token'), isNull);
      // The token is never shown again, only that there is one.
      expect(textOf(tester), contains('A token is kept'));
      expect(textOf(tester), isNot(contains('github_pat_abc')));
      expect(tokenField(), findsNothing);
      await press(tester, action('Forget'));
      expect(githubToken(), '');
      expect(ground.secrets.held, isEmpty);
      expect(tokenField(), findsOneWidget);
      await away(tester);
    });

    // Not a case of the page's: the token is read from the secure store after the page is up.
    testWidgets('says a token is kept as soon as the secure store has been read', (tester) async {
      ground.secrets.held['glyph-github-token'] = 'ghp_kept';
      expect(githubToken(), isEmpty);
      // The setup's card at the page's head reads the store as the page opens (github_setup.dart, its prepare), so a
      // kept token shows without the root's warming.
      await pumpPane(tester, const GitHubPane());
      await tester.runAsync(warmGithub);
      await tester.pump();
      expect(textOf(tester), contains('A token is kept'));
      expect(textOf(tester), isNot(contains('No token')));
      await away(tester);
    });
  });
}
