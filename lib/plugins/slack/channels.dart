/// The Slack plugin's channels on this device: what each is called, and the way to post to it. A port of
/// `src/app/plugins/slack/channels.ts`, and of `src-tauri/src/slack.rs`, whose work is this file's here.
///
/// Matt: "include #6 as a plugin as well as #5", where #5 was "Slack: post a meeting's summary, or a note, to a
/// channel when you choose to. It pairs well with organizations: a team's news could go to its channel too. Sending
/// is always your choice, so the encryption holds." He chose incoming webhooks: nothing to sign in to and nothing
/// on the server, the post goes straight from the device.
///
/// A channel is two halves kept in two places:
///
/// - **Its name and id** in the plugin's storage, `glyph-slack-channels`, which the page lists and a reset clears.
///   The name is the person's own ("#launch"); Slack never tells a webhook's poster which channel it is.
/// - **Its webhook** in the device's secure store, under [webhookPrefix] and the id. A webhook URL is a secret,
///   since whoever holds it can post to the channel, so once it is handed over no page shows it again: a post names
///   the channel, and the webhook is read here for that post alone.
///
/// Both follow the account (Matt, 2026-10-26: "make it so things like the Claude tokens and other stuff is kept in
/// sync across all instances of ghost logged in to my account"; until then nothing here synced, and a second phone had
/// no channels until they were added there). Each webhook and the list are sealed on their own into the synced
/// settings (lib/sync/sealed_keys.dart, lib/sync/connections.dart) and written back on another device under the same
/// names, the webhook first, so a channel added on the Fold posts from the Mac and one forgotten anywhere is forgotten
/// everywhere. Not on an iPhone, where Slack is not yet. Where an organization's news goes stays each device's: it is
/// posted from each device that has a channel set for it (news.dart), so that choice is made on one.
///
/// What differs:
/// - **There is no Rust.** The page went through four commands because a WebView has an origin and hooks.slack.com
///   answers none; here the post is `host.fetch`, held to `hooks.slack.com`, and the webhook is `host.secrets`.
///   Rust's own checks came with the work: a webhook is held to Slack's two shapes when it is kept and again when it
///   is posted to ([allowedWebhook]), an id to letters, digits and dashes ([allowedId]), a message to 200,000
///   bytes, and Slack's answer is turned into a sentence ([slackAnswer]). Rust's sentences are kept as it wrote
///   them, straight apostrophes and all.
/// - **A webhook that could not be kept is found by reading it back**, since the secure store's door says nothing
///   when a write fails: a channel is still never listed without the way to post to it.
/// - **A post follows whatever the network follows.** Rust's client followed no redirect. `FetchRequest` has no
///   such switch; `dart:io` follows none for a POST except a 303, which it follows as a GET with no body. See the
///   report for lib/account/api.dart.
/// - [slackReadyNow] starts true: nothing of the binary is needed here, and the ground says so
///   (`hasNativeGeneration`). [slackAvailable] still asks, and what it answers is what [slackReadyNow] says after.
/// - [keptWebhooks] asks the store for each listed channel, where Rust listed its file.
/// - `useChannels` is `onPluginStorage` (lib/plugins/host.dart): a page listens and reads [channels] again.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../account/api.dart' show FetchRequest, FetchResponse;
import '../../core/iphone_app.dart' show notOnIPhone;
import '../host.dart' show PluginPermissionError;
import 'manifest.dart';

const String _channelsKey = 'glyph-slack-channels';

/// One channel (`Channel`).
@immutable
class Channel {
  const Channel({required this.id, required this.name});

  /// Made here when the channel is added: the key its webhook is kept under.
  final String id;

  /// The person's name for it: "#launch".
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) => other is Channel && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'Channel($id, $name)';
}

// ---- availability ------------------------------------------------------------------------------------------------

bool _ready = true;

/// Whether this build can post to Slack at all: the native generation the manifest asks for, as the ground answers
/// it (`slackAvailable`).
Future<bool> slackAvailable() async => _ready = await host.nativeReady();

/// The last answer of [slackAvailable], for code that cannot wait (whether a row on the More sheet shows)
/// (`slackReadyNow`).
bool slackReadyNow() => _ready;

/// For the tests: as though the build had answered (`setSlackReady`).
// ignore: use_setters_to_change_properties
void setSlackReady(bool yes) => _ready = yes;

// ---- the webhook's shape -----------------------------------------------------------------------------------------

/// The two kinds Slack hands out: an app's incoming webhook, and a Workflow Builder trigger (`WEBHOOK`).
final RegExp _webhook = RegExp(r'^https:\/\/hooks\.slack\.com\/(?:services|workflows)\/[A-Za-z0-9_/-]+$');
const List<String> _webhookPrefixes = ['https://hooks.slack.com/services/', 'https://hooks.slack.com/workflows/'];
final RegExp _tokenChars = RegExp(r'^[A-Za-z0-9_/-]+$');
final RegExp _idChars = RegExp(r'^[A-Za-z0-9-]+$');

