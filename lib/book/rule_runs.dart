/// A notebook's rules, run (Matt, 2026-10-31, of the ticket features: "Rules / automations"; what a rule says is
/// rules.dart). Once, on one device, with each run on the app's record of running work (docs/ACTIVITY.md).
///
/// WHO RUNS A CHANGE'S RULES. The device that made the change, and no other: what is heard is this device's own saves
/// (lib/core/core_library.dart `savedHere`), which a note written by sync never passes, as the outgoing webhooks hear
/// them (lib/integrations/webhooks/outgoing.dart). A status set on the Mac posts to Slack from the Mac; the phone,
/// which the ticket reaches by sync a moment later, sees a ticket already Done and does nothing. A note's run of saves
/// is heard as one change once it has been quiet for [quietFor], so a status typed letter by letter (`Do`, `Don`,
/// `Done`) is one move to Done, not three.
///
/// AND A RUN ID, so nothing is run twice even so. Every run is known by its rule ([TicketRule.id], a hash of its
/// words), the ticket, and what set it off ([Fired.cause]), and for a change the moment of the change (the note's
/// `updatedAt`, which sync carries to every device as it is): `3fa2c1d0:<note>:status:done@1790000000000`. Each id
/// run is written into the synced settings ([ruleRunsKey], `{id: {at, by}}`) before its actions start, and a run whose
/// id is there already is not started, on this device or any other the settings reach. So the same change heard twice
/// (a second listener, a launch that hears a save again) runs once, and a ticket moved to Done, back, and to Done
/// again tomorrow runs twice, as it should.
///
/// THE CLOCK'S RULES (`due passes`, `blocked for 3 days`) have no change to hear, and every device would see the same
/// due day pass. So one device runs them: the one that holds the sweep's claim ([ruleSweepKey], `{by, name, at}`), the
/// summary handoff's way (lib/ai/summary_handoff.dart) and the header images' (lib/plugins/lovart/banner_run.dart):
/// the claim is written, a sync is run, and only a claim the account then holds as this device's lets the sweep run;
/// of two devices that claim at once the second one's write is refused by the account, and its merge keeps the live
/// claim it finds (lib/sync/prefs.dart). The claim lives for [sweepClaimMs] from its last renewal, so a device put
/// away hands the sweep on. Its runs are known by the due day (`due:2026-10-30`) or by when the block began
/// (`blocked:<ms>`, kept in [ruleBlockedKey] by the sweeping device), so a claim handed on runs nothing again.
///
/// A rule's own changes (a `set`) are saves like any other and can set off rules in turn, three deep at most: past
/// that a ring of rules (Done sets Doing, Doing sets Done) is stopped and said.
///
/// Rules are off for a ticket or a notebook in the Trash, and in a notebook [TicketRules.canEdit] says this account
/// cannot change; read-only views save nothing, so they set nothing off. What a rule reaches past the note with is
/// [RuleWorld], the screen's, so a test hands in fakes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/summary_handoff.dart' show SummaryDevice;
import '../core/background_jobs.dart';
import '../core/core_library.dart' show SavedHere;
import '../core/days.dart' show isoDay;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart' show noteTitle;
import '../core/preferences.dart' show Preferences;
import '../core/properties.dart' show ticketOf;
import 'rules.dart';
import 'tickets.dart' show TicketEntry, notebookFinder, ticketFinder, ticketsIn, waitingOn, ticketChoice;

/// The runs started, by id, in the synced settings (see the header).
const String ruleRunsKey = 'ticketRuleRuns';

/// When each ticket the sweep found blocked was first found so, by note id.
const String ruleBlockedKey = 'ticketBlocked';

/// Which device runs the clock's rules.
const String ruleSweepKey = 'ticketSweep';

/// How long the sweep's claim holds without being renewed, and how often the device holding it renews it.
const int sweepClaimMs = 30 * 60000;
const int sweepRenewMs = 10 * 60000;

