// The What's new card and the Changelog page, drawn (lib/changelog; Matt, 2026-10-30: "Add a changelog popup modal that
// shows after every update with iconography"): a sheet from the foot of a phone and a card in the middle of the opened
// Fold and the Mac; a release's lines with their icons, words and tags; several releases grouped under their versions
// with "and earlier changes"; Got it and See all changes; still where the device asks for less motion; no brand's mark
// in a store-shot build; Calm in ink.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/brand_marks.dart' show BrandMarkIcon, debugStoreShots;
import 'package:ghost_md/changelog/change_look.dart';
import 'package:ghost_md/changelog/changelog.dart';
import 'package:ghost_md/changelog/changelog_pane.dart';
import 'package:ghost_md/changelog/whats_new.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

const _r88 = Release(version: '2.3.88', date: '2026-10-30', title: 'Meetings in turns', items: [
  ChangeItem(icon: 'users', words: 'Meeting transcripts are split into turns.', kind: ChangeKind.fixed),
  ChangeItem(icon: 'text', words: 'A meeting has Note and Transcript buttons.', kind: ChangeKind.added),
  ChangeItem(icon: 'search', words: 'Finding words opens Transcript at that turn.', kind: ChangeKind.better),
]);
const _r87 = Release(version: '2.3.87', date: '2026-10-30', items: [ChangeItem(icon: 'palette', words: 'The menu shows its colours.', kind: ChangeKind.fixed)]);
const _r86 = Release(version: '2.3.86', date: '2026-10-30', title: 'Updates in Activity', items: [
  ChangeItem(icon: 'lovart', words: 'Plugin work wears its logo.', kind: ChangeKind.added),
  ChangeItem(icon: 'google-meet', words: 'Meet in white.', kind: ChangeKind.better),
  ChangeItem(icon: 'notion', words: 'Notion signs in.', kind: ChangeKind.fixed),
]);

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => debugStoreShots = null);

  /// A test whose debug switches (the shadows pumpApp turns on, the Mac's platform) are put back before the binding
  /// checks them.
  void look(String description, Future<void> Function(WidgetTester tester) body) => testWidgets(description, (tester) async {
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
          debugDisableShadows = true;
        }
      });

  const phone = Size(390, 844), fold = Size(880, 1000), mac = Size(1280, 800);

  Future<List<String>> card(WidgetTester tester, {Size size = phone, List<Release> releases = const [_r88], bool more = false, String theme = 'light', bool calm = false, bool platformMac = false}) async {
    final calls = <String>[];
    if (platformMac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpApp(
      tester,
      size: size,
      prefs: AppPreferences(theme: theme, calm: calm),
      home: WhatsNewCard(version: releases.first.version, releases: releases, more: more, onClose: () => calls.add('close'), onSeeAll: () => calls.add('see all')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return calls;
  }

  Rect panel(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('sheet-panel')));

  look('on a phone: a sheet from the foot, the title, each line with its icon, words and tag, and Got it', (tester) async {
    final calls = await card(tester);
    expect(find.text("What's new in Ghost.md 2.3.88"), findsOneWidget);
    expect(find.text('Meetings in turns'), findsOneWidget, reason: 'one release: its title under the heading');
    expect(panel(tester).bottom, moreOrLessEquals(phone.height, epsilon: 1));
    expect(panel(tester).width, phone.width);
    expect(find.byKey(const ValueKey('sheet-grip')), findsOneWidget);
    for (final item in _r88.items) {
      expect(find.text(item.words), findsOneWidget);
      expect(find.byKey(ValueKey('change-icon:${item.icon}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('change-tag:fixed')), findsOneWidget);
    expect(find.byKey(const ValueKey('change-tag:new')), findsOneWidget);
    expect(find.byKey(const ValueKey('change-tag:better')), findsOneWidget);
    expect(find.text('2.3.88'), findsNothing, reason: 'no heading for a single release');
    await tester.tap(find.byKey(WhatsNewCard.gotItKey));
    await tester.pump();
    await tester.tap(find.byKey(WhatsNewCard.seeAllKey));
    await tester.pump();
    expect(calls, ['close', 'see all']);
  });

  for (final (name, size, platformMac) in [('the opened Fold', fold, false), ('the Mac', mac, true)]) {
    look('on $name: a card in the middle, no grip', (tester) async {
      await card(tester, size: size, platformMac: platformMac);
      final rect = panel(tester);
      expect(rect.center.dx, moreOrLessEquals(size.width / 2, epsilon: 1));
      expect(rect.center.dy, moreOrLessEquals(size.height / 2, epsilon: 2));
      expect(rect.width, lessThan(size.width * 0.7));
      expect(find.byKey(const ValueKey('sheet-grip')), findsNothing);
    });
  }

  look('skipped versions: each under its heading, newest first, the one running said, then "and earlier changes"', (tester) async {
    final calls = await card(tester, size: const Size(390, 1400), releases: const [_r88, _r87, _r86], more: true);
    expect(find.text('3 updates since you last looked'), findsOneWidget);
    final tops = [for (final v in ['2.3.88', '2.3.87', '2.3.86']) tester.getTopLeft(find.text(v)).dy];
    expect(tops, orderedEquals([...tops]..sort()), reason: 'newest first');
    expect(find.textContaining("you're on this one"), findsOneWidget);
    expect(tester.getTopLeft(find.text('The menu shows its colours.')).dy, inExclusiveRange(tops[1], tops[2]), reason: '2.3.87’s line under its heading');
    expect(find.text('…and earlier changes'), findsOneWidget);
    await tester.tap(find.byKey(WhatsNewCard.earlierKey));
    await tester.pump();
    expect(calls, ['see all']);
  });

  look('a plugin\'s line wears its mark; a store-shot build none, only its glyph', (tester) async {
    debugStoreShots = false;
    await card(tester, releases: const [_r86]);
    expect(find.descendant(of: find.byKey(const ValueKey('change-icon:notion')), matching: find.byType(BrandMarkIcon)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('change-icon:lovart')), matching: find.byType(BrandMarkIcon)), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugStoreShots = true;
    await card(tester, releases: const [_r86]);
    expect(find.byType(BrandMarkIcon), findsNothing);
    expect(find.byKey(const ValueKey('change-icon:notion')), findsOneWidget);
  });

  look('the kinds\' colours are the activity\'s, light and dark, and Calm\'s ink', (tester) async {
    for (final (theme, calm) in [('light', false), ('dark', false), ('light', true)]) {
      await card(tester, theme: theme, calm: calm);
      final t = GlacierTheme.of(tester.element(find.byKey(const ValueKey('change-tag:new'))));
      expect(changeColour(t, ChangeKind.added), t.color('activity-downloads'));
      expect(changeColour(t, ChangeKind.better), t.color('activity-sync'));
      expect(changeColour(t, ChangeKind.fixed), t.color('activity-images-2'));
      final distinct = {for (final kind in ChangeKind.values) changeColour(t, kind)}.length;
      expect(distinct, calm ? 1 : 3, reason: '$theme${calm ? ', Calm' : ''}');
      if (calm) expect(changeColour(t, ChangeKind.added), t.color('app-ink'));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  look('with less motion asked for, it is up at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, home: WhatsNewCard(version: '2.3.88', releases: const [_r88], onClose: () {}));
    await tester.pump();
    final fades = tester.widgetList<Opacity>(find.ancestor(of: find.byKey(const ValueKey('sheet-panel')), matching: find.byType(Opacity)));
    expect(fades, isNotEmpty);
    expect(fades.every((fade) => fade.opacity == 1), isTrue);
  });

  look('the Changelog page: every release, newest first, its lines and the one running', (tester) async {
    await pumpApp(tester, size: const Size(390, 2400), home: const SingleChildScrollView(child: ChangelogPane(changelog: Changelog([_r88, _r87, _r86]), running: '2.3.87')));
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final titles = ['2.3.88 · MEETINGS IN TURNS', '2.3.87', '2.3.86 · UPDATES IN ACTIVITY'];
    final tops = [for (final title in titles) tester.getTopLeft(find.text(title)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.text("30 Oct 2026 · you're on this one"), findsOneWidget);
    for (final release in [_r88, _r87, _r86]) {
      for (final item in release.items) {
        expect(find.text(item.words), findsOneWidget);
      }
    }
  });
}
