// A meeting Ghost was in, written up across two of Matt's devices and filed in an organization's Meetings folder,
// is ONE note on every device: its summary at the top under the title, its transcript below, its recording with it
// (Matt, 2026-10-29: "make it so the transcripts and meeting summaries are shown in one file"; asked where they show
// apart, two notes per meeting).
//
// What his account showed that day: today's "Engineering Standup" in HelloTrade › Meetings, with its recording and a
// transcript and no summary, though it had been summarized, sorted into that folder and posted to Slack; and beside
// it "Engineering Standup (shared)", the same words again. The second is the share link's (test/share/
// app_links_test.dart). The first is played here, and it came out exactly so before this change: "# Engineering
// Standup / Ghost was in this meeting on 29 Oct, 09:28 to 10:06. / ## Transcript …" on both devices, and nothing else.
// The device holding the recording (the phone here) lands Whisper's transcript over the words it had, from before the
// summary; the device that wrote the summary (the Mac) files the meeting in HelloTrade › Meetings. When the team's row
// reached the phone, the phone's words were reconciled into it whole as its own change, and they said the summary
// was not there: it went from the team's note, and so from every device. Where the account's own feed met the two
// first, it kept the phone's as a second note of the meeting (a conflict copy).
//
// Each case is a different order of the same five things (the summary written, the filing, the transcript landed, and
// each device's passes), every order that two devices a pass apart can make of them, and each was proved to fail
// without the part of the change it names: lib/team/sync.dart `_ownWords` (A, B), lib/sync/notes.dart
// `NoteMark.before` (A, B), `_mergeIntoTeams` (D, E), and the meeting's three-way merge in `_merge` (E, which kept a
// copy).
//
// The devices are whole (test/e2e/world.dart: the real engine, account, organizations and keys, the real crypto and
// CRDT over the Mac's core, tool/build-native.sh host; skipped out loud without it), the other member the team's
// channel alone (support.dart), all over the service in memory.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/core/library.dart' show withTranscript;
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/summary_text.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/share/app_links.dart';
import 'package:ghost_md/share/share.dart';
import 'package:ghost_md/team/crdt.dart';

import '../e2e/world.dart';
import 'support.dart';

const String _password = 'correct horse battery';

const String _id = 'standup';

/// The note the meeting step files (lib/meet/meet_note.dart `meetNoteBody`), its captions waiting for the write-up.
const String _filed = '# Engineering Standup\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06. It is being written up on your device.\n\n## Captions\n\n**Sam Lee (0:04):** Morning.\n\n**Matt (0:10):** Shipping today.\n';

/// The summary the queue writes from the captions (lib/ai/summaries.dart, CAPTIONS FIRST).
const String _section = '## Summary\n\nThe team agreed to ship today.\n\n- [ ] Matt: ship the build';
const String _transcript = '## Transcript\n\n**Sam Lee (0:04):** Morning.\n\n**Matt (0:10):** Shipping today.';

/// The words with Whisper's transcript landed (tauri/src-tauri/src/transcript.rs `with_transcript`) and its speakers
/// named from the captions, which then go (lib/meet/meet_note.dart `withSpeakers`).
String _heard(String body) => withTranscript(body.replaceFirst(' It is being written up on your device.', '').replaceFirst(RegExp(r'\n## Captions[\s\S]*$'), '').trimRight(), _transcript);

final Uint8List _tape = Uint8List.fromList(List.generate(4096, (i) => i % 251));

