/// Which outgoing webhooks the account has, kept with its settings (docs/INTEGRATIONS.md, §1): each hook's URL, its
/// events, its scope and its secret. They travel sealed with the rest of the settings (lib/sync/prefs.dart,
/// `webhooks`), so a hook added on the phone is on the Mac; a secret is never shown again, never logged, and sent
/// nowhere but as the signature it makes. The incoming hooks are glyph-api's, default note and all (incoming.dart).
///
/// Kept under the preferences' `webhooks` key as JSON, which the typed [Preferences] keeps among the keys it does not
/// model ([Preferences.more]) and writes back as it was read: [webhookSetupOf] reads it, [withWebhookSetup] writes it.
/// How each hook last went is this device's own (outgoing.dart).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/preferences.dart';

/// The preferences' key.
const String webhooksKey = 'webhooks';

/// The plugin's id (plugin.dart): its switch, and its page (`plugin:webhooks`).
const String webhooksId = 'webhooks';

/// What a note's change is called to an outgoing hook.
enum WebhookEvent {
  created('note.created', 'A note is made'),
  edited('note.edited', 'A note is edited'),
  todoDone('todo.done', 'A to-do is ticked');

  const WebhookEvent(this.wire, this.words);

  /// As the JSON says it: `note.edited`.
  final String wire;

  /// As the pane says it.
  final String words;

  static WebhookEvent? fromWire(Object? said) => values.where((event) => event.wire == said).firstOrNull;
}

/// Which notes an outgoing hook hears of.
enum ScopeKind {
  all('all'),
  workspace('workspace'),
  notebook('notebook'),
  tag('tag');

  const ScopeKind(this.wire);
  final String wire;

  static ScopeKind fromWire(Object? said) => values.where((kind) => kind.wire == said).firstOrNull ?? all;
}

/// Every note, a workspace's (by id), a notebook's (by the notebook note's id, the notebook among them) or a tag's
/// (by its name, lower-cased, no `#`).
@immutable
class WebhookScope {
  const WebhookScope.all()
      : kind = ScopeKind.all,
        value = null;
  const WebhookScope(this.kind, this.value);

  final ScopeKind kind;

  /// The workspace's id, the notebook's note id or the tag's name; null for every note.
  final String? value;

  Map<String, Object?> toJson() => {'kind': kind.wire, if (value != null) 'value': value};

  static WebhookScope fromJson(Object? raw) {
    if (raw is! Map) return const WebhookScope.all();
    final kind = ScopeKind.fromWire(raw['kind']);
    final value = raw['value'];
    if (kind == ScopeKind.all || value is! String || value.trim().isEmpty) return const WebhookScope.all();
    return WebhookScope(kind, kind == ScopeKind.tag ? tagName(value) : value);
  }

  @override
  bool operator ==(Object other) => other is WebhookScope && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// A tag as a scope keeps it: lower-cased, without its `#`.
String tagName(String typed) => typed.trim().replaceFirst(RegExp('^#+'), '').toLowerCase();

/// A URL told when notes change.
@immutable
class OutgoingHook {
  const OutgoingHook({required this.id, required this.url, this.events = const {WebhookEvent.edited}, this.scope = const WebhookScope.all(), this.secret});

  final String id;
  final String url;
  final Set<WebhookEvent> events;
  final WebhookScope scope;

  /// What the body is signed with (`X-Ghost-Signature`); null for no signature.
  final String? secret;

  /// What a row says of it: the URL's host.
  String get label => Uri.tryParse(url)?.host.isNotEmpty == true ? Uri.parse(url).host : url;

  OutgoingHook copyWith({Set<WebhookEvent>? events, WebhookScope? scope, String? Function()? secret}) =>
      OutgoingHook(id: id, url: url, events: events ?? this.events, scope: scope ?? this.scope, secret: secret != null ? secret() : this.secret);

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'events': [for (final event in WebhookEvent.values) if (events.contains(event)) event.wire],
        'scope': scope.toJson(),
        if (secret != null) 'secret': secret,
      };

  static OutgoingHook? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['url'] is! String) return null;
    final events = raw['events'];
    final secret = raw['secret'];
    return OutgoingHook(
      id: raw['id'] as String,
      url: raw['url'] as String,
      events: {
        if (events is List)
          for (final each in events) ?WebhookEvent.fromWire(each),
      },
      scope: WebhookScope.fromJson(raw['scope']),
      secret: secret is String && secret.isNotEmpty ? secret : null,
    );
  }
}

/// Every webhook the account has.
@immutable
class WebhookSetup {
  const WebhookSetup({this.outgoing = const [], this.carried = const {}});

  static const WebhookSetup none = WebhookSetup();

  final List<OutgoingHook> outgoing;

  /// What a newer build keeps beside the hooks, carried and not read, so a round trip through this one loses none of
  /// it.
  final Map<String, Object?> carried;

  bool get isEmpty => outgoing.isEmpty && carried.isEmpty;

  WebhookSetup copyWith({List<OutgoingHook>? outgoing}) => WebhookSetup(outgoing: outgoing ?? this.outgoing, carried: carried);

  Map<String, Object?> toJson() => {
        ...carried,
        'outgoing': [for (final hook in outgoing) hook.toJson()],
      };

  static WebhookSetup fromJson(Object? raw) {
    if (raw is! Map) return none;
    final list = raw['outgoing'];
    return WebhookSetup(
      outgoing: List.unmodifiable([
        if (list is List)
          for (final each in list) ?OutgoingHook.fromJson(each),
      ]),
      carried: Map.unmodifiable({
        for (final MapEntry(:key, :value) in raw.entries)
          if (key is String && key != 'outgoing') key: value,
      }),
    );
  }

  @override
  bool operator ==(Object other) => other is WebhookSetup && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// The webhooks [prefs] keeps.
WebhookSetup webhookSetupOf(Preferences prefs) => WebhookSetup.fromJson(prefs.more[webhooksKey]);

/// [prefs] with [setup] kept; with none at all, the key is taken off.
Preferences withWebhookSetup(Preferences prefs, WebhookSetup setup) {
  final more = {...prefs.more};
  if (setup.isEmpty) {
    more.remove(webhooksKey);
  } else {
    more[webhooksKey] = setup.toJson();
  }
  return prefs.copyWith(more: Map.unmodifiable(more));
}

/// What a person typed, as the URL to tell, or why it is not one: a secure web address with a host, or a plain one
/// on this computer (`localhost`, `127.0.0.1`) for trying a receiver out.
({String? url, String? problem}) webhookUrl(String typed) {
  final text = typed.trim();
  if (text.isEmpty) return (url: null, problem: 'Paste the URL to tell.');
  if (RegExp(r'\s').hasMatch(text)) return (url: null, problem: 'A URL has no spaces in it.');
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty || !uri.hasScheme) return (url: null, problem: 'That isn’t a web address. It starts with https://.');
  final scheme = uri.scheme.toLowerCase();
  final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
  if (scheme == 'http' && !local) return (url: null, problem: 'Only a secure address (https://) is told: your notes go in the body.');
  if (scheme != 'https' && scheme != 'http') return (url: null, problem: 'A webhook’s URL starts with https://.');
  return (url: uri.toString(), problem: null);
}
