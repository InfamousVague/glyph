// The organizations against the service in memory (lib/orgs/orgs.dart). A port of
// `src/app/core/orgs/orgs.test.ts`, case for case: the calls and the service's words, the list kept per account, and
// the reconcile that makes an organization's workspace on every member's device - only after a list that arrived
// (D5), so a service without the route, or one that is down, unfiles nobody's notes.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/kept_workspaces.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/orgs/orgs.dart';

import '../feed/signed.dart';
import '../support/fake_service.dart';

/// This device: its account, its workspaces in its preferences, and its organizations.
class Here {
  Here(this.service) {
    prefs.startWithoutStorage();
    storage = KeptWorkspaceStorage(prefs: prefs, stored: kept);
    workspaces = WorkspaceStore(storage: storage);
    orgs = Orgs(account: account, api: apiOf(service), workspaces: workspaces, kept: kept);
  }
  final FakeService service;
  final MemoryStored kept = MemoryStored();
  final PreferencesStore prefs = PreferencesStore();
  final SignedAccount account = SignedAccount(session: testSession);
  late final KeptWorkspaceStorage storage;
  late final WorkspaceStore workspaces;
  late final Orgs orgs;

  CallContext get ctx => CallContext(token: service.signedIn());
  List<String> get ids => [for (final w in workspaces.value.list) w.id];
}

/// A device's view of the list, synced through [service].
class ListDevice {
  ListDevice(this.here, this.service, [Fetcher? fetcher]) : api = apiOf(service, fetcher);
  final Here here;
  final FakeService service;
  final Api api;
  OrgState state = OrgState.none;

  Future<List<OrgRow>?> sync() => here.orgs.syncOrgs(OrgsContext(token: service.signedIn(), api: api, save: (next) => state = next, now: () => 99));
}

Matcher throwsWords(String words) => throwsA(isA<ApiError>().having((e) => e.message, 'message', words));

