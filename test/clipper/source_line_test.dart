// A clip's `source:` under its title (lib/editor/media/source_line.dart): which notes have the line, what it says,
// that a tap opens the page, and that it follows the words as they change.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/source_line.dart';

import '../editor/media/support.dart';

const _clip = '---\nsource: https://field.example/2026/10/the-quiet-garden\nclipped: 2026-10-16\ntags: [reading]\n---\n# The Quiet Garden\n\nMost of the work happens underground.\n';

void main() {
  test('a note’s source is an http or https address in its front matter, and nothing else', () {
    expect(sourceOf(_clip), 'https://field.example/2026/10/the-quiet-garden');
    expect(sourceOf('---\nsource: "https://x.example/a b"\n---\n# A'), isNull);
    expect(sourceOf('---\nsource: the radio, Tuesday\n---\n# A'), isNull);
    expect(sourceOf('---\nsource: javascript:alert(1)\n---\n# A'), isNull);
    expect(sourceOf('# No front matter\n\nsource: https://x.example/\n'), isNull);
  });

  testWidgets('a clip says where it came from under its title, shortened, and a tap opens the page', (tester) async {
    final opened = <String>[];
    final view = await pumpNote(tester, _clip, theme: 'dark', more: [sourceLine(open: (url) async => opened.add(url))]);
    expect(find.text('From field.example/202…den', findRichText: true), findsOneWidget);
    await tester.tap(find.text('From field.example/202…den', findRichText: true));
    expect(opened, ['https://field.example/2026/10/the-quiet-garden']);
    // The words changed under it: a new source is read, and none takes the line away.
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: _clip.indexOf('field.example'), to: _clip.indexOf('field.example') + 'field.example'.length, insert: 'docs.example')));
    await tester.pump();
    expect(find.text('From docs.example/202…den', findRichText: true), findsOneWidget);
    final from = view.state.doc.toString().indexOf('source:');
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: from, to: view.state.doc.line(2).to, insert: 'source: a friend')));
    await tester.pump();
    expect(find.textContaining('From ', findRichText: true), findsNothing);
  });

  testWidgets('a note without a source has no line', (tester) async {
    await pumpNote(tester, '# A plain note\n\nWords.\n', theme: 'dark', more: [sourceLine()]);
    expect(find.textContaining('From ', findRichText: true), findsNothing);
  });
}
