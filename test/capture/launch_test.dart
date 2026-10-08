import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/launch.dart';

/// The order a recorder is opened in (lib/capture/launch.dart), case for case with the web's
/// `capture/launch.test.ts`.
void main() {
  group('capture launch ordering', () {
    test('does not mount immediate Speak until the deferred delete has finished', () async {
      final events = <String>[];
      final deleting = Completer<void>();
      final launch = afterPendingDeletes(
        () async {
          events.add('delete-started');
          await deleting.future;
          events.add('delete-finished');
        },
        () => events.add('capture-mounted'),
      );

      await Future<void>.value();
      expect(events, ['delete-started']);
      deleting.complete();
      await launch;
      expect(events, ['delete-started', 'delete-finished', 'capture-mounted']);
    });
  });
}