void main() {
  late GhostCore core;
  late FakeWorld world;
  final devices = <Device>[];
  final members = <TeamDevice>[];

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await GhostCore.open(libraryPath: File(coreLibrary).absolute.path);
    world = FakeWorld(core);
  });

  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  setUp(() async {
    if (coreBuilt) await world.fresh();
  });

  tearDown(() async {
    for (final each in devices) {
      await each.close();
    }
    for (final each in members) {
      await each.docs.forget();
    }
    devices.clear();
    members.clear();
  });

  Device device(String label) {
    final made = Device(world, core, label: label, folders: true);
    devices.add(made);
    return made;
  }

  /// The meeting filed on the phone, which kept its recording (lib/meet/meet_in.dart), and synced to the Mac.
  Future<({Device phone, Device mac, Workspace meetings, String orgId})> filed() async {
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp('matt', _password);
    await mac.account.signIn('matt', _password);
    final org = await phone.orgs.createOrg('HelloTrade', hue: 'violet');
    await phone.sync();
    final meetings = phone.workspaces.addWorkspace('Meetings', 'ink', orgWorkspaceId(org.id))!;
    phone.prefs.update((p) => p.copyWith(meetings: {...p.meetings, _id: 1}));
    phone.notes[_id] = Note(id: _id, body: _filed, createdAt: 10, updatedAt: 10, source: NoteSource.capture, recordingMs: 60000);
    phone.disk.files.tapes[_id] = _tape;
    await phone.sync();
    await mac.sync();
    await phone.sync();
    expect(mac.notes[_id]?.body, _filed);
    return (phone: phone, mac: mac, meetings: meetings, orgId: org.id);
  }

  /// The summary written on the Mac, as the queue writes it into a closed note (lib/ai/summaries.dart `_write`).
  void summarized(Device on) => on.write(_id, withSummary(on.notes[_id]!.body, _section), at: 20);

  /// Whisper's transcript landed on the phone, over the words the phone has.
  void heard(Device on) => on.write(_id, _heard(on.notes[_id]!.body), at: 30);

  Future<void> rounds(Device first, Device second, [int n = 3]) async {
    for (var i = 0; i < n; i += 1) {
      await first.sync();
      await second.sync();
    }
  }

  /// One note of the meeting, its summary at the top under the title, the transcript below, the recording with it.
  void oneNote(Device d, {required String orgId, required Workspace meetings}) {
    expect(d.notes.keys.toSet(), {_id}, reason: 'one note of the meeting, no copy');
    final body = d.notes[_id]!.body;
    expect(summarySection(body)?.text, _section);
    expect(body.indexOf('# Engineering Standup'), 0);
    expect(body.indexOf('## Summary'), lessThan(body.indexOf('Ghost was in this meeting')));
    expect(body.indexOf('Ghost was in this meeting'), lessThan(body.indexOf('## Transcript')));
    expect(body, isNot(contains('## Captions')));
    expect(body, isNot(contains('being written up')));
    expect('## Summary'.allMatches(body).length, 1);
    expect('## Transcript'.allMatches(body).length, 1);
    expect(d.notes[_id]!.recordingMs, 60000);
    expect(d.workspaces.workspaceOf(_id)?.id, meetings.id);
    expect(d.engine.status.value.conflicts, 0);
  }

  test('A: the summary written on the Mac and the meeting filed, then the phone, a pass behind, lands its transcript over the words from before the summary: one note, both, on both devices and a member’s', () async {
    final (:phone, :mac, :meetings, :orgId) = await filed();
    summarized(mac);
    await mac.sync();
    mac.workspaces.fileNote(_id, meetings.id);
    await mac.sync();
    heard(phone);
    await rounds(phone, mac);
    for (final d in [phone, mac]) {
      oneNote(d, orgId: orgId, meetings: meetings);
    }
    expect(phone.notes[_id]!.body, mac.notes[_id]!.body);
    expect(mac.disk.files.tapes[_id], _tape, reason: 'the recording reached the Mac');
    // The team holds it, the account's own row is gone, and another member reads the same one note.
    expect(world.service.teamNotes(orgId)[_id]?.deleted, isFalse);
    expect(world.service.notes[_id]?.deleted, isTrue);
    final other = TeamDevice(crdt: Crdt(core.invoke), api: world.api(), crypto: CoreCrypto(core.invoke), token: () => phone.account.session!.token, orgId: orgId, orgKey: phone.orgKeys.orgKeyOf(orgId)!, folders: true);
    members.add(other);
    await other.sync();
    expect(other.notes.keys.toSet(), {_id});
    expect(other.notes[_id]!.body, mac.notes[_id]!.body);
    expect(other.workspaces!.workspaceOf(_id)?.name, 'Meetings');
  }, skip: coreSkip);

  test('B: filed on the Mac in the same pass as its summary went, the phone a pass behind', () async {
    final (:phone, :mac, :meetings, :orgId) = await filed();
    summarized(mac);
    mac.workspaces.fileNote(_id, meetings.id);
    await mac.sync();
    heard(phone);
    await rounds(phone, mac);
    for (final d in [phone, mac]) {
      oneNote(d, orgId: orgId, meetings: meetings);
    }
  }, skip: coreSkip);

  test('C: the phone has the summary before its transcript lands', () async {
    final (:phone, :mac, :meetings, :orgId) = await filed();
    summarized(mac);
    await mac.sync();
    mac.workspaces.fileNote(_id, meetings.id);
    await mac.sync();
    await phone.sync();
    expect(summarySection(phone.notes[_id]!.body), isNotNull);
    heard(phone);
    await rounds(phone, mac);
    for (final d in [phone, mac]) {
      oneNote(d, orgId: orgId, meetings: meetings);
    }
  }, skip: coreSkip);

  test('D: the phone’s transcript reaches the account before the Mac, which summarized and filed it, takes the account’s row away', () async {
    final (:phone, :mac, :meetings, :orgId) = await filed();
    summarized(mac);
    mac.workspaces.fileNote(_id, meetings.id);
    heard(phone);
    await phone.sync();
    await rounds(mac, phone);
    for (final d in [phone, mac]) {
      oneNote(d, orgId: orgId, meetings: meetings);
    }
  }, skip: coreSkip);

  test('E: the transcript meets the summary in the account’s own feed before the filing: merged, not kept twice', () async {
    final (:phone, :mac, :meetings, :orgId) = await filed();
    summarized(mac);
    await mac.sync();
    heard(phone);
    await phone.sync();
    expect(phone.notes.keys.toSet(), {_id}, reason: 'no conflict copy');
    expect(summarySection(phone.notes[_id]!.body), isNotNull);
    mac.workspaces.fileNote(_id, meetings.id);
    await rounds(mac, phone);
    for (final d in [phone, mac]) {
      oneNote(d, orgId: orgId, meetings: meetings);
    }
  }, skip: coreSkip);

  test('the meeting’s share link, as Slack posts it, opened on the other device opens the meeting: no "(shared)" copy', () async {
    final (:phone, :mac, :meetings, :orgId) = await filed();
    summarized(mac);
    await mac.sync();
    mac.workspaces.fileNote(_id, meetings.id);
    // The Slack post's link (lib/plugins/slack/meetings.dart `shareLink`, the root's Shares.shareNote).
    final link = await mac.shares.shareNote(mac.notes[_id]!, mac.notes.values.toList());
    await mac.sync();
    heard(phone);
    await rounds(phone, mac);
    final found = readShareLink(link)!;
    // The reader page's Open in Ghost.md, on the phone, and the same on the Mac.
    for (final d in [phone, mac]) {
      final forked = await forkFromLink(
        'ghostmd://fork#${found.id}.${found.key}',
        shares: d.shares,
        notes: () async => d.notes.values.toList(),
        save: (body) async => fail('a copy was saved: ${body.split('\n').first}'),
      );
      expect(forked, isA<ForkedOwn>().having((f) => f.noteId, 'note', _id));
      oneNote(d, orgId: orgId, meetings: meetings);
    }
  }, skip: coreSkip);
}
