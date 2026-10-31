/// A ticket's pull requests (Matt, 2026-10-31, of the ticket features: "GitHub PR links"): a ticket key in a pull
/// request's title, its branch or its body, or in one of its commits' messages, links that pull request to the ticket,
/// shown on the ticket's panel as a chip with its state (open, draft, merged, closed) and its checks; and a merge can
/// move the ticket on.
///
/// POLLED FROM THE DEVICE, NOT TOLD BY A WEBHOOK. The notebook names its repos (`github: owner/repo`, lib/book/
/// rules.dart `githubReposOf`), and the phone asks GitHub with the plugin's own token (repos.dart `githubToken`, kept
/// on the device and sealed to the account's others), through the plugin's host, which holds every request to
/// api.github.com:
/// - **On every sync** ([PullLinks.pollRepo]): the repo's 50 most recently changed pull requests, open and closed
///   (`GET /repos/{o}/{r}/pulls?state=all&sort=updated&direction=desc&per_page=50`), each matched by its title, body
///   and branch. With an ETag: a repo that has not changed answers 304, which costs nothing of GitHub's rate limit.
/// - **When a ticket's panel opens** ([PullLinks.lookFor]): the older ones too, by GitHub's search
///   (`is:pr repo:{o}/{r} "HT-12" in:title,body`), and the commits whose messages name it (`GET /search/commits`),
///   each commit's pull requests (`GET /repos/{o}/{r}/commits/{sha}/pulls`); and the checks on each open one's head
///   (`GET /repos/{o}/{r}/commits/{sha}/check-runs`). Each with its ETag, and asked again at most every
///   [lookAgainAfter] for one ticket.
/// A webhook would tell sooner, but it needs routes on glyph-api and a secret per repo kept by the service, which
/// cannot read the notes it would have to change; polling on sync is minutes behind at worst and needs nothing new on
/// the server, so there is none.
///
/// What a key is: the notebook's key and a number, `HT-12`, anywhere in a title or a body (`Fixes HT-12`), and in a
/// branch in any case (`ht-12-fix-login`, `feature/HT-12`), never inside a longer word or number (`HT-123` is not
/// `HT-12`, `WHT-12` is not either).
///
/// THE MERGE. A notebook's `on-merge:` (rules.dart `onMergeOf`) says what a merged pull request does to its ticket:
/// `off` nothing, `done` (the default) its workflow's first done status, or a status named. [mergeMove] says, for a
/// ticket and its pulls, the status to move it to, or null; the root's sweep (lib/root/root_tickets.dart) moves it on
/// the one device that holds the rules' sweep (lib/book/rule_runs.dart), once, by the run id
/// `merge:<repo>#<number>:<note>`, so a merge seen by the Mac and the phone moves it once, and a ticket moved back by
/// hand after it stays where it was put.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../account/api.dart' show FetchRequest, FetchResponse;
import '../../core/properties.dart' show StatusCategory, statusCategory;
import '../types.dart' show Permission;
import 'manifest.dart' show GithubFailure, host;
import 'repos.dart' show githubToken;

/// Where a pull request stands, as its chip says it.
enum PullState {
  open('Open'),
  draft('Draft'),
  merged('Merged'),
  closed('Closed');

  const PullState(this.word);
  final String word;
}

/// How a pull request's checks went: the chip's dot.
enum PullChecks {
  passing('Checks passed'),
  failing('Checks failed'),
  pending('Checks running');

  const PullChecks(this.words);
  final String words;
}

/// Where a pull request names its ticket.
enum PullVia { title, body, branch, commit }

/// A pull request, as GitHub's list, search or a commit's pulls answer it.
@immutable
class PullRecord {
  const PullRecord({required this.repo, required this.number, required this.title, this.body = '', this.branch = '', required this.state, this.url = '', this.headSha, this.updatedAt = 0, this.commitKeys = const {}});

