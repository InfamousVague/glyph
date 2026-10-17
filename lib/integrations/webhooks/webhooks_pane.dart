import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/book.dart' show isBookBody;
import '../../core/note.dart';
import '../../core/note_text.dart' show noteTitle;
import '../../core/preferences.dart';
import '../../settings/account_forms.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/kit/settings_type.dart';
import '../../settings/settings_search.dart';
import '../../sync/engine.dart' show syncedWhen;
import 'incoming.dart';
import 'outgoing.dart';
import 'setup.dart';

/// What Settings' search finds on the Webhooks plugin's page: its two cards, always drawn.
List<SettingsFindable> webhooksFindable() => const [
      SettingsFindable('Outgoing webhooks', 'webhook outgoing url post json signature secret hmac zapier make ifttt automation note edited created todo done'),
      SettingsFindable('Incoming webhooks', 'webhook incoming url add to a note curl zapier make ifttt automation inbox task item'),
    ];

/// The row's reading: how many outgoing hooks.
String webhooksSummary(Preferences prefs) {
  final count = webhookSetupOf(prefs).outgoing.length;
  return count == 0 ? 'None going out' : (count == 1 ? '1 going out' : '$count going out');
}

/// What a scope says in a row.
String scopeWords(WebhookScope scope, {String? Function(String id)? named}) {
  final value = scope.value ?? '';
  return switch (scope.kind) {
    ScopeKind.all => 'Every note',
    ScopeKind.workspace => 'Notes in ${named?.call(value) ?? 'a workspace'}',
    ScopeKind.notebook => 'Pages of ${named?.call(value) ?? 'a notebook'}',
    ScopeKind.tag => 'Notes tagged #$value',
  };
}

/// The Webhooks plugin's page, Settings › Plugins › Webhooks (docs/INTEGRATIONS.md, §1; the port's own, 2026-10-17;
/// plugin.dart), reached once the plugin is switched on:
///
/// - **Outgoing webhooks**: a URL told when a note this device changes is made, edited or has a to-do ticked, for
///   every note, a workspace's, a notebook's or a tag's, signed with a secret where one is given. Each listed by its
///   URL's host with how its last send went, Send a test and Remove; then a form for a new one. Kept with the
///   account's settings, so every device of it sends what it changes.
/// - **Incoming webhooks**, signed in: a URL of ghostmarkdown.com's that adds to a note, made with a name and a
///   default note picked from the notes. Its URL is shown once, as it is made (the service keeps only its digest),
///   with Copy and examples for curl, Zapier, Make and IFTTT; each hook listed with its note and when it was last
///   used, and Delete.
///
/// Nothing is sent and nothing read with Local only on, which the page says.
class WebhooksPane extends StatefulWidget {
  const WebhooksPane({super.key, this.sender, this.prefs, this.services, this.incoming, this.notes});

  /// The outgoing hooks' sender; the app's own when left out.
  final WebhookSender? sender;

  /// The preferences, for Local only and the workspaces; the sender's own when left out.
  final PreferencesStore? prefs;

  /// The account, for the incoming hooks and the notes.
  final AccountServices? services;

  /// The incoming hooks; made over [services] when left out.
  final IncomingHooks? incoming;

  /// The notes, for a default note and a notebook; the account's when left out.
  final Future<List<Note>> Function()? notes;

  static Widget hosted(BuildContext context) => WebhooksPane(services: AccountScope.maybeOf(context));

  @override
  State<WebhooksPane> createState() => _WebhooksPaneState();
}

class _WebhooksPaneState extends State<WebhooksPane> {
  WebhookSender get _sender => widget.sender ?? webhooks;
  PreferencesStore get _prefs => widget.prefs ?? _sender.prefs;

  late final IncomingHooks? _incoming = widget.incoming ?? (widget.services == null ? null : IncomingHooks.of(widget.services!));
  late final bool _ownIncoming = widget.incoming == null;

  List<Note> _notes = const [];

  // The new outgoing hook.
  String _url = '';
  String _secret = '';
  String _tag = '';
  Set<WebhookEvent> _events = {WebhookEvent.edited};
  ScopeKind _kind = ScopeKind.all;
  String? _value;
  String? _outProblem;
  final Map<String, String> _tested = {};

