import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/ui/space_designs/space_design.dart';

import 'support/space_call_harness.dart';

/// Every space call design (lib/ui/space_designs) draws without fault on a phone and on a computer, in a full call, in
/// a call alone (this device's own level still moving its face), and in a group's channel with no chat; and the
/// switch in Settings › Developer names all seven. Each design's own test (space_design_<name>_test.dart) looks
/// closer. Matt, 2026-11-16: "give me 6 alternate designs for the calling chat and video screens for spaces".
void main() {
  for (final d in SpaceDesign.values.where((d) => d != SpaceDesign.standard)) {
    testWidgets('${d.name}: draws on a phone and a computer, full, alone, and without a chat', (tester) async {
      final h = await SpaceHarness.load(tester);
      addTearDown(tester.view.reset);
      for (final size in [SpaceHarness.phone, SpaceHarness.computer]) {
        await h.shoot(tester, d.page(h.call()), 'smoke-${d.name}', size: size);
        expect(tester.takeException(), isNull);
        await h.shoot(tester, d.page(h.call(people: 0, video: const {})), 'smoke-${d.name}-alone', size: size);
        expect(tester.takeException(), isNull);
        await h.shoot(tester, d.page(h.call(withChat: false)), 'smoke-${d.name}-nochat', size: size);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('each design names the app it is modelled on, says what it looks like, and has a picture', () {
    expect(SpaceDesign.values.length, 7);
    for (final d in SpaceDesign.values) {
      expect(d.label, isNotEmpty);
      expect(d.after, isNotEmpty);
      expect(d.description.length, greaterThan(20));
    }
    expect(SpaceDesign.named('zoom'), SpaceDesign.zoom);
    expect(SpaceDesign.named(''), isNull);
  });
}
