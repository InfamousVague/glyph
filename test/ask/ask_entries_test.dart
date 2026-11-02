// Where Ask is offered (docs/ASK_THE_ORG.md; Matt, 2026-11-02: "'Ask the org' with receipts"): the palette's Ask my
// notes and Ask <organization>, in simple mode too, each opening the sheet on its scope.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/palette.dart';

void main() {
  for (final simple in [false, true]) {
    test('the palette offers Ask my notes and each organization${simple ? ', in simple mode too' : ''}', () {
      final ran = <String>[];
      final doing = PaletteDoing(
        openNote: (_) {},
        newNote: () {},
        closeTab: (_) {},
        showList: () {},
        browseNotes: () {},
        back: () {},
        forward: () {},
        settings: () {},
        chooseWorkspace: (_) {},
        fileNote: (_, _) {},
        setTheme: (_) {},
        pin: (_, _) {},
        archive: (_) {},
        remove: (_) {},
        asks: [(key: 'mine', title: 'Ask my notes', run: () => ran.add('mine')), (key: 'org:o1', title: 'Ask HelloTrade', run: () => ran.add('o1'))],
      );
      final commands = paletteCommands(PaletteWorld(simple: simple), doing);
      final asks = [for (final c in commands) if (c.descriptor.id.startsWith('ask:')) c];
      expect(asks.map((c) => c.descriptor.label), ['Ask my notes', 'Ask HelloTrade']);
      asks.last.run();
      expect(ran, ['o1']);
    });
  }
}
