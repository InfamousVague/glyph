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
// copy). The Mac gives the title its day as it writes the summary, which only a true merge keeps: each of those cases
// is a merge from a base both sides grew from, not the fallback. And one case where the base cannot be trusted (the
// Testing session's review, 2026-10-29): the phone's words with the account are from after the meeting left it, the
// revision check sees so, and the fallback keeps everything but that title, where merging from them lost the
// transcript.
//
// The devices are whole (test/e2e/world.dart: the real engine, account, organizations and keys, the real crypto and
// CRDT over the Mac's core, tool/build-native.sh host; skipped out loud without it), the other member the team's
// channel alone (support.dart), all over the service in memory.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
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
const String _renamed = '# Engineering Standup, 29 Oct';
const String _transcript = '## Transcript\n\n**Sam Lee (0:04):** Morning.\n\n**Matt (0:10):** Shipping today.';

/// The words with Whisper's transcript landed (tauri/src-tauri/src/transcript.rs `with_transcript`) and its speakers
/// named from the captions, which then go (lib/meet/meet_note.dart `withSpeakers`).
String _heard(String body) => withTranscript(body.replaceFirst(' It is being written up on your device.', '').replaceFirst(RegExp(r'\n## Captions[\s\S]*$'), '').trimRight(), _transcript);

/// The service in memory as the phone reaches it, its settings and the organizations' list refused while [prefsDown]
/// is set: a pass goes on without them, as it does when those calls fail, so the phone hears neither of the filing nor
/// from the team's channel.
class _Patchy implements World {
  _Patchy(this.inner);
  final FakeWorld inner;
  bool prefsDown = false;

  @override
  String get name => inner.name;

  @override
  bool get manyAccounts => false;

  @override
  Future<void> fresh() async {}

  @override
  Api api() => Api(
        base: 'http://service.test/api',
        fetcher: (request) async {
          if (prefsDown && (request.url.path.endsWith('/prefs') || (request.method == 'GET' && request.url.path.endsWith('/orgs')))) return FetchResponse.json(503, {'error': 'Try again in a moment.'});
          return inner.service.fetcher(request);
        },
      );
}

