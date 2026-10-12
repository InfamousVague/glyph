/// The account's organizations on this device (docs/TEAMS.md). A port of `src/app/core/orgs/orgs.ts`: the calls for
/// every route, the list as the service last gave it, kept per account so the Organizations page and the home card
/// draw at once, and the step of the sync pass that takes the list again and brings the workspaces into line with
/// it.
///
/// The workspace is reconciled against the list after every pass that gets one (D5): made for each organization the
/// person is a member of, renamed and re-hued with it, dropped once they have left or it is gone - its notes
/// unfiled, never deleted. Only a 200 list is acted on; a list that did not arrive (offline, a service without the
/// route yet, a 500) leaves the workspaces and the cached list exactly as they were, because reading a failure as
/// "no organizations" would unfile every member's notes and push that to their other devices. The reconcile runs
/// outside the pass's `applyingRemote` (lib/sync/engine.dart), so the preference change it makes is pushed a moment
/// later rather than on the next pass.
///
/// A call that changes one organization brings that one's row and workspace up to date here as well, so the screens
/// do not wait for the pass; the next pass makes it the service's truth.
///
/// What differs:
/// - The page's module is [Orgs], made with the account ([AccountSource]), the [Api], the [WorkspaceStore] it
///   reconciles and this device's memory, and a [Listenable] where the page has `onOrgs` and `useOrgs`.
/// - A call's `ctx` is a [CallContext] with a token and, for a test that stands between this device and the service,
///   an [Api] of its own; without one it is the signed-in session's.
/// - `postInviteAnswer` is what the notifications feed is handed as its `answerInvite`
///   ([Orgs.inviteAnswerWith]; lib/sync/feed.dart).
library;

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/session.dart';
import '../core/stored.dart';
import '../core/workspaces.dart';
import '../sync/feed.dart' show InviteAnswer;
import 'types.dart';

export 'types.dart';

String _stateKey(int accountId) => 'glyph-sync-$accountId-orgs';

/// What a call needs of the session (`CallContext`): the signed-in session's by default, or a test's own.
@immutable
class CallContext {
  const CallContext({required this.token, this.api});
  final String token;

  /// The service through another fetcher; the [Orgs]' own when null.
  final Api? api;
}

/// How long a new link lasts and how many may join by it; none of either for good and without a limit
/// (`LinkTerms`).
@immutable
class LinkTerms {
  const LinkTerms({this.expiresIn, this.maxUses});

  /// Seconds, an hour to thirty days.
  final int? expiresIn;

  /// 1 to 50.
  final int? maxUses;
}

/// What the pass's step is handed (`OrgsContext`).
@immutable
class OrgsContext extends CallContext {
  const OrgsContext({required super.token, super.api, required this.save, this.now});

  /// Keeps the list that arrived: the account's store ([Orgs.saveOrgs]), or a test's variable.
  final void Function(OrgState state) save;

  /// The time, in ms: swapped in by the tests.
  final int Function()? now;
}

/// The organizations of whoever is signed in, kept on this device, and every call that changes them.
class Orgs extends ChangeNotifier {
  /// [kept] is this device's memory, the app's own unless given.
  Orgs({required this.account, required this.api, required this.workspaces, Stored? kept}) : _kept = kept {
    account.addListener(notifyListeners);
  }

  final AccountSource account;
  final Api api;
  final WorkspaceStore workspaces;
  final Stored? _kept;
  Stored get _device => _kept ?? stored;

  // --- what this device keeps ---------------------------------------------------------------------------------------

  /// The list for one account, read from storage once and kept.
  ({int accountId, OrgState state})? _cache;

  OrgState _stateOf(int accountId) {
    final cache = _cache;
    if (cache != null && cache.accountId == accountId) return cache.state;
    final state = _device.read<OrgState>(_stateKey(accountId), OrgState.none, OrgState.fromJson);
    _cache = (accountId: accountId, state: state);
    return state;
  }

  /// The rows kept for an account, signed in or not: for the sync engine forgetting an account's channels
  /// (`orgRowsOf`).
  List<OrgRow> orgRowsOf(int accountId) => _stateOf(accountId).list;