/// How long a run's id is kept: past this, nothing would hear its change again.
const int runKeptMs = 30 * 24 * 3600000;

/// How long a note goes unsaved before its change is heard.
const Duration quietFor = Duration(seconds: 3);

/// How often the clock's rules are looked at, on the device that holds the sweep.
const Duration sweepEvery = Duration(minutes: 15);

/// How deep a rule's change sets off rules in turn.
const int deepest = 3;

/// A person told by a rule (`notify`): who, about which ticket, in what words, and the run's id, which the bell's
/// row is posted under so a retry never tells them twice.
@immutable
class RuleNotice {
  const RuleNotice({required this.person, required this.noteId, required this.title, required this.words, required this.id});

  /// `me`, or a person's name or handle as the ticket writes it.
  final String person;
  final String noteId;
  final String title;
  final String words;
  final String id;

  @override
  String toString() => 'RuleNotice($person, $title: $words)';
}

/// What a rule reaches past its rules with, from the screen; one absent where the app cannot do it here, and a run
/// that needs it fails saying so.
class RuleWorld {
  const RuleWorld({this.setFields, this.post, this.claude, this.notify, this.make});

  /// Writes [fields] into the ticket's front matter as one save (an empty value takes one off).
  final Future<void> Function(String noteId, Map<String, String> fields)? setFields;

  /// Posts [text] (or, null, the note) to a channel of `slack` or `discord` by name; answers the channel's name and
  /// throws what went wrong, as a button's post (lib/editor/buttons/button_run.dart `ButtonWorld.post`).
  final Future<String> Function(String service, String? channel, String? text, String body)? post;

  /// The app's Claude on the ticket, with one of the Claude rules or a prompt.
  final Future<void> Function(String noteId, String title, {String? rule, String? prompt})? claude;

  /// A person told, through the bell (lib/sync/record.dart) or a team's mentions route.
  final Future<void> Function(RuleNotice notice)? notify;

  /// A note made from a template, in a notebook or folder, with a title; false where there is no such template.
  final bool Function(String template, String? place, String? title)? make;
}

/// One rule set off for one ticket, to run.
@immutable
class RuleRun {
  const RuleRun({required this.id, required this.rule, required this.noteId, required this.title, required this.body, required this.cause});
  final String id;
  final TicketRule rule;
  final String noteId;
  final String title;

  /// The ticket's words as it was when set off: what its braces are filled from.
  final String body;
  final String cause;

  @override
  String toString() => 'RuleRun($id)';
}

/// A run's id (see the header): the rule, the ticket, the cause, and for a change its moment.
String runId(TicketRule rule, String noteId, String cause, [int? at]) => '${rule.id}:$noteId:$cause${at == null ? '' : '@$at'}';

/// The runs started, by id.
Map<String, Object?> runsOf(Preferences prefs) => switch (prefs.more[ruleRunsKey]) { final Map map => map.cast<String, Object?>(), _ => const {} };

Map<String, int> _blockedOf(Preferences prefs) => {
      for (final MapEntry(:key, :value) in switch (prefs.more[ruleBlockedKey]) { final Map map => map.cast<String, Object?>(), _ => const <String, Object?>{} }.entries)
        if (value is num) key: value.toInt(),
    };

/// [prefs] with [id] marked started by [by] at [now]; the runs older than [runKeptMs] go at the same time.
Preferences withRun(Preferences prefs, String id, {required String by, required int now}) {
  final kept = <String, Object?>{
    for (final MapEntry(:key, :value) in runsOf(prefs).entries)
      if (value is Map && value['at'] is num && now - (value['at'] as num).toInt() < runKeptMs) key: value,
    id: {'at': now, 'by': by},
  };
  return prefs.copyWith(more: {...prefs.more, ruleRunsKey: kept});
}

