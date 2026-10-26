/// The Discord plugin's channels on this device: what each is called, and the way to post to it (Matt, 2026-10-26:
/// "Add a new plugin to post notes to discord chats"). The Slack plugin's channels.dart, for Discord's webhooks.
///
/// A channel is an **incoming webhook** the person makes in Discord (a channel's Edit › Integrations › Webhooks ›
/// New Webhook › Copy Webhook URL) and pastes here: nothing to sign in to, no bot to invite, nothing on the server,
/// and the post goes straight from the device. Two halves kept in two places, as Slack's are:
///
/// - **Its name and id** in the plugin's storage, `glyph-discord-channels`: the name is the person's own ("#launch");
///   a webhook's URL says nothing of the channel it posts to.
/// - **Its webhook** in the device's secure store, under [discordWebhookPrefix] and the id. Whoever holds the URL can
///   post to the channel, so once it is handed over no page shows it again.
///
/// Both follow the account, sealed (lib/sync/connections.dart, lib/sync/sealed_keys.dart), as Slack's do: a channel
/// added on the Fold posts from the Mac, and one forgotten anywhere is forgotten everywhere. Not on an iPhone, where
/// Slack is not either (lib/core/iphone_app.dart `notOnIPhone`).
///
/// The rules, each a test (test/plugins/discord/channels_test.dart):
///
/// - **A webhook is one of Discord's shapes** ([allowedDiscordWebhook]): https, `discord.com` or `discordapp.com`
///   (each also as `ptb.` and `canary.`, the test clients' hosts, which hand out the same URLs), the path
///   `/api/webhooks/<id>/<token>` with an optional `v10/` after `api/`, the id a snowflake of digits and the token
///   Discord's letters, digits, dashes and underscores, and nothing after it: no query (`?wait=`, `?thread_id=`),
///   no fragment, no `/slack` or `/github` (Discord's look-alike endpoints, which take other bodies). Checked as it is
///   typed ([discordWebhookProblem]), before it is kept and again before each post.
/// - **A post is one message** ([postToDiscord]): `content` of at most [discordContentMost] characters, with
///   `allowed_mentions` empty, so an `@everyone` or a `<@id>` in a note pings nobody, and link previews suppressed
///   (`flags`: SUPPRESS_EMBEDS), so the channel reads the note and not the cards of the sites it links.
/// - **Discord's rate limits** are a 429 with `retry_after` in seconds (and a `Retry-After` header). A short wait,
///   [discordRetryMost] at most, is waited and the post tried again, twice at most; a longer one is not waited by a
///   person holding a phone, and fails with the wait in its sentence, so a meeting's post goes back in its queue
///   (meetings.dart) and a note's says to try again. One message per post is also what keeps a long note clear of
///   them: a note cut into several messages would spend a webhook's few posts a second on one press.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../account/api.dart' show FetchRequest, FetchResponse;
import '../../core/iphone_app.dart' show notOnIPhone;
import '../host.dart' show PluginPermissionError;
import 'manifest.dart';

/// One channel.
@immutable
class DiscordChannel {
  const DiscordChannel({required this.id, required this.name});

  /// Made here when the channel is added: the key its webhook is kept under.
  final String id;

  /// The person's name for it: "#launch".
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) => other is DiscordChannel && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'DiscordChannel($id, $name)';
}

// ---- the webhook's shape -----------------------------------------------------------------------------------------

/// Discord's webhook URLs, whole: the four hosts, the optional API version, a snowflake and a token.
final RegExp _webhook = RegExp(r'^https:\/\/(?:(?:ptb|canary)\.)?discord(?:app)?\.com\/api\/(?:v\d{1,2}\/)?webhooks\/(\d{15,22})\/([A-Za-z0-9_-]{20,128})$');
final RegExp _host = RegExp(r'^https:\/\/(?:(?:ptb|canary)\.)?discord(?:app)?\.com\/', caseSensitive: false);
final RegExp _idChars = RegExp(r'^[A-Za-z0-9-]+$');

/// The most Discord takes in a message's `content`: 2000 characters.
const int discordContentMost = 2000;

/// The longest a 429's `retry_after` is waited before a post is tried again.
const Duration discordRetryMost = Duration(seconds: 5);

/// How many times a post is tried again after a 429 it could wait for.
const int discordRetries = 2;

/// SUPPRESS_EMBEDS, the one message flag besides SUPPRESS_NOTIFICATIONS a webhook may set.
const int _suppressEmbeds = 1 << 2;

/// What is wrong with a pasted webhook, in a sentence, or null when it is one Discord would hand out. Checked here so
/// the pane can say so as it is typed; [allowedDiscordWebhook] checks again before one is kept and before it is
/// posted to.
String? discordWebhookProblem(String pasted) {
  final url = pasted.trim();
  if (url.isEmpty) return 'Paste the webhook URL Discord gave you.';
  if (RegExp(r'^http:\/\/', caseSensitive: false).hasMatch(url)) return 'A Discord webhook starts with https://, never http://.';
  if (!_host.hasMatch(url)) return 'That isn’t a Discord webhook. It starts with https://discord.com/api/webhooks/.';
  if (url.contains('..') || !allowedDiscordWebhook(url)) {
    return 'That isn’t a Discord webhook URL. It is https://discord.com/api/webhooks/, a number, a slash and a token, with nothing after it.';
  }
  return null;
}

