/// What's new, once, after an update (Matt, 2026-10-30: "Add a changelog popup modal that shows after every update with
/// iconography"): the card that says what changed since the version this device last saw, from the changelog the app
/// carries (changelog.dart).
///
/// Who sees it, and when ([whatsNewVerdict]):
/// - **After an update**: the app starts on a version newer than the last one this device has seen, and the
///   changelog has an entry for the version running. Every release since the last seen is shown, newest first, each
///   under its own heading, at most [whatsNewMost] of them, then "and earlier changes".
/// - **A fresh install sees nothing**: with no version kept and nothing to say the app was used here before, the
///   version running is kept as seen and the card never comes. Used before is the walkthrough's key holding anything
///   (a person who has opened the app since the tour began, any edition of it), or the Mac's word that this launch is
///   the first of a version it put in place itself (`InstalledApp.justUpdated`, the launch screen's "Updated to
///   Ghost.md 2.3.88"); such a device with no version kept is shown the running version's changes alone.
/// - **Once**: the version is kept per device (`glyph-whats-new-seen`) as the card is put away, by Got it, See all
///   changes, the back gesture, Escape or a tap outside it.
/// - **A build that is no release** (a development build's 0.1.0, an iPhone's own numbering) has no entry of its own
///   and shows nothing, keeping nothing.
///
/// It never comes over another moment the person is in (lib/root/root_parts.dart decides, by [WhatsNew.waiting]): the
/// launch screen, the walkthrough, the way into an account, a recording, something shared in, or any sheet (a plugin's
/// setup, the + sheet, a question; [Sheet.shown]). It waits until they are done. Simple mode sees it too.
///
/// The card ([WhatsNewCard]) is the app's own sheet (lib/sheet/sheet.dart): up from the foot of a phone, a card in the
/// middle on the opened Fold and the Mac; its entrance is the sheet's, still where the device asks for less motion.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/ghost.dart';
import '../core/stored.dart';
import '../guide/guide_state.dart' show guideSeenKey;
import '../market/market_cards.dart' show MarketButton, MarketButtonLook;
import '../sheet/css.dart' show pageText;
import '../sheet/sheet.dart';
import '../shell/wide_screen.dart' show wideScreen;
import 'change_look.dart';
import 'changelog.dart';

/// The key the last version seen is kept under.
const String whatsNewSeenKey = 'glyph-whats-new-seen';

/// How many releases the card shows before "and earlier changes".
const int whatsNewMost = 5;

/// What a launch means for What's new: the releases to show (none for nothing), and a version to keep as seen at once
/// (a fresh install's, or one with nothing to say).
typedef WhatsNewVerdict = ({ReleasesSince? show, String? keep});

/// What a device running [running], having last seen [lastSeen] (null for never), is shown.
WhatsNewVerdict whatsNewVerdict({required Changelog changelog, required String? running, required String? lastSeen, required bool usedBefore, int most = whatsNewMost}) {
  if (running == null || changelog.of(running) == null) return (show: null, keep: null);
  if (lastSeen == null) {
    if (!usedBefore) return (show: null, keep: running);
    return (show: (releases: [changelog.of(running)!], more: false), keep: null);
  }
  if (compareVersions(running, lastSeen) <= 0) return (show: null, keep: null);
  final since = changelog.since(lastSeen, running, most: most);
  if (since.releases.isEmpty) return (show: null, keep: running);
  return (show: since, keep: null);
}

/// Whether this device's storage says the app was opened here before: the walkthrough's key holds anything.
bool usedBeforeOn(Stored store) => store.readText(guideSeenKey) != null;

/// This device's What's new: what waits to be shown, and the version kept as seen.
class WhatsNew extends ChangeNotifier {
  /// [usedBefore] is read from [store] where not given, as the app starts and before the walkthrough writes anything;
  /// [justUpdated] is the Mac's word that this launch is a new version's first. [runningVersion] is the version the
  /// app is taken to run, over what the phone says: a test's.
  WhatsNew({Stored? store, bool? usedBefore, bool justUpdated = false, this.runningVersion}) : _store = store ?? stored {
    _usedBefore = justUpdated || (usedBefore ?? usedBeforeOn(_store));
  }

  final Stored _store;
  final String? runningVersion;
  late bool _usedBefore;
  bool _up = false;
  String? _settled;
  String? _running;
  ReleasesSince? _waiting;

  /// The last version this device saw, or null.
  String? get lastSeen => _store.readText(whatsNewSeenKey);

  /// What waits to be shown: null for nothing.
  ReleasesSince? get waiting => _waiting;

  /// The version the card is about.
  String? get running => _running;

