/// The walkthrough's place in the app: whether it is up, the page it is on, and whether it is saying "Not yet,
/// finish reading." A port of `src/app/shell/useGuide.ts`, which is the Shell's half of the guide: it decides when
/// the guide opens by itself and what a launch in the middle of it means.
///
/// It opens by itself once, on the first launch that is not a side-key capture: a person who held the key is
/// already mid-sentence. After that it is opened from Settings, the palette or the Academy, and seen for good when
/// it is closed. While it is up, the page it is on is kept (too_soon.dart), so a relaunch can tell it came too
/// soon: the guide comes up again with its "Not yet" line, and the key's recording does not start.
///
/// What differs: a hook's state is this notifier's fields. It is made once the device's storage has been read
/// (lib/core/stored.dart [stored]), since what it reads as it is made is what a launch means; and it lives here,
/// beside the guide, where the page keeps it with the shell.
library;

import 'package:flutter/foundation.dart';

import '../core/stored.dart';
import 'too_soon.dart';

/// The key that says the guide was seen (`glyph-guide-seen`).
const String guideSeenKey = 'glyph-guide-seen';

/// What the key holds once this walkthrough is seen: the tour's edition. The colourful, narrated tour of 2026-10-27
/// is the second; the first's `1` reads as not seen, so it opens once for everyone who has not been through it, an
/// account or not (Matt, 2026-10-28: "if someone hasn't seen the onboarding flow yet. Show them it even if they
/// already have an account").
const String guideSeenValue = '2';

/// Whether this walkthrough was seen. No storage: showing it every launch would be worse than never.
StoredFlag guideSeen() => stored.flag(guideSeenKey, value: guideSeenValue, unreadable: true);

StoredFlag _seen() => guideSeen();

/// `GuideState`, with `useGuide(launchedByKey)` as its constructor.
class GuideController extends ChangeNotifier {
  /// [launchedByKey]: the side key launched this run of the app.
  GuideController({bool launchedByKey = false}) {
    tooSoonAtBoot = launchedTooSoon(_seen().isMarked);
    _open = !_seen().isMarked && (!launchedByKey || tooSoonAtBoot);
    _tooSoon = tooSoonAtBoot;
    _keep();
  }

  /// This launch came while the guide was left on a reading page: it is the guide's, and a side key's recording
  /// waits.
  late final bool tooSoonAtBoot;
  bool _open = false;
  bool _tooSoon = false;
  int _page = 0;

  bool get open => _open;
  int get page => _page;

  /// "Not yet, finish reading.": a relaunch, or the side key, while the guide was still on a reading page.
  bool get tooSoon => _tooSoon;

  /// Where the guide is, kept for a relaunch; gone once it is finished.
  void _keep() {
    if (!_open) return;
    markGuideStarted();
    rememberGuidePage(_page);
  }

  void _told() {
    _keep();
    notifyListeners();
  }

  /// Up, at [page] (`show`).
  void show([int page = 0]) {
    _page = page;
    _open = true;
    _told();
  }

  /// To [page], from the guide's own arrows: the too-soon line has been read (`turn`).
  void turn(int page) {
    _page = page;
    _tooSoon = false;
    _told();
  }

  /// Closed and seen: it will not open by itself again, and its progress goes (`close`). Not kept, it is seen for
  /// this run, at least.
  void close() {
    _seen().mark();
    clearGuideProgress();
    _open = false;
    notifyListeners();
  }

  /// Closed without being seen: the side key clearing the stage for a recording (`hide`).
  void hide() {
    _open = false;
    notifyListeners();
  }

  /// The side key pressed now would be too soon: the guide is up on a page still to be read (`onReadingPage`).
  bool onReadingPage() => _open && isReadingPage(_page);

  /// Say "Not yet" at the top of the guide (`sayTooSoon`).
  void sayTooSoon() {
    _tooSoon = true;
    notifyListeners();
  }
}
