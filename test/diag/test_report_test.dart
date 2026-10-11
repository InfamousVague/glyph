// The test report a build carries (docs/PARITY.md, section 33: Settings › Test results said "No test report in
// this build." in every build, because nothing wrote this app's own suite into one).
//
// tool/test_report.mjs reads what tool/check.sh leaves in build/check and writes assets/diag/test_report.json, in
// the shape Ghost.md's own scripts/test-report.mjs writes for its page. Held here three ways:
// - the tool's readers over a small check kept in this repository (fixtures/check: flutter's event-a-line reports,
//   gradle's XML, cargo's words), run by Node as a release runs them; skipped where there is no `node`;
// - the report the repository keeps is the empty one, so a build made without the tool says what the page says
//   of a build with none;
// - what the app reads of a build (lib/diag/built_report.dart): once, only when Developer mode is on, never an error.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/diag/built_report.dart';
import 'package:ghost_md/settings/panes/test_results_pane.dart';

/// A bundle with one report in it, or none.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.report);
  final String? report;
  int asked = 0;

  @override
  Future<ByteData> load(String key) async {
    asked += 1;
    if (key != builtTestReportAsset || report == null) throw FlutterError('no such asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(report!)));
  }
}

void main() {
  const fixtures = 'test/diag/fixtures/check';

  /// The suites the tool reads out of a check laid out as tool/check.sh leaves one: the fixtures copied to a
  /// folder of their own, gradle's XML written after the mark its run begins with.
  Map<String, Object?>? read({List<String> folders = const ['.', 'e2e', 'notes'], bool server = true, bool kotlin = true}) {
    if (Process.runSync('which', ['node']).exitCode != 0) return null;
    final check = Directory.systemTemp.createTempSync('ghost-check-');
    addTearDown(() => check.deleteSync(recursive: true));
    for (final file in Directory(fixtures).listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!server && name.startsWith('server-')) continue;
      file.copySync('${check.path}/$name');
    }
    final results = Directory('${check.path}/results')..createSync();
    if (kotlin) {
      File('${check.path}/kotlin.began').writeAsStringSync('');
      // Written, not copied: a copy keeps its file's time, and gradle's results are read only where they are newer
      // than the mark its run began with.
      for (final file in Directory('$fixtures/kotlin').listSync().whereType<File>()) {
        File('${results.path}/${file.uri.pathSegments.last}').writeAsStringSync(file.readAsStringSync());
      }
    }
    final script = '''
import { suitesFrom, totalsOf, written, EMPTY } from './tool/test_report.mjs';
const { suites } = suitesFrom(${jsonEncode(check.path)}, { root: '/checkout', folders: ${jsonEncode(folders)}, results: [${jsonEncode(results.path)}], versions: { flutter: 'Flutter 3.0.0', cargo: 'cargo 1.0.0' } });
process.stdout.write(written({ ...EMPTY, generatedAt: '2026-10-11T12:00:00.000Z', sourceHash: 'abc123', totals: totalsOf(suites), suites }));
''';
    final ran = Process.runSync('node', ['--input-type=module', '-e', script]);
    expect(ran.exitCode, 0, reason: '${ran.stderr}');
    return (jsonDecode(ran.stdout as String) as Map).cast<String, Object?>();
  }

  TestSuite suiteOf(TestReport report, String id) => report.suites.firstWhere((suite) => suite.id == id);
  TestResult testOf(TestSuite suite, String name) => suite.tests.firstWhere((test) => test.name == name);

  test('the tool reads a check into the page\'s report: a suite for the app, the kit, the phone\'s Kotlin and the core, each test with its file, its line and why it failed', () {
    final json = read();
    if (json == null) return markTestSkipped('`node` is not on this machine');
    final report = TestReport.fromJson(json);
    expect([for (final suite in report.suites) (suite.id, suite.title, suite.status)], [
      ('flutter:app', 'App (Flutter)', 'failed'),
      ('flutter:kit', 'Kit (Flutter)', 'passed'),
      ('kotlin', 'Phone (Kotlin)', 'failed'),
      ('cargo:core', 'Core (Rust)', 'failed'),
    ]);

    final app = suiteOf(report, 'flutter:app');
    expect((app.counts.total, app.counts.passed, app.counts.failed, app.counts.skipped), (7, 3, 3, 1));
    expect(app.reason, isNull, reason: 'every folder asked for was run');
    // A test's file is from the checkout's top, and its line its own: a widget test's is where it is written, not
    // where the framework's helper is.
    final drawn = testOf(app, 'every screen is drawn');
    expect((drawn.file, drawn.line, drawn.status, drawn.ms), ('test/shots_test.dart', 12, 'passed', 400));
    final pinned = testOf(app, 'a card: a pinned note wears its pin');
    expect((pinned.file, pinned.line, pinned.status), ('test/notes/cards_test.dart', 31, 'failed'));
    // What the framework printed of a widget test's failure, down to where its stack begins.
    expect(pinned.failure, startsWith('The following TestFailure was thrown running a test:\nExpected: exactly one matching candidate'));
    expect(pinned.failure, isNot(contains('this was the stack')));
    expect(testOf(app, 'a row: counts its to-dos').failure, 'Expected: <3>\n  Actual: <2>');
    expect(testOf(app, 'a card: its picture, once the real model is on this Mac').status, 'skipped');
    // A file that does not compile is a failure with a name, never a file that quietly ran nothing.
    final broken = testOf(app, '(the file did not run)');
    expect((broken.file, broken.status), ('test/notes/broken_test.dart', 'failed'));
    expect(broken.failure, contains("Expected ';' after this."));
    // test/e2e is run twice by a whole check: the run with the service is the one reported.
    expect(testOf(app, 'signs in against the service on this Mac').status, 'passed');
    expect(app.tests.where((test) => test.file.startsWith('test/e2e/')), hasLength(1));

    final phone = suiteOf(report, 'kotlin');
    expect((phone.counts.passed, phone.counts.failed, phone.counts.skipped), (1, 1, 1));
    final scaled = testOf(phone, 'scales_the_long_side_down_to_the_cap_and_never_up');
    expect((scaled.file, scaled.ms), ('com.mattssoftware.ghost_md.PicturesTest', 11));
    expect(scaled.failure, startsWith('java.lang.AssertionError: expected:<0.512> but was:<0.5>'));
    expect(testOf(phone, "draws_a_phone's_photograph").status, 'skipped');

    final core = suiteOf(report, 'cargo:core');
    expect((core.counts.passed, core.counts.failed, core.counts.skipped), (2, 1, 1));
    expect(testOf(core, 'an_update_cut_in_two_is_refused').failure, contains('assertion `left == right` failed'));
    expect(testOf(core, 'two_devices_converge').file, 'crdt::tests');
    expect(testOf(core, 'every_recorded_update_is_read').file, 'tests/yjs_vectors.rs');

    // And it is the page's own arithmetic that reads it.
    expect(verdict(report), 'failed');
    expect(reportSummary(report, buildSource: 'abc123'), '5 failed');
    expect(reportSummary(report, buildSource: 'another'), 'From other code');
  });

  test('a folder of test/ that was not run, a suite with nothing in the check, and e2e without its service are said, never passed over', () {
    final json = read(folders: ['.', 'e2e', 'notes', 'root', 'sheet'], server: false, kotlin: false);
    if (json == null) return markTestSkipped('`node` is not on this machine');
    final report = TestReport.fromJson(json);
    final app = suiteOf(report, 'flutter:app');
    expect(app.reason, 'Not run for this report: test/root, test/sheet (2 of 5 runs).');
    // A check of one folder leaves most of them out: a few are named and the rest counted.
    final most = TestReport.fromJson(read(folders: ['.', 'notes', for (var i = 0; i < 12; i += 1) 'f$i'], server: false, kotlin: false)!);
    expect(suiteOf(most, 'flutter:app').reason, 'Not run for this report: test/f0, test/f1, test/f2, test/f3, test/f4, test/f5, test/f6, test/f7 and 4 more (12 of 14 runs).');
    expect(suiteOf(most, 'flutter:app').status, 'failed', reason: 'what did run still says what failed in it');
    // Without the service's run the folder's own stands: its test skipped itself.
    expect(testOf(app, 'signs in against the service on this Mac').status, 'skipped');
    // The phone's Kotlin left nothing: it is not a suite of this read at all, which the tool's own run then marks.
    expect(report.suites.map((suite) => suite.id), ['flutter:app', 'flutter:kit', 'cargo:core']);
  });

  test('the report the repository keeps is the empty one: a build made without the tool says there is none', () {
    final kept = TestReport.fromJson((jsonDecode(File(builtTestReportAsset).readAsStringSync()) as Map).cast<String, Object?>());
    expect(verdict(kept), 'empty');
    expect(reportSummary(kept), 'No report yet');
    // And it is in the build: pubspec.yaml names it.
    expect(File('pubspec.yaml').readAsStringSync(), contains('- $builtTestReportAsset'));
  });

  test('a build\'s report is read from its bundle, and a build with none, or one that will not read, has none', () async {
    final report = jsonEncode({
      'generatedAt': '2026-10-11T12:00:00.000Z',
      'suites': [
        {'id': 'kit', 'title': 'Kit', 'status': 'passed', 'counts': {'total': 1, 'passed': 1, 'failed': 0, 'skipped': 0, 'todo': 0}, 'tests': <Object?>[]},
      ],
    });
    expect(verdict(TestReport.fromJson((await readBuiltTestReport(_Bundle(report)))!)), 'passed');
    expect(await readBuiltTestReport(_Bundle(null)), isNull);
    expect(await readBuiltTestReport(_Bundle('not a report')), isNull);
    expect(await readBuiltTestReport(_Bundle('[1, 2]')), isNull);
  });

  test('the app reads it once, and only once Developer mode is on and the app has said it may', () async {
    final developer = ValueNotifier<bool>(false);
    var reads = 0;
    final built = BuiltTestReport(
      wanted: developer,
      read: () async {
        reads += 1;
        return {'generatedAt': 'now'};
      },
    );
    addTearDown(built.dispose);
    var told = 0;
    built.addListener(() => told += 1);
    // Developer mode on before the app is up: not yet.
    developer.value = true;
    await Future<void>.delayed(Duration.zero);
    expect((reads, built.value), (0, null));
    built.start();
    await Future<void>.delayed(Duration.zero);
    expect((reads, told), (1, 1));
    expect(built.value, {'generatedAt': 'now'});
    // Off and on again, and started again: it has it.
    developer.value = false;
    developer.value = true;
    built.start();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);

    // A phone that never unlocks Developer mode never reads it.
    final never = BuiltTestReport(wanted: ValueNotifier<bool>(false), read: () async => fail('nobody could look at it'));
    addTearDown(never.dispose);
    never.start();
    await Future<void>.delayed(Duration.zero);
    expect(never.value, isNull);
  });
}
