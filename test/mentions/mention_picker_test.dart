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
    }
  }
}
