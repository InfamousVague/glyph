/// Projects: a GitHub repo a note is about, read by the model on the phone into a short context pack that goes with
/// the note whenever it is formatted. A port of `src/app/plugins/github/repos.ts`.
///
/// Matt: "bring back linking projects and have the local AI go through and examine them where possible for
/// context". A note about AttackFM formats better knowing what AttackFM is, what its parts are called, and which
/// names are people and which are features.
///
/// - Reading is GitHub's API: the repo's description and default branch, its file tree, and a handful of files that
///   say what the project is (the README, AGENTS.md, a few docs, and the manifest). A private repo needs a token,
///   kept in the secure store and sealed into the synced settings for the account's other devices
///   (lib/sync/connections.dart; Matt, 2026-10-26: the tokens kept the same on every device).
/// - Distilling is the phone's own model, asked for a plain summary of names, parts and terms. No model keeps the
///   README's opening instead, so a link always gives something.
/// - What is kept, and which note links to which project, is the plugin's storage: `glyph-github-projects` and
///   `glyph-project-links`, cleared by a reset.
///
/// What differs:
/// - **The token is a secret.** The page kept it in localStorage; here it is `host.secrets` ([tokenSecret]), and
///   [githubToken] answers what the host last saw of it (`held`), so the app's root must `warm()` the plugin's
///   secrets at launch ([warmGithub]) or a kept token reads as none until something asks. [setGithubToken] answers
///   a future, done when the store has it; [githubToken] is right from the moment it is called.
/// - **The model is a seam.** The page called `core/ai.ts` (`listModels`, `preferences().formatModel`, `MODELS`,
///   `generate`); lib/ai is another piece, so the model comes through [githubDistiller]: a function that answers the
///   model to write with, or null with none on the phone. Which model that is (the chosen one, else a smaller one
///   that is here) is the plug's to decide, as `distillModel` decided it on the page. Unset, no briefing is written
///   and the README's opening is kept, which is what the page did in a browser.
/// - Every request goes through `host.fetch`, which holds it to `api.github.com`.
/// - A step is a [ReadStep] class of three kinds, where the page had a union of object shapes.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../account/api.dart' show FetchRequest;
import '../types.dart';
import 'manifest.dart';

/// Not `glyph-projects`: the 0.4.x projects feature left entries of another shape there.
const String _projectsKey = 'glyph-github-projects';
const String _linksKey = 'glyph-project-links';

/// Characters of repo text handed to the model: about four thousand tokens.
const int _sourceChars = 16000;
const int _fileChars = 6000;
const int _maxFiles = 8;

/// A repo read on this phone (`Project`).
@immutable
class Project {
  const Project({
    required this.id,
    required this.owner,
    required this.repo,
    this.url = '',
    this.branch = '',
    this.description = '',
    this.files = const [],
    required this.pack,
    this.packModel,
    this.packedAt = 0,
  });

  /// A project as kept, or null for anything of another shape (the page's filter: an owner, a repo and a pack, all
  /// text).
  static Project? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final owner = raw['owner'], repo = raw['repo'], pack = raw['pack'];
    if (owner is! String || repo is! String || pack is! String) return null;
    final id = raw['id'], url = raw['url'], branch = raw['branch'], description = raw['description'], files = raw['files'], packModel = raw['packModel'], packedAt = raw['packedAt'];
    return Project(
      id: id is String ? id : '$owner/$repo'.toLowerCase(),
      owner: owner,
      repo: repo,
      url: url is String ? url : '',
      branch: branch is String ? branch : '',
      description: description is String ? description : '',
      files: files is List ? [for (final file in files) if (file is String) file] : const [],
      pack: pack,
      packModel: packModel is String ? packModel : null,
      packedAt: packedAt is num ? packedAt.toInt() : 0,
    );
  }

  final String id;
  final String owner;
  final String repo;
  final String url;
  final String branch;
  final String description;

  /// The files that were read.
  final List<String> files;

  /// The context pack: what the model wrote, or the README's opening.
  final String pack;

  /// The model that wrote the pack, or null when it is the README's opening.
  final String? packModel;
  final int packedAt;

  Map<String, Object?> toJson() =>
      {'id': id, 'owner': owner, 'repo': repo, 'url': url, 'branch': branch, 'description': description, 'files': files, 'pack': pack, 'packModel': packModel, 'packedAt': packedAt};

  @override
  String toString() => 'Project(${toJson()})';
}

