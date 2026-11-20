/// The admin page (Matt, 2026-11-19: "create a simple admin page for me to login to in order to issue souls with a pre
/// generated username and password hidden behind developer mode with a admin page login or some other way to make sure
/// only my matt account can access it and allow me to see all users who signed up on the relay and issue special badges
/// and souls").
///
/// Settings › Admin, there only in developer mode and only for @matt. Signed in with the admin username and password
/// (made by tool/admin-password.mjs, the relay keeping only the password's hash), and the relay answers only Matt's
/// account signed in so (relay/lib/handles.dart): everyone who signed up, searched; each one's souls and badges given or
/// taken; and the last of what was given.
library;

import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData, TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/semantic_colors.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import 'common.dart';
import 'settings.dart';
import 'souls.dart';
import 'plugins_page/plugin_art.dart' show PluginHues;
import 'special_badges.dart';

/// Whether the admin page is offered: developer mode on, and this is Matt's account.
bool adminOffered(SettingsModel m) => adminOfferedFor(m.app);

/// The same from the app's choices alone: the Marketplace's Review queue is offered by it, with no Settings round it.
bool adminOfferedFor(AppState app) => app.flag('dev_mode', fallback: false) && adminNames.contains(Me.instance.username);

/// The Ghost usernames the admin page is offered to (the relay's GHOST_ADMIN_NAMES says who it answers).
const adminNames = {'matt'};

List<Widget> adminPane(BuildContext context, SettingsModel m) => const [AdminPanel()];

/// Someone as the admin page lists them.
class AdminUser {
  AdminUser(Map j)
      : id = '${j['id']}',
        name = j['name'] is String ? j['name'] as String : null,
        named = j['named'] == true,
        since = j['at'] is String ? j['at'] as String : null,
        verified = j['verified'] == true,
        links = [for (final l in (j['links'] as List? ?? const [])) '$l'],
        souls = j['souls'] is int ? j['souls'] as int : 0,
        special = [for (final b in (j['special'] as List? ?? const [])) '$b'],
        here = j['here'] == true,
        account = j['account'] is String ? j['account'] as String : null,
        was = [for (final n in (j['was'] as List? ?? const [])) '$n'];
  final String id;
  final String? name;
  final bool named;
  final String? since;
  final bool verified;
  final List<String> links;
  int souls;
  List<String> special;
  final bool here;

  /// The Ghost account they signed up or signed back in with (0x…), the same on every device and after a reinstall
  /// (Matt, 2026-11-20: "tie users names to their accounts when they sign back in later or reconnect to the app so that we
  /// can give out bug bounties properly"); null where they have none.
  final String? account;

  /// The usernames they held before this one, newest last: a ticket filed under an old name still finds them.
  final List<String> was;

  /// Whether [q] (lower case, no @) finds them: a username now or before, the start of their id or of their account.
  bool matches(String q) => q.isEmpty || (name ?? '').contains(q) || was.any((n) => n.contains(q)) || id.startsWith(q) || (account?.toLowerCase().startsWith(q) ?? false);