/// Slack's limit on a message is 40,000 characters; anything near this is not a message the page meant to send
/// (slack.rs `MOST_BYTES`).
const int _mostBytes = 200000;

/// What is wrong with a pasted webhook, in a sentence, or null when it is one Slack would hand out. Checked here so
/// the pane can say so as it is typed; [allowedWebhook] checks again before one is kept and before it is posted to
/// (`webhookProblem`).
String? webhookProblem(String pasted) {
  final url = pasted.trim();
  if (url.isEmpty) return 'Paste the webhook Slack gave you.';
  if (RegExp(r'^http:\/\/', caseSensitive: false).hasMatch(url)) return 'A Slack webhook starts with https://, never http://.';
  if (!url.startsWith('https://hooks.slack.com/')) return 'That isn’t a Slack webhook. It starts with https://hooks.slack.com/services/.';
  if (url.contains('..') || !_webhook.hasMatch(url)) return 'That isn’t a Slack incoming webhook. It starts with https://hooks.slack.com/services/ and has no spaces or ? in it.';
  return null;
}

/// Whether [url] is a Slack webhook: https, hooks.slack.com, under `/services/` or `/workflows/`, and nothing after
/// that but the letters, digits, dashes, underscores and slashes Slack's tokens are made of. No query, no fragment,
/// no `..`, no user before the host (slack.rs `allowed_webhook`).
bool allowedWebhook(String url) {
  for (final prefix in _webhookPrefixes) {
    if (!url.startsWith(prefix)) continue;
    final rest = url.substring(prefix.length);
    return rest.isNotEmpty && rest.length <= 256 && !rest.contains('..') && _tokenChars.hasMatch(rest);
  }
  return false;
}

/// An id made here for a channel: a run of hex, or anything as plain (slack.rs `allowed_id`).
bool allowedId(String id) => id.isNotEmpty && id.length <= 64 && _idChars.hasMatch(id);

const String _notAWebhook = "That isn't a Slack incoming webhook. It starts with https://hooks.slack.com/services/.";

/// A channel's name as kept: trimmed, one space between words, at most 80 characters (`channelName`).
String channelName(String typed) {
  final name = typed.trim().replaceAll(RegExp(r'\s+'), ' ');
  return name.length <= 80 ? name : name.substring(0, 80);
}

/// What is wrong with a name for a new or renamed channel, or null. [except] is the channel being renamed
/// (`nameProblem`).
String? nameProblem(String typed, [String? except]) {
  final name = channelName(typed);
  if (name.isEmpty) return 'Give the channel a name, like #launch.';
  final taken = channels().any((c) => c.id != except && c.name.toLowerCase() == name.toLowerCase());
  return taken ? 'There is a channel called $name already.' : null;
}

// ---- the list ----------------------------------------------------------------------------------------------------

/// One list for as long as what is kept is the same: a note's More sheet asks on every draw.
({Object? from, List<Channel> list})? _shared;

/// The channels on this device, in the order they were added (`channels`).
List<Channel> channels() {
  final Object? kept = host.storage.get<Object?>(_channelsKey, const <Object?>[]);
  final shared = _shared;
  if (shared != null && identical(shared.from, kept)) return shared.list;
  final list = <Channel>[
    if (kept is List)
      for (final raw in kept)
        if (raw is Map && raw['id'] is String && (raw['id'] as String).isNotEmpty && raw['name'] is String && (raw['name'] as String).isNotEmpty)
          Channel(id: raw['id'] as String, name: raw['name'] as String),
  ];
  _shared = (from: kept, list: List.unmodifiable(list));
  return _shared!.list;
}

/// The channel with this id, or null (`channelById`).
Channel? channelById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final channel in channels()) {
    if (channel.id == id) return channel;
  }
  return null;
}

void _keep(List<Channel> list) {
  if (list.isNotEmpty) {
    host.storage.set(_channelsKey, [for (final channel in list) channel.toJson()]);
  } else {
    host.storage.remove(_channelsKey);
  }
}