  /// From any of GitHub's answers about a pull request (the pulls list, a commit's pulls, a search's issue), or null.
  static PullRecord? fromJson(String repo, Object? raw) {
    if (raw is! Map || raw['number'] is! num) return null;
    final head = raw['head'];
    final pull = raw['pull_request'];
    final merged = raw['merged_at'] is String || (pull is Map && pull['merged_at'] is String);
    final state = merged
        ? PullState.merged
        : raw['state'] == 'closed'
            ? PullState.closed
            : raw['draft'] == true
                ? PullState.draft
                : PullState.open;
    String text(Object? v) => v is String ? v : '';
    return PullRecord(
      repo: repo,
      number: (raw['number'] as num).toInt(),
      title: text(raw['title']),
      body: text(raw['body']),
      branch: head is Map ? text(head['ref']) : '',
      state: state,
      url: text(raw['html_url']),
      headSha: head is Map && head['sha'] is String ? head['sha'] as String : null,
      updatedAt: DateTime.tryParse(text(raw['updated_at']))?.millisecondsSinceEpoch ?? 0,
    );
  }

  /// `owner/repo`.
  final String repo;
  final int number;
  final String title;
  final String body;

  /// Its branch, where the answer said (a search's does not).
  final String branch;
  final PullState state;
  final String url;
  final String? headSha;
  final int updatedAt;

  /// The keys its commits' messages name, where they were read.
  final Set<String> commitKeys;

  /// `owner/repo#12`.
  String get name => '$repo#$number';

  /// What a later answer adds to what this one knew: a branch and a head a search leaves out, the commits' keys.
  PullRecord mergedWith(PullRecord? older) {
    if (older == null) return this;
    return PullRecord(
      repo: repo,
      number: number,
      title: title.isNotEmpty ? title : older.title,
      body: body.isNotEmpty ? body : older.body,
      branch: branch.isNotEmpty ? branch : older.branch,
      state: state,
      url: url.isNotEmpty ? url : older.url,
      headSha: headSha ?? older.headSha,
      updatedAt: updatedAt > 0 ? updatedAt : older.updatedAt,
      commitKeys: {...older.commitKeys, ...commitKeys},
    );
  }

  /// Where it names [key], first by title, body, branch, then commit; null where it does not.
  PullVia? names(String key) {
    final want = key.toUpperCase();
    if (ticketKeysIn(title).contains(want)) return PullVia.title;
    if (ticketKeysIn(body).contains(want)) return PullVia.body;
    if (ticketKeysIn(branch).contains(want)) return PullVia.branch;
    if (commitKeys.contains(want)) return PullVia.commit;
    return null;
  }

  @override
  bool operator ==(Object other) => other is PullRecord && other.name == name && other.title == title && other.body == body && other.branch == branch && other.state == state && other.headSha == headSha && setEquals(other.commitKeys, commitKeys);

  @override
  int get hashCode => Object.hash(name, title, branch, state, headSha);

  @override
  String toString() => 'PullRecord($name ${state.word} "$title")';
}

/// A pull request linked to a ticket, as its chip draws it.
@immutable
class LinkedPull {
  const LinkedPull({required this.pull, required this.via, this.checks});
  final PullRecord pull;
  final PullVia via;
  final PullChecks? checks;

  /// The chip's words: `#41 Merged`.
  String get words => '#${pull.number} ${pull.state.word}';

  @override
  bool operator ==(Object other) => other is LinkedPull && other.pull == pull && other.via == via && other.checks == checks;

  @override
  int get hashCode => Object.hash(pull, via, checks);

  @override
  String toString() => 'LinkedPull(${pull.name} ${pull.state.word} via ${via.name}${checks == null ? '' : ', ${checks!.name}'})';
}

final RegExp _key = RegExp(r'(?<![A-Za-z0-9])([A-Za-z][A-Za-z0-9]{1,9})-([1-9]\d{0,5})(?![0-9])');

/// Every ticket key [text] names, upper case: `Fixes HT-12 and ht-9` is `{HT-12, HT-9}`.
Set<String> ticketKeysIn(String text) => {for (final m in _key.allMatches(text)) '${m.group(1)!.toUpperCase()}-${m.group(2)}'};

