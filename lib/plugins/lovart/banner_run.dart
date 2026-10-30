/// Header images for the recent notes, as a job of the app's own (Matt, 2026-10-26: "add the banner to 100 of the
/// most recent notes that are not tickets or meetings"; then "Make the header generation async and a background task
/// that runs while the app is generating the images").
///
/// Settings › Lovart's Make them starts it; nothing of it is the page's. One [BannerJob], made by the app's root as the
/// summary queue is (lib/root/ghost_root.dart, beside lib/ai/summaries.dart's), runs it and is told Stop, wherever it
/// was pressed: the page, the line on the home page and in the sidebar (lib/notes/notices.dart `JobNotice`), or the
/// phone's notification. The person leaves Settings, opens notes and types while the pictures are made.
///
/// THE RUN. The [bannerRunMost] most recently changed notes that are ones to have a banner and were never given one
/// ([bannerCandidates]), [bannerRunAtOnce] asked of Lovart at a time, each by [LovartBanners.make], the maker a note
/// left uses too. Nothing waits on the page: each picture is fetched and kept off the frames, and is written into
/// its note by the root's writer, which hands it to the note's editor while the note is open (an edit of its front
/// matter, so what is being typed stays) and writes it where it is kept otherwise ([LovartBanners.write]).
/// Credits spent, keys refused, a costly step waiting, or pictures with nowhere to go stop the rest, and say why;
/// Lovart declining one note goes on, and that note is counted skipped.
///
/// TWO CHOICES FOR A RUN, on the page beside Make them, for that run alone (Matt, 2026-10-26: "remove the header banner
/// images on the docs as we will regenerate them"; [bannerAsks]):
/// - **Include notes whose header was taken off**: a note given one before is marked given (banners.dart), so a run
///   never picked it again once its banner went. With this it is asked again, where it is still a note to have one.
/// - **Redo black-and-white headers in colour**: the banners made before they were made in colour (the picture read
///   as lib/note/note_banner.dart reads it, `bannerInColour`) are made again and put in their place; one changed
///   meanwhile stands.
/// Leaving a note asks neither: there a banner is made once per note, and one taken off on purpose stays off.
///
/// KEPT AS IT GOES, in the plugin's storage on this device ([bannerRunKey]; the summary queue's pattern, a job kept
/// in the device's memory so one the app did not finish runs at the next launch): the notes left, the ones being
/// made now, and how many were made and skipped, written as each note starts and as each is done. A run the app was
/// closed or killed under is found there at launch ([BannerJob.resume]) and goes on from where it was: the notes
/// being made when it went are asked for again (taken off the list of notes given one, which they were put on
/// before Lovart was asked), the ones done are not. It waits for the plugin to be on and its keys to be read. A run
/// that ends, however it ends, takes its queue with it: one stopped for credits starts again from Make them, whose
/// notes are then the ones it did not reach.
///
/// IN THE BACKGROUND. While it runs the app tells the phone (lib/core/background_jobs.dart, `ghost_md/jobs`):
/// - **on Android** a foreground service holds the app up, as the meeting's recording and write-up are held up
///   (android/…/ghost_md/BackgroundJobs.kt), with a partial wake lock, so the run goes on with the screen off or the
///   app behind another; its notification says "Making header images", how far it is, with Stop. When it ends that
///   notification goes and one says what was made, as a meeting's "Written up" does. Swiped out of the recents, the
///   app is gone with its run: the notification says it goes on when Ghost.md opens, and it does.
/// - **on the Mac** the app is kept out of App Nap while it runs (macos/Runner/MainFlutterWindow.swift), so its
///   timers and its fetches are not slowed with the window behind others. The Mac app quits with its window, and a
///   run it quit under goes on at the next launch.
///
/// ONE AT A TIME. On this device the job runs one run, and Make them while it runs does nothing more. Across the
/// account's devices, a run is claimed in the synced settings before it starts ([BannerClaims], on the handoff's
/// pattern, lib/ai/summary_handoff.dart): the claim, `{by, name, at, done, total}`, written, a sync run, and only a
/// claim the account then holds as this device's lets the run go on. It is live for [bannerClaimMs] from when it was
/// made or last renewed, and renewed as the run goes ([bannerRenewMs] at most), so a device that died mid-run holds
/// the others off for minutes, not for ever; it is let go when the run ends. Make them on another device while it is
/// live says where they are being made and how far that is. Two devices that claim at once: the account refuses the
/// second one's stale write, and its merge keeps the live claim it finds over its own ([chosenBannerClaim]). A device
/// that syncs nothing (signed out, Local only) claims only for itself.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/summary_handoff.dart' show SummaryDevice;
import '../../core/background_jobs.dart';
import '../../core/note.dart' show Note;
import '../../core/preferences.dart' show Preferences;
import '../host.dart' show onPluginStorage;
import '../registry.dart' show pluginOn;
import '../types.dart';
import '../../core/banner.dart' show bannerOf;
import '../../core/book.dart' show chaptersOf, isBookBody, isJournalBody;
import '../../core/note_text.dart' show noteTitle;
import '../../core/title_key.dart' show titleKey;
import 'banners.dart';
import 'client.dart';
import 'manifest.dart';

