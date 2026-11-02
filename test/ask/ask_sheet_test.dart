// The Ask sheet (docs/ASK_THE_ORG.md, "The sheet"; Matt, 2026-11-02: "'Ask the org' with receipts: questions answered
// only from your notes, every claim linked to the note and line it came from; when notes disagree, it shows both
// instead of guessing"): the answer with its numbered chips, the two standups side by side with the newer first, a
// chip opening its note at its lines, "Your notes don't say", the scopes, who answers, Save as note, and simple
// mode's More. With pictures, on a phone and a desktop, light and dark, into build/feature-shots/ask/ under
// --update-goldens.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ask/ask.dart';
import 'package:ghost_md/ask/ask_model.dart';
import 'package:ghost_md/ask/ask_scope.dart';
import 'package:ghost_md/ask/ask_sheet.dart';

import '../sidebar/support.dart';
import '../support/feature_shot.dart';
import '../support/render.dart';
import 'support.dart';

/// A test of the sheet, the screen taken down after it (and the shadows' switch given back, [away]).
void testAsk(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await away(tester);
    });

void main() {
  setUpAll(loadAppFonts);

  Future<({List<String> said, List<AskScope> asked})> show(
    WidgetTester tester, {
    AskModel? model,
    String? question = 'When do we launch? Who owns the release notes?',
    AskScope scope = helloScope,
    bool simple = false,
    Size size = const Size(390, 844),
    String theme = 'light',
    bool noModel = false,
  }) async {
    final said = <String>[];
    final asked = <AskScope>[];
    final answering = model ?? ScriptedModel(launchAnswer);
    await pumpPage(
      tester,
      PageUnder(
        children: [
          AskSheet(
            scope: scope,
            scopes: askScopes(const [(id: 'o1', name: 'HelloTrade'), (id: 'o2', name: 'Other')]),
            folders: askFolders(workspaces.list),
            notesOf: (s) {
              asked.add(s);
              return notesInScope(library, s, world);
            },
            model: () => noModel ? null : answering,
            onOpen: (id, at) => said.add('open $id $at'),
            onClose: () => said.add('close'),
            onSave: (AskResult result) async {
              said.add('save ${result.question}');
              return 'Ask: ${result.question}';
            },
            simple: simple,
            question: question,
            now: () => nov2,
          ),
        ],
      ),
      size: size,
      theme: theme,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    return (said: said, asked: asked);
  }

  testAsk('the answer has a chip for each receipt, and the standups that disagree side by side, newest first', (tester) async {
    await show(tester);
    expect(find.text('Ask HelloTrade'), findsWidgets);
    expect(find.textContaining('Ana owns the release notes.', findRichText: true), findsOneWidget);
    expect(find.byKey(AskSheet.chipKey(0, 1)), findsOneWidget);
    expect(find.text('Your notes disagree'.toUpperCase()), findsOneWidget);
    final newer = tester.getTopLeft(find.byKey(AskSheet.sideKey(0, 0)));
    final older = tester.getTopLeft(find.byKey(AskSheet.sideKey(0, 1)));
    expect(newer.dx, lessThan(older.dx), reason: 'newest first, on the left');
    expect(find.descendant(of: find.byKey(AskSheet.sideKey(0, 0)), matching: find.textContaining('[[Standup Oct 29]]', findRichText: true)), findsOneWidget);
    expect(find.descendant(of: find.byKey(AskSheet.sideKey(0, 1)), matching: find.textContaining('Thursday', findRichText: true)), findsOneWidget);
    expect(find.byKey(AskSheet.receiptKey(3)), findsOneWidget);
    expect(find.textContaining('Answered by Claude, from HelloTrade’s notes.'), findsOneWidget);
  });

  testAsk('a chip opens its note at its lines, and so does a receipt', (tester) async {
    final (:said, asked: _) = await show(tester);
    await tester.tap(find.byKey(AskSheet.chipKey(0, 1)));
    expect(said, ['open s27 lines:8-8']);
    await tester.ensureVisible(find.byKey(AskSheet.receiptKey(2)));
    await tester.pump();
    await tester.tap(find.byKey(AskSheet.receiptKey(2)));
    expect(said.last, 'open s29 lines:4-4');
  });

  testAsk('a quote the note does not hold is not drawn as an answer', (tester) async {
    final model = ScriptedModel('{"sentences": [{"text": "The CEO signed off.", "citations": [{"noteId": "s27", "fromLine": 7, "toLine": 7, "quote": "the CEO signed off"}]}]}');
    await show(tester, model: model, question: 'Who signed off the launch?');
    expect(find.textContaining('The CEO signed off.', findRichText: true), findsNothing);
    expect(find.byKey(AskSheet.notFoundKey), findsOneWidget);
    expect(find.textContaining('One sentence was left out'), findsOneWidget);
  });

  testAsk('nothing in the notes says "your notes don’t say", and the model is never asked', (tester) async {
    final model = ScriptedModel(launchAnswer);
    await show(tester, model: model, question: 'What is the office wifi password?');
    expect(find.byKey(AskSheet.notFoundKey), findsOneWidget);
    expect(find.text('Your notes don’t say.'), findsOneWidget);
    expect(find.textContaining('Nothing in HelloTrade’s notes answers this'), findsOneWidget);
    expect(model.prompts, isEmpty);
  });

  testAsk('a scope chip asks another scope’s notes, and only them', (tester) async {
    final model = ScriptedModel('{"notFound": true}');
    final (said: _, :asked) = await show(tester, model: model, question: null);
    await tester.tap(find.byKey(AskSheet.scopeKey(const AskScope.mine())));
    await tester.pump();
    expect(find.text('Ask my notes'), findsWidgets);
    await tester.enterText(find.byKey(AskSheet.fieldKey), 'launch cake');
    await tester.tap(find.byKey(AskSheet.askKey));
    await tester.pump();
    await tester.pump();
    expect(asked.last, const AskScope.mine());
    expect(model.prompts.single, contains('Groceries'));
    expect(model.prompts.single, isNot(contains('Standup')));
  });

  testAsk('Save as note files it and says so', (tester) async {
    final (:said, asked: _) = await show(tester);
    await tester.ensureVisible(find.byKey(AskSheet.saveKey));
    await tester.pump();
    await tester.tap(find.byKey(AskSheet.saveKey));
    await tester.pump();
    await tester.pump();
    expect(said.last, 'save When do we launch? Who owns the release notes?');
    expect(find.textContaining('Saved as “Ask: When do we launch?'), findsOneWidget);
  });

  testAsk('on the device it says so, and that a small model may miss passages', (tester) async {
    await show(tester, model: ScriptedModel(launchAnswer, onDevice: true, name: 'Gemma 3 1B'));
    expect(find.textContaining('Answered on this device by Gemma 3 1B'), findsOneWidget);
    expect(find.textContaining('A small model may miss or misread passages.'), findsOneWidget);
  });

  testAsk('with no AI set up it says where to set one up, and Ask does nothing', (tester) async {
    await show(tester, noModel: true, question: null);
    expect(find.textContaining('Set up an AI in Settings › AI'), findsOneWidget);
  });

  testAsk('simple mode is the box and its answer: the scopes and the switch are behind More', (tester) async {
    await show(tester, simple: true, question: null);
    expect(find.byKey(AskSheet.scopeKey(const AskScope.mine())), findsNothing);
    expect(find.byKey(AskSheet.generalKey), findsNothing);
    await tester.tap(find.byKey(AskSheet.moreKey));
    await tester.pump();
    expect(find.byKey(AskSheet.scopeKey(const AskScope.mine())), findsOneWidget);
    expect(find.byKey(AskSheet.generalKey), findsOneWidget);
  });

  testAsk('general knowledge, once on, is marked as not from your notes', (tester) async {
    final model = ScriptedModel('{"sentences": [{"text": "App store reviews usually take a day or two.", "general": true, "citations": []}, {"text": "We planned Thursday.", "citations": [{"noteId": "s27", "fromLine": 7, "toLine": 7, "quote": "We ship on Thursday"}]}]}');
    await show(tester, model: model, question: null);
    await tester.tap(find.byKey(AskSheet.moreKey));
    await tester.pump();
    await tester.tap(find.byKey(AskSheet.generalKey));
    await tester.pump();
    await tester.enterText(find.byKey(AskSheet.fieldKey), 'How long is a store review for the launch?');
    await tester.tap(find.byKey(AskSheet.askKey));
    await tester.pump();
    await tester.pump();
    expect(model.systems.single, contains('"general": true'));
    expect(find.textContaining('General knowledge, not from your notes', findRichText: true), findsOneWidget);
  });

  group('pictures', () {
    for (final (where, size) in [('phone', const Size(390, 844)), ('desktop', const Size(1280, 860))]) {
      for (final theme in ['light', 'dark']) {
        testAsk('the answer, $where, $theme', (tester) async {
          await show(tester, size: size, theme: theme);
          await featureShot(tester, 'ask', 'answer-$where-$theme');
        });
      }
    }
    testAsk('not in your notes, phone', (tester) async {
      await show(tester, question: 'What is the office wifi password?');
      await featureShot(tester, 'ask', 'not-found-phone-light');
    });
    testAsk('simple mode, phone', (tester) async {
      await show(tester, simple: true, question: null);
      await featureShot(tester, 'ask', 'simple-phone-light');
    });
  });
}