/// Whether [url] is a Discord webhook: see the header. No query, no fragment, no `..`, no user before the host, no
/// path after the token.
bool allowedDiscordWebhook(String url) => url.length <= 256 && !url.contains('..') && _webhook.hasMatch(url);

/// An id made here for a channel: a run of hex, or anything as plain.
bool allowedDiscordId(String id) => id.isNotEmpty && id.length <= 64 && _idChars.hasMatch(id);

const String _notAWebhook = 'That isn’t a Discord webhook. It starts with https://discord.com/api/webhooks/.';

/// A channel's name as kept: trimmed, one space between words, at most 80 characters.
String discordChannelName(String typed) {
  final name = typed.trim().replaceAll(RegExp(r'\s+'), ' ');
  return name.length <= 80 ? name : name.substring(0, 80);
}

/// What is wrong with a name for a new or renamed channel, or null. [except] is the channel being renamed.
String? discordNameProblem(String typed, [String? except]) {
  final name = discordChannelName(typed);
  if (name.isEmpty) return 'Give the channel a name, like #launch.';
  final taken = discordChannels().any((c) => c.id != except && c.name.toLowerCase() == name.toLowerCase());
  return taken ? 'There is a channel called $name already.' : null;
}

// ---- the list ----------------------------------------------------------------------------------------------------

/// One list for as long as what is kept is the same: a note's More sheet asks on every draw.
({Object? from, List<DiscordChannel> list})? _shared;

/// The channels on this device, in the order they were added.
List<DiscordChannel> discordChannels() {
  final Object? kept = host.storage.get<Object?>(discordChannelsKey, const <Object?>[]);
  final shared = _shared;
  if (shared != null && identical(shared.from, kept)) return shared.list;
  final list = <DiscordChannel>[
    if (kept is List)
      for (final raw in kept)
        if (raw is Map && raw['id'] is String && (raw['id'] as String).isNotEmpty && raw['name'] is String && (raw['name'] as String).isNotEmpty)
          DiscordChannel(id: raw['id'] as String, name: raw['name'] as String),
  ];
  _shared = (from: kept, list: List.unmodifiable(list));
  return _shared!.list;
}

/// The channel with this id, or null.
DiscordChannel? discordChannelById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final channel in discordChannels()) {
    if (channel.id == id) return channel;
  }
  return null;
}

void _keep(List<DiscordChannel> list) {
  if (list.isNotEmpty) {
    host.storage.set(discordChannelsKey, [for (final channel in list) channel.toJson()]);
  } else {
    host.storage.remove(discordChannelsKey);
  }
}