/// How many recent notes a run gives banners to, and how many Lovart is asked for at once.
const int bannerRunMost = 100;
const int bannerRunAtOnce = 3;

/// How long a worker waits when Lovart has no room for another job, times how many times running it had none (at most
/// four), and how many refusals running, at one at a time, stop the run.
const Duration bannerBusyWait = Duration(seconds: 20);
const int bannerBusyMost = 12;

/// The job's name to the phone (lib/core/background_jobs.dart).
const String bannerJobId = 'lovart-banners';

/// The [most] most recently changed notes that are ones to have a banner and were never given one, newest first.
List<Note> bannerCandidates(List<Note> notes, {int most = bannerRunMost, PluginHost? via}) {
  final done = bannersGiven(via).toSet();
  final sorted = [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [for (final note in sorted) if (!done.contains(note.id) && wantsBanner(note)) note].take(most).toList();
}

/// The notes given a banner before whose banner is not there now, still ones to have one, newest first: the ones
/// Include notes whose header was taken off adds.
List<Note> bannerTakenOff(List<Note> notes, {int most = bannerRunMost, PluginHost? via}) {
  final done = bannersGiven(via).toSet();
  final sorted = [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [for (final note in sorted) if (done.contains(note.id) && wantsBanner(note)) note].take(most).toList();
}

/// What one note of a run is asked for: a banner where it has none, made [again] although it is marked given (one
/// taken off, or a page of a notebook asked for by name), or one made anew [replacing] the banner of that name.
typedef BannerAsk = ({String id, bool again, String? replacing});

/// Whether a banner, read as lib/note/note_banner.dart reads it (`BannerLook`), is one to make again when asked: black
/// and white (made before banners were in colour), or square (Lovart's first ones, 1254×1254, drawn into a strip with
/// most of each cut off): narrower than [bannerRedoNarrower] to its height.
bool bannerToRedo({required bool colour, required double aspect}) => !colour || aspect < bannerRedoNarrower;

/// A banner narrower than this, width over height, is square enough to make again: between a square and 16:9.
const double bannerRedoNarrower = 1.5;

Future<bool> _redoes(Future<bool> Function(String name) redo, String name) async {
  try {
    return await redo(name);
  } catch (_) {
    // A picture that cannot be read is left as it is.
    return false;
  }
}

/// A run's notes as Make them picks them, newest first, at most [most] (Matt, 2026-10-26: "add the banner to 100 of
/// the most recent notes that are not tickets or meetings"; then "remove the header banner images on the docs as we
/// will regenerate them"): the notes never given one ([bannerCandidates]); with [takenOff], the ones given one before
/// whose banner is not there now, which leaving a note never makes again; and with [redo] (whether the banner of that
/// name is one to make again: [bannerToRedo], read from the picture by the root), the ones whose banner is black and
/// white or square. Each must still be a note to have one.
Future<List<BannerAsk>> bannerAsks(List<Note> notes, {bool takenOff = false, Future<bool> Function(String name)? redo, int most = bannerRunMost, PluginHost? via}) async {
  final done = bannersGiven(via).toSet();
  final sorted = [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final asks = <BannerAsk>[];
  for (final note in sorted) {
    if (asks.length >= most) break;
    final banner = bannerOf(note.body);
    if (banner == null) {
      if (!wantsBanner(note)) continue;
      if (!done.contains(note.id)) {
        asks.add((id: note.id, again: false, replacing: null));
      } else if (takenOff) {
        asks.add((id: note.id, again: true, replacing: null));
      }
    } else if (redo != null && wantsBanner(note, replacing: true) && await _redoes(redo, banner)) {
      asks.add((id: note.id, again: true, replacing: banner));
    }
  }
  return asks;
}

// ---- a notebook's pages -------------------------------------------------------------------------------------------

/// The pages of the notebook [book], in its index's order (Matt, 2026-10-26: "Also add a feature to add header images
/// to all pages in a book"): each chapter's note, the ones indented under a chapter with them, and the pages of a
/// notebook that is itself a chapter, once each. A chapter is found by its title among [notes], one in the same
/// organization as the notebook first (a team's notebook lists the team's pages). Not the notebook itself, and none
/// in the archive.
List<Note> bookPages(Note book, List<Note> notes, {List<Note>? notebooks}) {
  String orgOf(Note note) {
    final path = note.path ?? '';
    if (!path.startsWith('orgs/')) return '';
    final cut = path.indexOf('/', 5);
    return cut < 0 ? path : path.substring(0, cut);
  }

  final byTitle = <String, List<Note>>{};
  for (final note in notes) {
    if (note.archivedAt != null) continue;
    byTitle.putIfAbsent(titleKey(noteTitle(note.body)), () => []).add(note);
  }
  final pages = <Note>[];
  final seen = <String>{book.id};
  void walk(Note from, int depth) {
    final here = orgOf(from);
    for (final chapter in chaptersOf(from.body)) {
      final found = byTitle[titleKey(chapter.title)] ?? const <Note>[];
      if (found.isEmpty) continue;
      final note = found.firstWhere((n) => orgOf(n) == here, orElse: () => found.first);
      if (!seen.add(note.id)) continue;
      // A notebook that is a chapter: its pages, in its own order, a level or two down at most.
      if (isBookBody(note.body) && !isJournalBody(note.body)) {
        notebooks?.add(note);
        if (depth < 2) walk(note, depth + 1);
        continue;
      }
      pages.add(note);
    }
  }

  walk(book, 0);
  return pages;
}

/// Everything of a notebook that has a banner: its own index first (its cover), the index of each notebook that is one
/// of its chapters, then its pages ([bookPages]).
List<Note> bookBannerNotes(Note book, List<Note> notes) {
  final notebooks = <Note>[];
  final pages = bookPages(book, notes, notebooks: notebooks);
  return [book, ...notebooks, ...pages];
}

/// What "Header images for every page" asks of a notebook's pages ([bookPages]): every page that is one to have a
/// banner and has none, whatever the once-per-note marks say, since the person asked for these by name; with [redo],
/// the ones whose banner is black and white or square, made again; with [redoAll], every one that has a banner. A
/// ticket, a meeting, a mail, a canvas, a template or a short page is left as it is ([wantsBanner]).
Future<List<BannerAsk>> bookBannerAsks(Note book, List<Note> notes, {Future<bool> Function(String name)? redo, bool redoAll = false}) async {
  final asks = <BannerAsk>[];
  for (final page in bookBannerNotes(book, notes)) {
    if (!wantsBanner(page, replacing: true)) continue;
    final banner = bannerOf(page.body);
    if (banner == null) {
      asks.add((id: page.id, again: true, replacing: null));
    } else if (redoAll || (redo != null && await _redoes(redo, banner))) {
      asks.add((id: page.id, again: true, replacing: banner));
    }
  }
  return asks;
}

/// The counts a notebook's action says before it starts: its pages to have a banner with none, and those with one.
({int missing, int existing}) bookBannerCounts(Note book, List<Note> notes) {
  var missing = 0, existing = 0;
  for (final page in bookBannerNotes(book, notes)) {
    if (!wantsBanner(page, replacing: true)) continue;
    if (bannerOf(page.body) == null) {
      missing += 1;
    } else {
      existing += 1;
    }
  }
  return (missing: missing, existing: existing);
}

// ---- where it stands ----------------------------------------------------------------------------------------------

/// Where a run over the recent notes stands: how many it set out to make, how many are done, how many came back with
/// a banner, and why it stopped where it stopped early. What the page, the line and the notification draw.
@immutable
class BannerRun {
  const BannerRun({required this.total, this.done = 0, this.made = 0, this.running = true, this.stopped, this.asked = false, this.elsewhere});
  final int total;

  /// The notes finished, made or skipped. One a stop put back to be tried again is not among them.
  final int done;
  final int made;
  final bool running;

  /// Why it ended before its last note, in a sentence ("Your Lovart credits have run out."), or null.
  final String? stopped;

  /// Ended by the person's Stop.
  final bool asked;

  /// Not started here because another of the account's devices is making them: that device's claim.
  final BannerClaim? elsewhere;

  /// The notes Lovart made none for, or that were no longer ones to have one.
  int get skipped => done - made;

  BannerRun next({int? done, int? made, bool? running, String? stopped, bool? asked}) =>
      BannerRun(total: total, done: done ?? this.done, made: made ?? this.made, running: running ?? this.running, stopped: stopped ?? this.stopped, asked: asked ?? this.asked);
}

/// The run on this device, if one has been since the app started: the page, the line and the notification draw it.
final ValueNotifier<BannerRun?> lovartBannerRun = ValueNotifier<BannerRun?>(null);

String _notes(int n) => n == 1 ? '1 note' : '$n notes';

/// The line while it runs, on the home page, in the sidebar and in the notification's title and text:
/// "Making header images · 12 of 100".
String bannerRunLine(BannerRun run) => 'Making header images · ${run.done} of ${run.total}${run.made > 0 ? ' · ${aboutCredits(run.made)}' : ''}';

/// What is said as it ends, in the toast and the notification: "Header images made for 97 notes · 3 skipped", or
/// where it stopped and why.
String bannerRunEndWords(BannerRun run) {
  final skipped = run.skipped > 0 ? ' · ${run.skipped} skipped' : '';
  if (run.stopped != null && !run.asked) return 'Header images stopped at ${run.done} of ${run.total}: ${run.stopped}';
  if (run.asked) return 'Header images stopped · ${run.made} made$skipped${run.made > 0 ? ' · ${aboutCredits(run.made)}' : ''}';
  if (run.total == 0) return 'Every recent note has a header image already, or is not one to have one.';
  return 'Header images made for ${_notes(run.made)}$skipped${run.made > 0 ? ' · ${aboutCredits(run.made)}' : ''}';
}

/// What a claim of another device's says where Make them is pressed here.
String bannerElsewhereWords(BannerClaim claim) => 'Header images are being made on your ${claim.name.isEmpty ? 'other device' : claim.name} · ${claim.done} of ${claim.total}.';

// ---- the queue, kept ----------------------------------------------------------------------------------------------

/// A run as it is kept ([bannerRunKey]): the notes left in order, the ones among them being made now, and the
/// counts so far.
@immutable
class BannerQueue {
  const BannerQueue({required this.total, required this.left, this.going = const [], this.made = 0, this.skipped = 0, this.again = const [], this.replacing = const {}});

  final int total;

  /// The notes not finished yet, in the run's order: the ones being made stay here until they are.
  final List<String> left;

  /// The ones Lovart was being asked for as this was written.
  final List<String> going;
  final int made;
  final int skipped;

  /// Of [left], the notes asked again although they were given one before (a banner taken off, or one to redo in
  /// colour), and of those, the black-and-white banner each replaces, by note.
  final List<String> again;
  final Map<String, String> replacing;

  /// What [id] is asked for.
  BannerAsk ask(String id) => (id: id, again: again.contains(id) || replacing.containsKey(id), replacing: replacing[id]);

  Map<String, Object?> toJson() => {'total': total, 'left': left, 'going': going, 'made': made, 'skipped': skipped, if (again.isNotEmpty) 'again': again, if (replacing.isNotEmpty) 'replacing': replacing};

  /// A queue as kept, or null for anything that is not one.
  static BannerQueue? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int n(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
    List<String> ids(Object? v) => v is List ? [for (final id in v) if (id is String) id] : const [];
    final left = ids(raw['left']);
    final total = n(raw['total']);
    if (raw['left'] is! List || total <= 0) return null;
    final replacing = raw['replacing'];
    return BannerQueue(
      total: total,
      left: left,
      going: ids(raw['going']),
      made: n(raw['made']),
      skipped: n(raw['skipped']),
      again: ids(raw['again']),
      replacing: replacing is Map ? {for (final MapEntry(:key, :value) in replacing.entries) if (key is String && value is String) key: value} : const {},
    );
  }
}

/// The run this device was making when the app last went, if it had one.
BannerQueue? keptBannerQueue([PluginHost? via]) => BannerQueue.fromJson((via ?? host).storage.get<Object?>(bannerRunKey, null));

// ---- across the account's devices ---------------------------------------------------------------------------------

/// The synced setting a run is claimed in, in [Preferences.more] (see the header).
const String bannerClaimKey = 'lovartBannerRun';

/// How long a claim holds without being renewed, and how often the device running renews it, at most.
const int bannerClaimMs = 10 * 60000;
const int bannerRenewMs = 2 * 60000;

/// One device's run, as the synced settings carry it.
@immutable
class BannerClaim {
  const BannerClaim({required this.by, this.name = '', required this.at, this.done = 0, this.total = 0});

  final String by;
  final String name;
  final int at;
  final int done;
  final int total;

  static BannerClaim? fromJson(Object? raw) {
    if (raw is! Map || raw['by'] is! String) return null;
    int n(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
    return BannerClaim(by: raw['by'] as String, name: raw['name'] is String ? raw['name'] as String : '', at: n(raw['at']), done: n(raw['done']), total: n(raw['total']));
  }

  Map<String, Object?> toJson() => {'by': by, 'name': name, 'at': at, 'done': done, 'total': total};

  /// Whether it holds at [now].
  bool liveAt(int now) => now - at < bannerClaimMs;
}

/// The claim the settings hold, if any.
BannerClaim? bannerClaimOf(Preferences prefs) => BannerClaim.fromJson(prefs.more[bannerClaimKey]);

Preferences _withClaim(Preferences prefs, BannerClaim? claim) {
  final more = {...prefs.more};
  if (claim == null) {
    more.remove(bannerClaimKey);
  } else {
    more[bannerClaimKey] = claim.toJson();
  }
  return prefs.copyWith(more: more);
}

/// Which of two devices' claims stands where both changed it since they last agreed (lib/sync/prefs.dart `merged`):
/// a live claim the account already held for another device, over this device's own or its letting go; else this
/// device's.
Object? chosenBannerClaim(Object? mine, Object? theirs, {int? now}) {
  final t = BannerClaim.fromJson(theirs);
  if (t == null) return mine;
  final m = BannerClaim.fromJson(mine);
  if (t.liveAt(now ?? DateTime.now().millisecondsSinceEpoch) && t.by != m?.by) return theirs;
  return mine;
}

/// A run claimed for this device in the synced settings (see the header).
class BannerClaims {
  BannerClaims({required this.device, required this.preferences, required this.setPreferences, required this.syncNow, this.accountHeld, int Function()? clock, void Function(String message)? warn})
      : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        warn = warn ?? debugPrint;

  final SummaryDevice Function() device;
  final Preferences Function() preferences;
  final void Function(Preferences Function(Preferences now) change) setPreferences;

  /// A sync now, waited for; its failure is no throw.
  final Future<void> Function() syncNow;

  /// The synced settings as the account holds them; null, or none given, where this device syncs nothing, and then
  /// no other device can see a claim, so the run is this device's to make.
  final Map<String, Object?>? Function()? accountHeld;
  final int Function() clock;
  final void Function(String message) warn;

  int _renewed = 0;

  /// Another device's live claim, if one holds.
  BannerClaim? elsewhere() {
    final claim = bannerClaimOf(preferences());
    if (claim == null || claim.by == device().id || !claim.liveAt(clock())) return null;
    return claim;
  }

  /// Claims the run for this device: null where it is this device's to make, else why not, in a sentence.
  Future<String?> claim({required int done, required int total}) async {
    final other = elsewhere();
    if (other != null) return bannerElsewhereWords(other);
    final me = device();
    final now = clock();
    final mine = BannerClaim(by: me.id, name: me.name, at: now, done: done, total: total);
    setPreferences((prefs) {
      final was = bannerClaimOf(prefs);
      if (was != null && was.by != me.id && was.liveAt(now)) return prefs;
      return _withClaim(prefs, mine);
    });
    _renewed = now;
    if (accountHeld == null || accountHeld!() == null) return null;
    try {
      await syncNow();
    } catch (failure) {
      warn('[lovart] the header images could not be claimed: $failure');
    }
    final held = accountHeld?.call();
    if (held == null) return null;
    final said = BannerClaim.fromJson(held[bannerClaimKey]);
    if (said != null && said.by == me.id) return null;
    if (said != null && said.liveAt(clock())) return bannerElsewhereWords(said);
    return 'Ghost.md could not check with your other devices. Try again once you are online.';
  }

  /// The claim kept live, with how far the run is: once it is [bannerRenewMs] old.
  void renew({required int done, required int total}) {
    final now = clock();
    if (now - _renewed < bannerRenewMs) return;
    _renewed = now;
    final me = device();
    setPreferences((prefs) {
      final was = bannerClaimOf(prefs);
      if (was != null && was.by != me.id && was.liveAt(now)) return prefs;
      return _withClaim(prefs, BannerClaim(by: me.id, name: me.name, at: now, done: done, total: total));
    });
  }

  /// The run ended here: the claim let go, where it is still this device's.
  void release() {
    final me = device().id;
    setPreferences((prefs) => bannerClaimOf(prefs)?.by == me ? _withClaim(prefs, null) : prefs);
  }
}

// ---- the job ------------------------------------------------------------------------------------------------------

/// The app's one run over the recent notes (see the header): made by the root, and handed to [lovartBannerJob].
class BannerJob {
  BannerJob({required this.notes, required this.banners, this.claims, BackgroundJobs? background, this.redo, this.ended, Future<void> Function(Duration wait)? wait, PluginHost? via})
      : background = background ?? const NoBackgroundJobs(),
        _wait = wait ?? _sleep,
        _host = via {
    this.background.onStop((id) {
      if (id == bannerJobId) stop();
    });
  }

  /// The library's notes now.
  final List<Note> Function() notes;

  /// The maker, with the root's writer.
  final LovartBanners banners;

  /// The claim across the account's devices; none claims only for this device.
  final BannerClaims? claims;

  /// The phone's half: the service and its notifications, the Mac's hold.
  final BackgroundJobs background;

  /// Whether the banner of that name is one to make again when asked ([bannerToRedo], read from the kept picture by
  /// the root, lib/note/note_banner.dart `bannerLook`); none, and nothing is redone but by [start]'s `asks`.
  final Future<bool> Function(String name)? redo;

  /// Told as a run ends, however it ends: the root's toast.
  final void Function(BannerRun run)? ended;
  final PluginHost? _host;

  /// How a worker waits for Lovart to have room: a timer, or a test's own.
  final Future<void> Function(Duration wait) _wait;
  static Future<void> _sleep(Duration wait) => Future<void>.delayed(wait);

  PluginHost get _on => _host ?? host;

  bool _running = false;
  bool _stop = false;
  bool _gone = false;
  VoidCallback? _unhear;

  /// Whether the run going now was asked for by the person ([start]) rather than picked up at launch ([resume]); and
  /// the notebook it is for, where it is one's.
  bool _asked = false;
  String? _book;

  /// The same run asked for again: a stopped run's Retry.
  Future<String?> Function()? _again;

  /// A stopped run's one fix (docs/ACTIVITY.md, Failures): Top up where Lovart said the plan or the credits do not
  /// cover it, Open Lovart where its agent wants a go-ahead there, Sign in again where the keys were refused or are
  /// gone, and otherwise Retry, the same run again from where it stopped.
  JobFix bannerFix(LovartFailure? failure) {
    if (failure != null && (failure.status == 402 || failure.code == 2012)) return activityRoutes.topUp(Uri.parse(lovartBillingUrl));
    if (failure is LovartNeedsConfirmation) return JobFix(JobFixKind.open, () => activityRoutes.openLink?.call(Uri.parse(lovartBillingUrl)), label: 'Open Lovart');
    if ((failure?.badKeys ?? false) || !hasLovartKeys(_host)) return activityRoutes.signIn(manifest.id);
    final again = _again;
    return JobFix(JobFixKind.retry, () {
      if (again != null) unawaited(again());
    });
  }

  /// Whether a run is going on this device now.
  bool get running => _running;

  /// Another device's live claim on a run, if one holds.
  BannerClaim? elsewhere() => claims?.elsewhere();

  /// Tells the app's record of running work of another device's live claim on a run (docs/ACTIVITY.md, Other
  /// devices): its job, dimmed in the ring, "on your Mac" in the tray, as far as it last said. Asked as the settings
  /// change, where claims arrive.
  void tellElsewhere() => activity.elsewhere(bannerClaimJobsSource, bannerJobsElsewhere(elsewhere()));

  /// Stops the run after the pictures being made now.
  void stop() => _stop = true;

  /// Waits [wait], or less where the run is stopped meanwhile.
  Future<void> _waitFor(Duration wait) async {
    const step = Duration(seconds: 1);
    var waited = Duration.zero;
    while (waited < wait && !_stop && !_gone) {
      final next = wait - waited < step ? wait - waited : step;
      await _wait(next);
      waited += next;
    }
  }

  /// What says a run cannot start here, or null.
  String? _unready() {
    if (!pluginOn(manifest)) return 'Lovart is off.';
    return bannerUnready();
  }

  /// Make them: a run over the recent notes ([bannerAsks]), with the notes whose banner was [takenOff] and, with
  /// [redoOld], the black-and-white and square banners made again where the job was told how to tell ([redo]); or
  /// over [asks] where given (a notebook's pages, [bookBannerAsks]). Answers why it did not start, or null where it
  /// did (or one was already going, which it leaves be).
  Future<String?> start({bool takenOff = false, bool redoOld = false, List<BannerAsk>? asks, String? book}) async {
    if (_running) return null;
    _running = true;
    // Asked for by the person (Settings' Make them, a notebook's More): its end chimes where it ran a while, and a
    // notebook's run opens the notebook from its chip.
    _asked = true;
    _book = book;
    _again = () => start(takenOff: takenOff, redoOld: redoOld, asks: asks, book: book);
    try {
      final unready = _unready();
      if (unready != null) {
        lovartBannerRun.value = BannerRun(total: 0, running: false, stopped: unready);
        return unready;
      }
      final queue = asks ?? await bannerAsks(notes(), takenOff: takenOff, redo: redoOld ? redo : null, via: _host);
      if (queue.isEmpty) {
        final run = lovartBannerRun.value = const BannerRun(total: 0, running: false);
        ended?.call(run);
        return null;
      }
      final refused = await claims?.claim(done: 0, total: queue.length);
      if (refused != null) {
        lovartBannerRun.value = BannerRun(total: 0, running: false, stopped: refused, elsewhere: elsewhere());
        return refused;
      }
      await _run(BannerQueue(
        total: queue.length,
        left: [for (final ask in queue) ask.id],
        again: [for (final ask in queue) if (ask.again && ask.replacing == null) ask.id],
        replacing: {for (final ask in queue) if (ask.replacing != null) ask.id: ask.replacing!},
      ));
      return null;
    } finally {
      _running = false;
    }
  }

  /// At launch: a run the app went under goes on from its kept queue, once the plugin is on and its keys are read;
  /// until then it waits, hearing the plugins and their storage. Nothing where none is kept.
  Future<void> resume({Listenable? changes}) async {
    if (_running || keptBannerQueue(_host) == null) return;
    try {
      await _on.secrets.warm();
    } catch (_) {
      // Read as they come.
    }
    if (_gone) return;
    if (_unready() == null) return _resumeNow();
    // Waits for the plugin, its keys and the pictures' store, as each arrives.
    void heard() {
      if (_running || _gone || _unready() != null) return;
      _unhear?.call();
      _unhear = null;
      unawaited(_resumeNow());
    }

    final unStorage = onPluginStorage(heard);
    changes?.addListener(heard);
    _unhear = () {
      unStorage();
      changes?.removeListener(heard);
    };
  }

  Future<void> _resumeNow() async {
    final kept = keptBannerQueue(_host);
    if (_running || kept == null) return;
    _running = true;
    _asked = false;
    _book = null;
    _again = () => start();
    try {
      // The ones being made as the app went were marked given before Lovart was asked: asked for again. Not the ones
      // asked again on purpose, given one before, which leaving them never makes again.
      forgetBannersGiven([for (final id in kept.going) if (!kept.ask(id).again) id], _host);
      final refused = await claims?.claim(done: kept.total - kept.left.length, total: kept.total);
      if (refused != null) {
        lovartBannerRun.value = BannerRun(total: kept.total, done: kept.total - kept.left.length, made: kept.made, running: false, stopped: refused, elsewhere: elsewhere());
        _on.storage.remove(bannerRunKey);
        return;
      }
      await _run(BannerQueue(total: kept.total, left: kept.left, made: kept.made, skipped: kept.skipped, again: kept.again, replacing: kept.replacing));
    } finally {
      _running = false;
    }
  }

  /// Let go with the root: a run waiting to resume stops waiting.
  void dispose() {
    _gone = true;
    _unhear?.call();
    _unhear = null;
  }

  Future<void> _run(BannerQueue queue) async {
    _stop = false;
    final total = queue.total;
    final left = [...queue.left];
    final going = <String>{};
    var made = queue.made, skipped = queue.skipped;
    String? stopped;
    // What stopped it, where Lovart said: its fix in the tray (Top up, Sign in again) follows from it.
    LovartFailure? stoppedBy;
    // On the app's record of running work (lib/core/background_jobs.dart; docs/ACTIVITY.md): the ring, the tray with
    // its Stop, the credits it should cost and has spent so far, and the chip as it ends.
    final book = _book;
    final job = activity.begin(
      bannerJobId,
      kind: JobKind.images,
      title: 'Making header images',
      personStarted: _asked,
      onStop: stop,
      onOpen: book == null ? null : activityRoutes.noteOpener(book),
      estimate: bannerRunEstimate(total - made - skipped),
      plugin: manifest.id,
    );

    void keep() => _on.storage.set(
          bannerRunKey,
          BannerQueue(
            total: total,
            left: left,
            going: going.toList(),
            made: made,
            skipped: skipped,
            again: [for (final id in queue.again) if (left.contains(id)) id],
            replacing: {for (final MapEntry(:key, :value) in queue.replacing.entries) if (left.contains(key)) key: value},
          ).toJson(),
        );
    BannerRun now() => BannerRun(total: total, done: made + skipped, made: made, running: true);
    void say() {
      final run = lovartBannerRun.value = now();
      unawaited(background.running(bannerJobId, title: 'Making header images', text: '${run.done} of ${run.total}', done: run.done, total: run.total));
      job
        ..progress(done: run.done, total: run.total)
        ..update(spent: run.made * lovartCreditsPerImage);
      claims?.renew(done: run.done, total: run.total);
    }

    keep();
    say();
    // Lovart at the account's limit of jobs at once ([LovartFailure.busy]): the run makes fewer at a time, down to
    // one, and the note waits its turn rather than the run stopping. Only one at a time refused [bannerBusyMost]
    // times running stops it.
    var allowed = bannerRunAtOnce;
    var refusals = 0;
    Future<void> worker(int index) async {
      while (!_stop && stopped == null) {
        if (index >= allowed) return;
        // The plugin switched off, or its keys forgotten, meanwhile: the rest wait for another run.
        final unready = _unready();
        if (unready != null) {
          stopped = unready;
          return;
        }
        String? id;
        for (final each in left) {
          if (!going.contains(each)) {
            id = each;
            break;
          }
        }
        if (id == null) return;
        going.add(id);
        keep();
        try {
          final ask = queue.ask(id);
          final ok = await banners.make(id, rethrowStopping: true, again: ask.again, replacing: ask.replacing);
          ok ? made += 1 : skipped += 1;
          left.remove(id);
          refusals = 0;
        } on LovartFailure catch (failure) {
          if (failure.passing) {
            // Lovart has no room for another, or the way to it was lost a moment: this note waits its turn (it is
            // still first in [left]), and this worker waits before it asks again. At the limit, one worker fewer asks.
            going.remove(id);
            refusals += 1;
            if (failure.busy && allowed > 1) {
              allowed -= 1;
            } else if (refusals >= bannerBusyMost) {
              stopped ??= failure.busy ? 'Lovart stayed at its limit of jobs at once. Make them again later to go on.' : failure.message;
            }
            if (stopped == null && !_stop) await _waitFor(bannerBusyWait * refusals.clamp(1, 4));
            continue;
          }
          // Not this note's fault: it stays in the queue for the next run, and the rest wait for it.
          stoppedBy ??= failure;
          stopped ??= failure is LovartNeedsConfirmation ? failure.said : failure.message;
        } catch (failure) {
          // Anything else is this note's alone: skipped, and the run goes on.
          debugPrint('[lovart] no banner for the note: $failure');
          skipped += 1;
          left.remove(id);
        } finally {
          going.remove(id);
        }
        keep();
        say();
      }
    }

    await Future.wait([for (var i = 0; i < bannerRunAtOnce; i += 1) worker(i)]);
    _on.storage.remove(bannerRunKey);
    claims?.release();
    final asked = _stop && stopped == null && left.isNotEmpty;
    final run = lovartBannerRun.value = BannerRun(total: total, done: made + skipped, made: made, running: false, stopped: asked ? 'Stopped.' : stopped, asked: asked);
    unawaited(background.ended(bannerJobId, title: bannerRunEndWords(run)));
    // The record: the chip says how it ended (it was the root's toast), one for the whole run.
    final tally = JobTally('banner', 'banners', made);
    if (asked) {
      job.stopped(tally: tally);
    } else if (run.stopped != null) {
      job.failed(bannerRunEndWords(run), fix: bannerFix(stoppedBy), tally: tally);
    } else {
      job.done(result: JobResult(bannerRunEndWords(run), action: book == null ? 'View' : 'Open', onOpen: book == null ? null : activityRoutes.noteOpener(book)), tally: tally);
    }
    ended?.call(run);
  }
}

/// "Header images for every page", asked on a notebook's More sheet: its choices are the question before anything is
/// spent (Matt, 2026-10-26: "Also add a feature to add header images to all pages in a book"), "Make header images for
/// 24 pages?" with about how many credits, "Redo existing too" where some pages have one, and Not now. Pages whose
/// banner is black and white or square are made again with the first, on top of its count.
List<ActionChoice> bookBannerChoices(String noteId) {
  final job = lovartBannerJob;
  final notes = job?.notes() ?? const <Note>[];
  Note? book;
  for (final note in notes) {
    if (note.id == noteId) book = note;
  }
  if (job == null || book == null) return const [];
  final counts = bookBannerCounts(book, notes);
  String pages(int n) => n == 1 ? '1 page' : '$n pages';
  final all = counts.missing + counts.existing;
  return [
    if (counts.missing > 0 || counts.existing > 0)
      ActionChoice(
        id: 'missing',
        label: counts.missing == 0 ? 'Redo black-and-white and square ones only?' : 'Make header images for ${pages(counts.missing)}?',
        hint: '${aboutCredits(counts.missing).replaceFirst('a', 'A')}. ${counts.existing == 0 ? 'Uses your Lovart credits.' : 'Of the ${pages(counts.existing)} with one, any in black and white or square is made again too, $lovartCreditsPerImage credits or so each.'}',
      ),
    if (counts.existing > 0) ActionChoice(id: 'all', label: 'Redo existing too: ${pages(all)}?', hint: '${aboutCredits(all).replaceFirst('a', 'A')}. Every page’s header made again.'),
    const ActionChoice(id: 'not-now', label: 'Not now', hint: 'Nothing is made.'),
  ];
}

/// The notebook's pages given their banners by the app's job ([bookBannerAsks]), as [choice] says; the run's line
/// and notification say how far it is.
Future<void> makeBookBanners(NoteEditing editing, String? choice) async {
  final job = lovartBannerJob;
  if (job == null || choice == null || choice == 'not-now') return;
  final unready = bannerUnready();
  if (unready != null) return editing.say(unready);
  Note? book;
  final notes = job.notes();
  for (final note in notes) {
    if (note.id == editing.noteId) book = note;
  }
  if (book == null) return;
  // The index as the editor has it, where it is open.
  final asks = await bookBannerAsks(book.copyWith(body: editing.body()), notes, redo: job.redo, redoAll: choice == 'all');
  if (asks.isEmpty) return editing.say('Every page has a header image already, or is not one to have one.');
  editing.say(asks.length == 1 ? 'Making a header image for 1 page.' : 'Making header images for ${asks.length} pages.');
  final refused = await job.start(asks: asks, book: book.id);
  if (refused != null) editing.say(refused);
}

/// The app's job, set by the root as it starts; null where there is no library (a test, the page alone).
BannerJob? lovartBannerJob;

/// The source another device's run is told to the app's record of running work under.
const String bannerClaimJobsSource = 'lovart-claim';

/// Another device's run as its job on the app's record of running work, or none.
List<Job> bannerJobsElsewhere(BannerClaim? claim) => [
      if (claim != null)
        Job(
          id: '$bannerJobId@${claim.by}',
          kind: JobKind.images,
          title: 'Making header images',
          steps: claim.total > 0 ? '${claim.done} of ${claim.total}' : null,
          fraction: claim.total > 0 ? claim.done / claim.total : null,
          device: claim.by,
          deviceName: claim.name,
          startedAt: DateTime.fromMillisecondsSinceEpoch(claim.at),
          plugin: manifest.id,
        ),
    ];

/// What a run of [count] header images should cost and take, said before one over about 20 credits starts
/// (lib/activity/activity_cost.dart; docs/ACTIVITY.md: "12 banners · ~72 Lovart credits · ~4 min") and in the tray as
/// it runs: [lovartCreditsPerImage] each, and about 20 seconds each, three being made at a time.
JobEstimate bannerRunEstimate(int count) =>
    JobEstimate(credits: count * lovartCreditsPerImage, provider: 'Lovart', duration: Duration(seconds: count * 20), count: count, one: 'header image', many: 'header images');

/// Settings › Lovart's Make them, with its two choices for the run.
Future<void> runBanners({bool takenOff = false, bool redoOld = false}) async {
  final job = lovartBannerJob;
  if (job != null) await job.start(takenOff: takenOff, redoOld: redoOld);
}

/// Its Stop, and the line's: after the pictures being made now.
void stopBannerRun() => lovartBannerJob?.stop();