  /// Keeps the list for an account: on this device for the next launch, and for everything watching it now
  /// (`saveOrgs`).
  void saveOrgs(int accountId, OrgState state) {
    _cache = (accountId: accountId, state: state);
    _device.write(_stateKey(accountId), state.toJson());
    notifyListeners();
  }

  /// Forgets the list this device kept of an account's organizations: for signing out (`forgetOrgs`).
  void forgetOrgs(int accountId) {
    if (_cache?.accountId == accountId) _cache = null;
    _device.write(_stateKey(accountId), null);
    notifyListeners();
  }

  /// The organizations of the account signed in now, as the service last listed them; none signed out
  /// (`orgsState`).
  OrgState orgsState() {
    final session = account.session;
    return session != null ? _stateOf(session.accountId) : OrgState.none;
  }

  /// One organization's row from the kept list, or null (`orgRow`).
  OrgRow? orgRow(String id) {
    for (final row in orgsState().list) {
      if (row.id == id) return row;
    }
    return null;
  }

  /// The kept list with one row replaced, added, or (for null) taken out; nothing signed out (`keepRow`).
  void _keepRow(String id, OrgRow? row) {
    final session = account.session;
    if (session == null) return;
    final was = _stateOf(session.accountId);
    final list = [
      for (final r in was.list)
        if (r.id != id) r,
      ?row,
    ];
    saveOrgs(session.accountId, was.copyWith(list: List.unmodifiable(list)));
  }

  // --- the calls ----------------------------------------------------------------------------------------------------

  CallContext _signedIn() {
    final session = account.session;
    if (session == null) throw const ApiError(401, 'Sign in first.');
    return CallContext(token: session.token);
  }

  Future<Map<String, Object?>> _call(String method, String path, CallContext? ctx, [Object? body]) {
    final with_ = ctx ?? _signedIn();
    return (with_.api ?? api).callMap(method, path, token: with_.token, body: body);
  }

  static String _enc(String part) => Uri.encodeComponent(part);

  /// A new organization, owned by the caller, with its workspace made here at once (`createOrg`).
  Future<Org> createOrg(String name, {String? hue, CallContext? ctx}) async {
    final org = Org.fromJson((await _call('POST', 'orgs', ctx, {'name': name.trim(), 'hue': hue}))['org']);
    _keepRow(org.id, org.row);
    workspaces.ensureOrgWorkspace(org);
    return org;
  }

  /// Every organization the account is in or invited to, and the account's own colour (docs/SHARED.md, S7;
  /// `listOrgs`). The kept list is not touched: that is the pass's ([syncOrgs]).
  Future<({List<OrgRow> rows, String? colour})> listOrgs({CallContext? ctx}) async {
    final answer = await _call('GET', 'orgs', ctx);
    final rows = answer['orgs'], colour = answer['colour'];
    return (rows: [if (rows is List) for (final each in rows) ?OrgRow.fromJson(each)], colour: colour is String ? colour : null);
  }

  /// The account's own colour set (one of the hues), or cleared with null; kept here at once (`setAccountColour`).
  Future<void> setAccountColour(String? hue, {CallContext? ctx}) async {
    final answer = await _call('PUT', 'account/colour', ctx, {'hue': hue});
    final colour = answer['colour'] is String ? answer['colour'] as String : null;
    final session = account.session;
    if (session == null) return;
    final was = _stateOf(session.accountId);
    // A row with no override wears the account's colour: brought up to date here without another list.
    final list = [for (final row in was.list) row.colour == was.colour ? row.copyWith(colour: () => colour) : row];
    saveOrgs(session.accountId, OrgState(list: List.unmodifiable(list), at: was.at, colour: colour));
  }

  /// The caller's colour in one organization set, or cleared with null to the account's own; its row follows at
  /// once (`setOrgColour`).
  Future<Org> setOrgColour(String id, String? hue, {CallContext? ctx}) async {
    final org = Org.fromJson((await _call('PUT', 'orgs/${_enc(id)}/colour', ctx, {'hue': hue}))['org']);
    _keepRow(org.id, org.row);
    return org;
  }