/// How a pull request's check runs went, from GitHub's `check_runs`: failing where any failed, running where any has
/// not finished, passed where all did; null for none.
PullChecks? checksOf(Object? raw) {
  final runs = raw is Map ? raw['check_runs'] : null;
  if (runs is! List || runs.isEmpty) return null;
  var pending = false;
  for (final run in runs) {
    if (run is! Map) continue;
    if (run['status'] != 'completed') {
      pending = true;
      continue;
    }
    if (const {'failure', 'timed_out', 'cancelled', 'action_required', 'startup_failure'}.contains(run['conclusion'])) return PullChecks.failing;
  }
  return pending ? PullChecks.pending : PullChecks.passing;
}

/// The status a ticket moves to for its merged pull requests (see the header), or null: [onMerge] null (`off`), no
/// pull merged, or the ticket already done or already there. `done` is the workflow's first done status.
String? mergeMove({required String? status, required List<String> statuses, required String? onMerge, required Iterable<LinkedPull> pulls}) {
  if (onMerge == null || !pulls.any((linked) => linked.pull.state == PullState.merged)) return null;
  final String target;
  if (onMerge.toLowerCase() == 'done') {
    target = statuses.where((each) => statusCategory(each, statuses) == StatusCategory.done).firstOrNull ?? 'Done';
  } else {
    target = statuses.where((each) => each.toLowerCase() == onMerge.toLowerCase()).firstOrNull ?? onMerge;
  }
  final now = (status ?? '').trim().toLowerCase();
  if (now == target.toLowerCase()) return null;
  if (onMerge.toLowerCase() == 'done' && statusCategory(status, statuses) == StatusCategory.done) return null;
  return target;
}

/// The run id a merge's move is known by, on every device.
String mergeRunId(PullRecord pull, String noteId) => 'merge:${pull.name}:$noteId';

/// What GitHub answered a GET, kept by its address with its ETag, so the same question asked again is a 304.
@immutable
class _Kept {
  const _Kept(this.etag, this.text);
  final String etag;
  final String text;
}

/// How long a ticket's own look is not asked again.
const Duration lookAgainAfter = Duration(minutes: 2);

/// The pull requests the device has read, by repo, and the ETags they came with (see the header).
class PullLinks extends ChangeNotifier {
  PullLinks({Future<FetchResponse> Function(FetchRequest request)? fetch, String Function()? token, int Function()? clock})
      : _fetch = fetch,
        _token = token ?? githubToken,
        clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Future<FetchResponse> Function(FetchRequest request)? _fetch;
  final String Function() _token;
  final int Function() clock;

  final Map<String, _Kept> _etags = {};
  final Map<String, Map<int, PullRecord>> _pulls = {};
  final Map<String, PullChecks?> _checks = {};
  final Map<String, int> _looked = {};

  /// How many GETs were sent, and how many came back unchanged: for a test.
  int asked = 0, unchanged = 0;

  /// Whether a token is in: nothing is asked without one (a public repo would answer, but sixty an hour, shared).
  bool get ready => _token().trim().isNotEmpty;

  Future<Object?> _get(String path) async {
    final url = 'https://api.github.com/$path';
    final kept = _etags[url];
    final token = _token().trim();
    final request = FetchRequest(method: 'GET', url: Uri.parse(url), headers: {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'If-None-Match': ?kept?.etag,
    });
    asked += 1;
    final FetchResponse answer;
    if (_fetch != null) {
      answer = await _fetch(request);
    } else {
      host.need(Permission.network);
      answer = await host.fetch(request);
    }
    if (answer.status == 304 && kept != null) {
      unchanged += 1;
      return jsonDecode(kept.text);
    }
    if (answer.status == 401) throw const GithubFailure('GitHub didn’t accept that token. Check it in Settings > GitHub.', status: 401);
    if (answer.status == 403 || answer.status == 429) throw GithubFailure('GitHub is limiting requests right now. Try again in a while.', status: answer.status);
    if (answer.status == 404) throw const GithubFailure('GitHub can’t find that repo with this token.', status: 404);
    if (!answer.ok) throw GithubFailure('GitHub answered ${answer.status}.', status: answer.status);
    final etag = answer.headers['etag'];
    if (etag != null && etag.isNotEmpty) _etags[url] = _Kept(etag, answer.text);
    return jsonDecode(answer.text);
  }

