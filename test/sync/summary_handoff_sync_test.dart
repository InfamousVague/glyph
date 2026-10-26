// A meeting's summary claimed once, between devices that sync their settings through the service in memory
// (lib/ai/summary_handoff.dart, lib/sync/prefs.dart; Matt, 2026-10-26: the standup the Mac could not summarize). Two
// devices that claim at once: the account writes the settings from the revision last seen and refuses the second
// write, the second device reads the first's claim, its merge keeps it over its own, and only the first runs. A
// claim nobody renews lapses after half an hour, and another device may take it. A summary written beats any claim,
// and the device that waited sees it done.
//
// Each device is its settings as JSON and what it remembers of the account's (prefs_test.dart's `PrefsDevice`), with
// a handoff over them: its sync is `syncPrefs`, and what the account holds is what that pass last saw.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/ai/summary_handoff.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/sync/prefs.dart';

import 'support.dart';

class HandoffDevice {
  HandoffDevice(this.service, this.device, {int Function()? clock}) : api = apiOf(service), clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    handoff = SummaryHandoff(
      device: () => device,
      preferences: () => Preferences.fromJson(prefs),
      setPreferences: (change) => prefs = change(Preferences.fromJson(prefs)).toJson(),
      syncNow: sync,
      accountHeld: () => state.seen == null ? const <String, Object?>{} : (jsonDecode(state.seen!) as Map).cast<String, Object?>(),
      getNote: (id) async => null,
      notes: () => const <Note>[],
      clock: () => this.clock(),
      warn: (_) {},
    );
  }

  final FakeService service;
  final SummaryDevice device;
  final Api api;
  int Function() clock;
  late final SummaryHandoff handoff;
  Map<String, Object?> prefs = Preferences.defaults.copyWith(meetings: {'standup': 0}).toJson();
  PrefsState state = const PrefsState();

  Future<void> sync() async {
    await syncPrefs(PrefsContext(
      token: service.signedIn(),
      key: service.accountKey,
      read: () => prefs,
      write: (next) => prefs = {...prefs, ...next},
      state: state,
      save: (next) => state = next,
      api: api,
      crypto: service.crypto,
    ));
  }

  Handoff? get entry => handoffsOf(Preferences.fromJson(prefs))['standup'];
}

