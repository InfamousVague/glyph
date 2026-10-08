import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/github/github.dart';
import 'package:ghost_md/sheet/kit.dart';

import 'support.dart';

/// The GitHub repo picker on a note's cog: a kept repo linked with a tap, and a new one read with its steps said as
/// they happen and linked once it is kept. Reading a repo is stood in for (projects_test.dart is the reading
/// itself). A port of `src/app/plugins/github/ProjectPicker.test.tsx`, case for case.
void main() {
  setUpAll(loadAppFonts);

  late TestGround ground;

  Map<String, Object?> kept(String id, [Map<String, Object?> over = const {}]) {
    final parts = id.split('/');
    return {'id': id, 'owner': parts[0], 'repo': parts[1], 'url': '', 'branch': 'main', 'description': '', 'files': <String>[], 'pack': 'A briefing.', 'packModel': null, 'packedAt': 1, ...over};
  }

  /// The reading: its steps as the test lets them out, and then the project, or a failure.
  late List<ReadStep> steps;
  Object? failure;

  Future<Project> read(String input, void Function(ReadStep step) onStep) async {
    steps.forEach(onStep);
    await null;
    if (failure != null) throw failure!;
    ground.kept.setItem('glyph-github-projects', jsonEncode([kept('o/new'), for (final p in projects()) p.toJson()]));
    return Project.fromJson(kept('o/new'))!;
  }

  setUp(() {
    ground = useGround();
    steps = [];
    failure = null;
  });

  Finder row(String label) => find.widgetWithText(SheetRow, label);
  bool pressable(WidgetTester tester, String label) => !tester.widget<SheetRow>(row(label)).disabled;
  Finder field(String label) => find.descendant(of: find.byWidgetPredicate((w) => w is SheetField && w.label == label), matching: find.byType(EditableText));

  group('the repo picker', () {
    testWidgets('links a kept repo with a tap, ticks it, and unlinks it again', (tester) async {
      ground.kept.setItem('glyph-github-projects', jsonEncode([kept('o/app', {'packModel': 'qwen3.5-4b'})]));
      var done = 0;
      await pumpSheetPage(tester, ProjectPicker(noteId: 'n1', onDone: () => done += 1, read: read));
      expect(textOf(tester), contains('Read by qwen3.5-4b.'));
      await press(tester, row('o/app'));
      expect(projectFor('n1')?.id, 'o/app');
      expect(done, 1);
      expect(tester.widget<SheetRow>(row('o/app')).chosen, isTrue);
      await press(tester, row('Don’t link a project'));
      expect(projectFor('n1'), isNull);
      await away(tester);
    });

    testWidgets('reads a pasted repo, keeps the token typed with it, and links the repo once it is kept', (tester) async {
      steps = const [ReadReading(), ReadFiles(done: 1, total: 3)];
      var done = 0;
      await pumpSheetPage(tester, ProjectPicker(noteId: 'n1', onDone: () => done += 1, read: read));
      expect(pressable(tester, 'Read and link'), isFalse);
      await tester.enterText(field('Link'), 'github.com/o/new');
      await tester.pump();
      await press(tester, row('Private repo?'));
      await tester.enterText(field('Token, for a private repo'), 'ghp_secret');
      await tester.pump();
      // Drawn as dots, never as its letters.
      final token = tester.widget<EditableText>(field('Token, for a private repo'));
      expect(token.controller.text, 'ghp_secret');
      expect(token.controller.buildTextSpan(context: tester.element(field('Token, for a private repo')), withComposing: false).toPlainText(), '•' * 'ghp_secret'.length);
      expect(token.keyboardType, TextInputType.visiblePassword);
      await press(tester, row('Read and link'));
      expect(projectFor('n1')?.id, 'o/new');
      expect(githubToken(), 'ghp_secret');
      expect(ground.secrets.held, {'glyph-github-token': 'ghp_secret'});
      expect(done, 1);
      expect(textOf(tester), contains('o/new'));
      await away(tester);
    });

    testWidgets('says why a repo would not read, and links nothing', (tester) async {
      steps = const [ReadReading()];
      failure = const GithubFailure('GitHub can’t find that repo. If it’s private, add a token.');
      await pumpSheetPage(tester, ProjectPicker(noteId: 'n1', onDone: () {}, read: read));
      await tester.enterText(field('Link'), 'o/missing');
      await tester.pump();
      await press(tester, row('Read and link'));
      expect(textOf(tester), contains('GitHub can’t find that repo. If it’s private, add a token.'));
      expect(projectFor('n1'), isNull);
      // Ready to try again.
      expect(pressable(tester, 'Read and link'), isTrue);
      await away(tester);
    });

    // Not cases of the page's: the steps' words, and a token that is not on show.
    test('says each step of a reading', () {
      expect(describeStep(const ReadReading()), 'Asking GitHub about the repo…');
      expect(describeStep(const ReadFiles(done: 1, total: 3)), 'Reading 2 of 3 files…');
      expect(describeStep(const ReadFiles(done: 3, total: 3)), 'Read the files.');
      expect(describeStep(const ReadDistilling(model: 'Qwen3.5 4B', tokensPerSecond: 11.6, text: '')), 'Qwen3.5 4B is reading it, 12 words a second…');
      expect(describeStep(const ReadDistilling(model: 'Qwen3.5 4B', tokensPerSecond: 0, text: '')), 'Qwen3.5 4B is reading it…');
    });

    testWidgets('leaves a kept token alone when its field was never opened', (tester) async {
      ground.secrets.held['glyph-github-token'] = 'ghp_kept';
      await pumpSheetPage(tester, ProjectPicker(noteId: 'n1', onDone: () {}, read: read));
      await tester.enterText(field('Link'), 'o/new');
      await tester.pump();
      await press(tester, row('Read and link'));
      expect(ground.secrets.held, {'glyph-github-token': 'ghp_kept'});
      await away(tester);
    });
  });
}
