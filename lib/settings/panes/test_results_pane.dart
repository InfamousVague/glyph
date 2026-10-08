import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../sheet/css.dart' show snapBorder;
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import 'settings_host.dart';

// --- the report (src/app/diag/testReport.ts) ----------------------------------------------------------------------

/// One test's result (`TestResult`): `status` is `passed`, `failed`, `skipped` or `todo`.
@immutable
class TestResult {
  const TestResult({required this.file, this.line, required this.name, required this.status, this.ms, this.failure});

  factory TestResult.fromJson(Map<String, Object?> json) => TestResult(
        file: json['file'] as String? ?? '',
        line: (json['line'] as num?)?.toInt(),
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? 'skipped',
        ms: json['ms'] as num?,
        failure: json['failure'] as String?,
      );

  final String file;
  final int? line;
  final String name;
  final String status;
  final num? ms;
  final String? failure;
}

/// How a suite's tests came out (`Counts`).
@immutable
class TestCounts {
  const TestCounts({this.total = 0, this.passed = 0, this.failed = 0, this.skipped = 0, this.todo = 0, this.notRun = 0});

  factory TestCounts.fromJson(Object? json) {
    final map = json is Map ? json : const <Object?, Object?>{};
    int n(String key) => (map[key] as num?)?.toInt() ?? 0;
    return TestCounts(total: n('total'), passed: n('passed'), failed: n('failed'), skipped: n('skipped'), todo: n('todo'));
  }

  final int total, passed, failed, skipped, todo;

  /// Suites that did not run; counted across a report, never within a suite.
  final int notRun;
}

/// One suite of the report (`Suite`): `status` is `passed`, `failed`, `error` or `notRun`.
@immutable
class TestSuite {
  const TestSuite({required this.id, required this.title, this.runnerVersion, this.command, required this.status, this.reason, this.exitCode, this.durationMs, this.counts = const TestCounts(), this.tests = const []});

  factory TestSuite.fromJson(Map<String, Object?> json) => TestSuite(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        runnerVersion: json['runnerVersion'] as String?,
        command: json['command'] as String?,
        status: json['status'] as String? ?? 'notRun',
        reason: json['reason'] as String?,
        exitCode: (json['exitCode'] as num?)?.toInt(),
        durationMs: json['durationMs'] as num?,
        counts: TestCounts.fromJson(json['counts']),
        tests: [
          for (final test in json['tests'] as List? ?? const [])
            if (test is Map) TestResult.fromJson(test.cast<String, Object?>()),
        ],
      );

  final String id;
  final String title;
  final String? runnerVersion;
  final String? command;
  final String status;
  final String? reason;
  final int? exitCode;
  final num? durationMs;
  final TestCounts counts;
  final List<TestResult> tests;
}

/// Every test the app has, from the last full run on the machine that built it (`TestReport`), read from the JSON
/// `scripts/test-report.mjs` writes.
@immutable
class TestReport {
  const TestReport({this.generatedAt, this.version, this.commit, this.dirty = false, this.sourceHash, this.os, this.node, this.tools = const [], this.suites = const []});

  factory TestReport.fromJson(Map<String, Object?> json) {
    final host = json['host'];
    final tools = json['tools'];
    return TestReport(
      generatedAt: json['generatedAt'] as String?,
      version: json['version'] as String?,
      commit: json['commit'] as String?,
      dirty: json['dirty'] == true,
      sourceHash: json['sourceHash'] as String?,
      os: host is Map ? host['os'] as String? : null,
      node: host is Map ? host['node'] as String? : null,
      tools: [
        if (tools is Map)
          for (final tool in tools.values)
            if (tool is String && tool.isNotEmpty) tool,
      ],
      suites: [
        for (final suite in json['suites'] as List? ?? const [])
          if (suite is Map) TestSuite.fromJson(suite.cast<String, Object?>()),
      ],
    );
  }

  final String? generatedAt;
  final String? version;
  final String? commit;
  final bool dirty;
  final String? sourceHash;
  final String? os;
  final String? node;
  final List<String> tools;
  final List<TestSuite> suites;
}

/// Whether the report is of the code this build was made from (`buildMatch`): `same`, `different` or `unknown`.
String buildMatch(TestReport report, String? build) => report.sourceHash == null || build == null
    ? 'unknown'
    : report.sourceHash == build
        ? 'same'
        : 'different';

