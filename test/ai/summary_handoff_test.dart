// A meeting's summary handed on to another of the account's devices (lib/ai/summary_handoff.dart; Matt, 2026-10-26:
// "The engineering standup meeting was not auto summarized and sorted into the hello trade meetings folder"): the
// device that cannot write it marks it waiting, keeps saying so with what to do, and lets its job go once another
// device has written it; the device that can claims it, writes the summary through its own queue, sorts it into the
// workspace's Meetings folder, and marks it done; a meeting a build from before left stranded is found and written
// the same way. The rules of the claim itself (once, with a timeout) between two devices that sync are
// test/sync/summary_handoff_sync_test.dart's.
//
// The queue and its stand-ins are summaries_test.dart's: one device at a time, its preferences a variable, its sync a
// count, and nothing held by an account (so a claim is this device's once it is written).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/meeting_sort.dart';
import 'package:ghost_md/ai/summaries.dart';
import 'package:ghost_md/ai/summary_handoff.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/core/workspaces.dart';

import 'summaries_test.dart' as q;

const mac = SummaryDevice(id: 'mac-1', name: 'Mac');
const phone = SummaryDevice(id: 'fold-1', name: 'phone');

int now = 10 * 3600000;
int synced = 0;

SummaryHandoff handoffFor(SummaryDevice device) => SummaryHandoff(
      device: () => device,
      preferences: () => q.prefs,
      setPreferences: (change) => q.prefs = change(q.prefs),
      syncNow: () async => synced += 1,
      getNote: (id) async => q.notes[id],
      notes: () => q.notes.values.toList(),
      clock: () => now,
      warn: (_) {},
    )..attach(q.summaries);

/// The settings with [noteId] a meeting, as the meeting step marks one.
Preferences meeting(Preferences prefs, String noteId, {num at = 0}) => prefs.copyWith(meetings: {...prefs.meetings, noteId: at});

/// Another device's change to the entry, as a sync lays it in.
void theirs(String noteId, Handoff entry) => q.prefs = withHandoff(q.prefs, noteId, entry, now: now);

RecordingJobState needsModel(String id) => RecordingJobState(id: id, title: 'Engineering standup', phase: RecordingJobPhase.needsModel);

void handoffTest(String name, Future<void> Function(WidgetTester tester) run) {
  testWidgets(name, (tester) async {
    q.begin();
    now = 10 * 3600000;
    synced = 0;
    try {
      await run(tester);
    } finally {
      q.summaries.handoff = null;
      await q.end(tester);
    }
  });
}

Future<void> advance(WidgetTester tester, int ms) => tester.pump(Duration(milliseconds: ms));

