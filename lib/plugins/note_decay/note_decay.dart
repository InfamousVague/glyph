/// Note decay alerts (docs/NOTE_DECAY.md; Matt, 2026-11-02, choosing from a list of AI ideas: "Note decay alerts:
/// docs and pages that reference things that have since changed (a renamed ticket, a merged PR on GitHub, an old
/// date) get a quiet 'may be out of date' mark with the reason"). The app's own plugin, off until added in the Market.
///
/// Where it shows, once added:
/// - **A note's lines** (marks.dart): a quiet mark on a line that may be out of date, its reason a tap away, with
///   Update with AI and Still right (sheets.dart). Drawn by the editor, never written into the note.
/// - **Pages that may be out of date** (decay_list.dart): on a teamspace's home, a docs notebook's index and the
///   plugin's page.
/// - **Its page in Settings** (decay_pane.dart): Check with AI, and behind More in Simple, GitHub and Figma's lookups
///   and how long a docs page may go unedited.
///
/// This file is the plugin and the app's wiring: the AI it asks ([AppDecayModel]), what GitHub and Figma are asked
/// ([appDecayLookups]), and [startNoteDecay], which the root calls once.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../account/api.dart' show FetchRequest;
import '../../ai/backend.dart' show RunOptions, aiBackend, generate;
import '../../assistant/app_assistant.dart' show appAssistant;
import '../../assistant/assistant.dart' show claudeAssistantId;
import '../../assistant/provider.dart' show aiText;
import '../../claude/claude_settings.dart' show claudeSettings;
import '../../claude/claude_spend.dart' show claudeLimitError, meterClaude;
import '../../claude/messages_api.dart' show ClaudeApi;
import '../../core/note.dart';
import '../../core/preferences.dart' show preferences;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../figma/client.dart' show FigmaClient, FigmaFailure, figmaLinkOfUrl;
import '../figma/frames.dart' show figmaFramesOn;
import '../github/manifest.dart' as github;
import '../github/repos.dart' show githubToken;
import '../host.dart' show onPluginStorage;
import '../registry.dart' show pluginOn, plugins;
import '../types.dart';
import 'ai.dart';
import 'decay.dart';
import 'decay_pane.dart';
import 'lookups.dart';
import 'manifest.dart';

export 'decay.dart' show NoteDecay, noteDecay;
export 'manifest.dart' show noteDecayId, noteDecayManifest;

/// The AI the plugin asks (see the header of ai.dart): whatever Settings › AI › Assistant has answer the chat, and with
/// Local only, or nobody connected, the phone's own model where the phone has one.
class AppDecayModel implements DecayModel {
  const AppDecayModel();

  bool get _localOnly => preferences.value.localOnly;

  /// Who answers in the cloud now: Claude's id, another provider's, or null.
  String? get _cloud => _localOnly ? null : appAssistant.chatBy;

  @override
  String get name {
    final by = _cloud;
    if (by != null) return appAssistant.nameOf(by);
    return 'the phone’s model';
  }

  @override
  bool get ready => _cloud != null || aiBackend.available;

  @override
  bool get onDevice => _cloud == null;

  @override
  Future<String> ask({required String system, required String prompt}) async {
    final by = _cloud;
    if (by == claudeAssistantId) {
      final key = claudeSettings.key;
      if (key == null) throw StateError('Add your Anthropic API key in Settings › Claude.');
      if (claudeSettings.spend.reached) throw claudeLimitError(claudeSettings.spend);
      final model = claudeSettings.model;
      final call = meterClaude(ClaudeApi(key: key).stream(_body(model, system, prompt)), model: model, spend: claudeSettings.spend);
      return aiText(call, who: 'Claude');
    }
    final other = appAssistant.other(by);
    if (other != null) {
      final settings = other.settings;
      if (settings.spend.reached) throw claudeLimitError(settings.spend);
      final call = meterClaude(other.client(settings).stream(_body(settings.model, system, prompt)), model: settings.model, spend: settings.spend);
      return aiText(call, who: other.name);
    }
    if (!aiBackend.available) throw StateError('No AI is connected, and this phone has no model of its own.');
    final run = generate(RunOptions(model: preferences.value.formatModel, system: system, prompt: prompt, maxTokens: 900, temperature: 0.2, onProgress: (_) {}));
    return (await run.done).text;
  }

  static Map<String, Object?> _body(String model, String system, String prompt) => {
        'model': model,
        'max_tokens': 2000,
        'system': system,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      };
}