// ---- storage -----------------------------------------------------------------------------------------------------

/// One list for as long as what is kept is the same: the cog sheet's hints and a note's marks ask on every draw.
({Object? from, List<Project> list})? _shared;

/// The projects kept on this phone, newest first (`projects`).
List<Project> projects() {
  final Object? kept = host.storage.get<Object?>(_projectsKey, const <Object?>[]);
  final shared = _shared;
  if (shared != null && identical(shared.from, kept)) return shared.list;
  final list = <Project>[
    if (kept is List)
      for (final raw in kept) ?Project.fromJson(raw),
  ];
  _shared = (from: kept, list: List.unmodifiable(list));
  return _shared!.list;
}

Map<String, String> _links() {
  final Object? kept = host.storage.get<Object?>(_linksKey, const <String, Object?>{});
  // A copy: what a read answers is shared with every other read of it (lib/plugins/host.dart).
  return {
    if (kept is Map)
      for (final MapEntry(:key, :value) in kept.entries)
        if (key is String && value is String) key: value,
  };
}

final RegExp _comment = RegExp(r'<!--[\s\S]*?-->');
final RegExp _tag = RegExp(r'<[^>]+>');
final RegExp _badge = RegExp(r'\[!\[[^\]]*\]\([^)]*\)\]\([^)]*\)');
final RegExp _picture = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final RegExp _emptyLink = RegExp(r'\[\s*\]\([^)]*\)');
final RegExp _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
final RegExp _ruleLine = RegExp(r'^\s*[-=*_]{3,}\s*$', multiLine: true);
final RegExp _blankRun = RegExp(r'\n{3,}');

/// A README as plain words for a fallback briefing: HTML, images, badges and link targets gone, blank runs squeezed
/// (`readmeWords`).
String readmeWords(String markdown) => markdown
    .replaceAll(_comment, '')
    .replaceAll(_tag, '')
    .replaceAll(_badge, '')
    .replaceAll(_picture, '')
    .replaceAll(_emptyLink, '')
    .replaceAllMapped(_link, (m) => m[1]!)
    .replaceAll(_ruleLine, '')
    .replaceAll(_blankRun, '\n\n')
    .trim();

void _saveProject(Project project) {
  host.storage.set(_projectsKey, [project.toJson(), for (final p in projects()) if (p.id != project.id) p.toJson()]);
}

/// Forgets a project, and unlinks every note from it (`removeProject`).
void removeProject(String id) {
  host.storage.set(_projectsKey, [for (final p in projects()) if (p.id != id) p.toJson()]);
  host.storage.set(_linksKey, _links()..removeWhere((note, project) => project == id));
}

/// The project a note is linked to, or null (`projectFor`).
Project? projectFor(String noteId) {
  final id = _links()[noteId];
  if (id == null || id.isEmpty) return null;
  for (final project in projects()) {
    if (project.id == id) return project;
  }
  return null;
}

/// Links a note to a project, or to none with null (`linkProject`).
void linkProject(String noteId, String? projectId) {
  final links = _links();
  if (projectId != null && projectId.isNotEmpty) {
    links[noteId] = projectId;
  } else {
    links.remove(noteId);
  }
  host.storage.set(_linksKey, links);
}

/// What the model is given with a note linked to a project, or null (`projectContextFor`).
String? projectContextFor(String noteId) {
  final project = projectFor(noteId);
  if (project == null || project.pack.trim().isEmpty) return null;
  return 'This note is about the project ${project.owner}/${project.repo}. What is known about it, for spelling names and understanding terms (do not add any of it to the note):\n\n${project.pack.trim()}';
}

