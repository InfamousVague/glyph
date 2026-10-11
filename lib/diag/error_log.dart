/// The errors nobody caught, kept and said: one place every uncaught error in the app comes to.
///
/// Until this there was none. An error thrown while a frame was built reached Flutter's own handler, which writes
/// it out in a debug build and in any other build says a line; an error thrown in a callback nothing was waiting
/// on (a timer, a channel's answer, a future let go with `unawaited`) reached nothing of the app's at all, and in a
/// release build was gone: the app carried on with whatever the error had left half done, and nobody could say what
/// had happened on the phone it happened on.
///
/// [installErrorLog], called once as the app starts, puts one handler under both ways an error escapes:
/// `FlutterError.onError` (the framework's: building, laying out, painting, a gesture's callback) and
/// `PlatformDispatcher.onError` (everything else in the root zone). Each error is kept in [ErrorLog] (the last
/// [ErrorLog.most], repeats counted, for whatever shows them: Settings › Developer has no page for them yet) and
/// said as one line on the log, `[ghost] uncaught …`, which a release build writes too.
///
/// **Nothing is swallowed in a debug build.** The framework's own handler is still called after this one, so a
/// debug build writes the error out in full as it always has and a test's handler still fails its test; and an
/// error outside the framework is answered "not handled" in a debug build, so the engine reports it as unhandled,
/// with its whole stack. In a profile or a release build it is answered "handled": it has been kept and said, and
/// there is nobody else to hand it to.
library;

import 'package:flutter/foundation.dart';

/// One uncaught error, as it is kept.
@immutable
class LoggedError {
  const LoggedError({required this.at, required this.where, required this.what, required this.stack, this.times = 1});

  /// When it was last thrown, in milliseconds since the epoch.
  final int at;

  /// What was being done: the framework's own words for it ("while building …"), or that nothing was waiting.
  final String where;

  /// The error's first line.
  final String what;

  /// The first lines of its stack, enough to find it.
  final String stack;

  /// How many times in a row it was thrown: an error in a build is thrown at every frame.
  final int times;

  /// One line, for the log.
  String said() => '[ghost] uncaught $where: $what${times > 1 ? ' (x$times)' : ''}';
}

/// The uncaught errors of this run, the newest last. Listen to it to draw them.
class ErrorLog extends ChangeNotifier {
  ErrorLog({this.most = 50, int Function()? clock, void Function(String line)? say})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _say = say ?? debugPrint;

  /// The app's own.
  static final ErrorLog instance = ErrorLog();

  /// How many are kept: the oldest goes when there are more.
  final int most;
  final int Function() _clock;
  final void Function(String line) _say;
  final List<LoggedError> _held = [];

  List<LoggedError> get errors => List.unmodifiable(_held);

  /// Keeps one error and says it. The same error thrown again at once is counted on the one kept, and said the
  /// first time and at each tenfold after (the 10th, the 100th), so an error in every frame does not fill the log.
  void record(Object error, StackTrace? stack, {required String where}) {
    final what = error.toString().split('\n').first;
    final lines = (stack?.toString() ?? '').split('\n').where((line) => line.trim().isNotEmpty).take(8).join('\n');
    final last = _held.isEmpty ? null : _held.last;
    final LoggedError kept;
    if (last != null && last.what == what && last.where == where) {
      kept = LoggedError(at: _clock(), where: where, what: what, stack: last.stack, times: last.times + 1);
      _held[_held.length - 1] = kept;
    } else {
      kept = LoggedError(at: _clock(), where: where, what: what, stack: lines);
      _held.add(kept);
      if (_held.length > most) _held.removeAt(0);
    }
    if (_tenfold(kept.times)) {
      _say(kept.said());
      if (kept.times == 1 && lines.isNotEmpty && !kDebugMode) _say(lines);
    }
    notifyListeners();
  }

  static bool _tenfold(int times) {
    var n = times;
    while (n >= 10 && n % 10 == 0) {
      n ~/= 10;
    }
    return n == 1;
  }

  /// Forgets them: for a test, and for whatever page comes to draw them.
  void clear() {
    if (_held.isEmpty) return;
    _held.clear();
    notifyListeners();
  }
}

bool _installed = false;

/// Puts the app's one handler under every uncaught error (see the header). Asked twice, it is put there once.
/// Whatever handled errors before is still asked, after: the framework's own writing out, a walk's own handler.
void installErrorLog({ErrorLog? log}) {
  if (_installed) return;
  _installed = true;
  final kept = log ?? ErrorLog.instance;
  final framework = FlutterError.onError;
  FlutterError.onError = (details) {
    // An error the framework says is not worth a report (an image that failed to load, say) is passed on as it was.
    if (!details.silent) kept.record(details.exception, details.stack, where: details.context?.toDescription() ?? 'in ${details.library ?? 'the framework'}');
    framework?.call(details);
  };
  final outside = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    kept.record(error, stack, where: 'in a callback nothing was waiting on');
    final handled = outside?.call(error, stack) ?? false;
    // A debug build is told it was not handled, and the engine reports it in full; any other has kept and said it.
    return handled || !kDebugMode;
  };
}

/// For a test: the next [installErrorLog] installs again. The handlers themselves are the test's to put back.
@visibleForTesting
void debugForgetErrorLog() => _installed = false;