  void _keep(String repo, Iterable<PullRecord> pulls) {
    final held = _pulls.putIfAbsent(repo.toLowerCase(), () => {});
    var changed = false;
    for (final pull in pulls) {
      final next = pull.mergedWith(held[pull.number]);
      if (held[pull.number] == next) continue;
      held[pull.number] = next;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// The repo's most recently changed pull requests read (see the header): what a sync asks.
  Future<void> pollRepo(String repo) async {
    if (!ready) return;
    final list = await _get('repos/$repo/pulls?state=all&sort=updated&direction=desc&per_page=50');
    if (list is List) _keep(repo, [for (final raw in list) ?PullRecord.fromJson(repo, raw)]);
  }

  /// Every repo of every notebook given, read; a repo that fails is passed over (said through [warn]).
  Future<void> poll(Iterable<String> repos, {void Function(String message)? warn}) async {
    for (final repo in {for (final each in repos) each.toLowerCase(): each}.values) {
      try {
        await pollRepo(repo);
      } catch (failure) {
        (warn ?? debugPrint)('[github] $repo was not read: $failure');
      }
    }
  }

  /// A ticket's own look, as its panel opens (see the header): GitHub's search for its key in pull requests and in
  /// commits, and the checks of its open pull requests. Not again within [lookAgainAfter], unless [force].
  Future<void> lookFor(String key, Iterable<String> repos, {bool force = false}) async {
    if (!ready) return;
    final want = key.toUpperCase();
    for (final repo in repos) {
      final marker = '${repo.toLowerCase()}:$want';
      final last = _looked[marker];
      if (!force && last != null && clock() - last < lookAgainAfter.inMilliseconds) continue;
      _looked[marker] = clock();
      final q = Uri.encodeQueryComponent('repo:$repo is:pr "$want" in:title,body');
      final found = await _get('search/issues?q=$q&per_page=20');
      final items = found is Map ? found['items'] : null;
      if (items is List) _keep(repo, [for (final raw in items) ?PullRecord.fromJson(repo, raw)]);
      final commits = await _get('search/commits?q=${Uri.encodeQueryComponent('repo:$repo $want')}&per_page=5');
      final shas = commits is Map && commits['items'] is List
          ? [
              for (final item in commits['items'] as List)
                if (item is Map && item['sha'] is String && item['commit'] is Map && ticketKeysIn('${(item['commit'] as Map)['message']}').contains(want)) item['sha'] as String,
            ]
          : const <String>[];
      for (final sha in shas.take(5)) {
        final pulls = await _get('repos/$repo/commits/$sha/pulls');
        if (pulls is List) {
          _keep(repo, [
            for (final raw in pulls)
              if (PullRecord.fromJson(repo, raw) case final pull?) PullRecord(repo: repo, number: pull.number, title: pull.title, body: pull.body, branch: pull.branch, state: pull.state, url: pull.url, headSha: pull.headSha, updatedAt: pull.updatedAt, commitKeys: {want}),
          ]);
        }
      }
      for (final linked in pullsFor(want, [repo])) {
        final sha = linked.pull.headSha;
        if (sha == null || linked.pull.state == PullState.merged || linked.pull.state == PullState.closed) continue;
        final checks = checksOf(await _get('repos/$repo/commits/$sha/check-runs'));
        if (_checks[linked.pull.name] != checks) {
          _checks[linked.pull.name] = checks;
          notifyListeners();
        }
      }
    }
  }

  /// The pull requests that name [key] in [repos], newest change first: what the ticket's panel draws.
  List<LinkedPull> pullsFor(String key, Iterable<String> repos) {
    final out = <LinkedPull>[];
    for (final repo in repos) {
      for (final pull in (_pulls[repo.toLowerCase()] ?? const <int, PullRecord>{}).values) {
        final via = pull.names(key);
        if (via != null) out.add(LinkedPull(pull: pull, via: via, checks: _checks[pull.name]));
      }
    }
    out.sort((a, b) {
      final by = b.pull.updatedAt.compareTo(a.pull.updatedAt);
      return by != 0 ? by : b.pull.number.compareTo(a.pull.number);
    });
    return out;
  }
}

/// The app's pull requests, as the root reads them; a test makes its own.
PullLinks pullLinks = PullLinks();