/// Changes when a note's project, or its pack, does: for "the note has changed since" checks
/// (`projectContextVersion`).
int projectContextVersion(String noteId) => projectFor(noteId)?.packedAt ?? 0;

/// The token kept on this device, or nothing (`githubToken`): what the host last saw of the secret.
String githubToken() => host.secrets.held(tokenSecret) ?? '';

/// Keeps a token, trimmed; an empty one forgets it (`setGithubToken`). [githubToken] answers it at once; the future
/// is done when the secure store has it.
Future<void> setGithubToken(String token) {
  final trimmed = token.trim();
  return host.secrets.write(tokenSecret, trimmed.isEmpty ? null : trimmed);
}

/// Reads the kept token from the secure store, so [githubToken] is true to it: the app's root, at launch.
Future<void> warmGithub() => host.secrets.warm();

/// Whose [token] is (the kept one where null): `GET /user`, which changes nothing, its login. The setup's check
/// (github_setup.dart). Throws a [GithubFailure] as every call here does.
Future<String> githubLogin([String? token]) async {
  final user = await _github('user', token ?? githubToken());
  final login = user is Map ? user['login'] : null;
  return login is String ? login : '';
}

// ---- reading a repo ----------------------------------------------------------------------------------------------

final RegExp _scheme = RegExp(r'^https?:\/\/', caseSensitive: false);
final RegExp _www = RegExp(r'^www\.', caseSensitive: false);
final RegExp _site = RegExp(r'^github\.com\/', caseSensitive: false);
final RegExp _dotGit = RegExp(r'\.git$', caseSensitive: false);
final RegExp _slashes = RegExp(r'\/+$');
final RegExp _ownerRepo = RegExp(r'^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)(?:\/.*)?$');

/// `owner` and `repo` from "https://github.com/o/r", "github.com/o/r.git", "o/r" (`parseRepo`).
({String owner, String repo})? parseRepo(String input) {
  final text = input.trim().replaceFirst(_scheme, '').replaceFirst(_www, '').replaceFirst(_site, '').replaceFirst(_dotGit, '').replaceFirst(_slashes, '');
  final match = _ownerRepo.firstMatch(text);
  return match == null ? null : (owner: match[1]!, repo: match[2]!);
}

final RegExp _skipped = RegExp(r'(^|\/)(node_modules|vendor|dist|build|target|\.git)\/');
final RegExp _readme = RegExp(r'^readme(\.|$)');
final RegExp _agents = RegExp(r'^agents\.md$');
final RegExp _designDoc = RegExp(r'^docs\/[^/]*design[^/]*\.md$', caseSensitive: false);
final RegExp _projectFile = RegExp(r'^(package\.json|cargo\.toml|pyproject\.toml|go\.mod|pubspec\.yaml)$');
final RegExp _doc = RegExp(r'^docs\/[^/]+\.md$', caseSensitive: false);
final RegExp _overview = RegExp(r'^(contributing|architecture|overview)\.md$');

/// Which files say what a project is, most telling first: the README, notes for AI tools (which are summaries of
/// the codebase), a few docs, and the manifest. Vendored and generated folders are skipped (`pickFiles`).
List<String> pickFiles(List<String> paths) {
  int? rank(String path) {
    final parts = path.split('/');
    final name = parts.last.toLowerCase();
    final depth = parts.length - 1;
    if (depth == 0 && _readme.hasMatch(name)) return 0;
    if (depth == 0 && _agents.hasMatch(name)) return 1;
    if (_designDoc.hasMatch(path)) return 2;
    if (depth == 0 && _projectFile.hasMatch(name)) return 3;
    if (_doc.hasMatch(path)) return 4;
    if (depth == 0 && _overview.hasMatch(name)) return 5;
    return null;
  }

  final ranked = [
    for (final (at, path) in paths.indexed)
      if (!_skipped.hasMatch(path))
        if (rank(path) case final rank?) (at: at, path: path, rank: rank),
  ];
  // Stable, as the page's sort is: two of a rank and a length keep the tree's order.
  ranked.sort((a, b) {
    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
    if (a.path.length != b.path.length) return a.path.length.compareTo(b.path.length);
    return a.at.compareTo(b.at);
  });
  return [for (final file in ranked.take(_maxFiles)) file.path];
}