void main() {
  group('the device that cannot write the summary', () {
    handoffTest('marks a meeting that needs a model as waiting, says what to do, and lets its job go once another device wrote it', (tester) async {
      q.prefs = meeting(q.prefs, 'n1');
      q.present = [];
      // The Mac's job as it stood on 2026-10-26, made before the handoff was there to mark it: the write-up's
      // transcript is in the note, and the summary needs a model the Mac does not have.
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      q.phoneStates = [needsModel('n1')];
      await advance(tester, 15000);
      expect(q.summaries.summariesNow().needsModel, {'n1'});
      expect(handoffsOf(q.prefs), isEmpty);

      // The build with the handoff: the queue's next look marks it.
      q.summaries.handoff = handoffFor(mac);
      await advance(tester, 15000);
      final waiting = handoffsOf(q.prefs)['n1']!;
      expect((waiting.from, waiting.fromName, waiting.claimBy, waiting.done), ('mac-1', 'Mac', null, null));
      expect(meetingWaitWords(q.prefs, 'n1', needsModelHere: true, here: mac, now: now),
          'Waiting for a summary: turn on Claude or download the summary model on this Mac, or open Ghost.md on your phone.');
      // Settings › Meetings, which cannot see the queue, says it from the mark alone.
      expect(meetingWaitWords(q.prefs, 'n1', needsModelHere: false, here: mac, now: now), startsWith('Waiting for a summary: '));
      expect(meetingWaitWords(q.prefs, 'n1', needsModelHere: false, here: phone, now: now), isNull, reason: 'another device says nothing of a meeting it may write itself');

      // The phone claimed it: the Mac says where it is being written, and still waits.
      theirs('n1', Handoff(from: 'mac-1', fromName: 'Mac', at: 0, claimBy: 'fold-1', claimName: 'phone', claimAt: now));
      expect(meetingWaitWords(q.prefs, 'n1', needsModelHere: true, here: mac, now: now), 'Being summarized on your phone.');
      expect(q.summaries.summaryPending('n1'), isTrue);
      // A claim not renewed for half an hour is no claim: the Mac says what to do again.
      expect(meetingWaitWords(q.prefs, 'n1', needsModelHere: true, here: mac, now: now + handoffClaimMs), startsWith('Waiting for a summary'));

      // Done on the phone: the Mac's job goes, and nothing waits.
      theirs('n1', Handoff(from: 'mac-1', fromName: 'Mac', at: 0, done: now, doneBy: 'fold-1'));
      await q.summaries.handoff!.look();
      await advance(tester, 0);
      expect(q.summaries.summaryPending('n1'), isFalse);
      expect(q.queued(), isEmpty);
      expect(q.summaries.summariesNow().needsModel, isEmpty);
      expect(meetingWaitWords(q.prefs, 'n1', needsModelHere: false, here: mac, now: now), isNull);
      expect(q.fakes, isEmpty, reason: 'the Mac wrote nothing itself');
    });

    handoffTest('a voice note that needs a model is not handed on: it is no meeting', (tester) async {
      q.present = [];
      q.summaries.handoff = handoffFor(mac);
      q.summaries.enqueueSummary('n1', SummaryKind.recording);
      await advance(tester, 0);
      expect(q.summaries.summariesNow().needsModel, {'n1'});
      expect(handoffsOf(q.prefs), isEmpty);
    });

  });

  group('the device that can', () {
    late WorkspaceStore store;
    late Workspace hello;
    final sorted = <String>[];

    /// The queue told of each meeting's summary as the root tells it: sorted into a workspace's Meetings folder.
    void sortHere() {
      store = WorkspaceStore();
      hello = store.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'HelloTrade'));
      final sorter = MeetingSorter(
        workspaces: store,
        preferences: () => q.prefs,
        setPreferences: (change) => q.prefs = change(q.prefs),
        getNote: (id) async => q.notes[id],
        ask: (system, prompt) async => '{"workspace":"${hello.id}","confident":true}',
      );
      sorted.clear();
      q.stop?.call();
      q.stop = q.summaries.startSummaries(() {}, q.summarized.add, meetingSummarized: (id, body) => unawaited(sorter.meetingSummarized(id, body).then((w) {
            if (w != null) sorted.add(id);
          })));
    }

    handoffTest('claims a meeting waiting elsewhere, writes the summary into the note, sorts it, and marks it done', (tester) async {
      sortHere();
      q.prefs = meeting(q.prefs, 'n1');
      theirs('n1', const Handoff(from: 'mac-1', fromName: 'Mac', at: 0));
      final handoff = q.summaries.handoff = handoffFor(phone);
      await handoff.look();
      expect(q.summaries.summaryPending('n1'), isTrue);
      await advance(tester, 0);
      // Claimed before the model was asked, with a sync to make the claim the account's.
      final claimed = handoffsOf(q.prefs)['n1']!;
      expect((claimed.claimBy, claimed.claimName, claimed.claimAt), ('fold-1', 'phone', now));
      expect(synced, greaterThan(0));
      expect(q.fakes, hasLength(1));
      q.fakes.single.finish(q.answer);
      await advance(tester, 0);
      await advance(tester, 0);
      expect(q.notes['n1']!.body, contains(q.section));
      final done = handoffsOf(q.prefs)['n1']!;
      expect((done.done, done.doneBy, done.claimBy), (now, 'fold-1', null));
      expect(sorted, ['n1']);
      expect(store.workspaceOf('n1')?.name, meetingsFolderName);
      expect(workspacePathName(store.value.list, store.workspaceOf('n1')!.id), 'HelloTrade › Meetings');
      // Looked at again, nothing more is asked.
      await handoff.look();
      await advance(tester, 0);
      expect(q.fakes, hasLength(1));
      expect(q.summaries.summaryPending('n1'), isFalse);
    });

    handoffTest('leaves a meeting another device holds a live claim on, and takes it once the claim has lapsed', (tester) async {
      q.prefs = meeting(q.prefs, 'n1');
      theirs('n1', Handoff(from: 'mac-1', at: 0, claimBy: 'tablet-1', claimName: 'tablet', claimAt: now));
      final handoff = q.summaries.handoff = handoffFor(phone);
      await handoff.look();
      await advance(tester, 0);
      expect(q.summaries.summaryPending('n1'), isFalse);
      expect(q.fakes, isEmpty);
      // The tablet died mid-summary: half an hour on, its claim is no claim.
      now += handoffClaimMs;
      await handoff.look();
      await advance(tester, 0);
      expect(handoffsOf(q.prefs)['n1']!.claimBy, 'fold-1');
      expect(q.fakes, hasLength(1));
    });

    handoffTest('asks nothing where it cannot write the summary either', (tester) async {
      q.present = [];
      q.prefs = meeting(q.prefs, 'n1');
      theirs('n1', const Handoff(from: 'mac-1', at: 0));
      final handoff = q.summaries.handoff = handoffFor(phone);
      await handoff.look();
      await advance(tester, 0);
      expect(q.summaries.summaryPending('n1'), isFalse);
      expect(handoffsOf(q.prefs)['n1']!.claimBy, isNull);
    });

    handoffTest('lets its claim go when its job fails for good, and does not take it again', (tester) async {
      q.prefs = meeting(q.prefs, 'n1');
      theirs('n1', const Handoff(from: 'mac-1', at: 0));
      final handoff = q.summaries.handoff = handoffFor(phone);
      await handoff.look();
      for (var i = 0; i < 3; i += 1) {
        await advance(tester, i == 0 ? 0 : 20000);
        q.fakes.last.fail('the model broke');
        await advance(tester, 0);
      }
      expect(q.summaries.summariesNow().failed, {'n1'});
      expect(handoffsOf(q.prefs)['n1']!.claimBy, isNull);
      final asked = q.fakes.length;
      await handoff.look();
      await advance(tester, 60000);
      expect(q.fakes, hasLength(asked));
    });

    handoffTest('finds a meeting a build from before left without its summary, and writes it once (Matt’s standup)', (tester) async {
      sortHere();
      const body = '# Engineering standup\n\nGhost was in this meeting on 26 Oct, 09:28 to 09:55.\n\n'
          '## Transcript\n\n**Phil Mulliken:** The release is on track.\n\n**Matt:** I will file the board today.\n';
      q.notes['n2'] = Note(id: 'n2', body: body, createdAt: 0, updatedAt: now - 2 * 3600000, revision: 1, recordingMs: 4000, segments: const [
        Segment(text: 'The release is on track.', startMs: 0, endMs: 2000),
        Segment(text: 'I will file the board today.', startMs: 2100, endMs: 4000),
      ]);
      q.prefs = meeting(q.prefs, 'n2', at: now - 3 * 3600000);
      final handoff = q.summaries.handoff = handoffFor(phone);
      await handoff.look();
      final found = handoffsOf(q.prefs)['n2']!;
      expect(found.from, '', reason: 'nobody marked it: found here');
      expect(q.summaries.summaryPending('n2'), isTrue);
      await advance(tester, 0);
      q.fakes.single.finish(q.answer);
      await advance(tester, 0);
      await advance(tester, 0);
      expect(q.notes['n2']!.body, contains(q.section));
      expect(handoffsOf(q.prefs)['n2']!.done, now);
      expect(sorted, ['n2']);
      expect(store.workspaceOf('n2')?.name, meetingsFolderName);
    });

    test('a stranded meeting is only one Ghost filed, written up, recent, quiet, unsummarized and unsorted', () {
      final at = 10 * 24 * 3600000;
      const body = '# Standup\n\nGhost was in this meeting on 26 Oct, 09:28 to 09:55.\n\n## Transcript\n\n**Sam:** Hello.\n';
      Note n(String text, {int updated = 0}) => Note(id: 'm', body: text, createdAt: 0, updatedAt: updated, revision: 1);
      final prefs = Preferences.defaults.copyWith(meetings: {'m': at - 3600000 * 2});
      expect(strandedMeeting(n(body), prefs, now: at), isTrue);
      expect(strandedMeeting(n(body, updated: at - 60000), prefs, now: at), isFalse, reason: 'quiet for an hour first');
      expect(strandedMeeting(n(body), Preferences.defaults, now: at), isFalse, reason: 'not a meeting');
      expect(strandedMeeting(n(body), prefs.copyWith(meetings: {'m': at - strandedWithinMs - 1}), now: at), isFalse, reason: 'over a week old');
      expect(strandedMeeting(n(body.replaceFirst('Ghost was in this meeting', 'Recorded')), prefs, now: at), isFalse, reason: 'not Ghost’s');
      expect(strandedMeeting(n(body.replaceFirst('09:55.', '09:55. It is being written up on your device.')), prefs, now: at), isFalse, reason: 'still being written up');
      expect(strandedMeeting(n(body.replaceFirst('\n\nGhost', '\n## Summary\nDone.\n\nGhost')), prefs, now: at), isFalse, reason: 'summarized');
      expect(strandedMeeting(n(body), prefs.copyWith(more: {meetingSortsKey: {'m': {'sorted': ''}}}), now: at), isFalse, reason: 'sorted once');
      expect(strandedMeeting(n(body), prefs.copyWith(summaries: 'off'), now: at), isFalse, reason: 'summaries off');
      expect(strandedMeeting(n('# Standup\n\nGhost was in this meeting on 26 Oct.\n'), prefs, now: at), isFalse, reason: 'no words');
    });
  });

  group('the words', () {
    test('a Mac says to turn on Claude or download the model there, or open the phone', () {
      expect(summaryWaitWords('Mac'), 'Waiting for a summary: turn on Claude or download the summary model on this Mac, or open Ghost.md on your phone.');
      expect(summaryWaitWords('phone'), 'Waiting for a summary: turn on Claude or download the summary model on this phone, or open Ghost.md on another of your devices.');
      expect(summaryElsewhereWords('phone'), 'Being summarized on your phone.');
      expect(summaryElsewhereWords(null), 'Being summarized on your other device.');
    });

    test('this device is named once, and keeps its id', () {
      final kept = MemoryStored();
      final first = thisDevice(kept);
      expect(first.id, hasLength(16));
      expect(thisDevice(kept).id, first.id);
    });
  });
}