/// Sixteen random bytes as hex: the id a channel's webhook is kept under.
String _newId() {
  final random = Random.secure();
  return [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

String _secretOf(String id) => '$discordWebhookPrefix$id';

/// A channel added: its webhook kept first, so a channel is never listed without the way to post to it, then its
/// name. Refused, in a sentence, for a name or a webhook that won't do. The secure store's door says nothing when a
/// write fails, so what it holds afterwards is the answer.
Future<DiscordChannel> addDiscordChannel(String typedName, String pastedUrl) async {
  final problem = discordNameProblem(typedName) ?? discordWebhookProblem(pastedUrl);
  if (problem != null) throw DiscordFailure(problem);
  final channel = DiscordChannel(id: _newId(), name: discordChannelName(typedName));
  final url = pastedUrl.trim();
  if (!allowedDiscordWebhook(url)) throw const DiscordFailure(_notAWebhook);
  await host.secrets.write(_secretOf(channel.id), url);
  if (await host.secrets.read(_secretOf(channel.id)) != url) throw const DiscordFailure('Ghost.md couldn’t keep the Discord webhook on this device.');
  _keep([...discordChannels(), channel]);
  return channel;
}

/// A new name for a channel; its webhook stays as it was.
void renameDiscordChannel(String id, String typedName) {
  final problem = discordNameProblem(typedName, id);
  if (problem != null) throw DiscordFailure(problem);
  _keep([for (final c in discordChannels()) c.id == id ? DiscordChannel(id: c.id, name: discordChannelName(typedName)) : c]);
}

/// A channel forgotten: its webhook gone from the secure store, then its name from here.
Future<void> forgetDiscordChannel(String id) async {
  if (allowedDiscordId(id)) await host.secrets.write(_secretOf(id), null);
  _keep([for (final c in discordChannels()) if (c.id != id) c]);
}

/// The ids of the listed channels that have a webhook kept: a channel listed without one (a cleared store) can't
/// post, and the pane says so.
Future<List<String>> keptDiscordWebhooks() async {
  final ids = <String>[];
  for (final channel in discordChannels()) {
    if (!allowedDiscordId(channel.id)) continue;
    final url = await host.secrets.read(_secretOf(channel.id));
    if (url != null && url.isNotEmpty) ids.add(channel.id);
  }
  return ids;
}

/// The webhook to post to for [id], held to Discord's shapes again: a store written some other way is not a way
/// round them.
Future<String> _webhookFor(String id) async {
  final url = allowedDiscordId(id) ? await host.secrets.read(_secretOf(id)) : null;
  if (url == null || url.isEmpty) throw const DiscordFailure('This channel’s webhook isn’t on this device. Add the channel again in Settings › Discord.');
  if (!allowedDiscordWebhook(url)) throw const DiscordFailure(_notAWebhook);
  return url;
}

// ---- Discord's answer --------------------------------------------------------------------------------------------

/// What Discord said in a refusal's body: `{"message": "Unknown Webhook", "code": 10015}`, or for a 429
/// `{"message": "You are being rate limited.", "retry_after": 1.2, "global": false}`.
({int? code, double? retryAfter}) _said(String body) {
  try {
    final read = jsonDecode(body);
    if (read is Map) {
      final code = read['code'], retry = read['retry_after'];
      return (code: code is num ? code.toInt() : null, retryAfter: retry is num ? retry.toDouble() : null);
    }
  } catch (_) {
    // Not JSON: a proxy's page, or nothing.
  }
  return (code: null, retryAfter: null);
}

/// How long a 429 asks to wait: its body's `retry_after`, else its `Retry-After` header, in seconds; a second where
/// neither says.
Duration discordRetryAfter(FetchResponse response) {
  final seconds = _said(response.text).retryAfter ?? double.tryParse(response.headers['retry-after'] ?? '') ?? 1;
  return Duration(milliseconds: (seconds.clamp(0, 3600) * 1000).ceil());
}

String _seconds(Duration wait) {
  final s = (wait.inMilliseconds / 1000).ceil();
  return s <= 1 ? 'a second' : (s < 120 ? '$s seconds' : '${(s / 60).ceil()} minutes');
}

/// Discord's answer to a post, as nothing or the reason in a sentence. A webhook answers 204 (or 200 with
/// `?wait=true`, which is not asked), and otherwise a status and a JSON `code`.
String? discordAnswer(int status, String body, {Duration? wait}) {
  if (status >= 200 && status < 300) return null;
  final code = _said(body).code;
  // 10015 Unknown Webhook; 50027 Invalid Webhook Token.
  if (code == 10015 || code == 50027 || status == 404 || status == 401) {
    return 'Discord no longer knows this webhook. Make a new one in Discord and add the channel again.';
  }
  if (status == 403) return 'Discord refused the post. The webhook may not post in that channel any more.';
  if (status == 413 || code == 50035 || status == 400) return 'Discord couldn’t read the message.';
  if (status == 429) return 'Discord asked for fewer posts. Try again in ${_seconds(wait ?? const Duration(seconds: 1))}.';
  if (status >= 500 && status <= 599) return 'Discord had a problem. Try again in a moment.';
  return 'Discord answered $status.';
}

/// How a post waits out a 429; a test stands in for it.
Future<void> Function(Duration wait) discordWait = Future<void>.delayed;

/// The body a post sends: the message, nobody pinged, no link previews.
Map<String, Object?> discordBody(String content) => {
      'content': content,
      'allowed_mentions': {'parse': <String>[]},
      'flags': _suppressEmbeds,
    };

/// Posts [content], in Discord's Markdown (markdown.dart), to a channel, as one message. Throws a [DiscordFailure]
/// with the sentence for why not. A 429 asking for a short wait is waited and tried again ([discordRetries]).
Future<void> postToDiscord(DiscordChannel channel, String content) async {
  final notHere = notOnIPhone('discord');
  if (notHere != null) throw DiscordFailure(notHere);
  if (content.trim().isEmpty) throw const DiscordFailure('There is nothing to post.');
  if (content.length > discordContentMost) throw const DiscordFailure('That is too long for one Discord message.');
  final url = await _webhookFor(channel.id);
  final body = Uint8List.fromList(utf8.encode(jsonEncode(discordBody(content))));
  for (var tries = 0;; tries++) {
    final FetchResponse response;
    try {
      response = await host.fetch(FetchRequest(method: 'POST', url: Uri.parse(url), headers: const {'Content-Type': 'application/json'}, body: body, timeout: const Duration(seconds: 20)));
    } on PluginPermissionError {
      rethrow;
    } on TimeoutException {
      throw const DiscordFailure('Discord took too long to answer. Try again.');
    } catch (_) {
      throw const DiscordFailure('Discord couldn’t be reached. Check the connection.');
    }
    if (response.status == 429) {
      final wait = discordRetryAfter(response);
      if (tries < discordRetries && wait <= discordRetryMost) {
        await discordWait(wait);
        continue;
      }
      throw DiscordFailure(discordAnswer(429, response.text, wait: wait)!);
    }
    final refused = discordAnswer(response.status, response.text);
    if (refused != null) throw DiscordFailure(refused);
    return;
  }
}