/// The repo's shape in a few lines: its top-level folders and how many files each holds (`outline`).
String outline(List<String> paths) {
  final counts = <String, int>{};
  for (final path in paths) {
    final top = path.contains('/') ? '${path.split('/').first}/' : path;
    counts[top] = (counts[top] ?? 0) + 1;
  }
  final order = {for (final (at, top) in counts.keys.indexed) top: at};
  final tops = counts.entries.toList()
    ..sort((a, b) {
      final by = b.value.compareTo(a.value);
      return by != 0 ? by : order[a.key]!.compareTo(order[b.key]!);
    });
  return [
    for (final MapEntry(key: top, value: n) in tops.take(30)) top.endsWith('/') ? '$top ($n ${n == 1 ? 'file' : 'files'})' : top,
  ].join('\n');
}

Future<Object?> _github(String path, String token, {bool raw = false}) async {
  host.need(Permission.network);
  final response = await host.fetch(
    FetchRequest(
      method: 'GET',
      url: Uri.parse('https://api.github.com/$path'),
      headers: {
        'Accept': raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ),
  );
  if (response.status == 404) throw GithubFailure(token.isNotEmpty ? 'GitHub can’t find that repo with this token.' : 'GitHub can’t find that repo. If it’s private, add a token.', status: 404);
  if (response.status == 401) throw const GithubFailure('GitHub didn’t accept that token.', status: 401);
  if (response.status == 403) throw const GithubFailure('GitHub is limiting requests right now. Try again in a while, or add a token.', status: 403);
  if (!response.ok) throw GithubFailure('GitHub answered ${response.status}.', status: response.status);
  return raw ? response.text : jsonDecode(response.text);
}

/// How far reading a repo has got, for the picker to say as it goes (`ReadStep`).
sealed class ReadStep {
  const ReadStep();
}

/// Asking GitHub about the repo.
class ReadReading extends ReadStep {
  const ReadReading();
}

/// [done] of [total] files read.
class ReadFiles extends ReadStep {
  const ReadFiles({required this.done, required this.total});
  final int done;
  final int total;
}

/// The model is writing: its name, its pace, and what it has written so far.
class ReadDistilling extends ReadStep {
  const ReadDistilling({required this.model, required this.tokensPerSecond, required this.text});
  final String model;
  final double tokensPerSecond;
  final String text;
}

/// What the model is told it is doing (`DISTILL_PROMPT`).
const String distillPrompt = '''You read a software project's own documents and write a short briefing for someone taking voice notes about it. Plain text, no markdown headings, at most 250 words:

1. One or two sentences on what the project is and who it is for.
2. Its main parts, as a short list of names with a few words each.
3. Names and terms that will come up in notes and how they are spelled: features, components, services, people or teams if the documents name them.
4. What the documents say is current work or open problems, if they say.

Only what the documents say. No guesses, no advice, no introduction and no closing remark.''';

/// What the model is asked for a briefing: the page's `generate({ model, system, prompt, maxTokens, temperature,
/// onProgress })`, less the model, which is the [Distiller]'s own.
class DistillAsk {
  const DistillAsk({required this.system, required this.prompt, required this.maxTokens, required this.temperature, required this.onProgress});
  final String system;
  final String prompt;
  final int maxTokens;
  final double temperature;

  /// Told as the model loads, reads and writes: its pace, and what it has written so far.
  final void Function(double tokensPerSecond, String partial) onProgress;
}

/// A model on the phone, as the briefing needs it.
class Distiller {
  const Distiller({required this.id, required this.name, required this.write});

  /// The model's id, kept as the project's `packModel`: "qwen3.5-4b".
  final String id;

  /// Its name as the picker says it while it writes (`modelName`): "Qwen3.5 4B".
  final String name;

  /// Runs the model and answers everything it wrote; throws when the run fails.
  final Future<String> Function(DistillAsk ask) write;
}

/// The model to distil with (`distillModel`): the one chosen for formatting if it is here, else another that is;
/// null with none on the phone. Null itself until lib/ai is plugged in, and then no briefing is written.
Future<Distiller?> Function()? githubDistiller;

/// The time, in milliseconds: a project's `packedAt`. A test's own where it wants one.
int Function() githubNow = _clock;
int _clock() => DateTime.now().millisecondsSinceEpoch;

String _cut(String text, int most) => text.length <= most ? text : text.substring(0, most);

final RegExp _readmeText = RegExp(r'^--- readme', caseSensitive: false);
final RegExp _fileHead = RegExp(r'^--- [^\n]+\n');

/// Reads a repo, distils it on the phone, keeps it, and answers the project (`addProject`).
Future<Project> addProject(String input, void Function(ReadStep step) onStep) async {
  final parsed = parseRepo(input);
  if (parsed == null) throw const GithubFailure('That doesn’t look like a GitHub repo. Paste a link like github.com/owner/repo.');
  final token = githubToken();
  onStep(const ReadReading());
  final meta = (await _github('repos/${parsed.owner}/${parsed.repo}', token) as Map).cast<String, Object?>();
  final names = (meta['full_name'] as String? ?? '').split('/');
  final owner = names.isNotEmpty && names[0].isNotEmpty ? names[0] : parsed.owner;
  final repo = names.length > 1 ? names[1] : parsed.repo;
  final branch = meta['default_branch'] as String? ?? '';
  final described = meta['description'] as String?;
  final tree = (await _github('repos/$owner/$repo/git/trees/${Uri.encodeComponent(branch)}?recursive=1', token) as Map).cast<String, Object?>();
  final paths = [
    for (final entry in tree['tree'] as List? ?? const [])
      if (entry is Map && entry['type'] == 'blob' && entry['path'] is String) entry['path'] as String,
  ];
  final chosen = pickFiles(paths);

  final texts = <String>[];
  for (final (i, path) in chosen.indexed) {
    onStep(ReadFiles(done: i, total: chosen.length));
    String text;
    try {
      text = await _github('repos/$owner/$repo/contents/${path.split('/').map(Uri.encodeComponent).join('/')}?ref=${Uri.encodeComponent(branch)}', token, raw: true) as String;
    } catch (_) {
      // A file that will not read is left out; the project is still read.
      text = '';
    }
    if (text.trim().isNotEmpty) texts.add('--- $path ---\n${_cut(text, _fileChars)}');
  }
  onStep(ReadFiles(done: chosen.length, total: chosen.length));

  final source = _cut(
    ['Repository: $owner/$repo', if (described != null && described.isNotEmpty) 'Description: $described', 'Folders:\n${outline(paths)}', ...texts].where((part) => part.isNotEmpty).join('\n\n'),
    _sourceChars,
  );

  final readmeFile = texts.where(_readmeText.hasMatch).firstOrNull;
  final readme = readmeFile?.replaceFirst(_fileHead, '') ?? described ?? '';
  var pack = _cut(readmeWords(readme), 1500).trim();
  String? packModel;
  host.need(Permission.ai);
  final model = await githubDistiller?.call();
  if (model != null) {
    try {
      final written = await model.write(
        DistillAsk(
          system: distillPrompt,
          prompt: source,
          maxTokens: 700,
          temperature: 0.2,
          onProgress: (tokensPerSecond, partial) => onStep(ReadDistilling(model: model.name, tokensPerSecond: tokensPerSecond, text: partial)),
        ),
      );
      if (written.trim().isNotEmpty) {
        pack = written.trim();
        packModel = model.id;
      }
    } catch (failure) {
      debugPrint('[glyph] project not distilled, keeping the README: $failure');
    }
  }

  final project = Project(
    id: '$owner/$repo'.toLowerCase(),
    owner: owner,
    repo: repo,
    url: meta['html_url'] as String? ?? '',
    branch: branch,
    description: described ?? '',
    files: chosen,
    pack: pack,
    packModel: packModel,
    packedAt: githubNow(),
  );
  _saveProject(project);
  return project;
}
