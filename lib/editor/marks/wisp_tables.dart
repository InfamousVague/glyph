/// The bend's noise tables for the marks that are drawn with it (the heat, lib/editor/marks/text_effects.dart; the
/// spoiler was one until it gave way to a blur, 2026-10-24), asked for when a note first shows such a mark and not
/// when its editor is made.
///
/// Each table is a turbulence worked out for a seed (lib/art/wisp_kit.dart), a few milliseconds each, on the UI
/// thread. The smoked words and the text effects asked for all of theirs as their plugins were made, eighteen
/// tables inside the first frame of every note opened, whether or not it had a smoked word in it: 18% of the
/// samples of a note opening on the Mac.
///
/// Now a note with no such mark asks for none. One whose first screen has such a mark asks for all at once, as
/// before, since the marks on screen are waiting for them. One that comes to such a mark later (scrolled to,
/// typed) asks for one table a frame, so no frame waits for all of them. A table not made yet when a letter is
/// drawn is asked for by the letter itself, as it always was (`WispKit.tableNow`), and the letter is its own blur
/// until then.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../../art/wisp_kit.dart';

class WispTables {
  WispTables(this.seeds);

  final List<int> seeds;
  bool _asked = false;

  /// Asks, the first time; later calls do nothing. `atOnce` for marks that are on the screen being made. `ready`
  /// is told when the tables are there, unless `gone` by then.
  void want({required bool atOnce, required bool Function() gone, required void Function() ready}) {
    if (_asked) return;
    _asked = true;
    if (atOnce) {
      unawaited(
        WispKit.load(seeds: seeds).then((_) {
          if (!gone()) ready();
        }, onError: (Object _) {}),
      );
      return;
    }
    unawaited(() async {
      try {
        final kit = await WispKit.load(seeds: const <int>[]);
        for (final seed in seeds) {
          if (gone()) return;
          await SchedulerBinding.instance.endOfFrame;
          await kit.table(seed);
        }
        if (!gone()) ready();
      } catch (_) {
        // No programs here (a test with no shaders): the letters stay their own blur.
      }
    }());
  }
}
