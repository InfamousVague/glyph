// The others' carets and selections as a team note's editor draws them (lib/live/editor_binding.dart), in a
// picture: a member in rose with a selection on one line, one in sea with a selection over three, and one in ink
// with a caret alone, each with their handle on it, on white and on black.
//
//   flutter test --no-pub --update-goldens test/live/caret_picture_test.dart     # writes test/shots/live_carets_*.png
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/live/editor_binding.dart';

import '../support/render.dart';

const String _note = '# Roadmap\n\nThe first thing is the relay, which carries what each of us types.\n\n- [ ] carets in their colours\n- [ ] presence on the dashboard\n- [x] the wire\n\nAnd a last line that sam is on.';

void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    testWidgets('the others\' carets on $theme paper', (tester) async {
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: _note, extensions: noteExtensions(more: <Extension>[liveBindingSlot()])));
      addTearDown(view.destroy);
      await pumpApp(tester, prefs: AppPreferences(theme: theme), home: Padding(padding: const EdgeInsets.only(top: 60), child: EditorColumn(view: view)));
      final relay = _note.indexOf('relay'), carets = _note.indexOf('carets'), wire = _note.indexOf('the wire') + 8, last = _note.indexOf('sam');
      view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[
        liveSlot.reconfigure(remoteCarets),
      ]));
      view.dispatch(TransactionSpec(effects: setRemoteCarets.of(<RemoteCaret>[
        RemoteCaret(client: 1, name: 'matt', hue: 'rose', anchor: relay, head: relay + 5),
        RemoteCaret(client: 2, name: 'ada', hue: 'sea', anchor: wire, head: carets),
        RemoteCaret(client: 3, name: 'sam', hue: null, anchor: last, head: last),
        RemoteCaret(client: 4, name: 'lee', hue: 'moss', anchor: 5, head: 5),
      ])));
      await tester.pump();
      expect(remoteCaretsOf(view.state), hasLength(4));
      // Ada's selection is over three lines: the first from where it starts, the last to where it ends, and the
      // line between washed whole, as a line's own ground (y-codemirror's `cm-yLineSelection`).
      final washed = <String>[];
      for (final set in view.decorations) {
        set.between(0, view.state.doc.length, (from, to, value) {
          final name = value.spec.className ?? '';
          if (name.contains('cm-yHue-sea')) washed.add('${name.split(' ').first} ${view.state.sliceDoc(from, to)}');
          return null;
        });
      }
      expect(washed, ['cm-ySelection carets in their colours', 'cm-yLineSelection ', 'cm-ySelection - [x] the wire']);
      final between = tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).firstWhere((line) => view.state.doc.lineAt(line.from).text == '- [ ] presence on the dashboard');
      expect(between.spec.look.background, isNotNull);
      expect((between.spec.look.marginStart, between.spec.look.marginEnd), (4, 2));
      expect(find.bySemanticsLabel('matt is here'), findsOneWidget);
      await shot(tester, 'live_carets_$theme');
    });
  }
}