  // The new incoming hook.
  String _name = '';
  String _note = '';
  String? _inProblem;
  bool _making = false;
  String? _said;

  bool get _signedIn => widget.services?.signedIn ?? widget.incoming != null;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void dispose() {
    if (_ownIncoming) _incoming?.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final list = widget.notes ?? widget.services?.listNotes;
    if (list != null) {
      try {
        final notes = await list();
        if (mounted) setState(() => _notes = notes);
      } catch (_) {
        // No notes to pick from: the default note is typed.
      }
    }
    final incoming = _incoming;
    if (incoming != null && _signedIn) {
      try {
        await incoming.refresh();
      } catch (failure) {
        if (mounted) setState(() => _inProblem = '$failure');
      }
    }
  }

  // ---- outgoing ------------------------------------------------------------------------------------------------

  void _add() {
    final value = _kind == ScopeKind.tag ? tagName(_tag) : _value;
    final problem = _sender.add(_url, events: _events, scope: _kind == ScopeKind.all ? const WebhookScope.all() : WebhookScope(_kind, value), secret: _secret);
    setState(() {
      _outProblem = problem;
      if (problem == null) {
        _url = _secret = _tag = '';
        _events = {WebhookEvent.edited};
        _kind = ScopeKind.all;
        _value = null;
      }
    });
  }

  Future<void> _test(String id) async {
    setState(() => _tested[id] = 'Sending…');
    final problem = await _sender.sendTest(id);
    if (mounted) setState(() => _tested[id] = problem ?? 'Sent. The URL answered.');
  }

  String? _named(String id) {
    for (final space in _prefs.value.workspaces.list) {
      if (space.id == id) return space.name;
    }
    for (final note in _notes) {
      if (note.id == id) return noteTitle(note.body);
    }
    return null;
  }

  String _statusLine(OutgoingHook hook, {required bool local}) {
    final tested = _tested[hook.id];
    if (tested != null) return tested;
    if (local) return 'Nothing is sent while Local only is on.';
    final status = _sender.statusOf(hook.id);
    if (status == null) return 'Nothing sent yet.';
    return status.problem == null ? 'Last sent ${syncedWhen(status.at)}.' : '${status.problem} Tried four times, ${syncedWhen(status.at)}.';
  }