/// Sixteen random bytes as hex: the id a channel's webhook is kept under (`newId`).
String _newId() {
  final random = Random.secure();
  return [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

String _secretOf(String id) => '$webhookPrefix$id';

/// A channel added: its webhook kept first, so a channel is never listed without the way to post to it, then its
/// name. Refused, in a sentence, for a name or a webhook that won't do (`addChannel`, slack.rs `save_channel`).
Future<Channel> addChannel(String typedName, String pastedUrl) async {
  final problem = nameProblem(typedName) ?? webhookProblem(pastedUrl);
  if (problem != null) throw SlackFailure(problem);
  final channel = Channel(id: _newId(), name: channelName(typedName));
  final url = pastedUrl.trim();
  if (!allowedId(channel.id)) throw const SlackFailure("That isn't a channel Ghost.md made.");
  if (!allowedWebhook(url)) throw const SlackFailure(_notAWebhook);
  await host.secrets.write(_secretOf(channel.id), url);
  // The store's door is silent when a write fails: what it holds now is the answer.
  if (await host.secrets.read(_secretOf(channel.id)) != url) throw const SlackFailure('cannot keep the Slack webhook on this device.');
  _keep([...channels(), channel]);
  return channel;
}

/// A new name for a channel; its webhook stays as it was (`renameChannel`).
void renameChannel(String id, String typedName) {
  final problem = nameProblem(typedName, id);
  if (problem != null) throw SlackFailure(problem);
  _keep([for (final c in channels()) c.id == id ? Channel(id: c.id, name: channelName(typedName)) : c]);
}

/// A channel forgotten: its webhook gone from the secure store, then its name from here. An organization whose news
/// went there is set to nowhere by the reader (news.dart `newsChannelFor`), which finds no channel by that id
/// (`forgetChannel`).
Future<void> forgetChannel(String id) async {
  if (allowedId(id)) await host.secrets.write(_secretOf(id), null);
  _keep([for (final c in channels()) if (c.id != id) c]);
}

/// The ids of the listed channels that have a webhook kept: a channel listed without one (a cleared store) can't
/// post, and the pane says so (`keptWebhooks`).
Future<List<String>> keptWebhooks() async {
  final ids = <String>[];
  for (final channel in channels()) {
    if (!allowedId(channel.id)) continue;
    final url = await host.secrets.read(_secretOf(channel.id));
    if (url != null && url.isNotEmpty) ids.add(channel.id);
  }
  return ids;
}

/// The webhook to post to for [id], held to the allow-list again: a store written some other way is not a way
/// round it (slack.rs `webhook_for`).
Future<String> _webhookFor(String id) async {
  final url = allowedId(id) ? await host.secrets.read(_secretOf(id)) : null;
  if (url == null || url.isEmpty) throw const SlackFailure("This channel's webhook isn't on this device. Add the channel again in Settings › Slack.");
  if (!allowedWebhook(url)) throw const SlackFailure(_notAWebhook);
  return url;
}

/// Slack's answer to a post, as nothing or the reason in a sentence. A webhook answers `ok` with 200, and otherwise
/// a status and a short code in the body (`no_service`, `channel_is_archived`, ...) (slack.rs `slack_answer`).
String? slackAnswer(int status, String body) {
  final code = body.trim();
  if (status >= 200 && status < 300) return null;
  if (code == 'channel_is_archived' || status == 410) return 'That Slack channel is archived, so nothing can be posted to it.';
  if (const {'no_service', 'no_team', 'channel_not_found', 'team_disabled'}.contains(code) || status == 404) {
    return 'Slack no longer knows this webhook. Make a new one in Slack and add the channel again.';
  }
  if (const {'action_prohibited', 'posting_to_general_channel_denied'}.contains(code) || status == 403) {
    return "Slack refused the post. The webhook's app may have been removed, or may not post there.";
  }
  if (const {'invalid_payload', 'too_many_attachments'}.contains(code) || status == 400) return "Slack couldn't read the message.";
  if (status == 429) return 'Slack asked for fewer posts. Try again in a minute.';
  if (status >= 500 && status <= 599) return 'Slack had a problem. Try again in a moment.';
  return 'Slack answered $status.';
}

/// Posts [text], as Slack's mrkdwn, to a channel. Throws a [SlackFailure] with the sentence for why not
/// (`postToChannel`, slack.rs `slack_post`).
Future<void> postToChannel(Channel channel, String text) async {
  // The Tauri app posts from Rust, which is not built for an iPhone: its sentence there (core/iphone_app.dart).
  final notHere = notOnIPhone('slack');
  if (notHere != null) throw SlackFailure(notHere);
  final url = await _webhookFor(channel.id);
  final body = Uint8List.fromList(utf8.encode(jsonEncode({'text': text})));
  if (body.length > _mostBytes) throw const SlackFailure('That is too long for one Slack message.');
  final FetchResponse response;
  try {
    response = await host.fetch(FetchRequest(method: 'POST', url: Uri.parse(url), headers: const {'Content-Type': 'application/json'}, body: body, timeout: const Duration(seconds: 20)));
  } on PluginPermissionError {
    rethrow;
  } on TimeoutException {
    throw const SlackFailure('Slack took too long to answer. Try again.');
  } catch (_) {
    throw const SlackFailure("Slack couldn't be reached. Check the connection.");
  }
  final refused = slackAnswer(response.status, response.text);
  if (refused != null) throw SlackFailure(refused);
}
