// Note decay alerts in the editor (lib/plugins/note_decay/marks.dart, sheets.dart, decay_list.dart; docs/NOTE_DECAY.md
// §2; Matt, 2026-11-02: "a quiet 'may be out of date' mark with the reason"): the mark on the line and at the page's
// head, never in the note's words; its reason a tap away; Still right written into the page's front matter as one
// change; Update with AI's edits shown as a diff that changes nothing until accepted; and the list of pages. Pictures
// in build/feature-shots/note-decay/ with --update-goldens. The model is a fake's.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/note_decay/ai.dart';
import 'package:ghost_md/plugins/note_decay/decay.dart';
import 'package:ghost_md/plugins/note_decay/decay_list.dart';
import 'package:ghost_md/plugins/note_decay/marks.dart';
import 'package:ghost_md/plugins/note_decay/sheets.dart';
import 'package:glacier/glacier.dart';

import '../../support/feature_shot.dart';
import '../../support/render.dart';

const String folder = 'note-decay';

class FakeModel implements DecayModel {
  FakeModel(this.answer);
  final String answer;
  int asked = 0;
  @override
  bool get ready => true;
  @override
  String get name => 'Claude';
  @override
  bool get onDevice => false;
  @override
  Future<String> ask({required String system, required String prompt}) async {
    asked += 1;
    return answer;
  }
}

final DateTime now = DateTime(2026, 11, 2, 10);

Note note(String id, String body, {DateTime? edited}) {
  final at = (edited ?? DateTime(2026, 10, 20)).millisecondsSinceEpoch;
  return Note(id: id, body: body, createdAt: at, updatedAt: at);
}

const String launch = '# Billing launch\n\nThe plan for moving every account to the new billing.\n\n- Billing ships on Nov 1.\n- Waits on [[GHO-12]] for the invoices.\n- Search stays as it is.';
const String gho12 = '---\ntype: ticket\nid: GHO-12\nstatus: Done\ndone: 2026-10-30\n---\n# Invoices in the new billing\n';

class Stage {
  Stage(List<Note> notes, {String answer = '{"edits": []}'}) : model = FakeModel(answer) {
    this.notes.value = notes;
    decay = NoteDecay(notes: () => this.notes.value, changes: this.notes, model: () => model, clock: () => now);
  }

  final ValueNotifier<List<Note>> notes = ValueNotifier(const []);
  final FakeModel model;
  late final NoteDecay decay;
  late final EditorView view;

  String get doc => view.state.doc.toString();

  Future<void> show(WidgetTester tester, {String id = 'a', String theme = 'light', Widget? below}) async {
    view = EditorView(
      wholeDocument: true,
      state: EditorState.create(
        doc: notes.value.firstWhere((n) => n.id == id).body,
        extensions: noteExtensions(
          more: <Extension>[
            history(),
            noteDecayMarks(DecayMarkHooks(
              signals: (body) => decay.signalsFor(id, body: body),
              press: (signals, view, context) => openDecay(context, decay: decay, noteId: id, signals: signals, view: view),
              changes: decay,
            )),
          ],
        ),
      ),
    );
    addTearDown(view.destroy);
    addTearDown(decay.dispose);
    await pumpApp(
      tester,
      size: const Size(390, 700),
      ratio: 3,
      prefs: AppPreferences(theme: theme),
      home: Builder(
        builder: (context) => BackScope(
          child: ColoredBox(
            color: context.tokens.color('app-paper'),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 390, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [EditorColumn(view: view), ?below])),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get chips => find.byType(DecayChip);

Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    testWidgets('a line that may be out of date is marked, its reason a tap away ($theme)', (tester) async {
      final stage = Stage([note('a', launch), note('t', gho12)]);
      await stage.show(tester, theme: theme);
      // Two lines marked: the date and the ticket; the note's words are as written.
      expect(chips, findsNWidgets(2));
      expect(stage.doc, launch);
      expect(find.bySemanticsLabel('May be out of date: Nov 1 has passed; this still speaks of it as ahead'), findsOneWidget);
      expect(find.bySemanticsLabel('May be out of date: GHO-12 was closed on Oct 30'), findsOneWidget);
      await featureShot(tester, folder, 'marks-$theme');
      await tester.tap(chips.at(1));
      await settle(tester);
      expect(find.byKey(const ValueKey('decay-reason')), findsOneWidget);
      expect(find.text('GHO-12 was closed on Oct 30'), findsOneWidget);
      await featureShot(tester, folder, 'reason-$theme');
      await away(tester);
    });
  }

  testWidgets('Still right is written into the page’s front matter as one change, and the mark goes', (tester) async {
    final stage = Stage([note('a', launch), note('t', gho12)]);
    await stage.show(tester);
    await tester.tap(chips.at(1));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('decay-still-right')));
    await settle(tester);
    expect(stage.doc, '---\ndecay-ok: [ticket:GHO-12@Done 2026-10-30]\n---\n$launch');
    expect(find.bySemanticsLabel('May be out of date: GHO-12 was closed on Oct 30'), findsNothing);
    expect(chips, findsOneWidget);
    // The editor's Undo takes it back whole.
    expect(undo(stage.view), isTrue);
    expect(stage.doc, launch);
    await away(tester);
  });

