// The pictures of templates by place, sub-tickets and blockers, and buttons in a note (Matt, 2026-10-30, of a list of
// plain-Markdown features: "add all 12"), into build/feature-shots/notes-native-2/: a parent ticket's panel with its
// bar and a blocked one's lock, a note with its buttons, the button builder, the template picker, the question a post
// asks and a board's cards with their marks; on a phone and on a Mac's width, light and dark. Written only with
// FEATURE_SHOTS=1 or --update-goldens.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/book/ticket_links.dart' show TicketProgress;
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/buttons/button_builder.dart';
import 'package:ghost_md/editor/buttons/buttons.dart';
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/tickets/tickets.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/notes/note_templates.dart';
import 'package:ghost_md/notes/template_choice.dart';
import 'package:ghost_md/sheet/ask_first.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'queries/support.dart' show pumpQueries;

const String folder = 'build/feature-shots/notes-native-2';

bool get _shots => autoUpdateGoldenFiles || Platform.environment.containsKey('FEATURE_SHOTS');

Future<void> snap(WidgetTester tester, String name) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  var target = tester.renderObject(find.byType(GhostApp));
  while (!target.isRepaintBoundary) {
    target = target.parent!;
  }
  final boundary = target;
  final bytes = await tester.runAsync(() async {
    final layer = boundary.debugLayer! as OffsetLayer;
    final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('$folder/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

Future<void> end(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

const TicketChoice cookie = TicketChoice(key: 'KLN-9', title: 'Fix the session cookie', status: 'In review', category: StatusCategory.doing);
const TicketChoice login = TicketChoice(key: 'KLN-13', title: 'Fix the login loop', status: 'Done', category: StatusCategory.done);
const TicketChoice docs = TicketChoice(key: 'KLN-14', title: 'Write the docs', status: 'In progress', category: StatusCategory.doing);
const TicketChoice changelog = TicketChoice(key: 'KLN-15', title: 'Write the changelog', status: 'To do', category: StatusCategory.todo);

Widget page(Widget child, double width) => Builder(
  builder: (context) => BackScope(
    child: ColoredBox(
      color: context.tokens.color('glacier-bg'),
      child: Align(alignment: Alignment.topCenter, child: SizedBox(width: width, child: SingleChildScrollView(padding: const EdgeInsets.only(top: 60), child: child))),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  for (final shade in ['light', 'dark']) {
    for (final (where, size) in [('phone', const Size(390, 844)), ('mac', const Size(1280, 800))]) {
      final width = where == 'phone' ? 390.0 : 720.0;

      testWidgets('a parent ticket’s panel, its bar, its sub-tickets and its lock, $where, $shade', (tester) async {
        if (!_shots) return;
        final options = TicketOptions(
          statuses: () => defaultStatuses,
          people: () => const ['Sam'],
          choices: () => const [cookie, login, docs, changelog],
          find: (target) => const [cookie, login, docs, changelog].where((choice) => choice.key == target.toUpperCase()).firstOrNull,
          open: (_) {},
          subTickets: () => const [login, docs, changelog],
          addSubTicket: (_) {},
        );
        await pumpApp(
          tester,
          size: size,
          prefs: AppPreferences(theme: shade),
          home: page(
            Builder(
              builder: (context) => TicketPanel(
                look: QueryLook.of(context, null),
                front: '---\ntype: ticket\nid: KLN-12\nstatus: In progress\nassignee: Sam\npriority: high\ndue: 2026-11-03\nblocked-by: "[[KLN-9]]"\n---',
                options: options,
                editable: true,
                today: '2026-10-30',
                locale: 'en-GB',
                write: (_, _) {},
                openLines: () {},
              ),
            ),
            width,
          ),
        );
        await snap(tester, 'ticket-panel-$where-$shade');
        await end(tester);
      });

      testWidgets('a note with its buttons, $where, $shade', (tester) async {
        if (!_shots) return;
        final view = EditorView(
          wholeDocument: true,
          state: EditorState.create(
            doc: '# Launch checklist\n\nWhen the beta is out:\n\n- [Move to done](ghost:set?status=Done) [Assign to Sam](ghost:set?assignee=Sam)\n- [Tell the team](ghost:post?to=slack&channel=launch&text=The%20beta%20is%20out)\n- [Tidy with Claude](ghost:claude?rule=Tidy%20my%20notes)\n- [Open the roadmap](ghost:open?note=Roadmap) [Log a bug](ghost:new?template=Bug%20report&in=Kiln)\n',
            extensions: noteExtensions(more: <Extension>[noteButtons(ButtonHooks(noteId: () => 'n1', title: () => 'Launch checklist'))]),
          ),
        );
        addTearDown(view.destroy);
        await pumpApp(tester, size: size, prefs: AppPreferences(theme: shade), home: page(EditorColumn(view: view), width));
        await snap(tester, 'buttons-$where-$shade');
        await end(tester);
      });
    }

    testWidgets('the button builder and the question a post asks, phone, $shade', (tester) async {
      if (!_shots) return;
      await pumpApp(tester, prefs: AppPreferences(theme: shade), home: BackScope(child: ButtonBuilderSheet(onDone: (_) {})));
      await snap(tester, 'button-builder-kinds-phone-$shade');
      await tester.tap(find.byKey(const ValueKey('button-kind:slack')));
      await tester.pump();
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('button-field:Channel')), matching: find.byType(EditableText)), 'launch');
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('button-field:Words')), matching: find.byType(EditableText)), 'The beta is out');
      await tester.pump();
      await snap(tester, 'button-builder-post-phone-$shade');
      await end(tester);
      await pumpApp(tester, prefs: AppPreferences(theme: shade), home: BackScope(child: FirstAskSheet(ask: const FirstAsk(title: 'Post to Slack?', note: '“The beta is out” goes to launch.', yes: 'Post'), onAnswer: (_) {})));
      await snap(tester, 'ask-first-post-phone-$shade');
      await end(tester);
    });

    testWidgets('the template picker, phone, $shade', (tester) async {
      if (!_shots) return;
      await pumpApp(tester, prefs: AppPreferences(theme: shade), home: BackScope(child: TemplateChoiceSheet(title: 'Template for Kiln', note: 'Every new note made in Kiln starts from it.', templates: builtIns, none: true, chosen: builtIns[6], onChoose: (_) {})));
      await snap(tester, 'template-choice-phone-$shade');
      await end(tester);
    });

    testWidgets('a board’s cards with their lock and their progress, mac, $shade', (tester) async {
      if (!_shots) return;
      const notes = [
        QueryNote(id: 'a', body: '---\ntype: ticket\nid: KLN-12\nstatus: In progress\n---\n# Ship the beta\n', createdAt: 0, updatedAt: 0),
        QueryNote(id: 'b', body: '---\ntype: ticket\nid: KLN-16\nstatus: To do\nblocked-by: "[[KLN-12]]"\n---\n# Announce the beta\n', createdAt: 0, updatedAt: 0),
        QueryNote(id: 'c', body: '---\ntype: ticket\nid: KLN-13\nstatus: Done\nparent: "[[KLN-12]]"\n---\n# Fix the login loop\n', createdAt: 0, updatedAt: 0),
      ];
      final options = QueryOptions(
        notes: () => notes,
        noteId: 'here',
        open: (_, _) {},
        write: (_, _) {},
        ticketMarks: (id) => switch (id) {
          'a' => (blockers: const <String>[], progress: const TicketProgress(done: 1, total: 3)),
          'b' => (blockers: const ['KLN-12'], progress: null),
          _ => null,
        },
      );
      await pumpQueries(tester, '# Kiln\n\n```query\nfrom: tickets\nshow: board\n```\n', options: options, theme: shade, screen: 1100, shadows: true);
      await snap(tester, 'board-marks-mac-$shade');
      await end(tester);
    });
  }
}