/// The sweep's claim, as kept.
@immutable
class SweepClaim {
  const SweepClaim({required this.by, this.name, required this.at});
  final String by;
  final String? name;
  final int at;

  static SweepClaim? fromJson(Object? raw) {
    if (raw is! Map || raw['by'] is! String || raw['at'] is! num) return null;
    return SweepClaim(by: raw['by'] as String, name: raw['name'] is String ? raw['name'] as String : null, at: (raw['at'] as num).toInt());
  }

  Map<String, Object?> toJson() => {'by': by, if (name != null) 'name': name, 'at': at};

  bool liveAt(int now) => now - at < sweepClaimMs;
}

SweepClaim? sweepClaimOf(Preferences prefs) => SweepClaim.fromJson(prefs.more[ruleSweepKey]);

/// Which of two devices' sweep claims stands where both changed it (lib/sync/prefs.dart `merged`): a live claim of
/// another device's that the account already held, over this device's own; else this device's.
Object? chosenSweepClaim(Object? mine, Object? theirs, {int? now}) {
  final t = SweepClaim.fromJson(theirs);
  if (t == null) return mine;
  final m = SweepClaim.fromJson(mine);
  if (t.liveAt(now ?? DateTime.now().millisecondsSinceEpoch) && t.by != m?.by) return theirs;
  return mine;
}

/// A ticket's change, heard and waiting for the note to go quiet.
class _Waiting {
  _Waiting(this.before, this.depth);
  final Note? before;
  final int depth;
  late Note after;
  Timer? quiet;
}

/// The rules, run for the life of the app (see the header).
class TicketRules {
  TicketRules({
    required this.device,
    required this.preferences,
    required this.setPreferences,
    required this.notes,
    required this.world,
    Future<void> Function()? syncNow,
    this.accountHeld,
    this.canEdit,
    this.isTrashed,
    int Function()? clock,
    this.quiet = quietFor,
    void Function(String message)? warn,
  })  : syncNow = syncNow ?? (() async {}),
        clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        warn = warn ?? debugPrint;

  final SummaryDevice Function() device;
  final Preferences Function() preferences;
  final void Function(Preferences Function(Preferences now) change) setPreferences;

  /// This device's notes, as the library holds them.
  final List<Note> Function() notes;
  final RuleWorld Function() world;

  /// A sync now, waited for; its failure is no throw.
  final Future<void> Function() syncNow;

  /// The synced settings as the account holds them; null where this device syncs nothing, and then the sweep is its
  /// own.
  final Map<String, Object?>? Function()? accountHeld;

  /// Whether this account can change the notebook (a team's, where it reads only); every notebook where absent.
  final bool Function(Note notebook)? canEdit;
  final bool Function(String noteId)? isTrashed;
  final int Function() clock;
  final Duration quiet;
  final void Function(String message) warn;

  final Map<String, _Waiting> _waiting = {};

  /// How deep the next save of a note a rule changed is: a rule's own change, heard.
  final Map<String, ({int depth, int at})> _ruleMade = {};

  final Expando<RuleSet> _read = Expando<RuleSet>('a notebook’s rules');

  RuleSet _rulesOf(Note notebook) => _read[notebook] ??= rulesIn(notebook.body);

  /// A save here heard (see the header): run once the note has gone quiet.
  void heard(SavedHere saved) {
    final after = saved.after;
    if (!after.body.contains('ticket')) return;
    final id = after.id;
    final made = _ruleMade.remove(id);
    final depth = made != null && clock() - made.at < 60000 ? made.depth : 0;
    final run = _waiting.putIfAbsent(id, () => _Waiting(saved.before, depth));
    run.after = after;
    run.quiet?.cancel();
    run.quiet = Timer(quiet, () => unawaited(_settle(id)));
  }

  /// Every change still waiting for its note to go quiet, heard now: for leaving the app, and for a test.
  Future<void> flush() async {
    for (final id in [..._waiting.keys]) {
      await _settle(id);
    }
  }

