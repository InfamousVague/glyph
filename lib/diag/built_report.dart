/// The test report this build carries, for Settings › Test results (Developer mode): `assets/diag/test_report.json`,
/// which tool/test_report.mjs writes from the whole suite before a release is built. Ghost.md's page compiles its
/// own in (`src/app/diag/testReport.ts`: `REPORT` from testReport.generated.json, and `BUILD_SOURCE` from the
/// fingerprint its build is stamped with); this is the same two things for a Flutter build.
///
/// What differs:
/// - The page's report is a module, there with the page. An asset is read, so it is read once and only when
///   someone could look at it: the first time Developer mode is on after the app says it may ([BuiltTestReport.start],
///   once the notes are read). A phone that never unlocks Developer mode never reads it.
/// - A build made without running the tool carries the empty report the repository keeps, and the page then says
///   what the web's says of a build with none: "No test report in this build."
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Where a build's report is (tool/test_report.mjs `REPORT_PATH`).
const String builtTestReportAsset = 'assets/diag/test_report.json';

const String _source = String.fromEnvironment('GHOST_SOURCE');

/// The source fingerprint this build was made from (`--dart-define=GHOST_SOURCE=…`, which is
/// `node tool/test_report.mjs --source`), or null for a build not given one: a development build (`BUILD_SOURCE`).
String? get buildSource => _source.isEmpty ? null : _source;

/// The build's report as its JSON, or null where there is none that can be read. Not kept by the bundle: whoever
/// asked keeps what it is read into.
Future<Map<String, Object?>?> readBuiltTestReport([AssetBundle? bundle]) async {
  try {
    final decoded = jsonDecode(await (bundle ?? rootBundle).loadString(builtTestReportAsset, cache: false));
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } catch (_) {
    return null;
  }
}

/// The build's report as the app holds it: null until it has been read, and read once, the first time [wanted]
/// (Developer mode) is on after [start]. Its listeners are told when it is there.
class BuiltTestReport extends ValueNotifier<Map<String, Object?>?> {
  BuiltTestReport({required this.wanted, Future<Map<String, Object?>?> Function()? read})
      : _read = read ?? readBuiltTestReport,
        super(null) {
    wanted.addListener(_look);
  }

  /// Whether anyone could look at the report now.
  final ValueListenable<bool> wanted;
  final Future<Map<String, Object?>?> Function() _read;
  bool _started = false, _asked = false, _gone = false;

  /// The app is up and may read it: from here it is read as soon as it is wanted.
  void start() {
    _started = true;
    _look();
  }

  void _look() {
    if (!_started || _asked || _gone || !wanted.value) return;
    _asked = true;
    unawaited(_read().then<void>((report) {
      if (!_gone && report != null) value = report;
    }, onError: (Object _) {}));
  }

  @override
  void dispose() {
    _gone = true;
    wanted.removeListener(_look);
    super.dispose();
  }
}