  /// Whether the card is up: raised once nothing was in its way, and up until it is put away, whatever comes over it.
  bool get up => _up;

  /// Up, where something waits.
  void raise() {
    if (_up || _waiting == null) return;
    _up = true;
    notifyListeners();
  }

  /// Told the version running and the changelog: decided once per version. A launch learns its version late on a
  /// phone (the package manager answers after the first frame), so the root tells it again as that arrives; the Mac's
  /// [justUpdated] may come with it.
  void settle({required Changelog changelog, required String? running, bool justUpdated = false}) {
    if (justUpdated) _usedBefore = true;
    if (running == null || running == _settled) return;
    final verdict = whatsNewVerdict(changelog: changelog, running: running, lastSeen: lastSeen, usedBefore: _usedBefore);
    if (verdict.show == null && changelog.of(running) == null) return;
    _settled = running;
    _running = running;
    final keep = verdict.keep;
    if (keep != null) _store.writeText(whatsNewSeenKey, keep);
    _waiting = verdict.show;
    notifyListeners();
  }

  /// Put away: the version running is seen, and nothing waits.
  void seen() {
    final running = _running;
    if (running != null) _store.writeText(whatsNewSeenKey, running);
    if (_waiting == null && !_up) return;
    _waiting = null;
    _up = false;
    notifyListeners();
  }
}

/// The card: "What's new in Ghost.md 2.3.88", the ghost with its parcel, each release's lines, Got it and See all
/// changes. [onClose] is every way it is put away; [onSeeAll] the full Changelog page.
class WhatsNewCard extends StatelessWidget {
  const WhatsNewCard({super.key, required this.version, required this.releases, this.more = false, required this.onClose, this.onSeeAll});

  final String version;
  final List<Release> releases;
  final bool more;
  final VoidCallback onClose;
  final VoidCallback? onSeeAll;

  static const Key gotItKey = ValueKey('whats-new:got-it');
  static const Key seeAllKey = ValueKey('whats-new:see-all');
  static const Key earlierKey = ValueKey('whats-new:earlier');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = "What's new in Ghost.md $version";
    final one = releases.length == 1;
    final subtitle = one ? releases.first.title : '${releases.length} updates since you last looked';
    final seeAll = onSeeAll;
    final wide = wideScreen(MediaQuery.sizeOf(context));
    // The window less the keyboard, as the sheet measures it.
    final height = MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom;
    final centred = wide || t.attrs['platform'] == 'desktop';
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Sheet(
        key: const ValueKey('whats-new'),
        label: title,
        onClose: onClose,
        // A card in the middle wherever the window is wide (the opened Fold, a tablet, the Mac); a drawer on a phone.
        centred: wide ? true : null,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 44, child: Ghost(scene: GhostScene.update, size: GhostSize.tiny, align: GhostAlign.center)),
              SizedBox(width: t.space(3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(header: true, child: Text(title, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('glacier-text'), height: 1.3))),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle'))),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: t.space(2)),
          // The lines scroll by themselves under the heading, so Got it is always in reach however many releases there
          // are: the heading and the actions take some 15rem of the sheet's height, the lines the rest.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(t.lenOf('8rem'), (centred ? math.min(height * 0.82, t.lenOf('48rem')) : height * 0.85) - t.lenOf('15rem'))),
            child: SingleChildScrollView(
              key: const ValueKey('whats-new:lines'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final release in releases) ...[
                    if (!one) ReleaseHeading(release: release, running: release.version == version),
                    for (final item in release.items) ChangeLine(item: item),
                  ],
                  if (more)
                    Padding(
                      padding: EdgeInsets.only(top: t.space(1), left: 34 + t.space(3)),
                      child: GlacierPressable(
                        key: earlierKey,
                        onPressed: seeAll,
                        semanticLabel: 'And earlier changes',
                        builder: (context, state) => Text('…and earlier changes', style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle'))),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: t.space(4)),
          Row(
            children: [
              if (seeAll != null)
                GlacierPressable(
                  key: seeAllKey,
                  onPressed: seeAll,
                  semanticLabel: 'See all changes',
                  builder: (context, state) => Padding(
                    padding: EdgeInsets.symmetric(vertical: t.space(2)),
                    child: Text(
                      'See all changes',
                      style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color(state.hovered || state.pressed ? 'glacier-text' : 'glacier-text-muted')).copyWith(decoration: TextDecoration.underline),
                    ),
                  ),
                ),
              const Spacer(),
              MarketButton(key: gotItKey, label: 'Got it', onPress: onClose, look: MarketButtonLook.ink, large: true),
            ],
          ),
        ],
      ),
    );
  }
}
