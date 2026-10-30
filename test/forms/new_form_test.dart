// New form… in a notebook's index (lib/book/book_view.dart, docs/FORMS.md): offered where the note screen offers it,
// it asks for the form's title, puts it in the index as a page is, and makes it from a form's first words, whose fence
// files into this notebook once the page's template is filled (lib/book/entry_starts.dart `pageBody`). The web's
// index, which the reference pictures are of, has none.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/book/entry_starts.dart' show pageBody;
import 'package:ghost_md/core/book.dart' show chaptersOf;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/forms/form_def.dart';

import '../book_ui/support.dart';

const String book = '---\nbook: true\nkey: BUG\n---\n# Bug reports\n\n1. [[Crash on launch]]\n';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));

  Future<void> show(WidgetTester tester, {required bool offers, required ValueChanged<String> onChange, required void Function(String, String) openNew}) => pumpView(
        tester,
        BookView(body: book, title: 'Bug reports', known: (_) => true, open: (_) {}, titles: () => const [], onChange: onChange, openNew: openNew, offersForms: offers, clock: () => DateTime(2026, 10, 30, 9)),
      );

  testWidgets('makes a form that files into this notebook, in its index as a page', (tester) async {
    String? changed;
    final made = <(String, String)>[];
    await show(tester, offers: true, onChange: (body) => changed = body, openNew: (title, words) => made.add((title, words)));
    await press(tester, 'New form…');
    await tester.enterText(find.byKey(const ValueKey('book-form-title')), 'Report a bug');
    await tester.pump();
    await press(tester, 'Add and open');
    expect(chaptersOf(changed!).map((c) => c.title), ['Crash on launch', 'Report a bug']);
    expect(made, [('Report a bug', newFormWords())]);
    // As the note screen makes the page: the fence names this notebook.
    final body = pageBody('Report a bug', made.single.$2, 'Bug reports', DateTime(2026, 10, 30, 9));
    expect(body, startsWith('# Report a bug\n\n'));
    final def = formOf(body)!;
    expect(def.to, 'Bug reports');
    expect(def.fields.map((f) => f.label), ['Summary', 'Details', 'Your email']);
    await away(tester);
  });

  testWidgets('is not offered where the index offers no forms', (tester) async {
    await show(tester, offers: false, onChange: (_) {}, openNew: (_, _) {});
    expect(button('New form…'), findsNothing);
    expect(button('Add a page'), findsOneWidget);
    await away(tester);
  });
}