  /// One organization in full, for a member; 404 "No such organization." otherwise (`fetchOrg`).
  Future<Org> fetchOrg(String id, {CallContext? ctx}) async {
    final org = Org.fromJson((await _call('GET', 'orgs/${_enc(id)}', ctx))['org']);
    _keepRow(org.id, org.row);
    return org;
  }

  /// The organization renamed or re-hued (owner or admin); its workspace follows at once (`updateOrg`). [hue] is a
  /// function so that "leave the hue alone" (null) and "take the hue off" (a function answering null) are two things.
  Future<Org> updateOrg(String id, {String? name, String? Function()? hue, CallContext? ctx}) async {
    final body = <String, Object?>{if (name != null) 'name': name.trim(), if (hue != null) 'hue': hue()};
    final org = Org.fromJson((await _call('PUT', 'orgs/${_enc(id)}', ctx, body))['org']);
    _keepRow(org.id, org.row);
    workspaces.ensureOrgWorkspace(org);
    return org;
  }

  /// The organization deleted (owner); its workspace goes here, its notes unfiled (`deleteOrg`).
  Future<void> deleteOrg(String id, {CallContext? ctx}) async {
    await _call('DELETE', 'orgs/${_enc(id)}', ctx);
    _keepRow(id, null);
    workspaces.dropOrgWorkspace(id);
  }

  /// Someone invited by handle (owner or admin; `inviteByHandle`). The service resolves the handle - 404 "No one has
  /// that handle." - and says when they are already in, declined lately, have too many invitations waiting, or the
  /// organization is full.
  Future<Member> inviteByHandle(String id, String handle, {CallContext? ctx}) async => _member((await _call('POST', 'orgs/${_enc(id)}/members', ctx, {'handle': handle.trim()}))['member']);

  static Member _member(Object? raw) => Member.fromJson(raw) ?? (throw const FormatException('The service answered without the member.'));

  /// A member or invitee taken out (owner or admin, with the owner the only one who can remove an admin), or the
  /// caller leaving by their own handle: then the organization and its workspace go from this device
  /// (`removeMember`).
  Future<void> removeMember(String id, String handle, {CallContext? ctx}) async {
    await _call('DELETE', 'orgs/${_enc(id)}/members/${_enc(handle.trim())}', ctx);
    final session = account.session;
    if (session != null && session.handle.toLowerCase() == handle.trim().toLowerCase()) {
      _keepRow(id, null);
      workspaces.dropOrgWorkspace(id);
    }
  }

  /// An AI's entry removed from the organization's list (owner or admin, or the member it came through). The record
  /// goes; the member's own access, which is what their connector reads with, is as it was (`removeOrgAi`).
  Future<void> removeOrgAi(String id, String ai, {CallContext? ctx}) async {
    await _call('DELETE', 'orgs/${_enc(id)}/ais/${_enc(ai)}', ctx);
  }

  /// A member's role set by the owner; `owner` hands the organization over, and the old owner becomes an admin
  /// (`setRole`).
  Future<Member> setRole(String id, String handle, String role, {CallContext? ctx}) async {
    final member = _member((await _call('PUT', 'orgs/${_enc(id)}/members/${_enc(handle.trim())}', ctx, {'role': role}))['member']);
    // Handing over: the caller is an admin now, which the kept row should say before the pass does.
    final row = orgRow(id);
    if (role == 'owner' && row != null) _keepRow(id, row.copyWith(role: 'admin'));
    return member;
  }

  /// The invitation answered on the wire: the organization, joined, or null for declined (`postInviteAnswer`). 404
  /// "You were not invited." when there is no pending invitation - answered from another device already. The feed's
  /// `answerInvite` (lib/sync/feed.dart) is what a screen calls: it applies the answer here at once and replays this.
  Future<Org?> postInviteAnswer(String id, bool accept, {CallContext? ctx}) async {
    final answer = await _call('POST', 'orgs/${_enc(id)}/invite', ctx, {'accept': accept});
    if (answer.containsKey('org')) {
      final org = Org.fromJson(answer['org']);
      _keepRow(org.id, org.row);
      workspaces.ensureOrgWorkspace(org);
      return org;
    }
    _keepRow(id, null);
    return null;
  }

