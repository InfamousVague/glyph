// A verified page's badge and Verify… (lib/verified/verified_badge.dart; Matt, 2026-10-30: "add all 12"): green,
// amber within a week, grey "Needs review" after, "edited since verified" beside it; the page picks an owner and a
// period and writes them; and the More sheet's row, behind More… in simple mode. On a phone and a desktop, light and
// dark, with pictures into build/feature-shots/mentions-verified/ under --update-goldens.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/note/note_settings.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:ghost_md/verified/verified.dart';
import 'package:ghost_md/verified/verified_badge.dart';
import 'package:glacier/glacier.dart';

import '../support/feature_shot.dart';
import '../sidebar/support.dart' show pumpPage;
import '../support/render.dart';

final DateTime friday = DateTime(2026, 10, 30, 10);

Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

class _Paper extends StatelessWidget {
  const _Paper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(color: context.tokens.color('app-paper'), child: SizedBox.expand(child: child));
}

void main() {
  setUpAll(loadAppFonts);

  Color inkOf(WidgetTester tester, String words) {
    Color? found;
    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      text.text.visitChildren((span) {
        if (found == null && span is TextSpan && (span.text ?? '').startsWith(words)) found = span.style?.color;
        return found == null;
      });
      if (found != null) break;
    }
    return found!;
  }

  for (final theme in ['light', 'dark']) {
    for (final (size, where) in [(const Size(390, 844), 'phone'), (const Size(1280, 800), 'desktop')]) {
      testWidgets('the badge green, amber within a week, grey after, edited since; $where, $theme', (tester) async {
        await pumpPage(
          tester,
          _Paper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                VerifiedBadge(verified: const Verified(by: 'matt', until: '2026-12-01'), edited: false, today: friday),
                VerifiedBadge(verified: const Verified(by: 'sam', until: '2026-11-04'), edited: false, today: friday),
                VerifiedBadge(verified: const Verified(by: 'matt', until: '2026-10-20'), edited: false, today: friday),
                VerifiedBadge(verified: const Verified(by: 'matt', until: '2026-12-01', words: 'old'), edited: true, today: friday),
              ],
            ),
          ),
          size: size,
          theme: theme,
        );
        final t = tester.element(find.byType(_Paper)).tokens;
        expect(inkOf(tester, 'Verified by Matt · until Dec 1'), t.color('glacier-green-11'));
        expect(inkOf(tester, 'Verified by Sam · until Nov 4'), t.color('glacier-amber-11'));
        expect(inkOf(tester, 'Needs review'), t.color('app-ink-3'));
        expect(find.bySemanticsLabel('Verified by Matt · until Dec 1, edited since verified'), findsOneWidget);
        await featureShot(tester, 'mentions-verified', 'badges-$where-$theme');
        await away(tester);
      });

      testWidgets('Verify… picks an owner and a period, and writes them; $where, $theme', (tester) async {
        final said = <String>[];
        await pumpPage(
          tester,
          _Paper(
            child: Sheet(
              label: 'Verify',
              onClose: () => said.add('close'),
              children: [
                VerifyPage(
                  owners: const ['matt', 'sam', 'ana'],
                  me: 'matt',
                  verified: null,
                  edited: false,
                  today: friday,
                  onVerify: (by, days) => said.add('verify $by $days'),
                  onRemove: () => said.add('remove'),
                  close: () => said.add('close'),
                ),
              ],
            ),
          ),
          size: size,
          theme: theme,
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Matt (you)'), findsOneWidget);
        expect(find.text('Until Jan 28, 2027'), findsOneWidget, reason: '90 days, the one chosen at first');
        await featureShot(tester, 'mentions-verified', 'verify-page-$where-$theme');
        await tester.tap(find.byKey(const ValueKey('verify-owner-sam')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('verify-days-30')));
        await tester.pump();
        expect(find.text('By Sam, until Nov 29.'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('verify-now')));
        await tester.pump();
        expect(said, ['verify sam 30', 'close']);
        expect(find.byKey(const ValueKey('verify-remove')), findsNothing, reason: 'nothing to take off yet');
        await away(tester);
      });
    }
  }

  testWidgets('a page verified already: Verify again, and Take it off', (tester) async {
    final said = <String>[];
    await pumpPage(
      tester,
      _Paper(
        child: Sheet(
          label: 'Verify',
          onClose: () {},
          children: [
            VerifyPage(
              owners: const ['sam'],
              me: 'matt',
              verified: const Verified(by: 'sam', until: '2026-11-04', words: 'x'),
              edited: true,
              today: friday,
              onVerify: (by, days) => said.add('verify $by $days'),
              onRemove: () => said.add('remove'),
              close: () => said.add('close'),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Verified by Sam · until Nov 4 · edited since verified'), findsOneWidget);
    expect(find.text('Verify again'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('verify-remove')));
    await tester.pump();
    expect(said, ['remove', 'close']);
    await away(tester);
  });

  for (final simple in [false, true]) {
    testWidgets('the More sheet’s Verify… row, ${simple ? 'behind More… in simple mode' : 'in advanced'}', (tester) async {
      await pumpPage(
        tester,
        _Paper(
          child: NoteSettings(
            noteId: 'n1',
            title: 'Launch plan',
            pinned: false,
            workspaces: WorkspaceStore(),
            onClose: () {},
            onPin: () {},
            onArchive: () {},
            onDelete: () {},
            simple: simple,
            verify: NoteSheetItem(
              id: 'verify',
              icon: Lucide.shieldCheck,
              label: 'Verify…',
              hint: verifyHint(null, false, friday),
              page: (context, close) => [const Text('the verify page')],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      if (simple) {
        expect(find.text('Verify…'), findsNothing);
        await tester.tap(find.text('More…'));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.ensureVisible(find.text('Verify…'));
      await tester.pump();
      expect(find.text('Mark it as the team’s current truth, for a while.'), findsOneWidget);
      await tester.tap(find.text('Verify…'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('the verify page'), findsOneWidget);
      await away(tester);
    });
  }
}