/// The report's numbers, added up from its suites rather than taken from its own word (`tally`).
TestCounts tally(TestReport report) {
  var total = 0, passed = 0, failed = 0, skipped = 0, todo = 0, notRun = 0;
  for (final suite in report.suites) {
    if (suite.status == 'notRun' || suite.status == 'error') notRun += 1;
    total += suite.counts.total;
    passed += suite.counts.passed;
    failed += suite.counts.failed;
    skipped += suite.counts.skipped;
    todo += suite.counts.todo;
  }
  return TestCounts(total: total, passed: passed, failed: failed, skipped: skipped, todo: todo, notRun: notRun);
}

/// `passed`, `failed`, `incomplete` or `empty` (`verdict`).
String verdict(TestReport report) {
  if (report.generatedAt == null || report.suites.isEmpty) return 'empty';
  final totals = tally(report);
  if (totals.failed > 0) return 'failed';
  if (totals.notRun > 0) return 'incomplete';
  return 'passed';
}

/// Test results' row in the list (`reportSummary`).
String reportSummary(TestReport? report, {String? buildSource}) {
  if (report == null) return 'No report yet';
  final kind = verdict(report);
  if (kind == 'empty') return 'No report yet';
  final totals = tally(report);
  if (buildMatch(report, buildSource) == 'different') return 'From other code';
  if (kind == 'failed') return '${totals.failed} failed';
  if (kind == 'incomplete') return '${totals.notRun} ${totals.notRun == 1 ? 'suite' : 'suites'} missing';
  return '${totals.passed} passed';
}

/// A suite's tests by file, failures first in each and the files with failures first (`byFile`).
List<({String file, List<TestResult> tests, int failed})> byFile(Iterable<TestResult> tests) {
  final groups = <String, List<TestResult>>{};
  for (final test in tests) {
    groups.putIfAbsent(test.file, () => []).add(test);
  }
  final out = [
    for (final entry in groups.entries)
      (
        file: entry.key,
        tests: [...entry.value.where((t) => t.status == 'failed'), ...entry.value.where((t) => t.status != 'failed')],
        failed: entry.value.where((t) => t.status == 'failed').length,
      ),
  ];
  out.sort((a, b) => b.failed != a.failed ? b.failed - a.failed : a.file.compareTo(b.file));
  return out;
}

/// Whether every word typed is in the test's name or file (`matches`).
bool testMatches(TestResult test, String query) {
  final hay = '${test.name} ${test.file}'.toLowerCase();
  return query.toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).every(hay.contains);
}

/// "8 hr ago" (`ago`).
String ago(String iso, [DateTime? now]) {
  final then = DateTime.tryParse(iso);
  if (then == null) return iso;
  final minutes = ((now ?? DateTime.now()).difference(then).inMilliseconds / 60000).round();
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min ago';
  final hours = (minutes / 60).round();
  if (hours < 48) return '$hours hr ago';
  return '${(hours / 24).round()} days ago';
}

/// "640 ms", "1.4 s", "32 s" (`seconds`).
String testSeconds(num? ms) {
  if (ms == null) return '';
  return ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(ms < 10000 ? 1 : 0)} s';
}

/// A moment as the page's `toLocaleString()` says it in English: "10/7/2026, 7:06:56 PM".
String _when(String iso) {
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '${at.month}/${at.day}/${at.year}, $hour:${two(at.minute)}:${two(at.second)} ${at.hour < 12 ? 'AM' : 'PM'}';
}

// --- the page -----------------------------------------------------------------------------------------------------

/// `--test-red`, `--test-green` (TestResultsPane.module.css): the only colours in Settings, and only here.
Color _red(Tokens t) => t.colorOf('oklch(0.62 0.21 25)');
Color _green(Tokens t) => t.colorOf('oklch(0.62 0.15 150)');

const Map<String, GlacierPillTone> _statusTone = {'passed': GlacierPillTone.success, 'failed': GlacierPillTone.danger, 'error': GlacierPillTone.danger, 'notRun': GlacierPillTone.warning};
const Map<String, String> _statusWord = {'passed': 'Passed', 'failed': 'Failed', 'error': 'Did not run', 'notRun': 'Not run'};

