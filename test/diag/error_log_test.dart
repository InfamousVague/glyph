import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/diag/error_log.dart';

/// The app's one handler for the errors nobody caught (lib/diag/error_log.dart): each is kept and said, and what
/// handled errors before is still asked, so a debug build writes it out as it always has.
void main() {
  group('the errors kept', () {
    test('are each one line, the newest last, with a repeat counted on the one kept', () {
      final said = <String>[];
      final log = ErrorLog(clock: () => 5, say: said.add);
      var told = 0;
      log.addListener(() => told += 1);
      log.record(StateError('the note was deleted'), StackTrace.fromString('#0 a\n#1 b'), where: 'while building Home');
      log.record(StateError('the note was deleted'), null, where: 'while building Home');
      log.record(const FormatException('half a file'), null, where: 'in a callback nothing was waiting on');
      expect([for (final each in log.errors) (each.what, each.times)], [('Bad state: the note was deleted', 2), ('FormatException: half a file', 1)]);
      expect(log.errors.first.stack, '#0 a\n#1 b');
      expect(told, 3);
      // Said the first time, and not at every frame an error in a build is thrown again.
      expect(said.where((line) => line.startsWith('[ghost] uncaught')).toList(), [
        '[ghost] uncaught while building Home: Bad state: the note was deleted',
        '[ghost] uncaught in a callback nothing was waiting on: FormatException: half a file',
      ]);
    });

    test('are said again at the tenth and the hundredth of a run, and no more than that', () {
      final said = <String>[];
      final log = ErrorLog(say: said.add);
      for (var i = 0; i < 120; i += 1) {
        log.record(StateError('again'), null, where: 'during layout');
      }
      expect(log.errors.single.times, 120);
      expect(said.where((line) => line.startsWith('[ghost] uncaught')).toList(), [
        '[ghost] uncaught during layout: Bad state: again',
        '[ghost] uncaught during layout: Bad state: again (x10)',
        '[ghost] uncaught during layout: Bad state: again (x100)',
      ]);
    });

    test('are the last fifty', () {
      final log = ErrorLog(most: 3, say: (_) {});
      for (var i = 0; i < 5; i += 1) {
        log.record(StateError('$i'), null, where: 'somewhere');
      }
      expect([for (final each in log.errors) each.what], ['Bad state: 2', 'Bad state: 3', 'Bad state: 4']);
      log.clear();
      expect(log.errors, isEmpty);
    });
  });

  group('the handler under the app', () {
    late FlutterExceptionHandler? framework;
    late ErrorCallback? outside;

    setUp(() {
      framework = FlutterError.onError;
      outside = PlatformDispatcher.instance.onError;
      debugForgetErrorLog();
    });

    tearDown(() {
      FlutterError.onError = framework;
      PlatformDispatcher.instance.onError = outside;
      debugForgetErrorLog();
    });

    test('keeps what the framework reports, and still hands it to whatever handled it before', () {
      final before = <FlutterErrorDetails>[];
      FlutterError.onError = before.add;
      final log = ErrorLog(say: (_) {});
      installErrorLog(log: log);
      final details = FlutterErrorDetails(exception: StateError('no shell'), stack: StackTrace.current, library: 'widgets library', context: ErrorDescription('while building a part'));
      FlutterError.onError!(details);
      expect((log.errors.single.where, log.errors.single.what), ('while building a part', 'Bad state: no shell'));
      expect(before.single, same(details), reason: 'a debug build still writes it out in full');
      // One the framework marks silent is passed on and not kept.
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('an image'), silent: true));
      expect(log.errors.length, 1);
      expect(before.length, 2);
    });

    test('keeps an error nothing was waiting on, and in a debug build does not call it handled', () {
      final before = <Object>[];
      PlatformDispatcher.instance.onError = (error, stack) {
        before.add(error);
        return false;
      };
      final log = ErrorLog(say: (_) {});
      installErrorLog(log: log);
      final handled = PlatformDispatcher.instance.onError!(StateError('a timer'), StackTrace.current);
      expect(log.errors.single.what, 'Bad state: a timer');
      expect(log.errors.single.where, 'in a callback nothing was waiting on');
      expect(before.length, 1);
      // A test is a debug build: left unhandled, so the engine reports it with its whole stack.
      expect(kDebugMode, isTrue);
      expect(handled, isFalse);
    });

    test('is put there once', () {
      final log = ErrorLog(say: (_) {});
      FlutterError.onError = (_) {};
      installErrorLog(log: log);
      final first = FlutterError.onError;
      installErrorLog(log: log);
      expect(FlutterError.onError, same(first));
    });
  });
}