  Future<void> _settle(String id) async {
    final run = _waiting.remove(id);
    if (run == null) return;
    run.quiet?.cancel();
    try {
      await changed(run.before, run.after, depth: run.depth);
    } catch (failure) {
      warn('[rules] a ticket’s rules were not run: $failure');
    }
  }

  /// The notebook [note] is in, and its rules, where they are this device's to run; null for neither.
  ({Note notebook, RuleSet rules})? _placed(Note note, Note? Function(Note note) notebookOf) {
    if (isTrashed?.call(note.id) ?? false) return null;
    final notebook = notebookOf(note);
    if (notebook == null || (isTrashed?.call(notebook.id) ?? false)) return null;
    if (!(canEdit?.call(notebook) ?? true)) return null;
    final rules = _rulesOf(notebook);
    if (rules.rules.isEmpty) return null;
    return (notebook: notebook, rules: rules);
  }

  /// One change to a ticket made here, from [before] (null for one just made) to [after]: the rules it sets off, run.
  /// Answers the runs started.
  Future<List<RuleRun>> changed(Note? before, Note after, {int depth = 0}) async {
    final now = ticketOf(after.body);
    if (now == null) return const [];
    final all = notes();
    final library = [for (final note in all) if (note.id == after.id) after else note];
    if (!library.any((note) => note.id == after.id)) library.add(after);
    final placed = _placed(after, notebookFinder(library));
    if (placed == null) return const [];
    if (depth >= deepest) {
      warn('[rules] a ring of rules was stopped at “${noteTitle(after.body)}”');
      return const [];
    }
    final was = before == null ? null : ticketOf(before.body);
    final fired = firedByChange(placed.rules.rules, before: was == null ? null : before!.body, after: after.body, was: was, now: now);
    final runs = <RuleRun>[];
    for (final each in fired) {
      final run = RuleRun(id: runId(each.rule, after.id, each.cause, after.updatedAt), rule: each.rule, noteId: after.id, title: NoteFacts.of(after).title, body: after.body, cause: each.cause);
      if (claimRun(run.id)) runs.add(run);
    }
    for (final run in runs) {
      await this.run(run, depth: depth);
    }
    return runs;
  }

  /// The run's id written as started here, unless it is there already: true where it is this device's to run.
  bool claimRun(String id) {
    if (runsOf(preferences()).containsKey(id)) return false;
    final me = device().id;
    final now = clock();
    var mine = false;
    setPreferences((prefs) {
      if (runsOf(prefs).containsKey(id)) return prefs;
      mine = true;
      return withRun(prefs, id, by: me, now: now);
    });
    return mine;
  }

  /// The job a run is on: one for each run, so a retry is the same row.
  static String jobId(String runId) => 'rule:$runId';

  /// Runs [run]'s actions in order from [from], as one job on the app's record of running work: its plugin's mark
  /// where it reaches one, its line what it does now. A failure is the job's red row with the cause and a Retry,
  /// which runs the rest from the action that failed. Answers whether every action ran.
  Future<bool> run(RuleRun run, {int from = 0, int depth = 0}) async {
    final rule = run.rule;
    final plugin = rule.actions.skip(from).map((action) => action.plugin).whereType<String>().firstOrNull;
    final kind = rule.actions.any((action) => action.verb == RuleVerb.claude)
        ? JobKind.ai
        : rule.actions.any((action) => action.verb == RuleVerb.post)
            ? JobKind.meetings
            : JobKind.sync;
    final key = ticketOf(run.body)?.id;
    final job = activity.begin(jobId(run.id), kind: kind, title: '${key ?? run.title}: when ${rule.when.words}', line: rule.actions[from].doing, plugin: plugin, onOpen: activityRoutes.noteOpener(run.noteId));
    for (var i = from; i < rule.actions.length; i += 1) {
      final action = rule.actions[i];
      job.running(line: action.doing);
      try {
        await _do(action, run, depth: depth, step: i);
      } catch (failure) {
        final words = failure is String ? failure : _words(failure);
        job.failed(words, fix: JobFix(JobFixKind.retry, () => unawaited(this.run(run, from: i, depth: depth))), tally: const JobTally('rule that failed', 'rules that failed'));
        return false;
      }
    }
    job.done(quiet: true, tally: const JobTally('rule run', 'rule runs'));
    return true;
  }