/// Port of `TestResultsPane` (src/app/settings/TestResultsPane.tsx with TestResultsPane.module.css), a page of
/// Developer mode: every test the app has, from the last full run on the machine that built it. A verdict card
/// first, red or green, from the suites themselves, with the four numbers that matter. Then whatever makes the
/// results less than they seem, where they came from, a search with "only failures", and one card per suite, its
/// tests grouped by file with failures first and open, each failure's output under it. Nothing here runs a test.
///
/// What differs from the web original:
/// - **The Flutter build carries no report**: the web's is a JSON file its build bakes in (`testReport.generated.json`
///   from `scripts/test-report.mjs`). The page takes a [report] in that same shape ([SettingsFeatures.testReport] in
///   Settings) and, with none, draws the page's own "No test report in this build."
/// - A failure's output is a block as tall as it is; the page capped it at 14rem and scrolled inside.
/// - A file's tests fold under its name by a tap, as the page's `<details>` do, without the browser's marker (the
///   page hid it too).
class TestResultsPane extends StatefulWidget {
  const TestResultsPane({super.key, this.report, this.buildSource, this.now});

  final TestReport? report;

  /// This build's source fingerprint, to check the report against; null for a development build.
  final String? buildSource;

  /// The moment "8 hr ago" is said from; now when null.
  final DateTime? now;

  static Widget hosted(BuildContext context) {
    final features = SettingsHost.maybeOf(context)?.features;
    final json = features?.testReport;
    return TestResultsPane(report: json == null ? null : TestReport.fromJson(json), buildSource: features?.testBuildSource, now: features?.testNow);
  }

  @override
  State<TestResultsPane> createState() => _TestResultsPaneState();
}