  List<Widget> _outgoing(WebhookSetup setup, {required bool local}) {
    final spaces = _prefs.value.workspaces.list;
    final books = [for (final note in _notes) if (isBookBody(note.body)) note];
    return [
      PaneSection(
        title: 'Outgoing webhooks',
        description: const Text('A URL told when a note you change on this device is made, edited, or has a to-do ticked: JSON with the note’s words and the lines that changed, at most once every 10 seconds a note. Every device of yours sends what it changes.'),
        children: [
          if (setup.outgoing.isEmpty) const SettingRow(label: 'None yet', hint: Text('Add a URL below.')),
          for (final hook in setup.outgoing)
            SettingRow(
              key: ValueKey('webhook-out-${hook.id}'),
              icon: const AppIcon(Lucide.send, size: 16),
              label: hook.label,
              hint: Text('${[for (final event in WebhookEvent.values) if (hook.events.contains(event)) event.wire].join(', ')} · ${scopeWords(hook.scope, named: _named)}${hook.secret == null ? '' : ' · signed'}\n${_statusLine(hook, local: local)}'),
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RowAction(onPress: () => unawaited(_test(hook.id)), disabled: local, child: const Text('Test')),
                  RowAction(onPress: () => _sender.remove(hook.id), child: const Text('Remove')),
                ],
              ),
            ),
        ],
      ),
      PaneSection(
        title: 'New outgoing webhook',
        children: [
          SettingsForm(
            children: [
              GlacierInput(
                key: const ValueKey('webhook-url'),
                ariaLabel: 'Webhook URL',
                placeholder: 'https://',
                type: GlacierInputType.url,
                autoCorrect: false,
                spellCheck: false,
                value: _url,
                onChange: (text) => setState(() => _url = text),
              ),
            ],
          ),
          for (final event in WebhookEvent.values)
            SettingRow(
              label: event.words,
              hint: Text(event.wire),
              control: GlacierSwitch(
                ariaLabel: event.words,
                checked: _events.contains(event),
                onCheckedChange: (on) => setState(() => _events = on ? {..._events, event} : ({..._events}..remove(event))),
              ),
            ),
          for (final (kind, words) in [(ScopeKind.all, 'Every note'), (ScopeKind.workspace, 'A workspace'), (ScopeKind.notebook, 'A notebook'), (ScopeKind.tag, 'A tag')])
            SettingRow(
              key: ValueKey('webhook-scope-${kind.wire}'),
              label: words,
              control: Pick(checked: _kind == kind, label: 'Tell of ${words.toLowerCase()}', onPress: () => setState(() {
                _kind = kind;
                _value = null;
              })),
            ),
          if (_kind == ScopeKind.workspace)
            if (spaces.isEmpty)
              const SettingRow(label: 'No workspaces yet')
            else
              for (final space in spaces)
                SettingRow(
                  label: space.name,
                  hint: const Text('Workspace'),
                  control: Pick(checked: _value == space.id, label: 'Notes in ${space.name}', onPress: () => setState(() => _value = space.id)),
                ),
          if (_kind == ScopeKind.notebook)
            if (books.isEmpty)
              const SettingRow(label: 'No notebooks yet')
            else
              for (final book in books)
                SettingRow(
                  label: noteTitle(book.body),
                  hint: const Text('Notebook'),
                  control: Pick(checked: _value == book.id, label: 'Pages of ${noteTitle(book.body)}', onPress: () => setState(() => _value = book.id)),
                ),
          SettingsForm(
            children: [
              if (_kind == ScopeKind.tag)
                GlacierInput(
                  key: const ValueKey('webhook-tag'),
                  ariaLabel: 'Tag',
                  placeholder: '#work',
                  autoCorrect: false,
                  spellCheck: false,
                  value: _tag,
                  onChange: (text) => setState(() => _tag = text),
                ),
              GlacierInput(
                key: const ValueKey('webhook-secret'),
                ariaLabel: 'Secret',
                placeholder: 'Secret, to sign with (optional)',
                type: GlacierInputType.password,
                autoCorrect: false,
                spellCheck: false,
                value: _secret,
                onChange: (text) => setState(() => _secret = text),
              ),
              if (_outProblem != null) FormProblem(_outProblem!),
              FormSubmit('Add', wordKey: const ValueKey('webhook-add'), onPressed: _url.trim().isEmpty ? null : _add),
            ],
          ),
        ],
      ),
    ];
  }

  // ---- incoming ------------------------------------------------------------------------------------------------

  Future<void> _make() async {
    final incoming = _incoming;
    if (incoming == null || _making) return;
    setState(() {
      _making = true;
      _inProblem = null;
    });
    try {
      await incoming.create(_name, note: _note);
      if (mounted) {
        setState(() {
          _name = _note = '';
          _said = null;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => _inProblem = '$failure');
    } finally {
      if (mounted) setState(() => _making = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _incoming?.delete(id);
    } catch (failure) {
      if (mounted) setState(() => _inProblem = '$failure');
    }
  }

  Future<void> _copy(String text, String said) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _said = said);
    } catch (_) {
      if (mounted) setState(() => _said = text);
    }
  }

  String _hookLine(IncomingHook hook) {
    final into = hook.note == null ? 'Into a note named by what is posted' : 'Into ${hook.note}';
    final used = hook.lastUsedAt == null ? 'never used' : 'last used ${syncedWhen(hook.lastUsedAt!)}';
    return '$into · $used';
  }

  List<Widget> _incomingCards({required bool local}) {
    final incoming = _incoming;
    if (incoming == null || !_signedIn) {
      return const [
        PaneSection(
          title: 'Incoming webhooks',
          children: [SettingRow(label: 'Sign in to make one', hint: Text('An incoming webhook is a URL of ghostmarkdown.com’s that adds to a note: sign in under Settings › Account.'))],
        ),
      ];
    }
    final hooks = incoming.hooks;
    final made = incoming.made;
    final typed = _note.trim().toLowerCase();
    final titles = <String>{
      for (final note in _notes)
        if (noteTitle(note.body).trim() case final title when title.isNotEmpty && (typed.isEmpty || title.toLowerCase().contains(typed)) && title.toLowerCase() != typed) title,
    }.take(5);
    return [
      PaneSection(
        title: 'Incoming webhooks',
        description: const Text('A URL that adds to a note: post JSON { "note", "text", "as" } with as task, item, paragraph or note, or plain text, which goes to the hook’s own note. What arrives is sealed to your account at once, and your devices put it in the note.'),
        footer: _said == null ? null : Text(_said!),
        children: [
          if (!incoming.available)
            const SettingRow(label: 'Not on this service yet', hint: Text('The service this app talks to has no incoming webhooks.'))
          else if (hooks == null)
            const SettingRow(label: 'Looking for your webhooks…')
          else if (hooks.isEmpty)
            const SettingRow(label: 'None yet', hint: Text('Make one below.'))
          else
            for (final hook in hooks)
              SettingRow(
                key: ValueKey('webhook-in-${hook.id}'),
                icon: const AppIcon(Lucide.link, size: 16),
                label: hook.name,
                hint: Text(_hookLine(hook)),
                control: RowAction(onPress: () => unawaited(_delete(hook.id)), child: const Text('Delete')),
              ),
          if (made != null && made.url != null) ...[
            SettingRow(
              key: const ValueKey('webhook-made-url'),
              label: made.url!,
              hint: const Text('Copy it now: it won’t be shown again. Lost, make a new hook and delete this one.'),
              control: RowAction(onPress: () => unawaited(_copy(made.url!, 'The URL is copied.')), child: const Text('Copy')),
            ),
          ],
        ],
      ),
      if (made != null && made.url != null)
        PaneSection(
          title: 'Examples',
          children: [
            for (final example in hookExamples(made.url!, note: made.note))
              SettingRow(
                key: ValueKey('webhook-example-${example.name}'),
                label: example.name,
                hint: Builder(builder: (context) => Text(example.text, style: pageText(context.tokens, context.tokens.fontSize('sm'), color: context.tokens.color('app-ink-2'), mono: true))),
                control: RowAction(onPress: () => unawaited(_copy(example.text, 'The ${example.name} example is copied.')), child: const Text('Copy')),
              ),
          ],
        ),
      if (incoming.available)
        PaneSection(
          title: 'New incoming webhook',
          children: [
            SettingsForm(
              children: [
                GlacierInput(
                  key: const ValueKey('webhook-name'),
                  ariaLabel: 'Hook name',
                  placeholder: 'Name, as “Zapier”',
                  value: _name,
                  onChange: (text) => setState(() => _name = text),
                ),
                GlacierInput(
                  key: const ValueKey('webhook-note'),
                  ariaLabel: 'Default note',
                  placeholder: 'Default note (optional)',
                  value: _note,
                  onChange: (text) => setState(() => _note = text),
                ),
              ],
            ),
            for (final title in titles)
              SettingRow(
                key: ValueKey('webhook-pick-$title'),
                label: title,
                hint: const Text('A note'),
                control: Pick(checked: false, label: 'Into $title', onPress: () => setState(() => _note = title)),
              ),
            SettingsForm(
              children: [
                if (_inProblem != null) FormProblem(_inProblem!),
                FormSubmit(_making ? 'Making…' : 'Make', wordKey: const ValueKey('webhook-make'), onPressed: _making || local ? null : () => unawaited(_make())),
              ],
            ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_sender, _prefs, ?_incoming]),
      builder: (context, _) {
        final local = _prefs.value.localOnly;
        return PaneBody(
          children: [
            if (local) const SettingsCallout(child: Text('Local only is on: no webhook is told and nothing posted is read until it is off (Settings › Account).')),
            ..._outgoing(_sender.setup, local: local),
            ..._incomingCards(local: local),
            const SettingsFootnote(
              child: Text('Outgoing webhooks are sent by the device that made the change, never by ghostmarkdown.com, which cannot read your notes. A secret signs each body: X-Ghost-Signature: sha256=<HMAC-SHA256 of the body>.'),
            ),
          ],
        );
      },
    );
  }
}
