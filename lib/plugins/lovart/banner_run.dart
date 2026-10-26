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
import 'banners.dart';
import 'client.dart';
import 'manifest.dart';

/// How many recent notes a run gives banners to, and how many Lovart is asked for at once.
const int bannerRunMost = 100;
const int bannerRunAtOnce = 3;

/// The job's name to the phone (lib/core/background_jobs.dart).
const String bannerJobId = 'lovart-banners';

/// The [most] most recently changed notes that are ones to have a banner and were never given one, newest first.
List<Note> bannerCandidates(List<Note> notes, {int most = bannerRunMost, PluginHost? via}) {
  final done = bannersGiven(via).toSet();
  final sorted = [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [for (final note in sorted) if (!done.contains(note.id) && wantsBanner(note)) note].take(most).toList();
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
String bannerRunLine(BannerRun run) => 'Making header images · ${run.done} of ${run.total}';

/// What is said as it ends, in the toast and the notification: "Header images made for 97 notes · 3 skipped", or
/// where it stopped and why.
String bannerRunEndWords(BannerRun run) {
  final skipped = run.skipped > 0 ? ' · ${run.skipped} skipped' : '';
  if (run.stopped != null && !run.asked) return 'Header images stopped at ${run.done} of ${run.total}: ${run.stopped}';
  if (run.asked) return 'Header images stopped · ${run.made} made$skipped';
  if (run.total == 0) return 'Every recent note has a header image already, or is not one to have one.';
  return 'Header images made for ${_notes(run.made)}$skipped';
}

/// What a claim of another device's says where Make them is pressed here.
String bannerElsewhereWords(BannerClaim claim) => 'Header images are being made on your ${claim.name.isEmpty ? 'other device' : claim.name} · ${claim.done} of ${claim.total}.';

// ---- the queue, kept ----------------------------------------------------------------------------------------------

/// A run as it is kept ([bannerRunKey]): the notes left in order, the ones among them being made now, and the
/// counts so far.
@immutable
class BannerQueue {
  const BannerQueue({required this.total, required this.left, this.going = const [], this.made = 0, this.skipped = 0});

  final int total;

  /// The notes not finished yet, in the run's order: the ones being made stay here until they are.
  final List<String> left;

  /// The ones Lovart was being asked for as this was written.
  final List<String> going;
  final int made;
  final int skipped;

  Map<String, Object?> toJson() => {'total': total, 'left': left, 'going': going, 'made': made, 'skipped': skipped};

  /// A queue as kept, or null for anything that is not one.
  static BannerQueue? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int n(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
    List<String> ids(Object? v) => v is List ? [for (final id in v) if (id is String) id] : const [];
    final left = ids(raw['left']);
    final total = n(raw['total']);
    if (raw['left'] is! List || total <= 0) return null;
    return BannerQueue(total: total, left: left, going: ids(raw['going']), made: n(raw['made']), skipped: n(raw['skipped']));
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
  BannerJob({required this.notes, required this.banners, this.claims, BackgroundJobs? background, this.ended, PluginHost? via})
      : background = background ?? const NoBackgroundJobs(),
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

  /// Told as a run ends, however it ends: the root's toast.
  final void Function(BannerRun run)? ended;
  final PluginHost? _host;

  PluginHost get _on => _host ?? host;

  bool _running = false;
  bool _stop = false;
  bool _gone = false;
  VoidCallback? _unhear;

  /// Whether a run is going on this device now.
  bool get running => _running;

  /// Another device's live claim on a run, if one holds.
  BannerClaim? elsewhere() => claims?.elsewhere();

  /// Stops the run after the pictures being made now.
  void stop() => _stop = true;

  /// What says a run cannot start here, or null.
  String? _unready() {
    if (!pluginOn(manifest)) return 'Lovart is off.';
    return bannerUnready();
  }

  /// Make them: a run over the recent notes. Answers why it did not start, or null where it did (or one was
  /// already going, which it leaves be).
  Future<String?> start() async {
    if (_running) return null;
    _running = true;
    try {
      final unready = _unready();
      if (unready != null) {
        lovartBannerRun.value = BannerRun(total: 0, running: false, stopped: unready);
        return unready;
      }
      final queue = bannerCandidates(notes(), via: _host);
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
      await _run(BannerQueue(total: queue.length, left: [for (final note in queue) note.id]));
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
    try {
      // The ones being made as the app went were marked given before Lovart was asked: asked for again.
      forgetBannersGiven(kept.going, _host);
      final refused = await claims?.claim(done: kept.total - kept.left.length, total: kept.total);
      if (refused != null) {
        lovartBannerRun.value = BannerRun(total: kept.total, done: kept.total - kept.left.length, made: kept.made, running: false, stopped: refused, elsewhere: elsewhere());
        _on.storage.remove(bannerRunKey);
        return;
      }
      await _run(BannerQueue(total: kept.total, left: kept.left, made: kept.made, skipped: kept.skipped));
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

    void keep() => _on.storage.set(bannerRunKey, BannerQueue(total: total, left: left, going: going.toList(), made: made, skipped: skipped).toJson());
    BannerRun now() => BannerRun(total: total, done: made + skipped, made: made, running: true);
    void say() {
      final run = lovartBannerRun.value = now();
      unawaited(background.running(bannerJobId, title: 'Making header images', text: '${run.done} of ${run.total}', done: run.done, total: run.total));
      claims?.renew(done: run.done, total: run.total);
    }

    keep();
    say();
    Future<void> worker() async {
      while (!_stop && stopped == null) {
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
          final ok = await banners.make(id, rethrowStopping: true);
          ok ? made += 1 : skipped += 1;
          left.remove(id);
        } on LovartFailure catch (failure) {
          // Not this note's fault: it stays in the queue for the next run, and the rest wait for it.
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

    await Future.wait([for (var i = 0; i < bannerRunAtOnce; i += 1) worker()]);
    _on.storage.remove(bannerRunKey);
    claims?.release();
    final asked = _stop && stopped == null && left.isNotEmpty;
    final run = lovartBannerRun.value = BannerRun(total: total, done: made + skipped, made: made, running: false, stopped: asked ? 'Stopped.' : stopped, asked: asked);
    unawaited(background.ended(bannerJobId, title: bannerRunEndWords(run)));
    ended?.call(run);
  }
}

/// The app's job, set by the root as it starts; null where there is no library (a test, the page alone).
BannerJob? lovartBannerJob;

/// Settings › Lovart's Make them.
Future<void> runBanners() async {
  final job = lovartBannerJob;
  if (job != null) await job.start();
}

/// Its Stop, and the line's: after the pictures being made now.
void stopBannerRun() => lovartBannerJob?.stop();