class _TestResultsPaneState extends State<TestResultsPane> {
  String _query = '';
  bool _onlyFailures = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final report = widget.report;
    final kind = report == null ? 'empty' : verdict(report);
    if (report == null || kind == 'empty') {
      final mono = pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), mono: true);
      return PaneBody(
        children: [
          SettingsEmpty(
            icon: const AppIcon(Lucide.circleAlert, size: 22),
            title: 'No test report in this build.',
            body: Text.rich(
              TextSpan(children: [const TextSpan(text: 'Run '), TextSpan(text: 'node scripts/test-report.mjs', style: mono), const TextSpan(text: ' before building. Every over-the-air release does it for you.')]),
            ),
          ),
        ],
      );
    }

    final totals = tally(report);
    final match = buildMatch(report, widget.buildSource);
    final missing = [for (final suite in report.suites) if (suite.status == 'notRun' || suite.status == 'error') suite];
    final ok = kind == 'passed';
    final tone = ok ? _green(t) : _red(t);
    final xs = t.fontSize('xs');
    const alert = AppIcon(Lucide.circleAlert, size: 16);

    Widget count(String name, int value, {bool alarm = false}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(label: name, child: ExcludeSemantics(child: Text(name.toUpperCase(), style: pageText(t, xs, color: t.color('app-ink-3'), tracking: t.len('app-tracking-caps-close', em: xs))))),
              const SizedBox(height: 2),
              Text('$value', style: pageText(t, t.fontSize('xl'), weight: 'bold', color: alarm ? _red(t) : t.color('app-ink')).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        );

    return PaneBody(
      children: [
        Semantics(
          container: true,
          label: 'Verdict',
          child: Container(
            key: const ValueKey('test-verdict'),
            padding: EdgeInsets.all(t.space(4)),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(t.radius('lg')),
              // `--app-line` is 1.5px, drawn as a browser snaps a border: three device pixels at 2, four at 3.
              border: Border.all(color: tone, width: snapBorder(context, t.len('app-line'))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AppIcon(ok ? Lucide.circleCheck : Lucide.circleX, size: 22, color: tone),
                    SizedBox(width: t.space(2)),
                    Expanded(
                      child: Text(
                        ok ? 'Every test passed' : (kind == 'failed' ? '${totals.failed} ${totals.failed == 1 ? 'test' : 'tests'} failed' : 'Some suites did not run'),
                        style: pageText(t, t.fontSize('lg'), weight: 'bold', color: tone),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: t.space(3)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    count('Passed', totals.passed),
                    SizedBox(width: t.space(2)),
                    count('Failed', totals.failed, alarm: totals.failed > 0),
                    SizedBox(width: t.space(2)),
                    count('Skipped', totals.skipped + totals.todo),
                    SizedBox(width: t.space(2)),
                    count('Not run', totals.notRun, alarm: totals.notRun > 0),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (match == 'different') const SettingsCallout(icon: alert, child: Text('The code changed after these tests ran. They are not this build’s results.')),
        if (match == 'unknown') const SettingsCallout(icon: alert, child: Text('This build has no source fingerprint to check the report against (a development build).')),
        if (missing.isNotEmpty) SettingsCallout(icon: alert, child: Text('${missing.map((s) => s.title).join(', ')} did not run for this report.')),
        PaneSection(
          title: 'Where these come from',
          children: [
            SettingRow(label: 'Version', value: Text(report.version ?? '—')),
            SettingRow(
              label: 'Code',
              hint: match == 'same' ? const Text('The same code this build was made from.') : (match == 'different' ? const Text('Not the code this build was made from.') : null),
              control: GlacierPill(
                tone: match == 'same' ? GlacierPillTone.success : (match == 'different' ? GlacierPillTone.danger : GlacierPillTone.warning),
                variant: GlacierPillVariant.soft,
                size: GlacierPillSize.sm,
                child: Text(report.sourceHash ?? 'unknown'),
              ),
            ),
            SettingRow(label: 'Commit', value: Text('${report.commit ?? 'none'}${report.dirty ? ' + changes' : ''}')),
            if (report.generatedAt != null) SettingRow(label: 'Ran', value: Text(ago(report.generatedAt!, widget.now)), hint: Text(_when(report.generatedAt!))),
            if (report.os != null) SettingRow(label: 'On', value: Text(report.os!), hint: Text('Node ${report.node}')),
            SettingRow(
              label: 'Tools',
              layout: SettingRowLayout.stacked,
              control: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: t.space(1),
                  runSpacing: t.space(1),
                  children: [for (final tool in report.tools) GlacierPill(variant: GlacierPillVariant.outline, size: GlacierPillSize.sm, child: Text(tool))],
                ),
              ),
            ),
          ],
        ),
        PaneSection(
          title: 'Find',
          children: [
            SettingRow(
              layout: SettingRowLayout.stacked,
              label: 'Search tests',
              control: GlacierSearchField(value: _query, onValueChange: (value) => setState(() => _query = value), placeholder: 'Words in a test’s name or file', size: GlacierFieldSize.sm),
            ),
            SettingRow(label: 'Only failures', control: GlacierSwitch(ariaLabel: 'Only failures', checked: _onlyFailures, onCheckedChange: (on) => setState(() => _onlyFailures = on))),
          ],
        ),
        for (final suite in report.suites)
          if (!_hidden(suite)) _SuiteCard(key: ValueKey(suite.id), suite: suite, query: _query, onlyFailures: _onlyFailures),
        SettingsFootnote(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'From '),
                TextSpan(text: 'node scripts/test-report.mjs', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'), mono: true)),
                const TextSpan(text: ' on the machine that built this app. Real-model tests are skipped unless run by hand.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<TestResult> _visible(TestSuite suite) => [
        for (final test in suite.tests)
          if ((!_onlyFailures || test.status == 'failed') && (_query.isEmpty || testMatches(test, _query))) test,
      ];

  /// A suite that passed and has nothing left after the filter is not drawn at all.
  bool _hidden(TestSuite suite) => (_onlyFailures || _query.isNotEmpty) && suite.status == 'passed' && _visible(suite).isEmpty;
}

/// One suite (`SuiteCard`): its count and its state on a row that opens it, then its files.
class _SuiteCard extends StatefulWidget {
  const _SuiteCard({super.key, required this.suite, required this.query, required this.onlyFailures});
  final TestSuite suite;
  final String query;
  final bool onlyFailures;

  @override
  State<_SuiteCard> createState() => _SuiteCardState();
}

class _SuiteCardState extends State<_SuiteCard> {
  late bool _open = widget.suite.status != 'passed';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final suite = widget.suite;
    final xs = t.fontSize('xs');
    final filtering = widget.onlyFailures || widget.query.isNotEmpty;
    final visible = [
      for (final test in suite.tests)
        if ((!widget.onlyFailures || test.status == 'failed') && (widget.query.isEmpty || testMatches(test, widget.query))) test,
    ];
    final meta = pageText(t, xs, color: t.color('app-ink-3')).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final hint = [testSeconds(suite.durationMs), if (suite.runnerVersion != null) suite.runnerVersion!].where((part) => part.isNotEmpty).join(' · ');
    return PaneSection(
      title: suite.title,
      // `<code>` in the footer's own lines: the small mono, on the footer's line height.
      footer: suite.command == null
          ? null
          : Text(
              suite.command!,
              style: pageText(t, xs, color: t.color('app-ink-2'), mono: true),
              strutStyle: StrutStyle(fontSize: t.fontSize('sm'), height: t.len('glacier-leading-sm'), forceStrutHeight: true),
            ),
      children: [
        SettingRow(
          label: '${suite.counts.passed}/${suite.counts.total} passed${suite.counts.skipped > 0 ? ' · ${suite.counts.skipped} skipped' : ''}',
          hint: hint.isEmpty ? null : Text(hint),
          control: GlacierPill(tone: _statusTone[suite.status] ?? GlacierPillTone.neutral, variant: GlacierPillVariant.soft, size: GlacierPillSize.sm, child: Text(_statusWord[suite.status] ?? suite.status)),
          onPress: () => setState(() => _open = !_open),
        ),
        if (suite.reason != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.space(3), horizontal: t.space(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Failure(suite.reason!),
                if (suite.exitCode != null) ...[SizedBox(height: t.space(1)), Text('exit code ${suite.exitCode}', style: meta)],
              ],
            ),
          ),
        if (_open || filtering)
          for (final group in byFile(visible)) _FileGroup(key: ValueKey(group.file), file: group.file, tests: group.tests, failed: group.failed, open: group.failed > 0 || filtering, meta: meta),
      ],
    );
  }
}

/// A file's tests (`.file`): a disclosure row, then the tests.
class _FileGroup extends StatefulWidget {
  const _FileGroup({super.key, required this.file, required this.tests, required this.failed, required this.open, required this.meta});
  final String file;
  final List<TestResult> tests;
  final int failed;
  final bool open;
  final TextStyle meta;

  @override
  State<_FileGroup> createState() => _FileGroupState();
}

class _FileGroupState extends State<_FileGroup> {
  late bool _open = widget.open;

  @override
  void didUpdateWidget(_FileGroup old) {
    super.didUpdateWidget(old);
    if (old.open != widget.open) _open = widget.open;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    final sm = t.fontSize('sm');
    final failed = widget.failed > 0;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GlacierPressable(
            onPressed: () => setState(() => _open = !_open),
            toggled: _open,
            builder: (context, state) => GlacierFocusRing(
              visible: state.focused,
              radius: t.radius('sm'),
              offset: -3,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: t.space(3), horizontal: t.space(4)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text(widget.file, style: pageText(t, xs, weight: failed ? 'bold' : 'regular', color: failed ? _red(t) : t.color('app-ink'), mono: true))),
                    SizedBox(width: t.space(3)),
                    Text('${failed ? '${widget.failed} failed · ' : ''}${widget.tests.length}', maxLines: 1, softWrap: false, style: widget.meta),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: EdgeInsets.only(left: t.space(4), right: t.space(4), bottom: t.space(3)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.tests.length; i++) ...[
                    if (i > 0) SizedBox(height: t.space(1)),
                    () {
                      final test = widget.tests[i];
                      final (icon, colour, word) = switch (test.status) {
                        'passed' => (Lucide.circleCheck, _green(t), 'Passed'),
                        'failed' => (Lucide.circleX, _red(t), 'Failed'),
                        'todo' => (Lucide.minusCircle, t.color('app-ink-4'), 'To do'),
                        _ => (Lucide.minusCircle, t.color('app-ink-4'), 'Skipped'),
                      };
                      final tail = [if (test.line != null) ':${test.line}', testSeconds(test.ms)].where((part) => part.isNotEmpty).join(' ');
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              // The icon sits on the words' line, as an inline svg does.
                              Baseline(baseline: 12, baselineType: TextBaseline.alphabetic, child: AppIcon(icon, size: 14, color: colour, semanticLabel: word)),
                              SizedBox(width: t.space(2)),
                              Expanded(child: Text(test.name, style: pageText(t, sm, color: test.status == 'failed' ? t.color('app-ink') : t.color('app-ink-2')))),
                              SizedBox(width: t.space(2)),
                              Text(tail, maxLines: 1, softWrap: false, style: widget.meta),
                            ],
                          ),
                          if (test.failure != null) Padding(padding: EdgeInsets.only(top: t.space(1), bottom: t.space(2)), child: _Failure(test.failure!)),
                        ],
                      );
                    }(),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// `.failure`: what a failed test or a suite that did not run printed, in a block washed with the red.
class _Failure extends StatelessWidget {
  const _Failure(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(3)),
      decoration: BoxDecoration(color: _red(t).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(t.radius('md'))),
      child: Text(text, style: pageText(t, t.fontSize('xs'), height: 1.5, color: t.color('app-ink'), mono: true)),
    );
  }
}
