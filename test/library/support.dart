import 'package:ghost_md/core/core_library.dart';

import 'fake_core.dart';

export '../core/make_note.dart';
export 'fake_core.dart';

/// A library over a fake core, with no binding to listen to and waits that take no time: each wait asked for is
/// written down in [waits] instead.
({FakeCore core, CoreLibrary library, List<Duration> waits, List<String> said}) libraryOver([FakeCore? over]) {
  final core = over ?? FakeCore();
  final waits = <Duration>[];
  final said = <String>[];
  final library = CoreLibrary(
    core.invoke,
    resume: false,
    clock: () => core.now,
    wait: (time) async => waits.add(time),
    log: said.add,
  );
  return (core: core, library: library, waits: waits, said: said);
}
