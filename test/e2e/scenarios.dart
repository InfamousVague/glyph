// The end-to-end scenarios of stage 7 (docs/STAGE7.md), written once and run in each world (world.dart): against
// the service in memory with the REAL crypto, offline (real_crypto_test.dart), and against the real service on
// 127.0.0.1 (local_server_test.dart). Every device is whole: the real `Account`, the real `SyncEngine`, the real
// CRDT, keys kept and restored through the device key store.
//
// They are the account, sync, organizations, share and feed stories the stage's own tests tell with the fake
// crypto (test/account_dart, test/sync, test/orgs, test/share, test/feed), told again end to end: what those prove
// rule by rule against stand-ins, these prove once each with nothing standing in.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/share/share.dart';

import 'world.dart';

const String _password = 'correct horse battery';

/// A PNG's first bytes and a few more: a picture as far as anything here looks.
final Uint8List _picture = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4, 5, 6, 7, 8, 9]);

/// Registers every scenario against [world]. [world] and [core] are asked for when a test runs, not when it is
/// declared; [manyAccounts] says, at declaring, whether the world will hold more than one account.
void scenarios(World Function() world, GhostCore Function() core, {required bool manyAccounts, String? skip}) {
  final devices = <Device>[];

  Device device(String label, {Disk? disk}) {
    final made = Device(world(), core(), label: label, disk: disk);
    devices.add(made);
    return made;
  }

  setUp(() async {
    if (skip == null) await world().fresh();
  });

  tearDown(() async {
    for (final each in devices) {
      await each.close();
    }
    devices.clear();
  });

  test('an account made on one device opens on another by its password, again by this device\'s key, and by a recovery code', () async {
    final handle = freshHandle('acct');
    final phone = device('phone');
    final made = await phone.account.signUp(handle, _password);
    expect(made.codes, hasLength(8));
    expect(made.codes.first, matches(RegExp(r'^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$')));
    expect(phone.account.value.unlocked, isTrue);
    phone.write('n1', '# Sealed on the phone');
    await phone.sync();

    // Another device, the password: the same account key comes out of its wrap, and opens what the phone sealed.
    final mac = device('mac');
    await expectLater(mac.account.signIn(handle, 'not the password'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)));
    await mac.account.signIn(handle, _password);
    expect(mac.account.session?.handle.toLowerCase(), handle);
    await mac.sync();
    expect(mac.notes['n1']?.body, '# Sealed on the phone');

    // What the phone keeps is three keys, each written down by the core, and the session: nothing else.
    expect(phone.disk.secure.held.keys.toSet(), {'glyph-account-session', 'account', 'device', 'encryption'});
    // The phone closed and opened: the keys are raised from what was kept, and still open the account.
    var again = await phone.relaunched(label: 'phone');
    devices.add(again);
    expect(again.account.value.unlocked, isTrue);
    expect(again.account.session, phone.account.session);
    await again.sync();
    // Its session lapsed: this device signs the service's challenge with the key it kept, and is in again with no
    // password asked.
    final lapsed = again.account.session!;
    await again.keys.setSession(Session(token: 'a-token-the-service-never-gave', handle: lapsed.handle, accountId: lapsed.accountId));
    again = await again.relaunched(label: 'phone');
    devices.add(again);
    await again.account.resume();
    expect(again.account.session, isNotNull, reason: 'the device key did not sign it back in');
    // No longer the token it was left with, which the service never gave: nothing but the device's key gets it
    // another, and the sync below is the service taking that one. (Not "a token other than the one that lapsed":
    // the service's token is the account and the second it was made in, server/src/accounts.rs, so signing in
    // within a second of the last sign-in gives the same token again, and on a quiet Mac this scenario gets
    // here inside the second.)
    expect(again.account.session!.token, isNot('a-token-the-service-never-gave'));
    expect(again.account.value.unlocked, isTrue);
    again.write('n2', 'written after signing in by the device key');
    await again.sync();
    await mac.sync();
    expect(mac.notes['n2']?.body, 'written after signing in by the device key');

    // A recovery code and a new password, on a third device: the key comes out of the code's wrap, the old password
    // is the account's no longer, and the notes are still read.
    final tablet = device('tablet');
    final recovered = await tablet.account.recover(handle, made.codes[3].toLowerCase(), 'a new password entirely');
    expect(recovered.codes, hasLength(8));
    await tablet.sync();
    expect(tablet.notes.keys.toSet(), {'n1', 'n2'});
    final late_ = device('late');
    await expectLater(late_.account.signIn(handle, _password), throwsA(isA<ApiError>()));
    await late_.account.signIn(handle, 'a new password entirely');
    await late_.sync();
    expect(late_.notes['n1']?.body, '# Sealed on the phone');
    // A code is spent once.
    await expectLater(device('thief').account.recover(handle, made.codes[3], 'another password'), throwsA(isA<ApiError>()));
  }, skip: skip);

  test('notes, a picture, a versions file and the settings cross between two devices; an edit on both keeps a copy; a deletion and a notification follow', () async {
    final handle = freshHandle('sync');
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp(handle, _password);
    await mac.account.signIn(handle, _password);

    phone.write('n1', '# Groceries\n\nmilk ![](image/list.png)');
    phone.write('n2', 'a second note', starred: true);
    phone.pictures['list.png'] = _picture;
    phone.disk.files.versions['n1'] = '# Ghost.md versions 1\n# note n1\n\nv1 2026-10-05T00:00:00.000Z $handle 00000000 full\n  +# Groceries\n';
    phone.disk.files.owing.add('n1');
    phone.prefs.update((now) => now.copyWith(theme: 'ember'));
    final home = phone.workspaces.addWorkspace('Home', 'sea')!;
    phone.workspaces.fileNote('n1', home.id);
    await phone.sync();

    await mac.sync();
    expect(mac.notes['n1']?.body, '# Groceries\n\nmilk ![](image/list.png)');
    expect(mac.notes['n2']?.starred, isTrue);
    expect(mac.pictures['list.png'], _picture);
    expect(mac.versions['n1'], contains('v1 2026-10-05'));
    expect(mac.prefs.value.theme, 'ember');
    expect(mac.workspaces.workspaceOf('n1')?.name, 'Home');
    expect(mac.told, greaterThan(0));

    // A setting changed on each, apart: both stand after a pass each way.
    mac.prefs.update((now) => now.copyWith(theme: 'dawn'));
    final work = phone.workspaces.addWorkspace('Work', 'moss')!;
    await mac.sync();
    await phone.sync();
    await mac.sync();
    expect((phone.prefs.value.theme, mac.prefs.value.theme), ('dawn', 'dawn'));
    expect(mac.workspaces.value.list.map((w) => w.id), containsAll([home.id, work.id]));

    // The same note edited on both: the later pass keeps this device's words as a copy, and says so in the feed.
    mac.write('n1', '# Groceries\n\nmilk ![](image/list.png)\neggs', at: 5);
    phone.write('n1', '# Groceries\n\nmilk ![](image/list.png)\nbread', at: 6);
    await mac.sync();
    await phone.engine.syncNow();
    expect(phone.engine.status.value.conflicts, 1);
    expect(phone.notes['n1']?.body, endsWith('eggs'));
    expect(phone.notes.values.where((n) => n.body.endsWith('bread')), hasLength(1));
    await phone.sync();
    await mac.sync();
    expect(mac.notes.values.where((n) => n.body.endsWith('bread')), hasLength(1));
    final told = mac.feed.notifications().where((n) => n.kind == 'sync-conflict').toList();
    expect(told, hasLength(1), reason: 'the copy kept on the phone is a row in the mac\'s feed');
    expect((await mac.feed.detailsFor(told.single))?.noteId, isNotNull);

    // A deletion follows.
    phone.notes.remove('n2');
    await phone.sync();
    await mac.sync();
    expect(mac.notes.containsKey('n2'), isFalse);

    // A notification made on the phone is sealed for the account, and read on the mac without a whole pass.
    await phone.record.record('summary-written', {'noteId': 'n1', 'title': 'Standup'});
    await mac.engine.syncNotificationsNow();
    final written = mac.feed.notifications().where((n) => n.kind == 'summary-written').toList();
    expect(written, hasLength(1));
    expect(written.single.blob, isNot(contains('Standup')));
    final opened = await mac.feed.detailsFor(written.single);
    expect((opened?.noteId, opened?.title), ('n1', 'Standup'));
  }, skip: skip);

  test('a note shared by a link, with its picture, is read with the link alone', () async {
    final handle = freshHandle('share');
    final phone = device('phone');
    await phone.account.signUp(handle, _password);
    phone.write('n1', '# Trip\n\n![](image/map.png)\n\nPack light.');
    phone.pictures['map.png'] = _picture;
    final link = await phone.shares.shareNote(phone.notes['n1']!, phone.notes.values.toList());
    final found = readShareLink(link)!;
    // Anyone with the link, and no account: a device that never signed in.
    final reader = device('reader');
    final shared = await reader.shares.readShared(link);
    expect(shared.title, 'Trip');
    expect(shared.pages.single.body, contains('Pack light.'));
    expect(shared.pictures?['map.png'], _picture);
    // The key is in the link and nowhere on the service: another key opens nothing.
    final other = shareLink(found.id, newShareKey(CoreCrypto(core().invoke)));
    await expectLater(reader.shares.readShared(other), throwsA(anything));
    // The share is one of the account's settings, and goes with them.
    expect(phone.shares.linkFor('n1'), link);
    await phone.sync();
    // Taken down: the link reads nothing.
    await phone.shares.stopSharing('n1');
    await expectLater(reader.shares.readShared(link), throwsA(anything));
  }, skip: skip);

  test('an organization: its key made on one device and read on the account\'s other, and a team note edited on both, merged with no copy', () async {
    final handle = freshHandle('team');
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp(handle, _password);
    await mac.account.signIn(handle, _password);
    final org = await phone.orgs.createOrg('Ghost', hue: 'moss');
    await phone.sync();
    expect(phone.orgKeys.orgKeyGeneration(org.id), 1);
    final space = orgWorkspaceId(org.id);
    phone.write('t1', 'one\ntwo\nthree ![](image/team.png)');
    phone.pictures['team.png'] = _picture;
    phone.workspaces.fileNote('t1', space);
    phone.write('own', 'the account\'s own note');
    await phone.sync();

    // The mac: the account's pair from the service, the organization key out of its wrap, the team's note and its
    // picture from the organization, filed in its workspace; the account's own note by the account's feed.
    await mac.sync();
    expect(mac.orgKeys.orgKeyGeneration(org.id), 1);
    expect(mac.notes['t1']?.body, 'one\ntwo\nthree ![](image/team.png)');
    expect(mac.workspaces.workspaceOf('t1')?.id, space);
    expect(mac.pictures['team.png'], _picture);
    expect(mac.notes['own']?.body, 'the account\'s own note');

    // Edited on both, apart: the phone at the top, the mac at the foot. The CRDT merges; nobody keeps a copy.
    phone.write('t1', 'ONE\ntwo\nthree ![](image/team.png)', at: 7);
    mac.write('t1', 'one\ntwo\nTHREE ![](image/team.png)', at: 8);
    await phone.sync();
    await mac.sync();
    await phone.sync();
    const merged = 'ONE\ntwo\nTHREE ![](image/team.png)';
    expect((phone.notes['t1']?.body, mac.notes['t1']?.body), (merged, merged));
    expect(phone.engine.status.value.conflicts + mac.engine.status.value.conflicts, 0);
    expect(phone.notes.keys.toSet(), {'t1', 'own'});
    expect(mac.notes.keys.toSet(), {'t1', 'own'});

    // The phone closed and opened: its documents are read back from where they were kept, the organization key
    // from its wrap, and a third edit crosses.
    final again = await phone.relaunched(label: 'phone');
    devices.add(again);
    again.write('t1', '$merged\nfour', at: 9);
    await again.sync();
    await mac.sync();
    expect(mac.notes['t1']?.body, '$merged\nfour');

    // Unfiled on the mac: no evidence it left, so it stays the team's (ddeb6141) and the phone keeps it.
    mac.workspaces.fileNote('t1', null);
    await mac.sync();
    await again.sync();
    expect(again.notes.containsKey('t1'), isTrue);

    // Filed in a workspace of the account's own on the mac: gone from the team, and from the phone.
    final mine = mac.workspaces.addWorkspace('Mine', 'sea')!;
    mac.workspaces.fileNote('t1', mine.id);
    await mac.sync();
    await again.sync();
    expect(again.notes.containsKey('t1'), isFalse);
  }, skip: skip);

  test('two accounts in one organization: invited by handle, the key wrapped for the member, a team note edited by both, and the key turned when the member goes', () async {
    final owner = freshHandle('owner'), member = freshHandle('member');
    final ada = device('ada'), ben = device('ben');
    await ada.account.signUp(owner, _password);
    await ben.account.signUp(member, 'another password, ben\'s');
    final org = await ada.orgs.createOrg('Ghost');
    await ada.sync();
    final space = orgWorkspaceId(org.id);
    ada.write('t1', '# Plan\n- a');
    ada.workspaces.fileNote('t1', space);
    await ada.sync();
    await ada.orgs.inviteByHandle(org.id, member);

    // Ben hears of the invitation in his feed, answers it, and registers his pair; Ada's next pass wraps the key
    // for him; his next reads it, and the team's note with it.
    await ben.engine.syncNotificationsNow();
    expect(ben.feed.notifications().where((n) => n.kind == 'invite'), hasLength(1));
    ben.feed.answerInvite(org.id, true);
    await ben.sync();
    await ada.sync();
    await ben.sync();
    expect(ben.orgKeys.orgKeyGeneration(org.id), 1);
    expect(ben.notes['t1']?.body, '# Plan\n- a');

    // Each adds a line, apart.
    ada.write('t1', '# Plan\n- a\n- ada\'s', at: 3);
    ben.write('t1', '# Plan (ben)\n- a', at: 4);
    await ada.sync();
    await ben.sync();
    await ada.sync();
    const merged = '# Plan (ben)\n- a\n- ada\'s';
    expect((ada.notes['t1']?.body, ben.notes['t1']?.body), (merged, merged));

    // Ben is removed: Ada's pass turns the key and seals the team's notes again under the new one.
    await ada.orgs.removeMember(org.id, member);
    await ada.sync();
    await ada.sync();
    expect(ada.orgKeys.orgKeyGeneration(org.id), 2);
    ada.write('t1', '$merged\n- after ben', at: 9);
    await ada.sync();
    // A second device of Ada's reads everything with the new key alone.
    final laptop = device('ada\'s laptop');
    await laptop.account.signIn(owner, _password);
    await laptop.sync();
    expect(laptop.orgKeys.orgKeyGeneration(org.id), 2);
    expect(laptop.notes['t1']?.body, '$merged\n- after ben');
    // Ben's device is told he is no longer a member, and what was written after never reaches it.
    await ben.engine.syncNow();
    expect(ben.orgs.orgsState().list.where((row) => row.id == org.id && row.state == 'member'), isEmpty);
    expect(ben.notes['t1']?.body ?? merged, isNot(contains('after ben')));
  }, skip: skip ?? (manyAccounts ? null : 'the service in memory holds one account'));
}