final Uint8List _tape =Uint8List.fromList(List.generate(4096, (i) => i % 251));

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

  Device device(String label, {World? through}) {
    final made = Device(through ?? world, core, label: label, folders: true);
    devices.add(made);
    return made;
  }

  /// The meeting filed on the phone, which kept its recording (lib/meet/meet_in.dart), and synced to the Mac. The phone
  /// reaches the service through [phoneLine] where one is given.
  Future<({Device phone, Device mac, Workspace meetings, String orgId})> filed({World? phoneLine}) async {
    final phone = device('phone', through: phoneLine), mac = device('mac');
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

  /// The summary written on the Mac, as the queue writes it into a closed note (lib/ai/summaries.dart `_write`), and the
  /// title given its day there: a change of the summary's side that only a merge keeps (the fallback, this device's
  /// words with the summary, would not), so each case shows the merge was made from a base it could trust.
  void summarized(Device on) => on.write(_id, withSummary(on.notes[_id]!.body, _section).replaceFirst('# Engineering Standup\n', '$_renamed\n'), at: 20);

  /// Whisper's transcript landed on the phone, over the words the phone has.
  void heard(Device on) => on.write(_id, _heard(on.notes[_id]!.body), at: 30);

  Future<void> rounds(Device first, Device second, [int n = 3]) async {
    for (var i = 0; i < n; i += 1) {
      await first.sync();
      await second.sync();
    }
  }

  /// One note of the meeting, its summary at the top under the title, the transcript below, the recording with it.
  void oneNote(Device d, {required String orgId, required Workspace meetings, bool merged = true}) {
    expect(d.notes.keys.toSet(), {_id}, reason: 'one note of the meeting, no copy');
    final body = d.notes[_id]!.body;
    expect(summarySection(body)?.text, _section);
    expect(body.indexOf('# Engineering Standup'), 0);
    if (merged) expect(body, startsWith('$_renamed\n'), reason: 'merged: the summary side’s other change stands too');
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

  // The Testing session's review, 2026-10-29: a merge is only as good as its base. Here the phone's words with the
  // account are from AFTER the meeting went to the team: it put its transcript back as the account's row (the
  // deletion answered with its words), then wrote on and sent that too, all before it heard of the filing (its settings
  // not arriving). Its last words with the account are then its own words, and "unchanged since" would have taken the
  // team's words over them: the transcript and the line it wrote went (proved so with the revision check taken out).
  // The team's row says it left the account at the Mac's revision, the phone's words are of a later one, so they are
  // not trusted: the phone's words stand, with the team's summary, and nothing is doubled. The Mac's new title, the
  // one thing only a merge would have kept, is the price.
  test('a stale base: the phone’s words with the account are from after the meeting left for the team, so they are not merged from, and nothing is lost or doubled', () async {
    final line = _Patchy(world);
    final (:phone, :mac, :meetings, :orgId) = await filed(phoneLine: line);
    summarized(mac);
    await mac.sync();
    mac.workspaces.fileNote(_id, meetings.id);
    await mac.sync();
    expect(world.service.teamNotes(orgId)[_id]?.deleted, isFalse);
    // The phone, its settings and organizations not arriving: its transcript put back as the account's row, then a line
    // written and sent.
    line.prefsDown = true;
    heard(phone);
    await phone.engine.syncNow();
    phone.write(_id, '${phone.notes[_id]!.body}\n\nMatt: follow up with Sam.', at: 40);
    await phone.engine.syncNow();
    expect(world.service.notes[_id]?.deleted, isFalse, reason: 'the account holds the phone’s words again');
    line.prefsDown = false;
    await rounds(phone, mac);
    for (final d in [phone, mac]) {
      oneNote(d, orgId: orgId, meetings: meetings, merged: false);
      final body = d.notes[_id]!.body;
      expect(body, contains('Matt: follow up with Sam.'));
      expect('Matt: follow up with Sam.'.allMatches(body).length, 1);
      expect('**Sam Lee (0:04):** Morning.'.allMatches(body).length, 1);
    }
    expect(phone.notes[_id]!.body, mac.notes[_id]!.body);
  }, skip: coreSkip);

  // A row put again by something that writes only what it knows of a team's row: the connector before 2026-10-29
  // (mcp/team.ts `putRow` wrote the note, the document and its seq, the pictures and the versions, nothing else), or
  // any build from before a field it does not carry. Here it pins the meeting from Claude, between the Mac's filing and
  // the phone's first read of the team's row, and the row loses its 'from'. The phone never saw it, so it has no word
  // of where the note left the account and no base it can trust: its own words stand with the team's summary, the
  // fallback, and nothing is lost or doubled. The Mac's new title, which only a merge keeps, is the price; case A is
  // this same order with the row as the Mac put it, and merges.
  test('a connector puts the team’s row again without its "from": the phone, which never saw it, keeps its words with the team’s summary, nothing lost or doubled', () async {
    final (:phone, :mac, :meetings, :orgId) = await filed();
    summarized(mac);
    await mac.sync();
    mac.workspaces.fileNote(_id, meetings.id);
    await mac.sync();
    final crypto = CoreCrypto(core.invoke), key = mac.orgKeys.orgKeyOf(orgId)!, context = 'org:$orgId:note:$_id';
    Future<Map<Object?, Object?>> payload() async => await crypto.open(key, world.service.teamNotes(orgId)[_id]!.blob!, context) as Map<Object?, Object?>;
    final put = await payload();
    expect(put['from'], isA<Map<Object?, Object?>>(), reason: 'the Mac said which revision the meeting left the account at');
    // The connector's put: what it knew of the row, the pin set.
    final stripped = {
      for (final field in ['v', 'note', 'state', 'seq', 'images', 'versions'])
        if (put.containsKey(field)) field: put[field],
    };
    stripped['note'] = {...put['note']! as Map<Object?, Object?>, 'starred': true};
    final blob = await crypto.seal(key, stripped, context);
    await world.api().call('PUT', 'orgs/${Uri.encodeComponent(orgId)}/notes/$_id', token: mac.account.session!.token, body: {'base': world.service.teamNotes(orgId)[_id]!.rev, 'blob': blob, 'upTo': put['seq']});
    expect((await payload()).containsKey('from'), isFalse);

    heard(phone);
    await rounds(phone, mac);
    for (final d in [phone, mac]) {
      oneNote(d, orgId: orgId, meetings: meetings, merged: false);
      final body = d.notes[_id]!.body;
      expect(body, startsWith('# Engineering Standup\n'), reason: 'the fallback, not a merge: no base it could trust');
      expect('**Sam Lee (0:04):** Morning.'.allMatches(body).length, 1);
      expect('**Matt (0:10):** Shipping today.'.allMatches(body).length, 1);
      expect('Ghost was in this meeting'.allMatches(body).length, 1);
      expect(d.notes[_id]!.starred, isTrue, reason: 'the connector’s pin stands');
    }
    expect(phone.notes[_id]!.body, mac.notes[_id]!.body);
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
