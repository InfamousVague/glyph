// The at sign's picker as it is drawn (lib/mentions/ui/mention_picker.dart; Matt, 2026-10-30: "add all 12"): the team's
// members in the colours they wear, you among them, then the days, the one Enter takes lit; a tap writes the one
// pressed. On a phone and a desktop, light and dark, with pictures into build/feature-shots/mentions-verified/.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/mentions.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/mentions/ui/mention_picker.dart';
import 'package:glacier/glacier.dart';

import '../sidebar/support.dart' show away, pumpPage;
import '../support/feature_shot.dart';
import '../support/render.dart';

final DateTime friday = DateTime(2026, 10, 30, 10);

void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    for (final (size, where) in [(const Size(390, 844), 'phone'), (const Size(1280, 800), 'desktop')]) {
      testWidgets('the team, you and the days, and a tap writes the one pressed; $where, $theme', (tester) async {
        final picker = MentionPicker(people: () => const [(handle: 'sam', hue: 'sea'), (handle: 'ana', hue: 'rose'), (handle: 'kevin', hue: 'amber')], me: () => 'matt', today: () => friday);
        final view = EditorView(wholeDocument: true, state: EditorState.create(doc: 'Ask @', selection: EditorSelection.single(5), extensions: noteExtensions(more: <Extension>[mentions(MentionHooks(picking: picker, today: () => friday))])));
        addTearDown(view.destroy);
        picker.asked(view, const MentionAsk(4, ''));
        await pumpPage(
          tester,
          Builder(
            builder: (context) => ColoredBox(
              color: context.tokens.color('app-paper'),
              child: Align(alignment: const Alignment(-0.6, -0.7), child: SizedBox(width: 260, child: ListenableBuilder(listenable: picker, builder: (context, _) => MentionList(picker: picker)))),
            ),
          ),
          size: size,
          theme: theme,
        );
        await tester.pump(const Duration(milliseconds: 200));
        for (final key in ['mention-person-matt', 'mention-person-sam', 'mention-person-ana', 'mention-person-kevin', 'mention-day-2026-10-30', 'mention-day-2026-10-31']) {
          expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
        }
        expect(find.text('you'), findsOneWidget);
        await featureShot(tester, 'mentions-verified', 'picker-$where-$theme');
        await tester.tap(find.byKey(const ValueKey('mention-person-sam')));
        await tester.pump();
        expect(view.state.doc.toString(), 'Ask @sam ');
        await away(tester);
      });

      testWidgets('a day picked in a team’s note is signed with you, unless the person it is for is named before it; $where, $theme', (tester) async {
        final picker = MentionPicker(people: () => const [(handle: 'sam', hue: 'sea')], me: () => 'matt', today: () => friday, owner: () => 'matt');
        final view = EditorView(wholeDocument: true, state: EditorState.create(doc: 'Done by @', selection: EditorSelection.single(9), extensions: noteExtensions(more: <Extension>[mentions(MentionHooks(picking: picker, today: () => friday, owner: () => 'matt'))])));
        addTearDown(view.destroy);
        picker.asked(view, const MentionAsk(8, ''));
        await pumpPage(tester, ListenableBuilder(listenable: picker, builder: (context, _) => MentionList(picker: picker)), size: size, theme: theme);
        await tester.tap(find.byKey(const ValueKey('mention-day-2026-10-31')));
        await tester.pump();
        expect(view.state.doc.toString(), 'Done by @matt @2026-10-31 ');
        // Sam's day: Sam named right before it.
        final sams = MentionPicker(people: () => const [(handle: 'sam', hue: 'sea')], me: () => 'matt', today: () => friday, owner: () => 'matt');
        final other = EditorView(wholeDocument: true, state: EditorState.create(doc: 'Ask @sam @', selection: EditorSelection.single(10), extensions: noteExtensions(more: <Extension>[mentions(MentionHooks(picking: sams, today: () => friday, owner: () => 'matt'))])));
        addTearDown(other.destroy);
        sams.asked(other, const MentionAsk(9, ''));
        sams.pick(sams.choices.firstWhere((choice) => choice.value == '2026-10-31'));
        expect(other.state.doc.toString(), 'Ask @sam @2026-10-31 ');
        await away(tester);
      });
    }
  }
}