  Future<void> _do(RuleAction action, RuleRun run, {required int depth, required int step}) async {
    final world = this.world();
    String fill(String? text) => text == null || text.isEmpty ? '' : filledIn(text, body: run.body, title: run.title);
    switch (action.verb) {
      case RuleVerb.set:
        final set = world.setFields;
        if (set == null) throw 'Tickets cannot be changed from here.';
        _ruleMade[run.noteId] = (depth: depth + 1, at: clock());
        await set(run.noteId, {action['field']!: fill(action['value'])});
      case RuleVerb.post:
        final post = world.post;
        final service = action['to'] == 'discord' ? 'discord' : 'slack';
        if (post == null) throw '${service == 'discord' ? 'Discord' : 'Slack'} is not set up on this device.';
        final text = fill(action['text']);
        await post(service, action['channel'], text.isEmpty ? null : text, run.body);
      case RuleVerb.claude:
        final claude = world.claude;
        if (claude == null) throw 'Claude is not set up on this device.';
        final rule = action['rule'];
        await claude(run.noteId, run.title, rule: rule == null || rule.isEmpty ? null : rule, prompt: rule == null || rule.isEmpty ? fill(action['prompt']) : null);
      case RuleVerb.notify:
        final notify = world.notify;
        if (notify == null) throw 'Nobody can be told from this device. Sign in to tell people.';
        final said = action['person'] ?? 'assignee';
        final person = said == 'assignee' ? (ticketOf(run.body)?.assignee ?? '') : said;
        if (person.isEmpty) throw '${ticketOf(run.body)?.id ?? 'This ticket'} has no assignee to tell.';
        final words = fill(action['text']);
        await notify(RuleNotice(person: person, noteId: run.noteId, title: run.title, words: words.isEmpty ? '${ticketOf(run.body)?.id ?? run.title}: ${run.rule.when.words}' : words, id: '${run.id}#$step'));
      case RuleVerb.make:
        final make = world.make;
        if (make == null) throw 'Notes cannot be made from here.';
        final template = action['template']!;
        final title = fill(action['title']);
        if (!make(template, action['in'], title.isEmpty ? null : title)) throw 'There is no template called “$template”${(action['in'] ?? '').isEmpty ? '' : ', or no ${action['in']} to put it in'}.';
    }
  }

  // ---- the clock's rules --------------------------------------------------------------------------------------

  bool _confirmed = false;
  int _renewed = 0;

  /// Whether this device holds the sweep (see the header): another device's live claim says no; this device's own,
  /// once the account was seen to hold it, says yes and is renewed as it ages; else it is claimed, a sync run, and
  /// the account asked.
  Future<bool> holdsSweep() async {
    final me = device();
    final now = clock();
    final claim = sweepClaimOf(preferences());
    if (claim != null && claim.by != me.id && claim.liveAt(now)) {
      _confirmed = false;
      return false;
    }
    if (claim != null && claim.by == me.id && claim.liveAt(now) && _confirmed) {
      if (now - _renewed >= sweepRenewMs) {
        _renewed = now;
        setPreferences((prefs) => prefs.copyWith(more: {...prefs.more, ruleSweepKey: SweepClaim(by: me.id, name: me.name, at: now).toJson()}));
      }
      return true;
    }
    setPreferences((prefs) {
      final was = sweepClaimOf(prefs);
      if (was != null && was.by != me.id && was.liveAt(now)) return prefs;
      return prefs.copyWith(more: {...prefs.more, ruleSweepKey: SweepClaim(by: me.id, name: me.name, at: now).toJson()});
    });
    _renewed = now;
    if (accountHeld == null || accountHeld!() == null) return _confirmed = sweepClaimOf(preferences())?.by == me.id;
    try {
      await syncNow();
    } catch (failure) {
      warn('[rules] the sweep could not be claimed: $failure');
    }
    final held = accountHeld?.call();
    final said = held == null ? sweepClaimOf(preferences()) : SweepClaim.fromJson(held[ruleSweepKey]);
    return _confirmed = said != null && said.by == me.id;
  }