  /// [postInviteAnswer] as the notifications feed takes it (lib/sync/feed.dart `NotificationsContext.answerInvite`),
  /// with the session the pass is running under.
  InviteAnswer inviteAnswerWith(CallContext ctx) => (orgId, accept) async {
        await postInviteAnswer(orgId, accept, ctx: ctx);
      };

  // --- invite links -------------------------------------------------------------------------------------------------

  /// A new invite link (owner or admin); 409 when the organization has as many working as it may
  /// (`makeInviteLink`).
  Future<InviteLink> makeInviteLink(String id, {LinkTerms terms = const LinkTerms(), CallContext? ctx}) async {
    final body = <String, Object?>{if (terms.expiresIn != null) 'expiresIn': terms.expiresIn, if (terms.maxUses != null) 'maxUses': terms.maxUses};
    return InviteLink.fromJson((await _call('POST', 'orgs/${_enc(id)}/links', ctx, body))['link']);
  }

  /// The organization's working links, newest first (owner or admin; `listInviteLinks`).
  Future<List<InviteLink>> listInviteLinks(String id, {CallContext? ctx}) async {
    final links = (await _call('GET', 'orgs/${_enc(id)}/links', ctx))['links'];
    return [if (links is List) for (final each in links) InviteLink.fromJson(each)];
  }

  /// A link turned off: its code joins nobody from now on (`dropInviteLink`).
  Future<void> dropInviteLink(String id, String link, {CallContext? ctx}) async {
    await _call('DELETE', 'orgs/${_enc(id)}/links/${_enc(link)}', ctx);
  }

  /// What a code joins, before it is followed; 404 "That invite link has expired or was turned off." when it does
  /// not (`previewJoin`).
  Future<JoinPreview> previewJoin(String code, {CallContext? ctx}) async => JoinPreview.fromJson(await _call('GET', 'joins/${_enc(code)}', ctx));

  /// The caller in by a code, with the organization's row and workspace made here at once, as accepting makes them
  /// (`joinByLink`).
  Future<Org> joinByLink(String code, {CallContext? ctx}) async {
    final org = Org.fromJson((await _call('POST', 'joins/${_enc(code)}', ctx))['org']);
    _keepRow(org.id, org.row);
    workspaces.ensureOrgWorkspace(org);
    return org;
  }

  // --- the pass -----------------------------------------------------------------------------------------------------

  /// The workspaces brought into line with a list the service answered (`reconcileOrgWorkspaces`): one for each
  /// organization the person is a member of, named and coloured after it; an organization's workspace whose
  /// organization is not in the list goes, its notes unfiled. An invitation is not a membership, and gets no
  /// workspace until it is accepted.
  void reconcileOrgWorkspaces(List<OrgRow> list) {
    final members = [for (final row in list) if (row.state == 'member') row];
    for (final org in members) {
      workspaces.ensureOrgWorkspace(org);
    }
    final wanted = {for (final org in members) org.id};
    for (final workspace in workspaces.value.list.toList()) {
      final org = orgIdOf(workspace.id);
      if (org != null && !wanted.contains(org)) workspaces.dropOrgWorkspace(org);
    }
  }

  /// The step of the sync pass (`syncOrgs`): the list taken again, kept, and the workspaces reconciled against it.
  /// Answers the list, or null when the service does not have the route yet ([notYet]), which changes nothing here
  /// and says nothing. Any other failure is thrown as it is, and changes nothing either.
  Future<List<OrgRow>?> syncOrgs(OrgsContext ctx) async {
    final ({List<OrgRow> rows, String? colour}) listed;
    try {
      listed = await listOrgs(ctx: ctx);
    } catch (failure) {
      if (notYet(failure)) return null;
      rethrow;
    }
    ctx.save(OrgState(list: List.unmodifiable(listed.rows), at: (ctx.now ?? () => DateTime.now().millisecondsSinceEpoch)(), colour: listed.colour));
    reconcileOrgWorkspaces(listed.rows);
    return listed.rows;
  }

  @override
  void dispose() {
    account.removeListener(notifyListeners);
    super.dispose();
  }
}