  testWidgets('Update with AI shows the edit as a diff, and changes nothing until it is accepted', (tester) async {
    final stage = Stage([note('a', launch), note('t', gho12)], answer: '{"edits": [{"quote": "Billing ships on Nov 1.", "replacement": "Billing shipped on Nov 1.", "why": "Nov 1 has passed and GHO-12 is done."}]}');
    await stage.show(tester);
    await tester.tap(chips.first);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('decay-update')));
    await settle(tester);
    expect(find.byKey(const ValueKey('decay-diff')), findsOneWidget);
    expect(find.text('- Billing ships on Nov 1.'), findsOneWidget);
    expect(find.text('- Billing shipped on Nov 1.'), findsOneWidget);
    // Shown, not applied.
    expect(stage.doc, launch);
    await featureShot(tester, folder, 'update-with-ai');
    await tester.tap(find.byKey(const ValueKey('decay-accept')));
    await settle(tester);
    expect(stage.doc, launch.replaceFirst('Billing ships on', 'Billing shipped on'));
    expect(stage.model.asked, 1);
    await away(tester);
  });

  testWidgets('Reject leaves the page as it was, and an edit unchosen is not made', (tester) async {
    final stage = Stage([note('a', launch), note('t', gho12)], answer: '{"edits": [{"quote": "- Billing ships on Nov 1.", "replacement": "- Billing shipped on Nov 1."}]}');
    await stage.show(tester);
    await tester.tap(chips.first);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('decay-update')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('decay-reject')));
    await settle(tester);
    expect(stage.doc, launch);
    await tester.tap(chips.first);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('decay-update')));
    await settle(tester);
    // Unchosen, Accept has nothing to make.
    await tester.tap(find.byKey(const ValueKey('decay-edit-4')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('decay-accept')));
    await settle(tester);
    expect(find.byKey(const ValueKey('decay-diff')), findsOneWidget);
    expect(stage.doc, launch);
    await away(tester);
  });

  testWidgets('a docs page left while its links changed is marked at its head, under its front matter', (tester) async {
    const index = '---\nbook: true\ntype: docs\n---\n# Handbook\n\n## Billing\n\n1. [[Billing overview]]\n2. [[Pricing]]';
    const overview = '---\nicon: book\n---\n# Billing overview\n\nHow billing works, and what [[Pricing]] each plan has.';
    final stage = Stage([note('i', index), note('a', overview, edited: DateTime(2026, 6, 2)), note('p', '# Pricing\nNew prices.', edited: DateTime(2026, 10, 12))]);
    await stage.show(
      tester,
      below: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0), child: DecayPagesSection(decay: stage.decay, where: (_) => true, onOpen: (_) {})),
    );
    expect(chips, findsOneWidget);
    expect(find.bySemanticsLabel('May be out of date: Not edited since Jun 2, and [[Pricing]] changed since'), findsOneWidget);
    // The list under the page names it with its reason.
    expect(find.byKey(DecayPagesSection.rowKey('a')), findsOneWidget);
    expect(find.text('Pages that may be out of date'), findsOneWidget);
    await featureShot(tester, folder, 'page-head-and-list');
    await away(tester);
  });

  testWidgets('the list draws nothing where no page is marked, unless told what to say', (tester) async {
    final stage = Stage([note('a', '# Fine\nAll good.')]);
    await stage.show(tester, below: Column(children: [DecayPagesSection(decay: stage.decay, where: (_) => true, onOpen: null), DecayPagesSection(decay: stage.decay, where: (_) => true, onOpen: null, emptyWords: 'Nothing looks out of date.')]));
    expect(find.byKey(DecayPagesSection.listKey), findsOneWidget);
    expect(find.text('Nothing looks out of date.'), findsOneWidget);
    expect(chips, findsNothing);
    await away(tester);
  });
}
