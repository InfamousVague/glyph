// "Start timer on HT-12" in the palette (lib/commands/palette.dart; Matt, 2026-10-31, time tracking): the open
// ticket's first, any ticket once "timer" or a key is typed, Stop for this device's own, and simple mode keeps them.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/palette.dart';

import 'palette_test.dart' show Calls, doing, n;

void main() {
  const tickets = <PaletteTicket>[(noteId: 'a', key: 'HT-12', title: 'Fix the login'), (noteId: 'b', key: 'HT-13', title: 'Tidy the docs')];

  PaletteDoing timed(Calls calls) {
    final base = doing(calls);
    return PaletteDoing(
      openNote: base.openNote,
      newNote: base.newNote,
      closeTab: base.closeTab,
      showList: base.showList,
      browseNotes: base.browseNotes,
      back: base.back,
      forward: base.forward,
      settings: base.settings,
      chooseWorkspace: base.chooseWorkspace,
      fileNote: base.fileNote,
      setTheme: base.setTheme,
      pin: base.pin,
      archive: base.archive,
      remove: base.remove,
      startTimer: (id) => calls('startTimer $id'),
      stopTimer: () => calls('stopTimer'),
    );
  }

  List<String> labels(List<PaletteCommand> list) => [for (final c in list) if (c.descriptor.group == 'Timers') c.descriptor.label];

  test('the open ticket’s Start, and every ticket’s once timer or a key is typed', () {
    final calls = Calls();
    final world = PaletteWorld(note: n('a', 'Fix the login'), tickets: tickets);
    expect(labels(paletteCommands(world, timed(calls))), ['Start timer on HT-12']);
    expect(labels(paletteCommands(world, timed(calls), 'timer')), ['Start timer on HT-12', 'Start timer on HT-13 Tidy the docs']);
    expect(labels(paletteCommands(const PaletteWorld(tickets: tickets), timed(calls), 'ht-13')), ['Start timer on HT-12 Fix the login', 'Start timer on HT-13 Tidy the docs']);
    paletteCommands(world, timed(calls)).firstWhere((c) => c.descriptor.id == 'timer:start:a').run();
    expect(calls.said, ['startTimer a']);
  });

  test('Stop for the timer running here, in simple mode too; none without timers', () {
    final calls = Calls();
    final world = PaletteWorld(note: n('a', 'Fix the login'), tickets: tickets, timing: tickets.first, simple: true);
    expect(labels(paletteCommands(world, timed(calls))), ['Stop the timer on HT-12']);
    paletteCommands(world, timed(calls)).firstWhere((c) => c.descriptor.id == 'timer:stop').run();
    expect(calls.said, ['stopTimer']);
    expect(labels(paletteCommands(world, doing(calls), 'timer')), isEmpty);
  });
}
