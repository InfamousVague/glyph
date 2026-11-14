/// Settings › Me and Settings › Friends joining (Matt, 2026-11-14: "Add a 'me' section to settings and allow linking
/// popular social like telegram, discord, x, etc to be notified when one of your friends or followers joins ghost
/// messaging"). What they show is lib/me/me.dart's; docs/me.md says what the relay server keeps of it.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import '../sms.dart';
import 'common.dart';
import 'settings.dart';

Widget _icon(LucideIcon icon) => AppIcon(icon, size: 18);

/// A network's letter on the row's chip, in the chip's own colour: no network's logo is drawn.
class NetworkMark extends StatelessWidget {
  const NetworkMark(this.network, {super.key});
  final Network network;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(network.mark, style: pageText(t, 18, weight: 'bold', color: IconTheme.of(context).color ?? t.color('app-ink'), height: 1.1));
  }
}

/// Speaks to the relay server as the page opens, where this install never has: nothing is said to it about handles
/// until someone comes here.
class _Wake extends StatefulWidget {
  const _Wake({this.seen = false});

  /// The page shows who joined: they are no longer new once it has been looked at and left.
  final bool seen;

  @override
  State<_Wake> createState() => _WakeState();
}

class _WakeState extends State<_Wake> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Me.instance.wake());
  }

  @override
  void dispose() {
    // As the page is left, not as it opens: who is new is marked New while it is being looked at.
    if (widget.seen) Future.microtask(Me.instance.markSeen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

String meSummary(SettingsModel m) {
  final me = Me.instance;
  final have = [if (me.number != null) 'Number verified', for (final n in networks) if (me.links.containsKey(n.id)) n.name];
  return have.isEmpty ? 'Link your accounts' : have.join(', ');
}

String friendsSummary(SettingsModel m) {
  final me = Me.instance;
  if (me.unseen > 0) return '${me.unseen} new';
  if (me.watch.isEmpty) return 'Hear when people you know join';
  return 'Watching for ${me.watch.length}${me.joined.isEmpty ? '' : ' · ${me.joined.length} here'}';
}

List<Widget> mePane(BuildContext context, SettingsModel m) {
  final me = Me.instance;
  return [
    const _Wake(),
    PaneSection(
      title: 'You',
      children: [
        _NumberRow(own: m.ownNumber),
        SettingRow(icon: _icon(Lucide.keyRound), label: 'Encryption key', value: Text(m.myKey ?? 'Made when first used')),
      ],
    ),
    if (Sms.remote)
      const SettingsCallout(child: Text('Accounts are linked on your phone. Open Settings › Me in Ghost Messaging there.'))
    else if (!me.ready)
      SettingsCallout(child: Text(me.reachable ? 'Asking the relay server…' : 'Linking an account needs the relay server, which isn\'t connected right now (Settings › Network).')),
    PaneSection(
      title: 'Linked accounts',
      description: const Text('Show that an account is yours. Friends who asked to hear about that account are then told you\'re on Ghost Messaging, if you turn that on below.'),
      children: [for (final n in networks) _LinkRow(network: n)],
    ),
    PaneSection(
      title: 'Being found',
      footer: const Text(
          'Off, nobody is told anything. On, someone who already knows one of your linked handles, and asked to hear about it, is told that it is on Ghost Messaging. They are not given your number, your name or your other accounts, and nobody is told about your number, verified or not. The relay server keeps a scrambled form of each linked handle, never the handle itself.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.megaphone),
          label: 'Tell friends I\'m here',
          hint: Text(me.accounts.isEmpty ? 'Link an account first.' : 'People watching for ${me.accounts.length == 1 ? 'your account' : 'one of your accounts'} hear that you joined.'),
          control: GlacierSwitch(checked: me.listed, onCheckedChange: me.setListed, ariaLabel: 'Tell friends I\'m here', disabled: Sms.remote),
        ),
      ],
    ),
    PaneSection(
      title: 'Your data',
      children: [
        SettingRow(
          icon: _icon(Lucide.trash2),
          label: 'Remove everything about me',
          hint: const Text('Unlinks every account and your number, and clears the people you watch for, on this phone and on the relay server.'),
          disabled: !me.ready || (me.links.isEmpty && me.watch.isEmpty && !me.listed),
          onPress: () => showChoices(context, title: 'Unlink every account and clear your watch list? Friends will no longer be told you\'re here.', choices: [
            Choice('Remove everything', Lucide.trash2, () async {
              try {
                await me.forgetEverything();
                if (context.mounted) toast(context, 'Removed');
              } catch (e) {
                if (context.mounted) toast(context, 'Cleared on this phone. The relay server will be told when it next answers.', tone: GlacierToastTone.danger);
              }
            }, danger: true),
          ]),
        ),
      ],
    ),
  ];
}

/// This phone's number on the Me page: what the phone says it is, and whether a code texted to it has shown it to
/// be (Matt, 2026-11-14: "send the text code to a number to verify so it can't be spoofed").
class _NumberRow extends StatelessWidget implements PaneRow {
  const _NumberRow({required this.own});

  /// What Android, or the person, says this phone's number is.
  final String? own;

  @override
  Widget build(BuildContext context) {
    final me = Me.instance;
    final icon = _icon(Lucide.phone);
    final verified = me.number;
    if (verified != null) {
      final shown = showNumber(verified);
      return SettingRow(
        icon: icon,
        label: 'Number',
        labelAfter: const Padding(padding: EdgeInsets.only(left: 8), child: GlacierPill(size: GlacierPillSize.sm, child: Text('Verified'))),
        value: Text(shown),
        onPress: () => showChoices(context, title: '$shown is verified: a code texted to it reached this phone.', choices: [
          Choice('Copy number', Lucide.copy, () {
            Clipboard.setData(ClipboardData(text: verified));
            toast(context, 'Copied');
          }),
          Choice('Remove verification', Lucide.unlink, () async {
            await me.unlink('phone');
            if (context.mounted) toast(context, 'Number no longer verified');
          }, danger: true),
        ]),
      );
    }
    final shown = Text(own == null || own!.isEmpty ? 'Not known' : own!);
    if (Sms.remote || !me.ready) return SettingRow(icon: icon, label: 'Number', value: shown);
    if (!me.texts) return SettingRow(icon: icon, label: 'Number', value: shown, hint: const Text('Verifying a number by text isn\'t set up on the relay server yet.'));
    return SettingRow(icon: icon, label: 'Number', value: shown, hint: const Text('Verify it with a code sent by text'), onPress: () => push<void>(context, (_) => NumberScreen(own: own)));
  }
}

/// Showing a number is this phone's: the number, a code texted to it by the relay server's texting service, and
/// the code back. The code is read from the text as it arrives, so most of the time nothing is typed.
class NumberScreen extends StatefulWidget {
  const NumberScreen({super.key, this.own});
  final String? own;

  @override
  State<NumberScreen> createState() => _NumberScreenState();
}

class _NumberScreenState extends State<NumberScreen> {
  late final TextEditingController _number;
  final _code = TextEditingController();
  StreamSubscription<int>? _arrivals;

  /// The number a code was texted to, and when it was asked for.
  String? _sentTo;
  DateTime? _askedAt;

  /// A code that arrived before the server said it was sent: a text can be the quicker of the two.
  String? _early;
  String? _problem;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final own = tidyNumber(widget.own ?? '');
    _number = TextEditingController(text: numberFits(own) ? showNumber(own) : '');
    _arrivals = Sms.instance.changes.stream.listen(_arrived);
  }

  @override
  void dispose() {
    _arrivals?.cancel();
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  /// A conversation changed: where its newest text is the code asked for, the code is put in and checked.
  Future<void> _arrived(int thread) async {
    final since = _askedAt;
    if (since == null || thread < 0) return;
    try {
      final newest = (await Sms.instance.messages(thread, limit: 3)).where((m) => !m.outgoing && m.date.isAfter(since.subtract(const Duration(seconds: 30))));
      for (final m in newest) {
        final code = ownCodeIn(m.body);
        if (code == null || !mounted) continue;
        if (_sentTo == null || _busy) {
          _early = code;
        } else {
          _code.text = code;
          await _check();
        }
        return;
      }
    } catch (_) {
      // Not read: the code can still be typed.
    }
  }

  Future<void> _send() async {
    final number = tidyNumber(_number.text);
    if (!numberFits(number)) {
      setState(() => _problem = 'That doesn\'t look like a whole phone number. Write it with its country code, like +1 555 010 0199.');
      return;
    }
    setState(() { _busy = true; _problem = null; });
    _askedAt = DateTime.now();
    _early = null;
    try {
      final to = await Me.instance.textCode(number);
      if (mounted) setState(() { _sentTo = to; _code.clear(); });
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    final early = _early;
    _early = null;
    if (early != null && mounted && _sentTo != null) {
      _code.text = early;
      await _check();
    }
  }

  Future<void> _check() async {
    final number = _sentTo;
    final code = _code.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (number == null) return;
    if (code.length < 4) {
      setState(() => _problem = 'Type the code from the text.');
      return;
    }
    setState(() { _busy = true; _problem = null; });
    try {
      await Me.instance.tryCode(number, code);
      if (!mounted) return;
      toast(context, '${showNumber(number)} is verified');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sent = _sentTo;
    final problem = _problem == null ? null : Text(_problem!, style: TextStyle(color: t.colorOf('#dd3a30')));
    return GlacierScope(
      attrs: const {'hue': 'green'},
      child: GhostPage(
        title: 'Verify your number',
        body: SettingsPaneScope(
          finder: SettingsFinder(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              PaneSection(
                title: 'Your number',
                description: const Text('A code is texted to this number, and coming back it shows the number is this phone\'s. The relay server and the texting service it uses see the number. Nobody else is told it.'),
                footer: sent == null ? problem : null,
                children: [
                  SettingRowBox(
                    child: GlacierInput(
                      controller: _number,
                      type: GlacierInputType.tel,
                      placeholder: '+1 555 010 0199',
                      ariaLabel: 'Your phone number',
                      autoFocus: _number.text.isEmpty,
                      autoCorrect: false,
                      size: GlacierFieldSize.md,
                      onChange: (_) {
                        if (_sentTo != null) setState(() { _sentTo = null; _askedAt = null; _problem = null; });
                      },
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  if (sent == null) SettingRow(icon: _icon(Lucide.messageSquare), label: _busy ? 'Sending…' : 'Text me a code', disabled: _busy, onPress: _send),
                ],
              ),
              if (sent != null) ...[
                SizedBox(height: t.space(6)),
                PaneSection(
                  title: 'The code',
                  description: Text('Texted to ${showNumber(sent)}. It is read from the text as it arrives; you can type it too. It lasts ten minutes.'),
                  footer: problem,
                  children: [
                    SettingRowBox(
                      child: GlacierInput(
                        controller: _code,
                        type: GlacierInputType.number,
                        placeholder: '482913',
                        ariaLabel: 'The code from the text',
                        autoCorrect: false,
                        maxLength: 10,
                        size: GlacierFieldSize.md,
                        onSubmitted: (_) => _check(),
                      ),
                    ),
                    SettingRow(icon: _icon(Lucide.check), label: _busy ? 'Checking…' : 'Check the code', disabled: _busy, onPress: _check),
                    SettingRow(icon: _icon(Lucide.refreshCw), label: 'Send it again', disabled: _busy, onPress: _send),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One network on the Me page: linked with its handle, or how it is linked.
class _LinkRow extends StatelessWidget implements PaneRow {
  const _LinkRow({required this.network});
  final Network network;

  Future<void> _signIn(BuildContext context) async {
    try {
      final address = await Me.instance.signInAddress(network.id);
      final opened = await Sms.instance.openLink(address);
      if (!context.mounted) return;
      toast(context, opened ? 'Sign in with ${network.name} in your browser. This page updates when it\'s done.' : 'No browser could be opened.', tone: opened ? GlacierToastTone.neutral : GlacierToastTone.danger);
    } catch (e) {
      if (context.mounted) toast(context, '$e', tone: GlacierToastTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Me.instance;
    final n = network;
    final handle = me.links[n.id];
    final mark = NetworkMark(n);
    if (handle != null) {
      final page = n.profile(handle);
      return SettingRow(
        icon: mark,
        label: n.name,
        value: Text('@$handle'),
        onPress: () => showChoices(context, title: '@$handle on ${n.name}', choices: [
          if (page != null) Choice('Open profile', Lucide.externalLink, () => Sms.instance.openLink(page)),
          Choice('Copy handle', Lucide.copy, () {
            Clipboard.setData(ClipboardData(text: handle));
            toast(context, 'Copied');
          }),
          Choice('Unlink', Lucide.unlink, () async {
            await me.unlink(n.id);
            if (context.mounted) toast(context, '${n.name} unlinked');
          }, danger: true),
        ]),
      );
    }
    if (Sms.remote || !me.ready) return SettingRow(icon: mark, label: n.name, hint: const Text('Not linked'), disabled: true);
    if (n.signIn && me.ways[n.id] != 'signin') {
      return SettingRow(icon: mark, label: n.name, hint: Text('Signing in with ${n.name} isn\'t set up on the relay server yet.'), disabled: true);
    }
    return SettingRow(
      icon: mark,
      label: n.name,
      hint: Text(n.signIn ? 'Sign in with ${n.name} to link it' : 'Link with a code in your profile'),
      onPress: n.signIn ? () => _signIn(context) : () => push<void>(context, (_) => ProofScreen(network: n)),
    );
  }
}

/// Linking an account by a code in its public profile (Bluesky, Mastodon, GitHub): the handle, the code the relay
/// server makes for it, and the check.
class ProofScreen extends StatefulWidget {
  const ProofScreen({super.key, required this.network});
  final Network network;

  @override
  State<ProofScreen> createState() => _ProofScreenState();
}

class _ProofScreenState extends State<ProofScreen> {
  final _handle = TextEditingController();
  String? _code;
  String? _for;
  String? _problem;
  bool _busy = false;

  Network get n => widget.network;

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  Future<void> _getCode() async {
    final handle = tidyHandle(_handle.text);
    if (!handleFits(n.id, handle)) {
      setState(() => _problem = 'That doesn\'t look like a ${n.name} handle. It looks like ${n.example}.');
      return;
    }
    setState(() { _busy = true; _problem = null; });
    try {
      final code = await Me.instance.proofCode(n.id, handle);
      if (mounted) setState(() { _code = code; _for = handle; });
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final handle = _for;
    if (handle == null) return;
    setState(() { _busy = true; _problem = null; });
    try {
      await Me.instance.check(n.id, handle);
      if (!mounted) return;
      toast(context, '@$handle on ${n.name} is linked');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final code = _code;
    return GlacierScope(
      attrs: {'hue': n.hue},
      child: GhostPage(
        title: 'Link ${n.name}',
        body: SettingsPaneScope(
          finder: SettingsFinder(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              PaneSection(
                title: 'Your handle',
                footer: _problem == null ? null : Text(_problem!, style: TextStyle(color: t.colorOf('#dd3a30'))),
                children: [
                  SettingRowBox(
                    child: GlacierInput(
                      controller: _handle,
                      placeholder: n.example,
                      ariaLabel: 'Your ${n.name} handle',
                      autoFocus: true,
                      autoCorrect: false,
                      autoCapitalize: TextCapitalization.none,
                      size: GlacierFieldSize.md,
                      onChange: (_) {
                        if (_code != null) setState(() { _code = null; _for = null; });
                      },
                      onSubmitted: (_) => _getCode(),
                    ),
                  ),
                  if (code == null) SettingRow(icon: _icon(Lucide.keyRound), label: _busy ? 'Asking…' : 'Get my code', disabled: _busy, onPress: _getCode),
                ],
              ),
              if (code != null) ...[
                SizedBox(height: t.space(6)),
                PaneSection(
                  title: 'Your code',
                  description: Text('Put this code anywhere in ${n.where} and save. That shows the account is yours: only its owner can change its profile. You can take the code out again once it\'s linked.'),
                  children: [
                    SettingRow(
                      icon: _icon(Lucide.copy),
                      label: code,
                      value: const Text('Copy'),
                      onPress: () {
                        Clipboard.setData(ClipboardData(text: code));
                        toast(context, 'Code copied');
                      },
                    ),
                    if (n.profile(_for!) != null) SettingRow(icon: _icon(Lucide.externalLink), label: 'Open my ${n.name} profile', onPress: () => Sms.instance.openLink(n.profile(_for!)!)),
                    SettingRow(icon: _icon(Lucide.check), label: _busy ? 'Checking…' : 'I\'ve added it: check', disabled: _busy, onPress: _check),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _when(DateTime at) => listWhen(at);

List<Widget> friendsPane(BuildContext context, SettingsModel m) {
  final me = Me.instance;
  final importable = [for (final n in networks) if (n.follows && me.links.containsKey(n.id)) n];
  return [
    const _Wake(seen: true),
    PaneSection(
      title: 'On Ghost Messaging',
      children: [
        if (me.joined.isEmpty)
          const SettingRow(label: 'Nobody yet', hint: Text('When someone you watch for links their account and chooses to be found, they show here.'))
        else
          for (final j in me.joined) _JoinedRow(joined: j),
      ],
    ),
    PaneSection(
      title: 'Watching for',
      description: const Text('The handles you want to hear about. Discord, Telegram and X don\'t let an app read your friends or followers, so add those yourself. Bluesky, Mastodon and GitHub can bring in everyone you follow.'),
      footer: Text(me.watch.isEmpty
          ? 'The relay server is given a scrambled form of each handle, never the handle itself.'
          : '${me.watch.length} ${me.watch.length == 1 ? 'handle' : 'handles'}. The relay server holds a scrambled form of each, never the handle itself.'),
      children: [
        SettingRow(icon: _icon(Lucide.plus), label: 'Add handles', hint: const Text('Type or paste as many as you like.'), disabled: Sms.remote, onPress: () => push<void>(context, (_) => const AddWatchScreen())),
        for (final n in importable) _ImportRow(network: n),
        for (final n in networks)
          if (me.watch.any((w) => w.network == n.id))
            SettingRow(
              icon: NetworkMark(n),
              label: n.name,
              value: Text('${me.watch.where((w) => w.network == n.id).length}'),
              onPress: () => push<void>(context, (_) => WatchListScreen(network: n)),
            ),
      ],
    ),
  ];
}

class _JoinedRow extends StatelessWidget implements PaneRow {
  const _JoinedRow({required this.joined});
  final Joined joined;

  @override
  Widget build(BuildContext context) {
    final n = networkOf(joined.network);
    final page = n.profile(joined.handle);
    return SettingRow(
      icon: NetworkMark(n),
      label: '@${joined.handle}',
      labelAfter: joined.seen ? null : Padding(padding: const EdgeInsets.only(left: 8), child: const GlacierPill(size: GlacierPillSize.sm, child: Text('New'))),
      hint: Text('${n.name} · joined ${_when(joined.at)}'),
      onPress: () => showChoices(context, title: '@${joined.handle} from ${n.name} is on Ghost Messaging. Ask them for their number there to start a conversation here.', choices: [
        if (page != null) Choice('Open their ${n.name} profile', Lucide.externalLink, () => Sms.instance.openLink(page)),
        Choice('Copy handle', Lucide.copy, () {
          Clipboard.setData(ClipboardData(text: joined.handle));
          toast(context, 'Copied');
        }),
        Choice('Stop watching for them', Lucide.eyeOff, () => Me.instance.removeWatch(Watched(joined.network, joined.handle)), danger: true),
      ]),
    );
  }
}

class _ImportRow extends StatefulWidget implements PaneRow {
  const _ImportRow({required this.network});
  final Network network;

  @override
  State<_ImportRow> createState() => _ImportRowState();
}

class _ImportRowState extends State<_ImportRow> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final added = await Me.instance.importFollows(widget.network.id);
      if (mounted) toast(context, added == 0 ? 'Nobody new to add' : 'Watching for $added more from ${widget.network.name}');
    } catch (e) {
      if (mounted) toast(context, '$e', tone: GlacierToastTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingRow(
        icon: _icon(Lucide.download),
        label: _busy ? 'Reading who you follow…' : 'Bring in who I follow on ${widget.network.name}',
        hint: Text('@${Me.instance.links[widget.network.id]}'),
        disabled: _busy || !Me.instance.ready,
        onPress: _go,
      );
}

/// Adding handles to watch for: a network, and as many handles as are typed or pasted.
class AddWatchScreen extends StatefulWidget {
  const AddWatchScreen({super.key});

  @override
  State<AddWatchScreen> createState() => _AddWatchScreenState();
}

class _AddWatchScreenState extends State<AddWatchScreen> {
  String _network = networks.first.id;
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final all = Me.split(_text.text);
    final fits = all.where((h) => handleFits(_network, h)).toList();
    final added = Me.instance.addWatch(_network, fits);
    final skipped = all.length - fits.length;
    final n = networkOf(_network);
    toast(
      context,
      [
        added == 0 ? 'Nothing new to add' : 'Watching for $added on ${n.name}',
        if (skipped > 0) '$skipped didn\'t look like ${n.name} handles',
      ].join('. '),
    );
    if (added > 0) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = networkOf(_network);
    final count = Me.split(_text.text).length;
    final ink = pageText(t, t.fontSize('md'), color: t.color('app-ink'), height: 1.4);
    return GlacierScope(
      attrs: {'hue': n.hue},
      child: GhostPage(
        title: 'Add handles',
        body: SettingsPaneScope(
          finder: SettingsFinder(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              PaneSection(
                title: 'Where',
                children: [
                  for (final net in networks)
                    SettingRow(
                      icon: NetworkMark(net),
                      label: net.name,
                      control: Pick(checked: net.id == _network, label: 'On ${net.name}', onPress: () => setState(() => _network = net.id)),
                    ),
                ],
              ),
              SizedBox(height: t.space(6)),
              PaneSection(
                title: 'Handles',
                description: Text('One or many, separated by spaces, commas or new lines. On ${n.name} a handle looks like ${n.example}.'),
                children: [
                  SettingRowBox(
                    child: GestureDetector(
                      onTap: _focus.requestFocus,
                      child: Container(
                        constraints: BoxConstraints(minHeight: t.lenOf('6rem')),
                        padding: EdgeInsets.all(t.space(3)),
                        decoration: BoxDecoration(color: t.color('app-paper-3'), borderRadius: BorderRadius.circular(t.radius('md'))),
                        child: Stack(children: [
                          if (_text.text.isEmpty) IgnorePointer(child: Text('@maya  @jordan  @sam', style: ink.copyWith(color: t.color('app-ink-3')))),
                          EditableText(
                            controller: _text,
                            focusNode: _focus,
                            style: ink,
                            cursorColor: t.color('app-ink'),
                            backgroundCursorColor: t.color('app-ink-3'),
                            selectionColor: t.colorOf('color-mix(in srgb, #4f5bd5 30%, transparent)'),
                            minLines: 3,
                            maxLines: 10,
                            keyboardType: TextInputType.multiline,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.none,
                          ),
                        ]),
                      ),
                    ),
                  ),
                  SettingRow(
                    icon: _icon(Lucide.plus),
                    label: count == 0 ? 'Watch for them' : 'Watch for $count on ${n.name}',
                    disabled: count == 0,
                    onPress: _add,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The handles watched for on one network, each taken off by a press.
class WatchListScreen extends StatelessWidget {
  const WatchListScreen({super.key, required this.network});
  final Network network;

  @override
  Widget build(BuildContext context) {
    final n = network;
    return GlacierScope(
      attrs: {'hue': n.hue},
      child: ListenableBuilder(
        listenable: Me.instance,
        builder: (context, _) {
          final t = context.tokens;
          final me = Me.instance;
          final mine = me.watch.where((w) => w.network == n.id).toList();
          final here = {for (final j in me.joined) if (j.network == n.id) j.handle};
          return GhostPage(
            title: '${n.name} · ${mine.length}',
            body: SettingsPaneScope(
              finder: SettingsFinder(),
              child: ListView(
                padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
                children: [
                  PaneSection(
                    children: [
                      if (mine.isEmpty) const SettingRow(label: 'Nobody', hint: Text('Add handles from Friends joining.')),
                      for (final w in mine.take(400))
                        SettingRow(
                          label: '@${w.handle}',
                          value: here.contains(w.handle) ? const Text('Here') : null,
                          onPress: () => showChoices(context, title: '@${w.handle} on ${n.name}', choices: [
                            if (n.profile(w.handle) != null) Choice('Open profile', Lucide.externalLink, () => Sms.instance.openLink(n.profile(w.handle)!)),
                            Choice('Stop watching for them', Lucide.eyeOff, () => me.removeWatch(w), danger: true),
                          ]),
                        ),
                    ],
                  ),
                  if (mine.length > 400)
                    Padding(
                      padding: EdgeInsets.all(t.space(4)),
                      child: Text('And ${mine.length - 400} more.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