/// What GitHub says of one issue or pull request: its issue, which for a pull request carries `merged_at` too, through
/// the GitHub plugin's own host and token.
Future<GithubState?> githubDecayState(GithubRef ref) async {
  final token = githubToken().trim();
  final answer = await github.host.fetch(FetchRequest(
    method: 'GET',
    url: Uri.parse('https://api.github.com/repos/${ref.owner}/${ref.repo}/issues/${ref.number}'),
    headers: {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
  ));
  if (!answer.ok) return null;
  return githubStateOf(jsonDecode(answer.text));
}

/// GitHub's issue JSON as a [GithubState]: merged where its pull request says so, else closed or open.
GithubState? githubStateOf(Object? json) {
  if (json is! Map) return null;
  final pull = json['pull_request'];
  final merged = pull is Map && pull['merged_at'] is String ? DateTime.tryParse(pull['merged_at'] as String) : null;
  final closed = json['closed_at'] is String ? DateTime.tryParse(json['closed_at'] as String) : null;
  final title = json['title'] is String ? json['title'] as String : null;
  if (merged != null) return GithubState(GithubStateKind.merged, at: merged, title: title);
  if (json['state'] == 'closed') return GithubState(GithubStateKind.closed, at: closed, title: title);
  return GithubState(GithubStateKind.open, title: title);
}

/// Whether Figma says [url]'s frame or file is gone: a 404, or a frame its file no longer has.
Future<bool?> figmaDecayGone(String url) async {
  final link = figmaLinkOfUrl(url);
  final client = FigmaClient.kept();
  if (link == null || client == null) return null;
  try {
    final frame = await client.frame(link);
    return link.nodeId != null && frame.frame == null;
  } on FigmaFailure catch (failure) {
    return failure.status == 404 ? true : null;
  }
}

/// The app's lookups: GitHub and Figma asked only with their plugins on (which Local only holds off) and the
/// plugin's lookups switched on.
AppDecayLookups appDecayLookups() => AppDecayLookups(
      githubOn: () => !preferences.value.localOnly && decayLookupsOn() && pluginOn(github.manifest),
      figmaOn: () => !preferences.value.localOnly && decayLookupsOn() && figmaFramesOn(),
      askGithub: githubDecayState,
      askFigma: figmaDecayGone,
    );

VoidCallback? _unhear;

/// Puts the app's [noteDecay] in place over [notes], heard again on [changes]; the root calls it once. Its settings,
/// the plugins' switches and the preferences are heard too, so a switch moved draws the marks again.
NoteDecay startNoteDecay({required List<Note> Function() notes, Listenable? changes}) {
  _unhear?.call();
  noteDecay?.dispose();
  final lookups = appDecayLookups();
  final decay = noteDecay = NoteDecay(
    notes: notes,
    changes: changes,
    lookups: () => lookups,
    model: () => const AppDecayModel(),
    on: () => pluginOn(noteDecayManifest),
    aiOn: decayAiOn,
    months: decayMonths,
    renames: _renamesKept,
    keepRenames: (renames) {
      _renames = null;
      setDecayRenames(renames);
    },
  );
  void heard() {
    _renames = null;
    decay.settingsChanged();
  }

  final stopStorage = onPluginStorage(heard);
  plugins.addListener(heard);
  preferences.addListener(heard);
  _unhear = () {
    stopStorage();
    plugins.removeListener(heard);
    preferences.removeListener(heard);
  };
  return decay;
}

/// The renames as kept, read once a change (so the library's cache holds while nothing changed).
Map<String, String>? _renames;
Map<String, String> _renamesKept() => _renames ??= decayRenames();

/// What the search finds on the plugin's page.
const List<SettingsFindable> noteDecayFindable = [
  SettingsFindable('Check with AI', 'note decay out of date ai check stale'),
  SettingsFindable('Ask GitHub and Figma', 'note decay github pull request merged figma frame'),
  SettingsFindable('Docs pages unedited for', 'note decay stale docs months'),
];

String _summary() {
  final pages = noteDecay?.pages().length ?? 0;
  final ai = decayAiOn() ? ', with AI' : '';
  return pages == 0 ? 'Nothing marked$ai' : '$pages ${pages == 1 ? 'page' : 'pages'} marked$ai';
}

final GlyphPlugin noteDecayPlugin = GlyphPlugin(
  manifest: noteDecayManifest,
  icon: 'clock',
  settings: PluginSettings(pane: (context) => const NoteDecayPane(), summary: _summary, hue: 'amber', settings: noteDecayFindable),
);