void main() {
  test('two devices that claim one meeting at once: one of them has it, and the account says which', () async {
    final service = await FakeService.start(seed: testAccount);
    final mac = HandoffDevice(service, const SummaryDevice(id: 'mac-1', name: 'Mac'));
    final fold = HandoffDevice(service, const SummaryDevice(id: 'fold-1', name: 'phone'));
    final tablet = HandoffDevice(service, const SummaryDevice(id: 'tab-1', name: 'tablet'));
    // The Mac cannot write it, and says so.
    mac.handoff.waitingHere(['standup']);
    await mac.sync();
    await fold.sync();
    await tablet.sync();
    expect((fold.entry?.from, tablet.entry?.from), ('mac-1', 'mac-1'));

    final claims = await Future.wait([fold.handoff.claim('standup'), tablet.handoff.claim('standup')]);
    expect(claims.where((mine) => mine), hasLength(1), reason: 'claimed once');
    final winner = claims.first ? fold : tablet;
    final loser = claims.first ? tablet : fold;
    await mac.sync();
    await winner.sync();
    await loser.sync();
    for (final d in [mac, winner, loser]) {
      expect(d.entry?.claimBy, winner.device.id, reason: '${d.device.name} agrees who has it');
    }
    // Asked again, the loser still does not have it, and the winner does without another round.
    expect(await loser.handoff.claim('standup'), isFalse);
    expect(await winner.handoff.claim('standup'), isTrue);
    expect(loser.handoff.claimedElsewhere('standup'), isTrue);
  });

  test('a claim nobody renews lapses after half an hour, and another device takes it', () async {
    final service = await FakeService.start(seed: testAccount);
    var at = DateTime.now().millisecondsSinceEpoch;
    final mac = HandoffDevice(service, const SummaryDevice(id: 'mac-1', name: 'Mac'), clock: () => at);
    final fold = HandoffDevice(service, const SummaryDevice(id: 'fold-1', name: 'phone'), clock: () => at);
    final tablet = HandoffDevice(service, const SummaryDevice(id: 'tab-1', name: 'tablet'), clock: () => at);
    mac.handoff.waitingHere(['standup']);
    await mac.sync();
    await tablet.sync();
    await fold.sync();
    expect(await tablet.handoff.claim('standup'), isTrue);
    // The tablet dies mid-summary. The Fold hears of its claim and leaves it.
    await fold.sync();
    expect(await fold.handoff.claim('standup'), isFalse);
    at += handoffClaimMs - 1;
    expect(await fold.handoff.claim('standup'), isFalse, reason: 'still live');
    at += 1;
    expect(await fold.handoff.claim('standup'), isTrue, reason: 'lapsed: nobody renewed it');
    expect(fold.entry?.claimBy, 'fold-1');
  });

  test('the device writing renews its claim as it goes, so a long summary is not taken from under it', () async {
    final service = await FakeService.start(seed: testAccount);
    var at = DateTime.now().millisecondsSinceEpoch;
    final fold = HandoffDevice(service, const SummaryDevice(id: 'fold-1', name: 'phone'), clock: () => at);
    final tablet = HandoffDevice(service, const SummaryDevice(id: 'tab-1', name: 'tablet'), clock: () => at);
    fold.handoff.waitingHere(['standup']);
    await fold.sync();
    expect(await fold.handoff.claim('standup'), isTrue);
    for (var i = 0; i < 4; i += 1) {
      at += handoffRenewMs;
      fold.handoff.renew('standup');
      await fold.sync();
    }
    await tablet.sync();
    expect(await tablet.handoff.claim('standup'), isFalse, reason: 'forty minutes in, still the Fold’s');
  });

  test('the summary written: done beats any claim, and the device that waited sees it', () async {
    final service = await FakeService.start(seed: testAccount);
    final mac = HandoffDevice(service, const SummaryDevice(id: 'mac-1', name: 'Mac'));
    final fold = HandoffDevice(service, const SummaryDevice(id: 'fold-1', name: 'phone'));
    mac.handoff.waitingHere(['standup']);
    await mac.sync();
    await fold.sync();
    expect(await fold.handoff.claim('standup'), isTrue);
    await mac.sync();
    expect(meetingWaitWords(Preferences.fromJson(mac.prefs), 'standup', needsModelHere: true, here: mac.device), 'Being summarized on your phone.');
    fold.handoff.finished('standup');
    await fold.sync();
    await mac.sync();
    expect((mac.entry?.done != null, mac.entry?.doneBy, mac.entry?.claimBy), (true, 'fold-1', null));
    expect(mac.handoff.isDone('standup'), isTrue);
    expect(meetingWaitWords(Preferences.fromJson(mac.prefs), 'standup', needsModelHere: true, here: mac.device), isNull);
    // A claim made on a device that had not heard yet loses to the summary written.
    expect(chosenHandoff({'from': 'mac-1', 'at': 0, 'claim': {'by': 'tab-1', 'at': 5}}, {'from': 'mac-1', 'at': 0, 'done': 4, 'by': 'fold-1'}, now: 6), containsPair('done', 4));
    expect(chosenHandoff({'from': 'mac-1', 'at': 0, 'done': 4, 'by': 'fold-1'}, {'from': 'mac-1', 'at': 0, 'claim': {'by': 'tab-1', 'at': 5}}, now: 6), containsPair('done', 4));
  });

  test('the map is merged an entry at a time, so a meeting marked on one device and another claimed elsewhere both stand', () {
    final base = <String, Object?>{'a': {'from': 'mac-1', 'at': 0}};
    final mine = <String, Object?>{...base, 'b': {'from': 'mac-1', 'at': 1}};
    final theirs = <String, Object?>{'a': {'from': 'mac-1', 'at': 0, 'claim': {'by': 'fold-1', 'at': 2}}};
    expect(mergedHandoffs(base, mine, theirs, now: 3), {'a': theirs['a'], 'b': mine['b']});
    // Both claimed it: the one the account held, still live, stands; a lapsed one does not.
    final mineToo = <String, Object?>{'a': {'from': 'mac-1', 'at': 0, 'claim': {'by': 'tab-1', 'at': 2}}};
    expect(mergedHandoffs(base, mineToo, theirs, now: 3)['a'], theirs['a']);
    expect(mergedHandoffs(base, mineToo, theirs, now: 2 + handoffClaimMs)['a'], mineToo['a']);
  });
}
