// Run before every test file (flutter_test's own hook).
//
// The project tools (docs/PM_PLUGINS.md; Matt, 2026-11-01) ship off, and every test written before them tests their
// features as they were: tickets, boards, gantts, rules, timers and forms on. So each test starts with the whole suite
// on (lib/plugins/projects/suite.dart `ProjectSuite.debugAllOn`), and a test of the off state, or of where a switch
// is, sets it back to false (test/plugins/projects/).
//
// The more tools the same (docs/PM_PLUGINS.md §10; Matt, 2026-11-01): Canvas, Meetings, Diagrams and math, Places,
// Email to a note and Publishing ship off, and the tests of their features find them on (lib/plugins/more/
// more_tools.dart `MoreTools.debugAllOn`); a test of the off state sets it back (test/plugins/more/).

import 'dart:async';

import 'package:ghost_md/plugins/more/more_tools.dart' show MoreTools;
import 'package:ghost_md/plugins/projects/suite.dart' show ProjectSuite;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ProjectSuite.debugAllOn = true;
  MoreTools.debugAllOn = true;
  await testMain();
}