void main() {
  group('the calls', () {
    test('make an organization with the caller as owner, and its workspace here at once', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final org = await here.orgs.createOrg('  Ghost ', hue: 'sea', ctx: here.ctx);
      expect((org.name, org.hue, org.role, org.state), ('Ghost', 'sea', 'owner', 'member'));
      expect(org.members.map((m) => (m.handle, m.role, m.state)), [('matt', 'owner', 'member')]);
      expect(here.workspaces.value.list, [Workspace(id: 'org-${org.id}', name: 'Ghost', hue: 'sea')]);
      expect(here.workspaces.value.list.single.org, org.id);
      expect(here.orgs.orgsState().list.map((r) => (r.id, r.name, r.members)), [(org.id, 'Ghost', 1)]);
      expect((await here.orgs.listOrgs(ctx: here.ctx)).rows.map((r) => (r.id, r.role, r.state, r.members)), [(org.id, 'owner', 'member', 1)]);
      expect((await here.orgs.fetchOrg(org.id, ctx: here.ctx)).id, org.id);
    });

    test('invite by handle, and say so in the service’s words when nobody has it', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final org = await here.orgs.createOrg('Ghost', ctx: here.ctx);
      final invited = await here.orgs.inviteByHandle(org.id, 'sam', ctx: here.ctx);
      expect((invited.handle, invited.role, invited.state, invited.invitedBy), ('sam', 'member', 'invited', 'matt'));
      await expectLater(here.orgs.inviteByHandle(org.id, 'nobody', ctx: here.ctx), throwsWords('No one has that handle.'));
      await expectLater(here.orgs.inviteByHandle(org.id, 'matt', ctx: here.ctx), throwsWords('They are already a member.'));
      // A pending invitation asked again is refreshed, not doubled.
      await here.orgs.inviteByHandle(org.id, 'sam', ctx: here.ctx);
      expect((await here.orgs.fetchOrg(org.id, ctx: here.ctx)).members, hasLength(2));
    });

    test('rename and re-hue, with the workspace following; remove and leave; delete with the workspace gone', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final org = await here.orgs.createOrg('Ghost', ctx: here.ctx);
      await here.orgs.updateOrg(org.id, name: 'Boo', hue: () => 'rose', ctx: here.ctx);
      expect((here.workspaces.value.list[0].name, here.workspaces.value.list[0].hue), ('Boo', 'rose'));
      await here.orgs.inviteByHandle(org.id, 'sam', ctx: here.ctx);
      await here.orgs.removeMember(org.id, 'sam', ctx: here.ctx);
      expect((await here.orgs.fetchOrg(org.id, ctx: here.ctx)).members, hasLength(1));
      await expectLater(here.orgs.removeMember(org.id, 'sam', ctx: here.ctx), throwsWords('No one by that handle is in this organization.'));
      // The owner cannot leave, nor change their own role.
      await expectLater(here.orgs.removeMember(org.id, 'matt', ctx: here.ctx), throwsWords('Hand the organization over first.'));
      await expectLater(here.orgs.setRole(org.id, 'matt', 'admin', ctx: here.ctx), throwsWords('Hand the organization over first.'));
      here.workspaces.fileNote('n1', 'org-${org.id}');
      await here.orgs.deleteOrg(org.id, ctx: here.ctx);
      expect(here.workspaces.value.list, isEmpty);
      expect(here.workspaces.workspaceOf('n1'), isNull);
      expect(here.orgs.orgsState().list, isEmpty);
      // A 404 in the service's words surfaces as one: it is an answer, not a service without the route.
      await expectLater(here.orgs.fetchOrg(org.id, ctx: here.ctx), throwsWords('No such organization.'));
    });

    test('hand the organization over, and the old owner is an admin at once', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final org = await here.orgs.createOrg('Ghost', ctx: here.ctx);
      await here.orgs.inviteByHandle(org.id, 'sam', ctx: here.ctx);
      await expectLater(here.orgs.setRole(org.id, 'sam', 'owner', ctx: here.ctx), throwsWords('They have not joined yet.'));
      service.orgs[org.id]!.rows['sam']!.state = 'member';
      final handed = await here.orgs.setRole(org.id, 'sam', 'owner', ctx: here.ctx);
      expect((handed.handle, handed.role), ('sam', 'owner'));
      expect(here.orgs.orgRow(org.id)?.role, 'admin');
      expect(service.rowIn(org.id), (role: 'admin', state: 'member'));
    });

    test('answer an invitation: joined, with the workspace made; or declined, with the row gone', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final joined = service.invited('Ghost', 'sam');
      final declined = service.invited('Boo', 'sam');
      final phone = ListDevice(here, service);
      await phone.sync();
      expect(phone.state.list.map((r) => r.state), ['invited', 'invited']);
      // An invitation gets no workspace.
      expect(here.ids, isEmpty);
      final org = await here.orgs.postInviteAnswer(joined, true, ctx: here.ctx);
      expect((org?.id, org?.state, org?.role), (joined, 'member', 'member'));
      expect(here.ids, ['org-$joined']);
      expect(await here.orgs.postInviteAnswer(declined, false, ctx: here.ctx), isNull);
      await expectLater(here.orgs.postInviteAnswer(declined, true, ctx: here.ctx), throwsWords('You were not invited.'));
      await phone.sync();
      expect(phone.state.list.map((r) => (r.id, r.state)), [(joined, 'member')]);
    });

    test('refuse signed out, before any round trip', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      here.account.session = null;
      service.calls.clear();
      await expectLater(here.orgs.listOrgs(), throwsWords('Sign in first.'));
      expect(service.calls, isEmpty);
    });

    test('make, list and turn off an invite link; say what a code joins, and join by it', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final org = await here.orgs.createOrg('Ghost', ctx: here.ctx);
      final link = await here.orgs.makeInviteLink(org.id, terms: const LinkTerms(expiresIn: 3600, maxUses: 5), ctx: here.ctx);
      expect((link.maxUses, link.uses, link.by, link.expiresAt != null), (5, 0, 'matt', true));
      expect((await here.orgs.listInviteLinks(org.id, ctx: here.ctx)).map((l) => l.code), [link.code]);
      await expectLater(here.orgs.makeInviteLink(org.id, terms: const LinkTerms(expiresIn: 60), ctx: here.ctx), throwsWords('A link lasts an hour to thirty days, or until it is turned off.'));
      await here.orgs.dropInviteLink(org.id, link.id, ctx: here.ctx);
      expect(await here.orgs.listInviteLinks(org.id, ctx: here.ctx), isEmpty);
      await expectLater(here.orgs.previewJoin(link.code, ctx: here.ctx), throwsWords('That invite link has expired or was turned off.'));
      // A link a peer sent: what it joins is said before anything is joined, and joining makes the row and the
      // workspace here at once, as accepting does.
      final code = service.peerLink('Boo', by: 'sam');
      final preview = await here.orgs.previewJoin(code, ctx: here.ctx);
      expect((preview.name, preview.by, preview.member, preview.members), ('Boo', 'sam', false, 1));
      final joined = await here.orgs.joinByLink(code, ctx: here.ctx);
      expect((joined.name, joined.role, joined.state), ('Boo', 'member', 'member'));
      expect(here.ids, containsAll(['org-${org.id}', 'org-${joined.id}']));
      expect(here.orgs.orgRow(joined.id)?.members, 2);
    });

    test('set the account’s colour and one organization’s, each row following at once', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final ghost = await here.orgs.createOrg('Ghost', ctx: here.ctx);
      final boo = await here.orgs.createOrg('Boo', ctx: here.ctx);
      await here.orgs.setOrgColour(boo.id, 'rose', ctx: here.ctx);
      await here.orgs.setAccountColour('sea', ctx: here.ctx);
      expect(here.orgs.orgsState().colour, 'sea');
      // A row with no override wears the account's colour; one with its own keeps it.
      expect(here.orgs.orgRow(ghost.id)?.colour, 'sea');
      expect(here.orgs.orgRow(boo.id)?.colour, 'rose');
      await expectLater(here.orgs.setAccountColour('ultraviolet', ctx: here.ctx), throwsWords('That hue is not one of the workspace hues.'));
    });
  });

  group('the reconcile', () {
    test('runs on a list that arrived, and only over the organizations the person is a member of', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final ghost = await here.orgs.createOrg('Ghost', hue: 'moss', ctx: here.ctx);
      final invited = service.invited('Boo', 'sam');
      final phone = ListDevice(here, service);
      await phone.sync();
      expect((phone.state.at, phone.state.colour), (99, null));
      expect(phone.state.list.map((r) => (r.id, r.state)), [(ghost.id, 'member'), (invited, 'invited')]);
      expect(here.workspaces.value.list, [Workspace(id: 'org-${ghost.id}', name: 'Ghost', hue: 'moss')]);
      // Renamed elsewhere: the workspace follows on the next list. Left: it goes, and its notes are unfiled.
      service.orgs[ghost.id]!.name = 'Spectre';
      here.workspaces.fileNote('n1', 'org-${ghost.id}');
      await phone.sync();
      expect(here.workspaces.value.list[0].name, 'Spectre');
      expect(here.workspaces.workspaceOf('n1')?.id, 'org-${ghost.id}');
      service.orgs.remove(ghost.id);
      await phone.sync();
      expect(here.ids, isEmpty);
      expect(here.workspaces.workspaceOf('n1'), isNull);
    });

    test('changes nothing - no workspace, no kept list - when the list does not arrive', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final ghost = await here.orgs.createOrg('Ghost', ctx: here.ctx);
      here.workspaces.fileNote('n1', 'org-${ghost.id}');
      final was = here.workspaces.value;
      final notYet = await FakeService.start(seed: testAccount, teams: false);
      final older = ListDevice(here, notYet);
      expect(await older.sync(), isNull);
      expect(older.state, OrgState.none);
      expect(identical(here.workspaces.value, was), isTrue);

      final offline = ListDevice(here, service, down);
      await expectLater(offline.sync(), throwsWords('The service is down.'));
      expect(offline.state, OrgState.none);
      expect(identical(here.workspaces.value, was), isTrue);
      expect(here.workspaces.workspaceOf('n1')?.id, 'org-${ghost.id}');
    });

    test('makes one workspace per organization across devices, so a filing keyed by it survives whichever settings win', () async {
      final service = await FakeService.start(seed: testAccount);
      final here = Here(service);
      final ghost = await here.orgs.createOrg('Ghost', ctx: here.ctx);
      final phone = ListDevice(here, service);
      await phone.sync();
      here.workspaces.fileNote('n1', 'org-${ghost.id}');
      final mine = here.prefs.value.workspaces;
      // The other device's settings arrive (lib/sync/prefs.dart): it reconciled the same list and made the same id,
      // with a filing of its own; a build before organizations had rewritten the workspace without its marker.
      here.prefs.update((now) => now.copyWith(
            workspaces: KeptWorkspaces(list: [KeptWorkspace(id: 'org-${ghost.id}', name: 'Ghost')], notes: {...mine.notes, 'n2': 'org-${ghost.id}'}),
          ));
      here.workspaces.reloadWorkspaces();
      await phone.sync();
      expect(here.ids, ['org-${ghost.id}']);
      expect(here.workspaces.workspaceOf('n1')?.id, 'org-${ghost.id}');
      expect(here.workspaces.workspaceOf('n2')?.id, 'org-${ghost.id}');
      expect(here.workspaces.value.list[0].org, ghost.id);
    });
  });

  group('the list kept here', () {
    test('is the account’s, read once from storage and forgotten on signing out; none signed out', () async {
      final here = Here(await FakeService.start(seed: testAccount));
      here.orgs.saveOrgs(7, const OrgState(at: 5));
      expect(jsonDecode(here.kept.getItem('glyph-sync-7-orgs')!), {'list': <Object?>[], 'at': 5, 'colour': null});
      expect(here.orgs.orgsState().at, 5);
      here.account.session = null;
      expect(here.orgs.orgsState(), OrgState.none);
      here.account.session = testSession;
      here.orgs.forgetOrgs(7);
      expect(here.kept.getItem('glyph-sync-7-orgs'), isNull);
      expect(here.orgs.orgsState(), OrgState.none);
    });

    test('reads rubbish, or a row this build cannot read, as nothing', () async {
      final here = Here(await FakeService.start(seed: testAccount));
      here.kept.setItem(
        'glyph-sync-7-orgs',
        jsonEncode({
          'list': [
            {'id': 'o1', 'name': 'Ghost', 'role': 'owner', 'state': 'member'},
            {'id': 'o2'},
            'no',
          ],
          'at': 'then',
        }),
      );
      expect(here.orgs.orgsState(), const OrgState(list: [OrgRow(id: 'o1', name: 'Ghost', role: 'owner', state: 'member')]));
      expect(here.orgs.orgsState().list.single.toJson(), {
        'id': 'o1',
        'name': 'Ghost',
        'hue': null,
        'role': 'owner',
        'state': 'member',
        'members': 0,
        'invitedBy': null,
        'createdAt': 0,
        'colour': null,
        'keys': {'generation': 0, 'mine': false, 'missing': 0, 'stale': false},
      });
      here.kept.setItem('glyph-sync-7-orgs', 'not json');
      here.orgs.forgetOrgs(7);
      expect(here.orgs.orgsState(), OrgState.none);
    });

    test('tells its listeners once per change, and when the account changes', () async {
      final here = Here(await FakeService.start(seed: testAccount));
      var told = 0;
      void heard() => told += 1;
      here.orgs.addListener(heard);
      here.orgs.saveOrgs(7, const OrgState(at: 1));
      expect(told, 1);
      here.account.signIn(here.service);
      expect(told, 2);
      here.orgs.removeListener(heard);
      here.orgs.saveOrgs(7, const OrgState(at: 2));
      expect(told, 2);
    });
  });
}
