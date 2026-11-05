/// Wrapped (Matt, 2026-11-05: "create a plugin called "Wrapped" which gives you a "ghost markdown wrapped" kinda like
/// spotify wrapped but go through all the notes in the app in the backround slowly with whatever agent is connected
/// detect stale notes, unfinished items which we can chose to check off or remove from the list, suggested
/// reorginizations and more"; docs/WRAPPED.md). A personal plugin, off until added in the Market.
///
/// Where it shows, once added:
/// - **Its page in Settings** (pane.dart): the period, Make or Refresh with its estimate, how far a run is, the story.
/// - **The home page**: its card ([GlyphPlugin.homeCard], home_card.dart), in Simple too.
/// - **The sidebar**: a Wrapped row, and **the bar**: Open my Wrapped ([GlyphPlugin.places]); both open the page
///   (page.dart) with the story and the review.
/// - **The Activity tray**: the pass as a job with Stop, and a foreground service on Android while it reads.
///
/// The parts: stats.dart (the counts), todos.dart (to-dos read and changed), pass.dart (the slow pass and its asks),
/// state.dart (what is kept, in the Library), actions.dart (each press, and Undo), service.dart, story.dart,
/// review.dart, page.dart, home_card.dart, pane.dart. What it borrows: Cleanup's AIs, apply and undo
/// (lib/plugins/cleanup), Note decay alerts' stale pages, the contradiction finder's findings, the Activity's job and
/// cost question.
library;

import 'dart:async';

import '../registry.dart' show pluginOn;
import '../types.dart';
import 'home_card.dart';
import 'manifest.dart';
import 'page.dart';
import 'pane.dart';
import 'service.dart';

export 'actions.dart';
export 'home_card.dart';
export 'manifest.dart';
export 'page.dart';
export 'pane.dart';
export 'pass.dart';
export 'review.dart';
export 'service.dart';
export 'state.dart';
export 'stats.dart';
export 'story.dart';
export 'todos.dart';

/// Whether Wrapped is on.
bool wrappedOn() => pluginOn(wrappedManifest);

String _summary() {
  final service = WrappedService.current;
  if (service == null) return 'Not made yet';
  if (service.running) return 'Making… ${(service.fraction * 100).round()}%';
  return service.state.made ? headlineOf(service.stats()) : 'Not made yet';
}

final GlyphPlugin wrappedPlugin = GlyphPlugin(
  manifest: wrappedManifest,
  icon: 'sparkles',
  settings: PluginSettings(pane: (context) => const WrappedPane(), hue: 'magenta', settings: wrappedFindable, summary: _summary),
  places: [
    PluginPlace(
      id: wrappedId,
      name: 'Wrapped',
      icon: 'sparkles',
      command: 'Open my Wrapped',
      words: 'wrapped year review story recap stats unfinished todos stale tidy',
      open: (context) => unawaited(openWrappedPage(context)),
    ),
  ],
  homeCard: (context) => const WrappedHomeCard(),
);