  /// The clock's rules, looked at once where this device holds the sweep: each ticket of a notebook with rules, its
  /// due day and how long it has been blocked. Answers the runs started.
  Future<List<RuleRun>> sweep() async {
    final all = notes();
    final notebookOf = notebookFinder(all);
    final entries = ticketsIn(all);
    final timed = <TicketEntry, RuleSet>{};
    for (final entry in entries) {
      final placed = _placed(entry.note, notebookOf);
      if (placed != null && placed.rules.rules.any((rule) => rule.when.trigger.timed)) timed[entry] = placed.rules;
    }
    if (timed.isEmpty || !await holdsSweep()) return const [];
    final now = clock();
    final today = isoDay(DateTime.fromMillisecondsSinceEpoch(now));
    final find = ticketFinder(entries);
    final blocked = _blockedOf(preferences());
    final since = <String, int>{};
    final runs = <RuleRun>[];
    for (final MapEntry(key: entry, value: rules) in timed.entries) {
      final ticket = entry.ticket;
      final waits = waitingOn(ticket, (target) => switch (find(target)) { final found? => ticketChoice(found), null => null });
      final stuck = isBlockedTicket(ticket, waiting: waits.isNotEmpty);
      final began = stuck ? (blocked[entry.note.id] ?? now) : null;
      if (began != null) since[entry.note.id] = began;
      for (final each in firedByClock(rules.rules, body: entry.note.body, ticket: ticket, today: today, blockedSince: began, now: now)) {
        final run = RuleRun(id: runId(each.rule, entry.note.id, each.cause), rule: each.rule, noteId: entry.note.id, title: entry.title, body: entry.note.body, cause: each.cause);
        if (claimRun(run.id)) runs.add(run);
      }
    }
    if (!mapEquals(since, blocked)) setPreferences((prefs) => prefs.copyWith(more: {...prefs.more, ruleBlockedKey: since}));
    for (final run in runs) {
      await this.run(run);
    }
    return runs;
  }

  /// Hears [saves] (this device's own) and sweeps every [sweepEvery], and a while after [changes] says the notes
  /// changed; answers the way to stop.
  VoidCallback start(Stream<SavedHere> saves, {Listenable? changes, Duration settle = const Duration(seconds: 30)}) {
    final heard = saves.listen(this.heard);
    Timer? soon;
    void later() {
      soon?.cancel();
      soon = Timer(settle, () => unawaited(_sweepQuietly()));
    }

    changes?.addListener(later);
    final every = Timer.periodic(sweepEvery, (_) => unawaited(_sweepQuietly()));
    later();
    return () {
      unawaited(heard.cancel());
      soon?.cancel();
      every.cancel();
      changes?.removeListener(later);
      for (final run in _waiting.values) {
        run.quiet?.cancel();
      }
      _waiting.clear();
    };
  }

  bool _sweeping = false;

  Future<void> _sweepQuietly() async {
    if (_sweeping) return;
    _sweeping = true;
    try {
      await sweep();
    } catch (failure) {
      warn('[rules] the clock’s rules were not looked at: $failure');
    } finally {
      _sweeping = false;
    }
  }
}

String _words(Object failure) {
  final said = failure.toString();
  return said.startsWith('Exception: ') ? said.substring(11) : said;
}