  String get shown => name != null ? '@$name' : (named ? 'A username from before (not said yet)' : 'No username');
}

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key, this.ask});

  /// For a test: the relay's answers, in place of Me.admin.
  final Future<Map<String, dynamic>> Function(Map<String, Object?> what)? ask;

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _search = TextEditingController();
  bool _in = false;
  bool _busy = false;
  String? _problem;
  List<AdminUser>? _users;
  List<Map>? _log;

  Future<Map<String, dynamic>> _ask(Map<String, Object?> what) => (widget.ask ?? Me.instance.admin)(what);

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final got = await _ask({'dir': 'admin-login', 'user': _user.text.trim(), 'pass': _pass.text});
      if (got['ok'] != true) throw MeError('${got['err'] ?? 'That isn\'t right.'}');
      _pass.clear();
      _in = true;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _problem = e is MeError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final users = await _ask({'dir': 'admin-users'});
    if (users['ok'] != true) {
      // Signed out by the relay (it was restarted, or the connection went): sign in again.
      if (mounted) setState(() => _in = false);
      throw MeError('${users['err'] ?? 'Sign in again.'}');
    }
    final log = await _ask({'dir': 'admin-log'});
    if (!mounted) return;
    setState(() {
      _users = [for (final u in (users['users'] as List? ?? const [])) if (u is Map) AdminUser(u)];
      _log = [for (final g in (log['grants'] as List? ?? const [])) if (g is Map) g];
    });
  }

  Future<void> _refresh() async {
    try {
      await _load();
    } catch (e) {
      if (mounted) toast(context, e is MeError ? e.message : '$e');
    }
  }

  Future<void> _open(AdminUser u) async {
    await push<void>(context, (_) => AdminPersonScreen(user: u, ask: _ask));
    if (mounted) setState(() {});
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!_in) {
      return PaneSection(
        title: 'Admin sign-in',
        description: const Text('The admin username and password. Only your account (@matt) can sign in, and only while this device is connected.'),
        footer: _problem == null ? null : Text(_problem!, style: TextStyle(color: t.danger)),
        children: [
          SettingRowBox(
            child: GlacierInput(key: const ValueKey('admin-user'), controller: _user, placeholder: 'Admin username', ariaLabel: 'Admin username', autoCorrect: false, autoCapitalize: TextCapitalization.none, size: GlacierFieldSize.md),
          ),
          SettingRowBox(
            child: GlacierInput(
              key: const ValueKey('admin-pass'),
              controller: _pass,
              placeholder: 'Password',
              ariaLabel: 'Admin password',
              type: GlacierInputType.password,
              autoCorrect: false,
              size: GlacierFieldSize.md,
              onSubmitted: (_) => _signIn(),
            ),
          ),
          SettingRow(key: const ValueKey('admin-sign-in'), icon: AppIcon(Lucide.keyRound, size: 18), label: _busy ? 'Signing in…' : 'Sign in', disabled: _busy, onPress: _signIn),
        ],
      );
    }
    final users = _users;
    final q = _search.text.trim().toLowerCase().replaceFirst('@', '');
    final shown = users == null ? null : [for (final u in users) if (u.matches(q)) u];
    final total = users?.fold<int>(0, (n, u) => n + u.souls) ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      PaneSection(
        title: 'Everyone',
        description: Text(users == null
            ? 'Asking the relay…'
            : '${users.length} ${users.length == 1 ? 'person' : 'people'} · ${users.where((u) => u.here).length} connected now · ${soulsCount(total)} souls given out'),
        children: [
          SettingRowBox(child: GlacierInput(key: const ValueKey('admin-search'), controller: _search, placeholder: 'Search by username, old username, Ghost id or account', ariaLabel: 'Search people', autoCorrect: false, autoCapitalize: TextCapitalization.none, size: GlacierFieldSize.md)),
          SettingRow(icon: AppIcon(Lucide.refreshCw, size: 18), label: 'Refresh', onPress: _refresh),
          if (shown != null)
            for (final u in shown.take(300))
              SettingRow(
                key: ValueKey('admin-user-${u.id}'),
                icon: AppIcon(u.here ? Lucide.circleDot : Lucide.circle, size: 16, color: u.here ? t.color('app-accent') : t.color('app-ink-3')),
                label: u.shown,
                hint: Text([
                  if (u.since != null) 'Joined ${u.since}',
                  if (u.was.isNotEmpty) 'was ${u.was.reversed.map((n) => '@$n').join(', ')}',
                  if (u.account != null) 'account ${u.account!.substring(0, 6)}…${u.account!.substring(u.account!.length - 4)}',
                  if (u.verified) 'number verified',
                  if (u.links.isNotEmpty) u.links.join(', '),
                  for (final b in specialBadgesOf(u.special)) b.name,
                ].join(' · ').ifEmpty('${u.id.substring(0, u.id.length.clamp(0, 12))}…')),
                value: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SoulFlame(size: 14),
                  SizedBox(width: t.space(1)),
                  Text(soulsCount(u.souls)),
                ]),
                onPress: () => _open(u),
              ),
        ],
      ),
      if (_log != null && _log!.isNotEmpty) ...[
        SizedBox(height: t.space(6)),
        PaneSection(
          title: 'Given lately',
          children: [
            for (final g in _log!.take(20))
              SettingRow(
                icon: AppIcon(g['badge'] != null ? Lucide.sparkles : Lucide.flame, size: 16, color: g['badge'] != null ? null : soulsFlame(t)),
                label: _grantLine(g),
                hint: Text('${'${g['at'] ?? ''}'.replaceFirst('T', ' ').split('.').first} UTC${'${g['why'] ?? ''}'.isEmpty ? '' : ' · ${g['why']}'}'),
              ),
          ],
        ),
      ],
    ]);
  }

  String _grantLine(Map g) {
    final who = _users?.where((u) => u.id == g['to']).firstOrNull?.shown ?? '${g['to']}'.substring(0, 8);
    final badge = g['badge'] is String ? specialBadge(g['badge'] as String)?.name ?? '${g['badge']}' : null;
    if (badge != null) return g['on'] == true ? '$badge to $who' : '$badge taken from $who';
    final n = g['souls'] is int ? g['souls'] as int : 0;
    return n >= 0 ? '${soulsCount(n)} souls to $who' : '${soulsCount(-n)} souls taken from $who';
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// One person on the admin page: their souls given or taken, with why, and their badges switched on and off.
class AdminPersonScreen extends StatefulWidget {
  const AdminPersonScreen({super.key, required this.user, required this.ask});
  final AdminUser user;
  final Future<Map<String, dynamic>> Function(Map<String, Object?> what) ask;

  @override
  State<AdminPersonScreen> createState() => _AdminPersonScreenState();
}

class _AdminPersonScreenState extends State<AdminPersonScreen> {
  final _amount = TextEditingController(text: '10');
  final _why = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _why.dispose();
    super.dispose();
  }

  Future<void> _give(int sign) async {
    final n = int.tryParse(_amount.text.trim());
    if (n == null || n <= 0) return toast(context, 'Say how many souls');
    setState(() => _busy = true);
    try {
      final got = await widget.ask({'dir': 'admin-give', 'to': widget.user.id, 'souls': sign * n, 'why': _why.text.trim()});
      if (got['ok'] != true) throw MeError('${got['err'] ?? 'The relay said no.'}');
      setState(() => widget.user.souls = got['n'] is int ? got['n'] as int : widget.user.souls);
      if (mounted) toast(context, sign > 0 ? 'Gave ${soulsCount(n)} souls to ${widget.user.shown}' : 'Took ${soulsCount(n)} souls from ${widget.user.shown}');
      _why.clear();
    } catch (e) {
      if (mounted) toast(context, e is MeError ? e.message : '$e', tone: GlacierToastTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _badge(SpecialBadge b, bool on) async {
    setState(() => _busy = true);
    try {
      final got = await widget.ask({'dir': 'admin-badge', 'to': widget.user.id, 'badge': b.id, 'on': on});
      if (got['ok'] != true) throw MeError('${got['err'] ?? 'The relay said no.'}');
      setState(() => widget.user.special = [for (final x in (got['special'] as List? ?? const [])) '$x']);
    } catch (e) {
      if (mounted) toast(context, e is MeError ? e.message : '$e', tone: GlacierToastTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final u = widget.user;
    return GhostPage(
      title: u.name != null ? '@${u.name}' : 'Someone',
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
          children: [
            Row(children: [
              const SoulFlame(size: 26),
              SizedBox(width: t.space(2)),
              Text(soulsCount(u.souls), key: const ValueKey('admin-person-souls'), style: pageText(t, t.fontSize('2xl'), weight: 'bold', color: t.color('app-ink'))),
              SizedBox(width: t.space(2)),
              Text(u.souls == 1 ? 'soul' : 'souls', style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'))),
            ]),
            SizedBox(height: t.space(1)),
            Text([if (u.since != null) 'Joined ${u.since}', if (u.verified) 'number verified', if (u.here) 'connected now'].join(' · '), style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            SizedBox(height: t.space(6)),
            // Who they are, by what stays theirs: the id a ticket's "Reporter" line names, their account, and their names
            // before (Matt, 2026-11-20: "tie users names to their accounts ... so that we can give out bug bounties").
            PaneSection(
              title: 'Who',
              children: [
                SettingRow(
                  key: const ValueKey('admin-person-id'),
                  icon: AppIcon(Lucide.keyRound, size: 18),
                  label: 'Ghost id',
                  hint: Text(u.id),
                  value: const Text('Copy'),
                  onPress: () {
                    Clipboard.setData(ClipboardData(text: u.id));
                    toast(context, 'Ghost id copied');
                  },
                ),
                SettingRow(
                  key: const ValueKey('admin-person-account'),
                  icon: AppIcon(Lucide.userCheck, size: 18),
                  label: 'Account',
                  hint: Text(u.account ?? 'None: a new install without signing in would be someone new.'),
                  value: u.account == null ? null : const Text('Copy'),
                  onPress: u.account == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: u.account!));
                          toast(context, 'Account copied');
                        },
                ),
                if (u.was.isNotEmpty) SettingRow(key: const ValueKey('admin-person-was'), icon: AppIcon(Lucide.history, size: 18), label: 'Before', hint: Text(u.was.reversed.map((n) => '@$n').join(', '))),
              ],
            ),
            SizedBox(height: t.space(6)),
            PaneSection(
              title: 'Souls',
              description: const Text('Told to them as soon as they are given, with why, if they are connected; otherwise the next time they are.'),
              children: [
                SettingRowBox(child: GlacierInput(key: const ValueKey('admin-amount'), controller: _amount, placeholder: 'How many', ariaLabel: 'How many souls', autoCorrect: false, size: GlacierFieldSize.md)),
                SettingRowBox(child: GlacierInput(key: const ValueKey('admin-why'), controller: _why, placeholder: 'Why (they see it): "Found the Windows crash"', ariaLabel: 'Why', size: GlacierFieldSize.md)),
                SettingRow(key: const ValueKey('admin-give'), icon: const SoulFlame(size: 18), label: 'Give souls', disabled: _busy, onPress: () => _give(1)),
                SettingRow(key: const ValueKey('admin-take'), icon: AppIcon(Lucide.minus, size: 18), label: 'Take souls back', disabled: _busy, onPress: () => _give(-1)),
              ],
            ),
            SizedBox(height: t.space(6)),
            PaneSection(
              title: 'Badges',
              description: const Text('Shown beside their name in spaces, circles and on their profile.'),
              children: [
                for (final b in specialBadges)
                  SettingRow(
                    key: ValueKey('admin-badge-${b.id}'),
                    icon: AppIcon(b.icon, size: 18, color: PluginHues.of(t, b.hue).accent),
                    label: b.name,
                    hint: Text(b.about),
                    control: GlacierSwitch(checked: u.special.contains(b.id), ariaLabel: b.name, onCheckedChange: _busy ? null : (on) => _badge(b, on)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
